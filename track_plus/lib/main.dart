import 'dart:async';
import 'dart:math' as math;

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:sensors_plus/sensors_plus.dart';

import 'signal_estimator.dart';

// THESIS: The phone becomes the instrument; live physical signals lead every screen.
// OWN-WORLD: SAHA navy and teal on clinical white, with saffron/green identity moments.
// STORY: Choose a sensor, follow one placement instruction, watch the signal, receive an estimate.
// FIRST VIEWPORT: Animated SAHA mark resolves into two large measurement actions and a live-status strip.
// FORM: Focused Material 3 field instrument extending SAHA's established Android visual language.

const navy = Color(0xFF071E3D);
const blue = Color(0xFF0A5BD8);
const teal = Color(0xFF008A7C);
const saffron = Color(0xFFFF8A34);
const green = Color(0xFF16823A);
const ink = Color(0xFF10233F);
const canvas = Color(0xFFF4F8FC);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
      systemNavigationBarColor: Colors.transparent,
      systemNavigationBarIconBrightness: Brightness.dark,
    ),
  );
  runApp(const TrackPlusApp());
}

class TrackPlusApp extends StatelessWidget {
  const TrackPlusApp({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = ColorScheme.fromSeed(
      seedColor: blue,
      primary: blue,
      secondary: teal,
      surface: canvas,
      brightness: Brightness.light,
    );
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'SAHA TRACK PLUS',
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: scheme,
        scaffoldBackgroundColor: canvas,
        textTheme: Typography.material2021().black.apply(
          bodyColor: ink,
          displayColor: navy,
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            minimumSize: const Size.fromHeight(56),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
            textStyle: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
      home: const OpeningScreen(),
    );
  }
}

class OpeningScreen extends StatefulWidget {
  const OpeningScreen({super.key});

