import 'dart:typed_data';

/// Stub for non-web platforms. TensorFlow.js is not available.
class TfjsBridge {
  TfjsBridge._();
  static final instance = TfjsBridge._();

  bool get isAvailable => false;
  String get backend => '';

  // ── Heatmap / model-built stubs ─────────────────────────────
  List<double>? get lastImageHeatmap => null;
  int get lastImageHeatmapSize => 0;
  bool get isImageModelBuiltInBrowser => false;
  bool get isAudioModelBuiltInBrowser => false;
  bool get isImageModelMicroTrained => false;
  bool get isAudioModelMicroTrained => false;

  // ── Oral Cancer ─────────────────────────────────────────────
  bool get isOralModelLoaded => false;
  Future<bool> loadOralModel([String? modelUrl]) async => false;
  Future<List<double>?> classifyImage(Float32List input) async => null;

  // ── TB Cough ────────────────────────────────────────────────
  bool get isTbModelLoaded => false;
  Future<bool> loadTbModel([String? modelUrl]) async => false;
  Future<List<double>?> classifyAudio(Float32List input) async => null;

  void dispose() {}
}
