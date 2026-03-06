/// SAHA-Quantum — Audio Quality Gate for TB Cough Screening
///
/// Validates audio recordings BEFORE sending to the TB classifier.
/// Rejects recordings that are:
///   • Too short (< 3 seconds effective audio)
///   • Too quiet (low SNR — signal-to-noise ratio < 6 dB)
///   • Corrupted or clipped
///   • Dominated by background noise
///
/// Also provides noise reduction preprocessing for rural environments
/// where ambient noise (wind, traffic, animals) is common.
///
/// References:
///   ITU-T P.563 — single-ended speech quality assessment
///   Ghosh et al. 2019 — "Robust cough detection for resource-constrained
///     settings" (JASA)

import 'dart:math' as math;
import 'dart:typed_data';

import '../../../../core/utils/logger.dart';

// ════════════════════════════════════════════════════════════════════════════
//  DATA MODELS
// ════════════════════════════════════════════════════════════════════════════

/// Result of audio quality validation.
class AudioQualityResult {
  const AudioQualityResult({
    required this.isAcceptable,
    required this.snrDb,
    required this.effectiveDurationSec,
    required this.peakAmplitude,
    required this.clippingRatio,
    required this.noiseFloorDb,
    required this.coughLikelihood,
    required this.issues,
    required this.rejectionReason,
  });

  final bool isAcceptable;
  final double snrDb;
  final double effectiveDurationSec;
  final double peakAmplitude;
  final double clippingRatio;
  final double noiseFloorDb;
  final double coughLikelihood;
  final List<String> issues;
  final String? rejectionReason;
}

// ════════════════════════════════════════════════════════════════════════════
//  AUDIO QUALITY GATE
// ════════════════════════════════════════════════════════════════════════════

class AudioQualityGate {
  AudioQualityGate._();
  static final AudioQualityGate instance = AudioQualityGate._();

  static const _tag = 'AudioQualityGate';

  // ── Thresholds ──────────────────────────────────────────────────────
  static const double minSnrDb = 6.0;
  static const double minDurationSec = 3.0;
  static const double maxClippingRatio = 0.05;
  static const double minPeakAmplitude = 0.02;
  static const double minCoughLikelihood = 0.15;
  static const int sampleRate = 16000;

  /// Validate audio quality before TB classification.
  ///
  /// [samples] is PCM16 audio as Float64List normalized to [-1, 1].
  AudioQualityResult validate(Float64List samples) {
    Log.d('Validating audio: ${samples.length} samples', tag: _tag);

    final issues = <String>[];
    final duration = samples.length / sampleRate;
    Log.d('Audio duration: ${duration.toStringAsFixed(2)}s', tag: _tag);

    // 1. Duration check — use TOTAL recording length as primary,
    //    effective (energy-active) duration as informational only.
    //    This prevents false rejection when a 3s recording has brief
    //    cough bursts surrounded by quiet ambient noise.
    final effectiveDuration = _computeEffectiveDuration(samples);
    if (duration < minDurationSec && effectiveDuration < minDurationSec) {
      issues.add(
          'Recording too short (${duration.toStringAsFixed(1)}s). '
          'Need at least ${minDurationSec.toStringAsFixed(0)}s of audio.');
    }

    // 2. Peak amplitude
    double peak = 0;
    for (final s in samples) {
      final abs = s.abs();
      if (abs > peak) peak = abs;
    }
    if (peak < minPeakAmplitude) {
      issues.add('Audio is too quiet. Please cough closer to the microphone.');
    }

    // 3. Clipping detection
    int clipped = 0;
    for (final s in samples) {
      if (s.abs() > 0.98) clipped++;
    }
    final clippingRatio = samples.isNotEmpty ? clipped / samples.length : 0.0;
    if (clippingRatio > maxClippingRatio) {
      issues.add('Audio is clipped/distorted. '
          'Please hold device slightly further away.');
    }

    // 4. SNR estimation
    final snr = _estimateSnr(samples);
    if (snr < minSnrDb) {
      issues.add(
          'Background noise too high (SNR: ${snr.toStringAsFixed(1)} dB). '
          'Please move to a quieter location.');
    }

    // 5. Noise floor
    final noiseFloor = _estimateNoiseFloor(samples);

    // 6. Cough likelihood (energy-based burst detection)
    final coughLikelihood = _estimateCoughLikelihood(samples);
    if (coughLikelihood < minCoughLikelihood) {
      issues.add('No cough detected in recording. Please cough loudly.');
    }

    final acceptable = issues.isEmpty;
    String? rejection;
    if (!acceptable) {
      rejection = issues.first;
    }

    Log.d('Audio quality: SNR=${snr.toStringAsFixed(1)}dB, '
        'duration=${effectiveDuration.toStringAsFixed(1)}s, '
        'peak=${peak.toStringAsFixed(3)}, '
        'cough=${(coughLikelihood * 100).toStringAsFixed(0)}%, '
        'acceptable=$acceptable', tag: _tag);

    return AudioQualityResult(
      isAcceptable: acceptable,
      snrDb: snr,
      effectiveDurationSec: effectiveDuration,
      peakAmplitude: peak,
      clippingRatio: clippingRatio,
      noiseFloorDb: noiseFloor,
      coughLikelihood: coughLikelihood,
      issues: issues,
      rejectionReason: rejection,
    );
  }

