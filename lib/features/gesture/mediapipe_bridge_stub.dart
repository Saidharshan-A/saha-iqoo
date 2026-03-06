/// Stub for non-web platforms. MediaPipe is not available.
class MediaPipeBridge {
  MediaPipeBridge._();
  static final instance = MediaPipeBridge._();

  bool get isAvailable => false;
  bool get isActive => false;
  void start() {}
  void stop() {}
  List<List<double>>? getLandmarks() => null;
  String get handedness => '';
}