  @override
  State<OpeningScreen> createState() => _OpeningScreenState();
}

class _OpeningScreenState extends State<OpeningScreen>
    with TickerProviderStateMixin {
  late final AnimationController _spin;
  late final AnimationController _reveal;

  @override
  void initState() {
    super.initState();
    _spin = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    )..repeat();
    _reveal = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..forward();
    Timer(const Duration(milliseconds: 2400), () {
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        PageRouteBuilder<void>(
          pageBuilder: (_, animation, __) => FadeTransition(
            opacity: animation,
            child: const DashboardScreen(),
          ),
          transitionDuration: const Duration(milliseconds: 500),
        ),
      );
    });
  }

  @override
  void dispose() {
    _spin.dispose();
    _reveal.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Color(0xFFFFE1C4),
                  Colors.white,
                  Colors.white,
                  Color(0xFFD9F2DF),
                ],
                stops: [0, .28, .70, 1],
              ),
            ),
          ),
          SafeArea(
            child: FadeTransition(
              opacity: CurvedAnimation(
                parent: _reveal,
                curve: Curves.easeOutCubic,
              ),
              child: Column(
                children: [
                  const Spacer(flex: 3),
                  AnimatedBuilder(
                    animation: _spin,
                    builder: (_, child) => Transform.rotate(
                      angle: _spin.value * math.pi * 2,
                      child: child,
                    ),
                    child: CustomPaint(
                      size: const Size(116, 116),
                      painter: _ChakraPulsePainter(),
                    ),
                  ),
                  const SizedBox(height: 30),
                  const Text(
                    'S.A.H.A.',
                    style: TextStyle(
                      fontSize: 40,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 5,
                      color: navy,
                    ),
                  ),
                  const SizedBox(height: 5),
                  const Text(
                    'TRACK PLUS',
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 4,
                      color: teal,
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Your phone. Two vital signals. Fully on-device.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF43546B),
                    ),
                  ),
                  const Spacer(flex: 3),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 54),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: AnimatedBuilder(
                        animation: _reveal,
                        builder: (_, __) => LinearProgressIndicator(
                          value: _reveal.value,
                          minHeight: 5,
                          backgroundColor: const Color(0xFFDDE6EF),
                          color: blue,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Preparing motion sensors + optical pulse',
                    style: TextStyle(fontSize: 12, color: Color(0xFF5D6D81)),
                  ),
                  const Spacer(),
                  const Text(
                    'OFFLINE  •  PRIVATE  •  MADE FOR BHARAT',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.1,
                      color: navy,
                    ),
                  ),
                  const SizedBox(height: 24),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

enum MeasureMode { chest, pulse }

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  int? chestBpm;
  int? pulseBpm;

  Future<void> _open(MeasureMode mode) async {
    final result = await Navigator.of(context).push<int>(
      MaterialPageRoute(builder: (_) => MeasurementScreen(mode: mode)),
    );
    if (result == null || !mounted) return;
    setState(() {
      if (mode == MeasureMode.chest) chestBpm = result;
      if (mode == MeasureMode.pulse) pulseBpm = result;
    });
  }

  @override
  Widget build(BuildContext context) {
    final bothReady = chestBpm != null && pulseBpm != null;
    return Scaffold(
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 28),
              sliver: SliverList.list(
                children: [
                  Row(
                    children: [
                      Container(
                        width: 46,
                        height: 46,
                        decoration: BoxDecoration(
                          color: navy,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: const Icon(
                          Icons.monitor_heart_rounded,
                          color: Colors.white,
                          size: 27,
                        ),
                      ),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'SAHA TRACK PLUS',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w900,
                                letterSpacing: .4,
                                color: navy,
                              ),
                            ),
                            Text(
                              'On-device vital signal lab',
                              style: TextStyle(
                                fontSize: 12,
                                color: Color(0xFF637389),
                              ),
                            ),
                          ],
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 7,
                        ),
                        decoration: BoxDecoration(
                          color: Color(0xFFDDF5EA),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: const Row(
                          children: [
                            Icon(Icons.lock_rounded, size: 14, color: green),
                            SizedBox(width: 4),
                            Text(
                              'OFFLINE',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w900,
                                color: green,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 28),
                  const Text(
                    'Measure two signals\nwith one phone.',
                    style: TextStyle(
                      fontSize: 34,
                      height: 1.08,
                      fontWeight: FontWeight.w900,
                      letterSpacing: -1,
                      color: navy,
                    ),
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    'Complete each guided reading. SAHA shows real signal quality and only returns a number when the waveform is usable.',
                    style: TextStyle(
                      fontSize: 15,
                      height: 1.45,
                      color: Color(0xFF52647A),
                    ),
                  ),
                  const SizedBox(height: 26),
                  _MeasureTile(
                    color: blue,
                    icon: Icons.vibration_rounded,
                    title: 'Chest heartbeat',
                    subtitle: 'Phone flat on lower chest · stay still',
                    method: 'MOTION SENSOR',
                    value: chestBpm,
                    onTap: () => _open(MeasureMode.chest),
                  ),
                  const SizedBox(height: 14),
                  _MeasureTile(
                    color: teal,
                    icon: Icons.fingerprint_rounded,
                    title: 'Fingertip pulse',
                    subtitle: 'Finger over rear camera + flash',
                    method: 'OPTICAL SENSOR',
                    value: pulseBpm,
                    onTap: () => _open(MeasureMode.pulse),
                  ),
                  const SizedBox(height: 20),
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 350),
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: bothReady ? navy : const Color(0xFFE8EEF5),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: bothReady
                        ? Row(
                            children: [
                              const Icon(
                                Icons.compare_arrows_rounded,
                                color: Colors.white,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  'Signals differ by ${(chestBpm! - pulseBpm!).abs()} BPM',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w800,
                                    fontSize: 16,
                                  ),
                                ),
                              ),
                              const Text(
                                'COMPLETE',
                                style: TextStyle(
                                  color: Color(0xFF8CE3D2),
                                  fontSize: 10,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ],
                          )
                        : const Row(
                            children: [
                              Icon(
                                Icons.insights_rounded,
                                color: Color(0xFF5E7088),
                              ),
                              SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  'Complete both readings to compare the two rates.',
                                  style: TextStyle(
                                    color: Color(0xFF53657B),
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ],
                          ),
                  ),
                  const SizedBox(height: 18),
                  const Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.info_outline_rounded,
                        size: 18,
                        color: Color(0xFF637389),
                      ),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Experimental screening estimates. Not an ECG, stethoscope, diagnosis, or emergency tool.',
                          style: TextStyle(
                            fontSize: 12,
                            height: 1.4,
                            color: Color(0xFF637389),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MeasureTile extends StatelessWidget {
  const _MeasureTile({
    required this.color,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.method,
    required this.value,
    required this.onTap,
  });
  final Color color;
  final IconData icon;
  final String title;
  final String subtitle;
  final String method;
  final int? value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label:
          '$title. ${value == null ? 'Not measured' : '$value beats per minute'}',
      child: Material(
        color: Colors.white,
        elevation: 2,
        shadowColor: navy.withAlpha(24),
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Row(
              children: [
                Container(
                  width: 54,
                  height: 54,
                  decoration: BoxDecoration(
                    color: color.withAlpha(24),
                    borderRadius: BorderRadius.circular(15),
                  ),
                  child: Icon(icon, color: color, size: 29),
                ),
                const SizedBox(width: 15),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        method,
                        style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 1.1,
                          color: color,
                        ),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        title,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          color: navy,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        subtitle,
                        style: const TextStyle(
                          fontSize: 12,
                          height: 1.35,
                          color: Color(0xFF617187),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                value == null
                    ? Icon(Icons.arrow_forward_rounded, color: color)
                    : Column(
                        children: [
                          Text(
                            '$value',
                            style: TextStyle(
                              fontSize: 27,
                              fontWeight: FontWeight.w900,
                              color: color,
                            ),
                          ),
                          const Text(
                            'BPM',
                            style: TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.w900,
                              color: Color(0xFF637389),
                            ),
                          ),
                        ],
                      ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class MeasurementScreen extends StatefulWidget {
  const MeasurementScreen({super.key, required this.mode});
  final MeasureMode mode;

  @override
  State<MeasurementScreen> createState() => _MeasurementScreenState();
}

class _MeasurementScreenState extends State<MeasurementScreen>
    with WidgetsBindingObserver {
  final _clock = Stopwatch();
  final List<TimedSample> _samples = [];
  final List<double> _wave = [];
  final List<double> _candidates = [];
  StreamSubscription<UserAccelerometerEvent>? _accelSub;
  StreamSubscription<GyroscopeEvent>? _gyroSub;
  CameraController? _camera;
  Timer? _ticker;
  Timer? _waveRefresh;
  bool _running = false;
  bool _preparing = false;
  bool _frameBusy = false;
  int _elapsed = 0;
  int? _liveBpm;
  int? _result;
  String _status = 'Ready when you are';
  double _quality = 0;
  double _gyroEnergy = 0;
  int _gyroCount = 0;
  int _lastFrameMs = -100;
  double _brightness = 0;

  bool get _isChest => widget.mode == MeasureMode.chest;
  int get _duration => _isChest ? 28 : 22;
  Color get _accent => _isChest ? blue : teal;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed && _running) {
      _finish(
        cancelled: true,
        message: 'Measurement paused. Return and start again.',
      );
    }
  }

  Future<void> _start() async {
    if (_running || _preparing) return;
    setState(() {
      _preparing = true;
      _result = null;
      _liveBpm = null;
      _elapsed = 0;
      _quality = 0;
      _status = _isChest
          ? 'Starting motion sensors…'
          : 'Starting camera and flash…';
    });
    _samples.clear();
    _wave.clear();
    _candidates.clear();
    _gyroEnergy = 0;
    _gyroCount = 0;
    _brightness = 0;
    try {
      if (_isChest) {
        _startChest();
      } else {
        await _startPulse();
      }
      _clock
        ..reset()
        ..start();
      _ticker = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
      _waveRefresh = Timer.periodic(const Duration(milliseconds: 120), (_) {
        if (mounted && _running) setState(() {});
      });
      if (mounted)
        setState(() {
          _running = true;
          _preparing = false;
          _status = _isChest
              ? 'Place phone flat and keep completely still'
              : 'Cover the camera and flash gently';
        });
    } catch (_) {
      await _disposeSources();
      if (mounted)
        setState(() {
          _preparing = false;
          _running = false;
          _status = _isChest
              ? 'Motion sensor unavailable. Try again.'
              : 'Camera unavailable. Allow camera access and try again.';
        });
    }
  }

  void _startChest() {
    _accelSub =
        userAccelerometerEventStream(
          samplingPeriod: SensorInterval.gameInterval,
        ).listen(
          (event) {
            if (!_clock.isRunning) return;
            final value = math.sqrt(
              event.x * event.x + event.y * event.y + event.z * event.z,
            );
            _addSample(value);
          },
          onError: (_) => _finish(
            cancelled: true,
            message: 'Motion sensor interrupted. Please retry.',
          ),
        );
    _gyroSub = gyroscopeEventStream(samplingPeriod: SensorInterval.gameInterval)
        .listen((event) {
          final magnitude = math.sqrt(
            event.x * event.x + event.y * event.y + event.z * event.z,
          );
          _gyroEnergy += magnitude * magnitude;
          _gyroCount++;
        });
  }

  Future<void> _startPulse() async {
    final cameras = await availableCameras();
    final back = cameras
        .where((camera) => camera.lensDirection == CameraLensDirection.back)
        .first;
    final controller = CameraController(
      back,
      ResolutionPreset.medium,
      enableAudio: false,
      imageFormatGroup: ImageFormatGroup.yuv420,
    );
    await controller.initialize();
    await controller.setFlashMode(FlashMode.torch);
    await controller.startImageStream(_readFrame);
    _camera = controller;
  }

  void _readFrame(CameraImage image) {
    if (_frameBusy || !_clock.isRunning) return;
    final now = _clock.elapsedMilliseconds;
    if (now - _lastFrameMs < 45) return;
    _lastFrameMs = now;
    _frameBusy = true;
    try {
      final plane = image.planes.first;
      final vPlane = image.planes.length > 2 ? image.planes[2] : null;
      final rowStride = plane.bytesPerRow;
      final pixelStride = plane.bytesPerPixel ?? 1;
      final left = image.width ~/ 4;
      final right = image.width * 3 ~/ 4;
      final top = image.height ~/ 4;
      final bottom = image.height * 3 ~/ 4;
      var total = 0;
      var redTotal = 0.0;
      var count = 0;
      for (var y = top; y < bottom; y += 8) {
        for (var x = left; x < right; x += 8) {
          final index = y * rowStride + x * pixelStride;
          if (index < plane.bytes.length) {
            final yValue = plane.bytes[index];
            total += yValue;
            if (vPlane != null) {
              final chromaIndex =
                  (y ~/ 2) * vPlane.bytesPerRow +
                  (x ~/ 2) * (vPlane.bytesPerPixel ?? 1);
              redTotal += chromaIndex < vPlane.bytes.length
                  ? (yValue + 1.402 * (vPlane.bytes[chromaIndex] - 128)).clamp(
                      0,
                      255,
                    )
                  : yValue;
            } else {
              redTotal += yValue;
            }
            count++;
          }
        }
      }
      if (count > 0) {
        _brightness = total / count;
        if (now > 2000) _addSample(redTotal / count);
      }
    } finally {
      _frameBusy = false;
    }
  }

  void _addSample(double value) {
    final now = _clock.elapsedMilliseconds;
    _samples.add(TimedSample(now, value));
    _wave.add(value);
    if (_wave.length > 120) _wave.removeAt(0);
  }

  void _tick() {
    if (!_running) return;
    final elapsed = _clock.elapsed.inSeconds;
    final cutoff = _clock.elapsedMilliseconds - 14000;
    _samples.removeWhere((sample) => sample.timeMs < cutoff);
    SignalEstimate? estimate;
    if (elapsed >= 11)
      estimate = SignalEstimator.estimate(
        _samples,
        minConfidence: _isChest ? .30 : .10,
      );
    final gyroRms = _gyroCount == 0 ? 0.0 : math.sqrt(_gyroEnergy / _gyroCount);
    final placementOk = _isChest ? gyroRms < .32 : _brightness > 5;
    if (estimate != null && placementOk) {
      _candidates.add(estimate.bpm);
      if (_candidates.length > 3) _candidates.removeAt(0);
      final spread = _candidates.isEmpty
          ? 999
          : _candidates.reduce(math.max) - _candidates.reduce(math.min);
      final stable =
          _candidates.length >= (_isChest ? 3 : 1) &&
          spread <= (_isChest ? 9 : 15);
      _liveBpm = estimate.bpm.round();
      _quality = (estimate.confidence * (stable ? 1 : .78)).clamp(0, 1);
      _status = stable
          ? 'Stable rhythm found — keep holding'
          : 'Rhythm found — confirming stability';
    } else {
      _quality = math.max(0, _quality - .08);
      _status = !placementOk
          ? (_isChest
                ? 'Movement detected — relax and hold still'
                : 'Cover both camera and flash completely')
          : (elapsed < 11
                ? 'Calibrating live signal…'
                : 'Signal is weak — adjust placement slightly');
    }
    if (mounted) setState(() => _elapsed = elapsed);
    if (elapsed >= _duration) _finish();
  }

  Future<void> _finish({bool cancelled = false, String? message}) async {
    if (!_running && !_preparing) return;
    _clock.stop();
    _ticker?.cancel();
    _waveRefresh?.cancel();
    final spread = _candidates.length < 3
        ? 999.0
        : _candidates.reduce(math.max) - _candidates.reduce(math.min);
    final stable =
        _candidates.length >= (_isChest ? 3 : 1) &&
        spread <= (_isChest ? 9 : 15);
    final result = !cancelled && stable
        ? (_candidates.reduce((a, b) => a + b) / _candidates.length).round()
        : null;
    await _disposeSources();
    if (!mounted) return;
    setState(() {
      _running = false;
      _preparing = false;
      _result = result;
      _quality = result == null ? 0 : _quality;
      _status =
          message ??
          (result == null
              ? (_isChest
                    ? 'No stable chest signal. Press retry and hold the phone more firmly.'
                    : 'No stable optical pulse. Cover the lens and flash fully, then retry.')
              : 'Measurement complete');
    });
  }

  Future<void> _disposeSources() async {
    await _accelSub?.cancel();
    await _gyroSub?.cancel();
    _accelSub = null;
    _gyroSub = null;
    final controller = _camera;
    _camera = null;
    if (controller != null) {
      try {
        if (controller.value.isStreamingImages)
          await controller.stopImageStream();
        await controller.setFlashMode(FlashMode.off);
      } catch (_) {}
      await controller.dispose();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _clock.stop();
    _ticker?.cancel();
    _waveRefresh?.cancel();
    _accelSub?.cancel();
    _gyroSub?.cancel();
    final controller = _camera;
    if (controller != null) {
      if (controller.value.isStreamingImages) controller.stopImageStream();
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final progress = (_elapsed / _duration).clamp(0.0, 1.0);
    return PopScope(
      canPop: !_running,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _running)
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Stop the measurement before leaving.'),
            ),
          );
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(_isChest ? 'Chest heartbeat' : 'Fingertip pulse'),
          backgroundColor: canvas,
          surfaceTintColor: canvas,
        ),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
            child: Column(
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    child: Column(
                      children: [
                        _SensorStage(
                          mode: widget.mode,
                          accent: _accent,
                          running: _running,
                          camera: _camera,
                        ),
                        const SizedBox(height: 20),
                        Text(
                          _isChest
                              ? 'Place the phone flat on your lower sternum'
                              : 'Rest your fingertip across the rear camera and flash',
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 21,
                            height: 1.2,
                            fontWeight: FontWeight.w900,
                            color: navy,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _isChest
                              ? 'Sit back or lie down. Breathe normally and do not speak.'
                              : 'Press gently. Keep your hand still while the flash reads tiny blood-flow changes.',
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 14,
                            height: 1.45,
                            color: Color(0xFF5A6B80),
                          ),
                        ),
                        const SizedBox(height: 20),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(16),
                            boxShadow: [
                              BoxShadow(
                                color: navy.withAlpha(18),
                                blurRadius: 18,
                                offset: const Offset(0, 6),
                              ),
                            ],
                          ),
                          child: Column(
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        const Text(
                                          'LIVE SIGNAL',
                                          style: TextStyle(
                                            fontSize: 10,
                                            fontWeight: FontWeight.w900,
                                            letterSpacing: 1.1,
                                            color: Color(0xFF65758A),
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          _status,
                                          style: const TextStyle(
                                            fontSize: 13,
                                            fontWeight: FontWeight.w700,
                                            color: ink,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  if (_running || _result != null)
                                    Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.end,
                                      children: [
                                        Text(
                                          '${_result ?? _liveBpm ?? '--'}',
                                          style: TextStyle(
                                            fontSize: 32,
                                            height: 1,
                                            fontWeight: FontWeight.w900,
                                            color: _accent,
                                          ),
                                        ),
                                        const Text(
                                          'BPM',
                                          style: TextStyle(
                                            fontSize: 9,
                                            fontWeight: FontWeight.w900,
                                            color: Color(0xFF65758A),
                                          ),
                                        ),
                                      ],
                                    ),
                                ],
                              ),
                              const SizedBox(height: 15),
                              SizedBox(
                                height: 86,
                                width: double.infinity,
                                child: CustomPaint(
                                  painter: _WavePainter(
                                    values: List.of(_wave),
                                    color: _accent,
                                    active: _running,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 12),
                              ClipRRect(
                                borderRadius: BorderRadius.circular(5),
                                child: LinearProgressIndicator(
                                  value: _result != null ? 1 : progress,
                                  minHeight: 8,
                                  color: _accent,
                                  backgroundColor: _accent.withAlpha(22),
                                ),
                              ),
                              const SizedBox(height: 9),
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    _running
                                        ? '${math.max(0, _duration - _elapsed)} seconds remaining'
                                        : (_result == null
                                              ? '$_duration-second guided reading'
                                              : 'Stable signal accepted'),
                                    style: const TextStyle(
                                      fontSize: 11,
                                      color: Color(0xFF65758A),
                                    ),
                                  ),
                                  Text(
                                    'QUALITY ${(_quality * 100).round()}%',
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w900,
                                      color: _quality > .5
                                          ? green
                                          : const Color(0xFF65758A),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                        const Text(
                          'Experimental estimate only · not for diagnosis or emergencies',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 11,
                            color: Color(0xFF6A7789),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                if (_result != null)
                  FilledButton.icon(
                    onPressed: () => Navigator.pop(context, _result),
                    icon: const Icon(Icons.check_rounded),
                    label: const Text('Save this reading'),
                  )
                else if (_running)
                  FilledButton.tonalIcon(
                    onPressed: () => _finish(
                      cancelled: true,
                      message: 'Measurement stopped. Ready to try again.',
                    ),
                    icon: const Icon(Icons.stop_rounded),
                    label: const Text('Stop measurement'),
                  )
                else
                  FilledButton.icon(
                    onPressed: _preparing ? null : _start,
                    icon: _preparing
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.play_arrow_rounded),
                    label: Text(
                      _status.contains('No stable')
                          ? 'Retry measurement'
                          : 'Start measurement',
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SensorStage extends StatelessWidget {
  const _SensorStage({
    required this.mode,
    required this.accent,
    required this.running,
    required this.camera,
  });
  final MeasureMode mode;
  final Color accent;
  final bool running;
  final CameraController? camera;

  @override
  Widget build(BuildContext context) {
    final cameraReady = camera?.value.isInitialized == true;
    return Center(
      child: Stack(
        alignment: Alignment.center,
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 500),
            width: 176,
            height: 176,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: accent.withAlpha(running ? 22 : 12),
            ),
          ),
          AnimatedContainer(
            duration: const Duration(milliseconds: 500),
            width: 132,
            height: 132,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: accent.withAlpha(running ? 42 : 22),
            ),
          ),
          Container(
            width: 96,
            height: 96,
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(shape: BoxShape.circle, color: accent),
            child: mode == MeasureMode.pulse && cameraReady
                ? ColorFiltered(
                    colorFilter: ColorFilter.mode(
                      accent.withAlpha(90),
                      BlendMode.srcATop,
                    ),
                    child: CameraPreview(camera!),
                  )
                : Icon(
                    mode == MeasureMode.chest
                        ? Icons.vibration_rounded
                        : Icons.fingerprint_rounded,
                    size: 48,
                    color: Colors.white,
                  ),
          ),
          if (running)
            SizedBox(
              width: 160,
              height: 160,
              child: CircularProgressIndicator(
                strokeWidth: 3,
                color: accent,
                backgroundColor: Colors.transparent,
              ),
            ),
        ],
      ),
    );
  }
}

class _WavePainter extends CustomPainter {
  const _WavePainter({
    required this.values,
    required this.color,
    required this.active,
  });
  final List<double> values;
  final Color color;
  final bool active;

  @override
  void paint(Canvas canvas, Size size) {
    final baseline = Paint()
      ..color = const Color(0xFFDCE5EE)
      ..strokeWidth = 1;
    canvas.drawLine(
      Offset(0, size.height / 2),
      Offset(size.width, size.height / 2),
      baseline,
    );
    if (values.length < 3) return;
    final minValue = values.reduce(math.min);
    final maxValue = values.reduce(math.max);
    final range = math.max(0.00001, maxValue - minValue);
    final path = Path();
    for (var i = 0; i < values.length; i++) {
      final x = i * size.width / math.max(1, values.length - 1);
      final normalized = (values[i] - minValue) / range;
      final y = size.height * (.84 - normalized * .68);
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = active ? color : color.withAlpha(120)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.4
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(covariant _WavePainter oldDelegate) => true;
}

class _ChakraPulsePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 4;
    final ring = Paint()
      ..color = navy
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3;
    canvas.drawCircle(center, radius, ring);
    canvas.drawCircle(center, radius * .22, ring);
    for (var i = 0; i < 24; i++) {
      final angle = i * math.pi * 2 / 24;
      canvas.drawLine(
        Offset(
          center.dx + radius * .24 * math.cos(angle),
          center.dy + radius * .24 * math.sin(angle),
        ),
        Offset(
          center.dx + radius * .92 * math.cos(angle),
          center.dy + radius * .92 * math.sin(angle),
        ),
        Paint()
          ..color = navy
          ..strokeWidth = 1.7,
      );
    }
    final pulse = Path()
      ..moveTo(18, center.dy)
      ..lineTo(39, center.dy)
      ..lineTo(48, center.dy - 18)
      ..lineTo(59, center.dy + 19)
      ..lineTo(68, center.dy - 7)
      ..lineTo(77, center.dy)
      ..lineTo(98, center.dy);
    canvas.drawPath(
      pulse,
      Paint()
        ..color = saffron
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