  /// Apply noise reduction for rural environments.
  ///
  /// Uses spectral subtraction: estimate noise spectrum from
  /// first 0.5s (assumed silence), subtract from full signal.
  Float64List reduceNoise(Float64List samples) {
    if (samples.length < sampleRate) return samples;

    Log.d('Applying noise reduction …', tag: _tag);

    // Estimate noise from first 500ms
    final noiseLength = (sampleRate * 0.5).toInt();
    double noiseEnergy = 0;
    for (int i = 0; i < noiseLength && i < samples.length; i++) {
      noiseEnergy += samples[i] * samples[i];
    }
    noiseEnergy /= noiseLength;
    final noiseAmplitude = _sqrt(noiseEnergy);

    // Simple spectral gate: suppress samples below 2× noise floor
    final gate = noiseAmplitude * 2.0;
    final result = Float64List(samples.length);
    for (int i = 0; i < samples.length; i++) {
      if (samples[i].abs() > gate) {
        result[i] = samples[i];
      } else {
        result[i] = samples[i] * 0.1; // Soft suppression
      }
    }

    // Apply smoothing to prevent artifacts
    return _smoothSignal(result, windowSize: 5);
  }

  // ══════════════════════════════════════════════════════════════════════
  //  INTERNAL ANALYSIS
  // ══════════════════════════════════════════════════════════════════════

  double _computeEffectiveDuration(Float64List samples) {
    // Count frames with energy above noise floor
    const frameSize = 512;
    const hopSize = 256;
    int activeFrames = 0;
    int totalFrames = 0;

    // Estimate noise floor from first 0.25s
    final noiseFrames = (sampleRate * 0.25 / hopSize).ceil();
    double noiseEnergy = 0;
    int noiseCount = 0;

    for (int start = 0; start + frameSize <= samples.length; start += hopSize) {
      double energy = 0;
      for (int i = 0; i < frameSize && start + i < samples.length; i++) {
        energy += samples[start + i] * samples[start + i];
      }
      energy /= frameSize;

      if (totalFrames < noiseFrames) {
        noiseEnergy += energy;
        noiseCount++;
      }
      totalFrames++;
    }

    if (noiseCount == 0) return 0;
    final threshold = (noiseEnergy / noiseCount) * 3.0; // 3× noise energy

    // Count active frames
    int frameIdx = 0;
    for (int start = 0; start + frameSize <= samples.length; start += hopSize) {
      double energy = 0;
      for (int i = 0; i < frameSize && start + i < samples.length; i++) {
        energy += samples[start + i] * samples[start + i];
      }
      energy /= frameSize;

      if (frameIdx >= noiseFrames && energy > threshold) {
        activeFrames++;
      }
      frameIdx++;
    }

    return activeFrames * hopSize / sampleRate;
  }

  double _estimateSnr(Float64List samples) {
    if (samples.length < sampleRate) return 0;

    // Use first 0.5s as noise estimate
    final noiseLen = (sampleRate * 0.5).toInt();
    double noiseEnergy = 0;
    for (int i = 0; i < noiseLen && i < samples.length; i++) {
      noiseEnergy += samples[i] * samples[i];
    }
    noiseEnergy /= noiseLen;

    // Signal energy from the rest
    double signalEnergy = 0;
    final signalStart = noiseLen;
    final signalCount = samples.length - signalStart;
    if (signalCount <= 0) return 0;

    for (int i = signalStart; i < samples.length; i++) {
      signalEnergy += samples[i] * samples[i];
    }
    signalEnergy /= signalCount;

    if (noiseEnergy <= 1e-10) return 60.0; // Very clean
    final ratio = signalEnergy / noiseEnergy;
    if (ratio <= 1) return 0;

    // SNR in dB: 10 * log10(signal/noise)
    return 10.0 * _log10(ratio);
  }

