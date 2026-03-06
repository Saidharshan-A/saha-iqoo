/// SAHA — TensorFlow.js Inference Bridge (barrel export).
///
/// Uses conditional export to provide real TF.js interop on web
/// and a no-op stub on mobile/desktop platforms.
export 'tfjs_bridge_stub.dart'
    if (dart.library.js_interop) 'tfjs_bridge_web.dart';
