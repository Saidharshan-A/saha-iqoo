import 'package:go_router/go_router.dart';

import '../../core/utils/logger.dart';
import 'hand_tracker.dart';

/// Maps detected hand gestures to GoRouter navigation actions.
class GestureNav {
  GestureNav._();

  static const _tag = 'GestureNav';

  /// Convert a gesture into a navigation command.
  static void handleGesture(GestureType gesture, GoRouter router) {
    Log.d('Gesture detected: ${gesture.name}', tag: _tag);

    switch (gesture) {
      case GestureType.swipeLeft:
        // Navigate forward in patient list
        router.push('/patients');
        break;
      case GestureType.swipeRight:
        // Navigate back
        router.pop();
        break;
      case GestureType.thumbsUp:
        // Confirm action (no-op without context)
        break;
      case GestureType.openPalm:
        // Go back
        router.pop();
        break;
      case GestureType.fist:
        // Go home
        router.go('/');
        break;
      case GestureType.scrollUp:
        // Scroll up — handled at widget level, no-op here
        break;
      case GestureType.scrollDown:
        // Scroll down — handled at widget level, no-op here
        break;
      case GestureType.unknown:
        break;
    }
  }
}
