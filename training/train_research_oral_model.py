"""Train a compact on-device oral-lesion research screening model.

Input data layout expected from the public Kaggle image dataset:
training/data/oral_images/OralCancer/cancer
training/data/oral_images/OralCancer/non-cancer

The third class is composed of generic natural images and rejects photos that
are not of an oral cavity. This is a research screening model only; it is not
a diagnostic device and positive outputs require clinician review.
"""

from __future__ import annotations

import json
import random
import shutil
from pathlib import Path

import numpy as np
import tensorflow as tf

SEED = 42
IMAGE_SIZE = 224
BATCH_SIZE = 8
EPOCHS = 10
ROOT = Path(__file__).resolve().parents[1]
ORAL_ROOT = ROOT / "training" / "data" / "oral_images" / "OralCancer"
MODEL_PATH = ROOT / "assets" / "models" / "oral_cancer_efficientnetb0.tflite"
METADATA_PATH = ROOT / "assets" / "models" / "oral_cancer_model_metadata.json"
LABELS = ("Cancer", "Normal Oral", "Non-Oral")


def _files(folder: Path) -> list[Path]:
    return sorted(
        path
        for path in folder.rglob("*")
        if path.suffix.lower() in {".jpg", ".jpeg", ".png", ".bmp"}
    )


def _split(paths: list[Path]) -> tuple[list[Path], list[Path], list[Path]]:
    shuffled = list(paths)
    random.Random(SEED).shuffle(shuffled)
    total = len(shuffled)
    train_end = max(1, int(total * 0.70))
    valid_end = max(train_end + 1, int(total * 0.85))
    return shuffled[:train_end], shuffled[train_end:valid_end], shuffled[valid_end:]


def _cifar_non_oral() -> tuple[list[np.ndarray], list[np.ndarray], list[np.ndarray]]:
    """Use everyday-photo images only for rejecting non-oral camera input."""
    (images, _), _ = tf.keras.datasets.cifar10.load_data()
    images = images[:300]
    random.Random(SEED).shuffle(images)
    return list(images[:210]), list(images[210:255]), list(images[255:300])


def _load_path(path: tf.Tensor, label: tf.Tensor) -> tuple[tf.Tensor, tf.Tensor]:
    raw = tf.io.read_file(path)
    image = tf.io.decode_image(raw, channels=3, expand_animations=False)
    image.set_shape([None, None, 3])
    image = tf.image.resize(image, [IMAGE_SIZE, IMAGE_SIZE])
    return tf.cast(image, tf.float32) / 255.0, label


def _build_dataset(
    image_paths: list[Path], labels: list[int], non_oral: list[np.ndarray], *, training: bool
) -> tf.data.Dataset:
    path_strings = [str(path) for path in image_paths]
    ds_oral = tf.data.Dataset.from_tensor_slices((path_strings, labels))
    ds_oral = ds_oral.map(_load_path, num_parallel_calls=tf.data.AUTOTUNE)

    non_oral_tensor = tf.convert_to_tensor(non_oral, dtype=tf.float32) / 255.0
    ds_non_oral = tf.data.Dataset.from_tensor_slices(
        (non_oral_tensor, tf.fill([len(non_oral)], 2))
    )
    ds_non_oral = ds_non_oral.map(
        lambda image, label: (tf.image.resize(image, [IMAGE_SIZE, IMAGE_SIZE]), label),
        num_parallel_calls=tf.data.AUTOTUNE,
    )

    dataset = ds_oral.concatenate(ds_non_oral)
    if training:
        dataset = dataset.shuffle(512, seed=SEED)
    return dataset.batch(BATCH_SIZE).prefetch(tf.data.AUTOTUNE)


def main() -> None:
    tf.keras.utils.set_random_seed(SEED)
    cancer = _files(ORAL_ROOT / "cancer")
    normal = _files(ORAL_ROOT / "non-cancer")
    if len(cancer) < 10 or len(normal) < 10:
        raise RuntimeError("Expected cancer and non-cancer oral image folders with at least 10 images each.")

    cancer_split = _split(cancer)
    normal_split = _split(normal)
    non_oral_split = _cifar_non_oral()

    datasets = []
    for index in range(3):
        oral_paths = cancer_split[index] + normal_split[index]
        oral_labels = [0] * len(cancer_split[index]) + [1] * len(normal_split[index])
        datasets.append(_build_dataset(oral_paths, oral_labels, non_oral_split[index], training=index == 0))
    train_ds, validation_ds, test_ds = datasets

    inputs = tf.keras.Input(shape=(IMAGE_SIZE, IMAGE_SIZE, 3), name="image")
    # Keep augmentation out of the exported graph: TFLite only needs the
    # deterministic screening network that runs on the phone.
    x = tf.keras.layers.Rescaling(2.0, offset=-1.0)(inputs)
    # Small architecture is intentional: it keeps the APK lean and gives a
    # stable, fast inference path on a hackathon phone. This is research only,
    # never a clinical diagnostic model.
    x = tf.keras.layers.Conv2D(16, 3, strides=2, activation="relu")(x)
    x = tf.keras.layers.SeparableConv2D(32, 3, padding="same", activation="relu")(x)
    x = tf.keras.layers.MaxPooling2D()(x)
    x = tf.keras.layers.SeparableConv2D(64, 3, padding="same", activation="relu")(x)
    x = tf.keras.layers.MaxPooling2D()(x)
    x = tf.keras.layers.SeparableConv2D(96, 3, padding="same", activation="relu")(x)
    x = tf.keras.layers.GlobalAveragePooling2D()(x)
    x = tf.keras.layers.Dropout(0.30)(x)
    outputs = tf.keras.layers.Dense(3, activation="softmax", name="classification")(x)
    model = tf.keras.Model(inputs, outputs, name="saha_oral_research_screening")
    model.compile(
        optimizer=tf.keras.optimizers.Adam(learning_rate=1e-3),
        loss=tf.keras.losses.SparseCategoricalCrossentropy(),
        metrics=["accuracy"],
    )
    model.fit(
        train_ds,
        validation_data=validation_ds,
        epochs=EPOCHS,
        callbacks=[tf.keras.callbacks.EarlyStopping(patience=3, restore_best_weights=True)],
        verbose=2,
    )

    test_loss, test_accuracy = model.evaluate(test_ds, verbose=0)
    saved_model_dir = ROOT / "training" / "outputs" / "oral_research_saved_model"
    if saved_model_dir.exists():
        shutil.rmtree(saved_model_dir)
    model.export(str(saved_model_dir))
    converter = tf.lite.TFLiteConverter.from_saved_model(str(saved_model_dir))
    converter.optimizations = [tf.lite.Optimize.DEFAULT]
    tflite_bytes = converter.convert()
    MODEL_PATH.write_bytes(tflite_bytes)
    METADATA_PATH.write_text(
        json.dumps(
            {
                "model_name": "saha_oral_research_screening",
                "labels": list(LABELS),
                "input": [1, IMAGE_SIZE, IMAGE_SIZE, 3],
                "test_accuracy": round(float(test_accuracy), 4),
                "test_loss": round(float(test_loss), 4),
                "dataset_counts": {"cancer": len(cancer), "normal_oral": len(normal), "non_oral": 300},
                "intended_use": "Research oral-lesion screening; requires clinician review and is not a diagnosis.",
            },
            indent=2,
        )
    )
    print(f"Saved {MODEL_PATH} ({len(tflite_bytes) / 1024 / 1024:.1f} MB)")
    print(f"Held-out accuracy: {test_accuracy:.3f}")


if __name__ == "__main__":
    main()
