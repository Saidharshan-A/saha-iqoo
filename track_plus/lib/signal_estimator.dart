import 'dart:math' as math;

class TimedSample {
  const TimedSample(this.timeMs, this.value);
  final int timeMs;
  final double value;
}

class SignalEstimate {
  const SignalEstimate({
    required this.bpm,
    required this.confidence,
    required this.sampleRate,
  });
  final double bpm;
  final double confidence;
  final double sampleRate;
}

/// Finds the dominant pulse period using normalized autocorrelation.
class SignalEstimator {
  static SignalEstimate? estimate(
    List<TimedSample> input, {
    double minBpm = 40,
    double maxBpm = 180,
    double minConfidence = 0.34,
  }) {
    if (input.length < 80) return null;
    final duration = (input.last.timeMs - input.first.timeMs) / 1000;
    if (duration < 8) return null;
    final sampleRate = (input.length - 1) / duration;
    if (sampleRate < 12) return null;

    final raw = input.map((sample) => sample.value).toList(growable: false);
    final mean = raw.reduce((a, b) => a + b) / raw.length;
    final centered = raw.map((value) => value - mean).toList(growable: false);
    final baselineWindow = math.max(5, (sampleRate * 1.4).round());
    final detrended = List<double>.filled(centered.length, 0);
    var rolling = 0.0;
    for (var i = 0; i < centered.length; i++) {
      rolling += centered[i];
      if (i >= baselineWindow) rolling -= centered[i - baselineWindow];
      final count = math.min(i + 1, baselineWindow);
      detrended[i] = centered[i] - rolling / count;
    }

    final smooth = List<double>.filled(detrended.length, 0);
    for (var i = 0; i < detrended.length; i++) {
      var total = 0.0;
      var count = 0;
      for (var j = math.max(0, i - 2); j <= i; j++) {
        total += detrended[j];
        count++;
      }
      smooth[i] = total / count;
    }
    final energy = smooth.fold<double>(0, (sum, value) => sum + value * value);
    if (energy <= 1e-9) return null;

    final minLag = math.max(2, (sampleRate * 60 / maxBpm).round());
    final maxLag = math.min(
      smooth.length ~/ 2,
      (sampleRate * 60 / minBpm).round(),
    );
    var bestLag = 0;
    var bestCorrelation = -1.0;
    for (var lag = minLag; lag <= maxLag; lag++) {
      var numerator = 0.0;
      var leftEnergy = 0.0;
      var rightEnergy = 0.0;
      for (var i = lag; i < smooth.length; i++) {
        final left = smooth[i];
        final right = smooth[i - lag];
        numerator += left * right;
        leftEnergy += left * left;
        rightEnergy += right * right;
      }
      final denominator = math.sqrt(leftEnergy * rightEnergy);
      if (denominator == 0) continue;
      final correlation = numerator / denominator;
      if (correlation > bestCorrelation) {
        bestCorrelation = correlation;
        bestLag = lag;
      }
    }
    if (bestLag == 0 || bestCorrelation < minConfidence) return null;
    final bpm = 60 * sampleRate / bestLag;
    if (bpm < minBpm || bpm > maxBpm) return null;
    return SignalEstimate(
      bpm: bpm,
      confidence: bestCorrelation.clamp(0, 1),
      sampleRate: sampleRate,
    );
  }
}
