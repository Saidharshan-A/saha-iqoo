import 'dart:convert';
import 'dart:js_interop';
import 'dart:typed_data';

// -- JS bindings ---------------------------------------------------------------

@JS('isTfjsAvailable')
external JSBoolean _jsIsTfjsAvailable();

@JS('getTfjsBackend')
external JSString _jsGetTfjsBackend();

@JS('loadOralCancerModel')
external JSPromise<JSBoolean> _jsLoadOralCancerModel(JSString modelUrl);

@JS('runOralCancerInference')
external JSPromise<JSString> _jsRunOralCancerInference(JSString inputJson);

@JS('isOralModelLoaded')
external JSBoolean _jsIsOralModelLoaded();

@JS('loadTbCoughModel')
external JSPromise<JSBoolean> _jsLoadTbCoughModel(JSString modelUrl);

@JS('runTbCoughInference')
external JSPromise<JSString> _jsRunTbCoughInference(JSString inputJson);

@JS('isTbModelLoaded')
external JSBoolean _jsIsTbModelLoaded();

@JS('disposeTfjsModels')
external void _jsDisposeTfjsModels();

// -- Dart bridge singleton -----------------------------------------------------

/// Bridge to TensorFlow.js running in the browser.
class TfjsBridge {
  TfjsBridge._();
  static final instance = TfjsBridge._();

  // -- Cached CAM heatmap data from last inference --

  List<double>? _lastImageHeatmap;
  int _lastImageHeatmapSize = 0;
  bool _imageModelBuilt = false;
  bool _audioModelBuilt = false;
  bool _imageModelMicroTrained = false;
  bool _audioModelMicroTrained = false;

  /// Low-res CAM heatmap from the last [classifyImage] call.
  List<double>? get lastImageHeatmap => _lastImageHeatmap;

  /// Side length of the square heatmap (e.g. 28 for 28x28).
  int get lastImageHeatmapSize => _lastImageHeatmapSize;

  /// Whether the oral cancer model was built in-browser (not loaded from file).
  bool get isImageModelBuiltInBrowser => _imageModelBuilt;

  /// Whether the TB cough model was built in-browser.
  bool get isAudioModelBuiltInBrowser => _audioModelBuilt;

  /// Whether the oral cancer model was micro-trained on synthetic data.
  bool get isImageModelMicroTrained => _imageModelMicroTrained;

  /// Whether the TB model was micro-trained on synthetic data.
  bool get isAudioModelMicroTrained => _audioModelMicroTrained;

  // -- Availability --

  bool get isAvailable {
    try {
      return _jsIsTfjsAvailable().toDart;
    } catch (_) {
      return false;
    }
  }

  String get backend {
    try {
      return _jsGetTfjsBackend().toDart;
    } catch (_) {
      return '';
    }
  }

  // -- Oral Cancer Model --

  bool get isOralModelLoaded {
    try {
      return _jsIsOralModelLoaded().toDart;
    } catch (_) {
      return false;
    }
  }

  Future<bool> loadOralModel([String? modelUrl]) async {
    try {
      final url = (modelUrl ?? 'models/oral_cancer/model.json').toJS;
      final result = await _jsLoadOralCancerModel(url).toDart;
      return result.toDart;
    } catch (e) {
      return false;
    }
  }

  /// Run oral cancer inference. Returns softmax probabilities or null.
  /// Side-effect: stores CAM heatmap in [lastImageHeatmap].
  Future<List<double>?> classifyImage(Float32List input) async {
    try {
      final inputJson = jsonEncode(input.toList());
      final jsResult = await _jsRunOralCancerInference(inputJson.toJS).toDart;
      final resultJson = jsResult.toDart;
      if (resultJson.isEmpty) return null;

      final decoded = jsonDecode(resultJson);

      // New format: JSON object {predictions, heatmap, ...}
      if (decoded is Map<String, dynamic>) {
        final preds = (decoded['predictions'] as List)
            .cast<num>()
            .map((n) => n.toDouble())
            .toList();
        _lastImageHeatmap = null;
        _lastImageHeatmapSize = 0;
        if (decoded['heatmap'] != null) {
          _lastImageHeatmap = (decoded['heatmap'] as List)
              .cast<num>()
              .map((n) => n.toDouble())
              .toList();
          _lastImageHeatmapSize =
              (decoded['heatmapSize'] as num?)?.toInt() ?? 0;
        }
        _imageModelBuilt = decoded['modelBuilt'] == true;
        _imageModelMicroTrained = decoded['microTrained'] == true;
        return preds;
      }

      // Legacy format: JSON array
      if (decoded is List) {
        _lastImageHeatmap = null;
        _lastImageHeatmapSize = 0;
        _imageModelBuilt = false;
        return decoded.cast<num>().map((n) => n.toDouble()).toList();
      }

      return null;
    } catch (e) {
      return null;
    }
  }

  // -- TB Cough Model --

  bool get isTbModelLoaded {
    try {
      return _jsIsTbModelLoaded().toDart;
    } catch (_) {
      return false;
    }
  }

  Future<bool> loadTbModel([String? modelUrl]) async {
    try {
      final url = (modelUrl ?? 'models/tb_cough/model.json').toJS;
      final result = await _jsLoadTbCoughModel(url).toDart;
      return result.toDart;
    } catch (e) {
      return false;
    }
  }

  /// Run TB cough inference. Returns sigmoid probability or null.
  Future<List<double>?> classifyAudio(Float32List input) async {
    try {
      final inputJson = jsonEncode(input.toList());
      final jsResult = await _jsRunTbCoughInference(inputJson.toJS).toDart;
      final resultJson = jsResult.toDart;
      if (resultJson.isEmpty) return null;

      final decoded = jsonDecode(resultJson);

      if (decoded is Map<String, dynamic>) {
        _audioModelBuilt = decoded['modelBuilt'] == true;
        _audioModelMicroTrained = decoded['microTrained'] == true;
        return (decoded['predictions'] as List)
            .cast<num>()
            .map((n) => n.toDouble())
            .toList();
      }

      if (decoded is List) {
        _audioModelBuilt = false;
        return decoded.cast<num>().map((n) => n.toDouble()).toList();
      }

      return null;
    } catch (e) {
      return null;
    }
  }

  // -- Cleanup --

  void dispose() {
    try {
      _jsDisposeTfjsModels();
    } catch (_) {}
    _lastImageHeatmap = null;
    _lastImageHeatmapSize = 0;
    _imageModelBuilt = false;
    _audioModelBuilt = false;
    _imageModelMicroTrained = false;
    _audioModelMicroTrained = false;
  }
}
