import '../../core/utils/logger.dart';

/// Stub for Bhashini VoicERA integration.
///
/// Phase 3 will implement full STT/TTS in 22 Indic languages.
/// For now, provides a voice command interface with basic
/// English and Hindi recognition using on-device speech APIs.
class BhashiniStub {
  BhashiniStub._();

  static final BhashiniStub instance = BhashiniStub._();
  static const _tag = 'Bhashini';

  bool _isListening = false;
  bool get isListening => _isListening;

  /// Supported voice commands (expandable).
  static const Map<String, String> voiceCommands = {
    'next patient': 'navigate_next',
    'previous patient': 'navigate_prev',
    'scan': 'open_scanner',
    'register': 'open_registration',
    'back': 'navigate_back',
    'home': 'navigate_home',
    'sync': 'trigger_sync',
    // Hindi
    'agla mareez': 'navigate_next',
    'pichla mareez': 'navigate_prev',
    'jaanch': 'open_scanner',
    'panjikaran': 'open_registration',
    'peechhe': 'navigate_back',
  };

  /// Start listening for voice commands.
  Future<void> startListening({
    required Function(String command) onCommand,
    String language = 'en-IN',
  }) async {
    if (_isListening) return;
    _isListening = true;

    Log.i('Bhashini listening started ($language)', tag: _tag);

    // TODO: Integrate speech_to_text package
    // final speech = SpeechToText();
    // await speech.listen(
    //   onResult: (result) {
    //     final text = result.recognizedWords.toLowerCase();
    //     final cmd = voiceCommands[text];
    //     if (cmd != null) onCommand(cmd);
    //   },
    //   localeId: language,
    // );
  }

  /// Stop listening.
  Future<void> stopListening() async {
    _isListening = false;
    Log.i('Bhashini listening stopped', tag: _tag);
  }

  /// Speak text aloud using TTS.
  Future<void> speak(String text, {String language = 'en'}) async {
    Log.i('TTS: "$text" ($language)', tag: _tag);

    // TODO: Integrate flutter_tts
    // final tts = FlutterTts();
    // await tts.setLanguage(language == 'hi' ? 'hi-IN' : 'en-IN');
    // await tts.speak(text);
  }
}
