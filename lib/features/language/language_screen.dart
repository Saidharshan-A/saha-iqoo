import 'package:flutter/material.dart';

import '../voice/bhashini_service.dart';

/// Bhashini 22-Language selector screen — allows FHWs to switch
/// the app UI language to any of the 22 scheduled Indian languages.
///
/// Features:
///   - Language selection grid with native script names
///   - Live translation preview panel
///   - TTS (Text-to-Speech) demo button
///   - Translation demo for key healthcare phrases
class LanguageScreen extends StatefulWidget {
  const LanguageScreen({super.key});

  @override
  State<LanguageScreen> createState() => _LanguageScreenState();
}

class _LanguageScreenState extends State<LanguageScreen> {
  final _bhashini = BhashiniService.instance;
  bool _isSpeaking = false;

  // Healthcare phrases to demonstrate translations
  static const _demoKeys = [
    'app_title',
    'register_patient',
    'oral_cancer_scan',
    'tb_cough_test',
    'screening_result',
    'risk_high',
    'risk_low',
    'refer_hospital',
    'save',
    'search',
  ];

  @override
  Widget build(BuildContext context) {
    final current = _bhashini.currentLocale.languageCode;
    final currentLang = BhashiniService.supportedLanguages
        .firstWhere((l) => l.code == current,
            orElse: () =>
                const BhashiniLanguage('en', 'English', 'English', 'en-IN'));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Bhashini — 22 Languages'),
        actions: [
          // TTS Demo button
          IconButton(
            icon: Icon(_isSpeaking ? Icons.stop_circle : Icons.volume_up),
            tooltip: _isSpeaking ? 'Stop' : 'Speak in ${currentLang.englishName}',
            onPressed: () async {
              if (_isSpeaking) {
                await _bhashini.stopSpeaking();
                setState(() => _isSpeaking = false);
              } else {
                setState(() => _isSpeaking = true);
                final text = _bhashini.t('app_title');
                await _bhashini.speak(text);
                if (mounted) setState(() => _isSpeaking = false);
              }
            },
          ),
        ],
      ),
      body: Column(
        children: [
          // Header with Digital India branding
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [Colors.orange.shade100, Colors.green.shade50],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.translate, size: 32, color: Colors.deepOrange),
                    const SizedBox(width: 8),
                    const Text(
                      'Digital India Bhashini',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  '22 Scheduled Indian Languages \u2022 Voice + Text',
                  style: TextStyle(color: Colors.grey.shade700, fontSize: 12),
                ),
                const SizedBox(height: 8),
                // Current language chip
                Chip(
                  avatar: CircleAvatar(
                    backgroundColor: Colors.deepOrange,
                    child: Text(
                      currentLang.code.toUpperCase().substring(
                          0, currentLang.code.length > 2 ? 3 : 2),
                      style: const TextStyle(
                          color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold),
                    ),
                  ),
                  label: Text(
                    '${currentLang.nativeName} (${currentLang.englishName})',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  backgroundColor: Colors.orange.shade200,
                ),
              ],
            ),
          ),

          // Translation preview panel
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            color: Colors.indigo.shade50,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.preview, size: 18, color: Colors.indigo),
                    const SizedBox(width: 6),
                    Text(
                      'Live Translation Preview \u2014 ${currentLang.englishName}',
                      style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                          color: Colors.indigo),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: _demoKeys.map((key) {
                    final translated = _bhashini.t(key);
                    return Chip(
                      label: Text(translated, style: const TextStyle(fontSize: 11)),
                      backgroundColor: Colors.white,
                      side: BorderSide(color: Colors.indigo.shade200),
                      visualDensity: VisualDensity.compact,
                    );
                  }).toList(),
                ),
              ],
            ),
          ),

          // Language grid
          Expanded(
            child: GridView.builder(
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                childAspectRatio: 2.8,
                crossAxisSpacing: 8,
                mainAxisSpacing: 8,
              ),
              itemCount: BhashiniService.supportedLanguages.length,
              padding: const EdgeInsets.all(12),
              itemBuilder: (_, i) {
                final lang = BhashiniService.supportedLanguages[i];
                final isSelected = lang.code == current;
                return InkWell(
                  onTap: () {
                    _bhashini.setLocale(lang.code);
                    setState(() {});
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                            'Language: ${lang.englishName} (${lang.nativeName})'),
                        duration: const Duration(seconds: 1),
                        behavior: SnackBarBehavior.floating,
                      ),
                    );
                  },
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      color: isSelected
                          ? Colors.deepOrange.shade100
                          : Colors.grey.shade50,
                      border: Border.all(
                        color: isSelected
                            ? Colors.deepOrange
                            : Colors.grey.shade300,
                        width: isSelected ? 2 : 1,
                      ),
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    child: Row(
                      children: [
                        CircleAvatar(
                          radius: 16,
                          backgroundColor: isSelected
                              ? Colors.deepOrange
                              : Colors.grey.shade300,
                          child: Text(
                            lang.code.toUpperCase().substring(
                                0, lang.code.length > 2 ? 3 : 2),
                            style: TextStyle(
                              color: isSelected
                                  ? Colors.white
                                  : Colors.grey.shade700,
                              fontWeight: FontWeight.bold,
                              fontSize: 10,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                lang.nativeName,
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14,
                                  color: isSelected
                                      ? Colors.deepOrange.shade800
                                      : Colors.black87,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                              Text(
                                lang.englishName,
                                style: TextStyle(
                                  fontSize: 11,
                                  color: Colors.grey.shade600,
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (isSelected)
                          const Icon(Icons.check_circle,
                              color: Colors.deepOrange, size: 20),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),

          // Bottom bar with STT/TTS capabilities
          Container(
            padding: const EdgeInsets.all(12),
            color: Colors.grey.shade100,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _capabilityChip(Icons.record_voice_over, 'TTS',
                    'Text-to-Speech in ${currentLang.englishName}'),
                _capabilityChip(Icons.mic, 'STT',
                    'Voice commands in ${currentLang.englishName}'),
                _capabilityChip(Icons.g_translate, 'NMT',
                    'Neural Machine Translation'),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _capabilityChip(IconData icon, String label, String tooltip) {
    return Tooltip(
      message: tooltip,
      child: Chip(
        avatar: Icon(icon, size: 16, color: Colors.deepOrange),
        label: Text(label, style: const TextStyle(fontSize: 11)),
        visualDensity: VisualDensity.compact,
        backgroundColor: Colors.white,
      ),
    );
  }
}
