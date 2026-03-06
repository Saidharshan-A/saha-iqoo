/// SAHA application-wide constants.
class AppConstants {
  AppConstants._();

  // ── App Info ──────────────────────────────────────────────
  static const String appName = 'SAHA';
  static const String appVersion = '0.1.0';
  static const String appTagline =
      'Sovereign Autonomous Health Architecture';

  // ── Database ──────────────────────────────────────────────
  static const String dbName = 'saha_secure.db';
  static const int dbVersion = 1;

  // ── Sync Engine ───────────────────────────────────────────
  static const String syncTaskName = 'com.saha.syncTask';
  static const Duration syncInterval = Duration(minutes: 15);
  static const int syncBatchSize = 50;

  /// NHA (National Health Authority) data sync endpoint.
  ///
  /// Production: https://ndhm.gov.in/api/v1
  /// Sandbox: https://healthidsbx.abdm.gov.in/api/v1
  ///
  /// Uses ABDM sandbox for hackathon demo. The sync engine POSTs
  /// queued records here when connectivity is available.
  static const String syncBaseUrl = 'https://healthidsbx.abdm.gov.in/api/v1';

  // ── ABHA ──────────────────────────────────────────────────
  static const String abhaBaseUrl = 'https://healthidsbx.abdm.gov.in/api';
  static const int abhaIdLength = 14;

  // ── Screening Thresholds ──────────────────────────────────
  static const double cancerHighRiskThreshold = 0.70;
  static const double cancerMediumRiskThreshold = 0.40;
  static const double tbPositiveThreshold = 0.60;

  /// Non-Oral class probability above this → reject the image.
  static const double oralCancerRejectThreshold = 0.50;

  /// Max confidence below this → inconclusive result.
  static const double oralCancerInconclusiveThreshold = 0.80;

  /// TB risk tier thresholds (sigmoid output).
  static const double tbLowRiskThreshold = 0.30;
  static const double tbHighRiskThreshold = 0.60;

  // ── Model Paths (assets — TFLite for mobile) ─────────────
  static const String oralCancerModelPath =
      'assets/models/oral_cancer_efficientnetb0.tflite';
  static const String oralCancerLabelsPath =
      'assets/models/labels/oral_cancer_labels.txt';
  static const String tbCoughModelPath =
      'assets/models/tb_cough_classifier.tflite';

  // ── Model Paths (web — TF.js LayersModel) ─────────────────
  static const String oralCancerWebModelPath =
      'models/oral_cancer/model.json';
  static const String tbCoughWebModelPath =
      'models/tb_cough/model.json';

  // ── Image / Audio ─────────────────────────────────────────
  static const int imageInputSize = 224; // EfficientNetB0 input
  static const int audioSampleRate = 16000;
  static const int audioDurationSeconds = 3;
  static const int mfccFeatureCount = 13;
  static const int mfccFrameCount = 99;

  // ── UI ────────────────────────────────────────────────────
  static const double borderRadius = 12.0;
  static const double cardElevation = 2.0;
  static const Duration animDuration = Duration(milliseconds: 300);
}
