import 'dart:developer' as developer;

/// Lightweight logger that wraps [developer.log].
///
/// Usage:
/// ```dart
/// Log.i('Patient saved', tag: 'PatientRepo');
/// Log.e('Sync failed', error: e, tag: 'SyncEngine');
/// ```
class Log {
  Log._();

  static const String _defaultTag = 'SAHA';

  /// Info-level log.
  static void i(String message, {String tag = _defaultTag}) {
    developer.log('ℹ️  $message', name: tag);
  }

  /// Debug-level log.
  static void d(String message, {String tag = _defaultTag}) {
    developer.log('🐛 $message', name: tag);
  }

  /// Warning-level log.
  static void w(String message, {String tag = _defaultTag}) {
    developer.log('⚠️  $message', name: tag);
  }

  /// Error-level log.
  static void e(
    String message, {
    String tag = _defaultTag,
    Object? error,
    StackTrace? stackTrace,
  }) {
    developer.log(
      '❌ $message',
      name: tag,
      error: error,
      stackTrace: stackTrace,
    );
  }
}
