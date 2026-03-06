import 'package:flutter/material.dart';

/// A dropdown selector for supported languages.
///
/// Phase 3 will integrate Bhashini TTS/STT for 22 Indic languages.
/// For now, this provides a visual placeholder with English and Hindi.
class LanguageSelector extends StatefulWidget {
  const LanguageSelector({super.key, this.onChanged});

  final ValueChanged<String>? onChanged;

  @override
  State<LanguageSelector> createState() => _LanguageSelectorState();
}

class _LanguageSelectorState extends State<LanguageSelector> {
  String _selected = 'en';

  static const _languages = {
    'en': 'English',
    'hi': 'हिन्दी',
    'ta': 'தமிழ்',
    'te': 'తెలుగు',
    'bn': 'বাংলা',
    'mr': 'मराठी',
    'gu': 'ગુજરાતી',
    'kn': 'ಕನ್ನಡ',
    'ml': 'മലയാളം',
    'pa': 'ਪੰਜਾਬੀ',
    'od': 'ଓଡ଼ିଆ',
    'as': 'অসমীয়া',
  };

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      initialValue: _selected,
      tooltip: 'Change language',
      onSelected: (value) {
        setState(() => _selected = value);
        widget.onChanged?.call(value);
      },
      itemBuilder: (_) => _languages.entries
          .map((e) => PopupMenuItem(
                value: e.key,
                child: Text(e.value),
              ))
          .toList(),
      child: Chip(
        avatar: const Icon(Icons.translate, size: 16),
        label: Text(_languages[_selected] ?? 'English'),
      ),
    );
  }
}
