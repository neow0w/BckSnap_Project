import 'dart:async';
import 'dart:math' as math;

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:sensors_plus/sensors_plus.dart';

import '../../services/pose_detector.dart';
import '../../services/screening_draft.dart';
import 'back_guide.dart';
import 'guide_checker.dart';
import 'photo_quality.dart';
import '../../services/pose_burst.dart';

enum _CamState { checking, needsPermission, blocked, noCamera, error, ready }

class CameraCaptureScreen extends StatefulWidget {
  const CameraCaptureScreen({super.key});

  @override
  State<CameraCaptureScreen> createState() => _CameraCaptureScreenState();
}

class _CameraCaptureScreenState extends State<CameraCaptureScreen>
    with WidgetsBindingObserver {
  CameraController? _controller;
  _CamState _state = _CamState.checking;
  String? _errorText;
  Uint8List? _captured; // set while the user is reviewing the photo
  bool _capturing = false;
  bool _starting = false;

  // Pose detection and the live guideline checker
  final BodyPoseDetector _detector = BodyPoseDetector();
  final GuideChecker _checker = GuideChecker();
  final ValueNotifier<GuideStatus?> _status = ValueNotifier<GuideStatus?>(null);
  String? _detectorError;
  int _lastRunMs = 0;
  final List<PoseFrame> _recent = [];
  final List<GuideStatus> _recentStatus = [];
  PhotoQuality? _quality;

  // Capture burst
  PoseBurst? _burst; // set while the burst is being collected
  final ValueNotifier<int> _burstCount = ValueNotifier<int>(0);

  // How the phone is held (from the accelerometer)
  StreamSubscription<AccelerometerEvent>? _accelSub;
  PhoneTilt? _tilt;
  int _lastTiltMs = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _listenTilt();
    _start(request: true);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _accelSub?.cancel();
    _controller?.dispose();
    _detector.stop();
    _status.dispose();
    _burstCount.dispose();
    super.dispose();
  }

  // Release the camera when the app goes to the background and
  // check again when it comes back (for example from Settings).
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused) {
      final c = _controller;
      if (c != null) {
        _controller = null;
        c.dispose(); // also stops the frame stream
        _clearLive();
        if (mounted && _captured == null) {
          setState(() => _state = _CamState.checking);
        }
      }
    } else if (state == AppLifecycleState.resumed) {
      if (_controller == null && _captured == null) _start();
    }
  }

  void _clearLive() {
    _status.value = null;
    _recent.clear();
    _recentStatus.clear();
    _checker.reset();
  }

  // ---- phone tilt -----------------------------------------------------------

  void _listenTilt() {
    try {
      _accelSub = accelerometerEventStream().listen((e) {
        final now = DateTime.now().millisecondsSinceEpoch;
        if (now - _lastTiltMs < 80) return;
        _lastTiltMs = now;

        // 0 degrees = phone upright in portrait, screen facing the user.
        final roll = math.atan2(e.x, e.y) * 180 / math.pi;
        final pitch =
            math.atan2(e.z, math.sqrt(e.x * e.x + e.y * e.y)) * 180 / math.pi;

        final old = _tilt;
        _tilt = old == null
            ? PhoneTilt(roll, pitch)
            : PhoneTilt(
                old.rollDeg * 0.7 + roll * 0.3,
                old.pitchDeg * 0.7 + pitch * 0.3,
              );
      }, onError: (_) {});
    } catch (_) {
      // No accelerometer: the "Level" check is simply skipped.
    }
  }

  // ---- camera start ---------------------------------------------------------

  /// [request] = true shows the system permission dialog (only on first
  /// open or when the user taps "Allow camera").
  Future<void> _start({bool request = false}) async {
    if (_starting) return;
    _starting = true;
    try {
      var status = await Permission.camera.status;
      if (!status.isGranted && request && !status.isPermanentlyDenied) {
        status = await Permission.camera.request();
      }
      if (!mounted) return;

      if (status.isPermanentlyDenied || status.isRestricted) {
        setState(() => _state = _CamState.blocked);
      } else if (!status.isGranted) {
        setState(() => _state = _CamState.needsPermission);
      } else {
        await _initCamera();
      }
    } finally {
      _starting = false;
    }
  }

  Future<void> _initCamera() async {
    try {
      final cameras = await availableCameras();
      final back = cameras.where(
        (c) => c.lensDirection == CameraLensDirection.back,
      );
      if (back.isEmpty) {
        if (mounted) setState(() => _state = _CamState.noCamera);
        return;
      }

      final controller = CameraController(
        back.first,
        ResolutionPreset.high,
        enableAudio: false,
        // The pose detector reads 3-plane YUV420 frames on Android.
        imageFormatGroup: defaultTargetPlatform == TargetPlatform.android
            ? ImageFormatGroup.yuv420
            : ImageFormatGroup.bgra8888,
      );
      await controller.initialize();
      await controller.lockCaptureOrientation(DeviceOrientation.portraitUp);

      if (!mounted) {
        await controller.dispose();
        return;
      }
      _controller?.dispose();
      _clearLive();
      setState(() {
        _controller = controller;
        _state = _CamState.ready;
      });
      _startAnalysis(controller);
    } on CameraException catch (e) {
      if (!mounted) return;
      setState(() {
        _state = _CamState.error;
        _errorText = e.description ?? e.code;
      });
    }
  }

  // ---- pose detection on live frames ----------------------------------------

  Future<void> _startAnalysis(CameraController c) async {
    try {
      await _detector.start();
      if (!mounted || _controller != c) return;
      if (c.value.isStreamingImages) return;
      await c.startImageStream(_onFrame);
      if (mounted && _detectorError != null) {
        setState(() => _detectorError = null);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _detectorError = e.toString());
    }
  }

  Future<void> _onFrame(CameraImage image) async {
    final c = _controller;
    if (c == null || _captured != null) return;

    final burst = _burst;
    if (_capturing && burst == null) return; // the photo is being taken

    // Live checking: at most 5 analyses per second.
    // During the burst: as fast as the detector allows, at full resolution.
    final now = DateTime.now().millisecondsSinceEpoch;
    if (_detector.busy) return;
    if (burst == null && now - _lastRunMs < 200) return;
    _lastRunMs = now;

    try {
      final frame = await _detector.detect(
        image,
        c.description.sensorOrientation,
        fullSize: burst != null && BurstRules.fullSize,
      );
      if (!mounted || frame == null || _controller != c) return;

      if (burst != null) {
        burst.add(frame);
        _burstCount.value = burst.count;
        return;
      }

      final status = _checker.update(
        frame,
        tilt: _tilt,
        aspect: 1 / c.value.aspectRatio,
      );
      _status.value = status;
      _recent.add(frame);
      _recentStatus.add(status);
      if (_recent.length > QualityRules.windowFrames) _recent.removeAt(0);
      if (_recentStatus.length > QualityRules.windowFrames) {
        _recentStatus.removeAt(0);
      }
    } catch (e) {
      if (mounted && _detectorError == null) {
        setState(() => _detectorError = e.toString());
      }
    }
  }

  // ---- capture --------------------------------------------------------------

  /// Shown only after the user taps the shutter too early.
  void _showUnmetRequirements(GuideStatus? status) {
    final unmet = status?.items.where((item) => !item.ok).toList() ?? [];

    final messages = unmet.map((item) {
      switch (item.label) {
        case 'Person':
          return 'Make sure the patient is visible.';
        case 'Visible':
          return 'Make sure the shoulders and hips are clearly visible.';
        case 'Facing':
          return 'Ask the patient to face away from the camera.';
        case 'Distance':
          return 'Adjust the distance between the patient and camera.';
        case 'Height':
          return 'Adjust the patient’s position in the frame.';
        case 'Centered':
          return 'Center the patient and keep the whole back in frame.';
        case 'Level':
          return 'Hold the phone upright and level.';
        case 'Still':
          return 'Ask the patient to hold still.';
        default:
          return item.problem ?? item.label;
      }
    }).toList();

    if (status == null) {
      messages.add('Point the camera at the patient’s back.');
    } else if (status.allOk && !status.ready) {
      messages.add('Hold still for a moment, then try again.');
    }

    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Please complete the requirements'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: messages
              .map(
                (message) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text('• $message'),
                ),
              )
              .toList(),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  Future<void> _capture() async {
    final c = _controller;
    if (c == null || !c.value.isInitialized || _capturing) return;

    final status = _status.value;
    if (status?.ready != true) {
      _showUnmetRequirements(status);
      return;
    }
    setState(() => _capturing = true);

    // Judge the live frames first (before they are cleared).
    final live = PhotoQuality.assess(
      List<PoseFrame>.of(_recent),
      List<GuideStatus>.of(_recentStatus),
    );

    try {
      // 1. Short burst: collect detections while the patient holds still.
      AveragedPose? averaged;
      if (_detector.ready && c.value.isStreamingImages) {
        averaged = await _collectBurst();
      }

      // 2. Then take the photo.
      if (c.value.isStreamingImages) await c.stopImageStream();
      final file = await c.takePicture();
      final bytes = await file.readAsBytes();
      if (!mounted) return;
      _clearLive();
      setState(() {
        _captured = bytes;
        _quality = live.withBurst(averaged);
      });
    } on CameraException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not take the photo: ${e.description ?? e.code}'),
        ),
      );
      _startAnalysis(c); // go back to live detection
    } finally {
      if (mounted) setState(() => _capturing = false);
    }
  }

  /// Collects detections for a moment and returns their average.
  Future<AveragedPose?> _collectBurst() async {
    final burst = PoseBurst();
    _burstCount.value = 0;
    _burst = burst;
    final deadline =
        DateTime.now().millisecondsSinceEpoch + BurstRules.timeoutMs;
    try {
      while (burst.count < BurstRules.frames &&
          DateTime.now().millisecondsSinceEpoch < deadline &&
          mounted) {
        await Future.delayed(const Duration(milliseconds: 40));
      }
    } finally {
      _burst = null;
    }
    final c = _controller;
    final aspect = c == null ? 9 / 16 : 1 / c.value.aspectRatio;
    return burst.average(aspect: aspect);
  }

  void _continue() {
    ScreeningDraft.photoBytes = _captured;
    ScreeningDraft.photoName = 'back_photo.jpg';
    ScreeningDraft.landmarks = _quality?.burst;
    ScreeningDraft.photoQualityGood = _quality?.good ?? false;
    context.go('/screening/steps/scoliometer');
  }

  void _retake() {
    _clearLive();
    setState(() {
      _captured = null;
      _quality = null;
    });
    final c = _controller;
    if (c == null) {
      _start();
    } else {
      _startAnalysis(c);
    }
  }

  // ---- UI -------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Take Back Photo'),
        leading: BackButton(
          onPressed: () => context.go('/screening/steps/pose'),
        ),
      ),
      body: SafeArea(child: _captured != null ? _buildReview() : _buildBody()),
    );
  }

  Widget _buildBody() {
    switch (_state) {
      case _CamState.checking:
        return const Center(child: CircularProgressIndicator());
      case _CamState.needsPermission:
        return _message(
          icon: Icons.camera_alt_outlined,
          title: 'Camera access needed',
          text:
              'The app uses the camera to photograph the back for screening. '
              'The photo is saved only to your account.',
          primaryLabel: 'Allow camera',
          onPrimary: () => _start(request: true),
        );
      case _CamState.blocked:
        return _message(
          icon: Icons.no_photography_outlined,
          title: 'Camera is blocked',
          text:
              'Camera permission was turned off. Open the app settings, '
              'tap Permissions, and allow Camera.',
          primaryLabel: 'Open settings',
          onPrimary: openAppSettings,
        );
      case _CamState.noCamera:
        return _message(
          icon: Icons.videocam_off_outlined,
          title: 'No camera found',
          text: 'This device has no back camera.',
        );
      case _CamState.error:
        return _message(
          icon: Icons.error_outline,
          title: 'Camera problem',
          text: _errorText ?? 'The camera could not be started.',
          primaryLabel: 'Try again',
          onPrimary: () => _start(request: true),
        );
      case _CamState.ready:
        return _buildPreview();
    }
  }

  Widget _message({
    required IconData icon,
    required String title,
    required String text,
    String? primaryLabel,
    VoidCallback? onPrimary,
  }) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 72),
            const SizedBox(height: 16),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(text, textAlign: TextAlign.center),
            const SizedBox(height: 24),
            if (primaryLabel != null)
              FilledButton(onPressed: onPrimary, child: Text(primaryLabel)),
          ],
        ),
      ),
    );
  }

  Widget _buildPreview() {
    final c = _controller!;
    return Column(
      children: [
        // Only a real detector failure is shown here, never the requirements.
        if (_detectorError != null)
          Container(
            width: double.infinity,
            color: Colors.red.shade700,
            padding: const EdgeInsets.all(8),
            child: Text(
              'Pose detector problem: $_detectorError',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.white, fontSize: 12),
            ),
          ),
        Expanded(
          child: Center(
            child: AspectRatio(
              aspectRatio: 1 / c.value.aspectRatio,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  CameraPreview(c),
                  // The outline: white until every requirement is met and
                  // the person is inside the guide, then green.
                  ValueListenableBuilder<GuideStatus?>(
                    valueListenable: _status,
                    builder: (context, st, _) => IgnorePointer(
                      child: CustomPaint(
                        painter: AlignmentOverlayPainter(
                          color: (st?.allOk ?? false)
                              ? Colors.greenAccent
                              : Colors.white,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(12),
          child: ValueListenableBuilder<GuideStatus?>(
            valueListenable: _status,
            builder: (context, st, _) => SizedBox(
              width: 72,
              height: 72,
              child: FilledButton(
                style: FilledButton.styleFrom(
                  shape: const CircleBorder(),
                  padding: EdgeInsets.zero,
                  backgroundColor: (st?.ready ?? false) ? Colors.green : null,
                ),
                onPressed: _capturing ? null : _capture,
                child: _capturing
                    ? ValueListenableBuilder<int>(
                        valueListenable: _burstCount,
                        builder: (context, n, _) => SizedBox(
                          width: 28,
                          height: 28,
                          child: CircularProgressIndicator(
                            strokeWidth: 3,
                            color: Colors.white,
                            value: (n / BurstRules.frames).clamp(0.0, 1.0),
                          ),
                        ),
                      )
                    : const Icon(Icons.camera_alt, size: 32),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildReview() {
    final q = _quality;
    final good = q?.good ?? false;

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (q != null)
            ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.sizeOf(context).height * 0.28,
              ),
              child: SingleChildScrollView(child: _qualityCard(q)),
            ),
          const SizedBox(height: 8),
          const Text(
            'Is the image clear and within the guidelines?',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Expanded(child: Image.memory(_captured!, fit: BoxFit.contain)),
          const SizedBox(height: 12),
          if (good) ...[
            FilledButton(
              onPressed: _continue,
              child: const Text('Yes, continue'),
            ),
            const SizedBox(height: 12),
            OutlinedButton(onPressed: _retake, child: const Text('No, retake')),
          ] else ...[
            FilledButton(onPressed: _retake, child: const Text('Retake photo')),
          ],
        ],
      ),
    );
  }

  Widget _qualityCard(PhotoQuality q) {
    final color = q.good ? Colors.green : Colors.orange;
    return Card(
      color: color.withValues(alpha: 0.15),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  q.good ? Icons.check_circle : Icons.warning_amber_rounded,
                  color: color,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    q.good
                        ? 'Quality check passed'
                        : 'Image quality is low: retake recommended',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            for (final p in q.problems)
              Padding(
                padding: const EdgeInsets.only(top: 4, left: 32),
                child: Text('• $p'),
              ),
            Padding(
              padding: const EdgeInsets.only(top: 6, left: 32),
              child: Text(
                'Landmark score: ${(q.averageScore * 100).round()}%  (${q.frames} frames)',
                style: const TextStyle(fontSize: 12),
              ),
            ),
            if (q.burst != null)
              Padding(
                padding: const EdgeInsets.only(top: 2, left: 32),
                child: Text(
                  'Steadiness: ${(q.burst!.spread * 100).toStringAsFixed(1)}% movement  '
                  '(${q.burst!.frames} frames averaged)',
                  style: const TextStyle(fontSize: 12),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
