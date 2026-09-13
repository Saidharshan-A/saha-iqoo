import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:saha_track_plus/signal_estimator.dart';

void main() {
  test('recovers a clean 72 BPM waveform', () {
    const sampleRate = 30.0;
    final samples = List.generate(360, (index) {
      final seconds = index / sampleRate;
      return TimedSample(
        (seconds * 1000).round(),
        math.sin(2 * math.pi * 1.2 * seconds) +
            0.08 * math.sin(2 * math.pi * 5 * seconds),
      );
    });
    final estimate = SignalEstimator.estimate(samples);
    expect(estimate, isNotNull);
    expect(estimate!.bpm, closeTo(72, 2));
  });

  test('rejects a flat signal', () {
    final samples = List.generate(360, (index) => TimedSample(index * 33, 1));
    expect(SignalEstimator.estimate(samples), isNull);
  });
}