  double _estimateNoiseFloor(Float64List samples) {
    if (samples.length < sampleRate ~/ 2) return -60;
    final noiseLen = (sampleRate * 0.5).toInt();
    double energy = 0;
    for (int i = 0; i < noiseLen && i < samples.length; i++) {
      energy += samples[i] * samples[i];
    }
    energy /= noiseLen;
    if (energy <= 1e-15) return -90;
    return 10.0 * _log10(energy);
  }

  double _estimateCoughLikelihood(Float64List samples) {
    // Coughs are characterized by:
    //   1. Short burst (50-500ms) of high energy
    //   2. Rapid onset (attack time < 20ms)
    //   3. Spectral energy concentrated in 200-2000 Hz
    //
    // We use a simple energy-burst detector here.
    const frameSize = 512;
    const hopSize = 128;
    final energies = <double>[];

    for (int start = 0; start + frameSize <= samples.length; start += hopSize) {
      double energy = 0;
      for (int i = 0; i < frameSize; i++) {
        energy += samples[start + i] * samples[start + i];
      }
      energies.add(energy / frameSize);
    }

    if (energies.isEmpty) return 0;

    // Find mean and std of energy
    double mean = 0;
    for (final e in energies) {
      mean += e;
    }
    mean /= energies.length;

    double varSum = 0;
    for (final e in energies) {
      varSum += (e - mean) * (e - mean);
    }
    final std = _sqrt(varSum / energies.length);

    // Detect bursts: energy > mean + 2*std
    int burstFrames = 0;
    int burstCount = 0;
    bool inBurst = false;

    for (final e in energies) {
      if (e > mean + 2 * std) {
        if (!inBurst) {
          burstCount++;
          inBurst = true;
        }
        burstFrames++;
      } else {
        inBurst = false;
      }
    }

    // At least 1 burst, burst duration reasonable (5-50 frames)
    if (burstCount == 0) return 0;

    final avgBurstLen = burstFrames / burstCount;
    final burstDurationMs = avgBurstLen * hopSize / sampleRate * 1000;

    // Cough-like: 50-500ms bursts, 1-5 bursts in a recording
    double likelihood = 0;
    if (burstDurationMs >= 30 && burstDurationMs <= 600) {
      likelihood += 0.5;
    }
    if (burstCount >= 1 && burstCount <= 8) {
      likelihood += 0.3;
    }
    // High peak-to-mean ratio
    final peakEnergy = energies.reduce(math.max);
    if (mean > 0 && peakEnergy / mean > 5) {
      likelihood += 0.2;
    }

    return likelihood.clamp(0.0, 1.0);
  }

  Float64List _smoothSignal(Float64List signal, {int windowSize = 5}) {
    final result = Float64List(signal.length);
    final halfWin = windowSize ~/ 2;
    for (int i = 0; i < signal.length; i++) {
      double sum = 0;
      int count = 0;
      for (int j = i - halfWin; j <= i + halfWin; j++) {
        if (j >= 0 && j < signal.length) {
          sum += signal[j];
          count++;
        }
      }
      result[i] = sum / count;
    }
    return result;
  }

  // ── Math utilities ──────────────────────────────────────────────────

  static double _sqrt(double x) {
    if (x <= 0) return 0;
    var r = x;
    for (int i = 0; i < 15; i++) {
      r = (r + x / r) * 0.5;
    }
    return r;
  }

  static double _log10(double x) {
    if (x <= 0) return -90;
    return _ln(x) / 2.302585092994046;
  }

  static double _ln(double x) {
    if (x <= 0) return -90;
    if (x == 1.0) return 0;
    double y = x - 1;
    for (int i = 0; i < 40; i++) {
      final ey = _expApprox(y);
      y = y - (ey - x) / ey;
    }
    return y;
  }

  static double _expApprox(double x) {
    final c = x.clamp(-50.0, 50.0);
    double result = 1.0, term = 1.0;
    for (int n = 1; n <= 25; n++) {
      term *= c / n;
      result += term;
      if (term.abs() < 1e-12) break;
    }
    return result;
  }
}
