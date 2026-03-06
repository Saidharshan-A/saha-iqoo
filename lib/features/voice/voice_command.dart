import '../../core/utils/logger.dart';

/// Voice command router — maps recognized voice commands
/// to navigation and app actions.
class VoiceCommandRouter {
  VoiceCommandRouter._();

  static const _tag = 'VoiceCmd';

  /// Process a recognized voice command and return the
  /// navigation route or action to execute.
  static String? processCommand(String command) {
    Log.d('Processing voice command: $command', tag: _tag);

    switch (command) {
      case 'navigate_next':
        return '/patients'; // Navigate to patient list
      case 'navigate_prev':
        return null; // Go back
      case 'open_scanner':
        return '/patients'; // Select patient first
      case 'open_registration':
        return '/register';
      case 'navigate_back':
        return null; // Pop
      case 'navigate_home':
        return '/';
      case 'trigger_sync':
        return 'ACTION_SYNC';
      default:
        Log.w('Unknown voice command: $command', tag: _tag);
        return null;
    }
  }
}
