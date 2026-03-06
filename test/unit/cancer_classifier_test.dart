import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:saha/features/screening/cancer/services/cancer_classifier.dart';

void main() {
  group('CancerClassifier', () {
    final classifier = CancerClassifier.instance;

    setUpAll(() async {
      await classifier.loadModel();
    });

    test('classify should return 3 labels', () async {
      final dummy = Uint8List(224 * 224 * 3);
      final results = await classifier.classify(dummy);
      expect(results.length, 3);
      expect(results.containsKey('Cancer'), true);
      expect(results.containsKey('Normal Oral'), true);
      expect(results.containsKey('Non-Oral'), true);
    });

    test('probabilities should sum to ~1.0', () async {
      final dummy = Uint8List(224 * 224 * 3);
      final results = await classifier.classify(dummy);
      final sum = results.values.reduce((a, b) => a + b);
      expect(sum, closeTo(1.0, 0.01));
    });

    test('getRiskLevel returns valid level', () {
      expect(
        classifier.getRiskLevel({'Cancer': 0.1, 'Normal Oral': 0.8, 'Non-Oral': 0.1}),
        'low',
      );
      expect(
        classifier.getRiskLevel({'Cancer': 0.75, 'Normal Oral': 0.15, 'Non-Oral': 0.1}),
        'high',
      );
    });
  });
}
