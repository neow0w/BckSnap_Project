import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:kwon_mediapipe_landmarker/kwon_mediapipe_landmarker.dart';

/// One detected body point.
class BodyPoint {
  final double x; // 0..1 across the upright image (left to right)
  final double y; // 0..1 down the upright image (top to bottom)
  final double score; // visibility score, 0..1
  const BodyPoint(this.x, this.y, this.score);
}

/// BlazePose landmark numbers (the same 33 points MediaPipe and ML Kit use).
class PoseIndex {
  static const int nose = 0;
  static const int leftEar = 7;
  static const int rightEar = 8;
  static const int leftShoulder = 11;
  static const int rightShoulder = 12;
  static const int leftElbow = 13;
  static const int rightElbow = 14;
  static const int leftHip = 23;
  static const int rightHip = 24;
}

/// The result of analysing one camera frame.
class PoseFrame {
  final List<BodyPoint> points; // empty = nobody detected
  final int millis; // how long the detection took
  const PoseFrame(this.points, this.millis);

  bool get found => points.isNotEmpty;
  BodyPoint? point(int i) => (i >= 0 && i < points.length) ? points[i] : null;
}

/// The only file that knows which pose library is used.
/// To switch to another detector later, only this file changes.
class BodyPoseDetector {
  // Lowered a little because the patient is photographed from behind.
  static const double minDetection = 0.3;
  static const double minTracking = 0.3;

  bool _ready = false;
  bool _busy = false;

  bool get busy => _busy;
  bool get ready => _ready;

  Future<void> start() async {
    if (_ready) return;
    if (!KwonMediapipeLandmarker.isInitialized) {
      await KwonMediapipeLandmarker.initialize(
        face: false,
        pose: true,
        poseOptions: const PoseOptions(
          numPoses: 1,
          minDetectionConfidence: minDetection,
          minTrackingConfidence: minTracking,
        ),
      );
    }
    _ready = true;
  }

  /// Analyses one camera frame. Returns null when it was skipped
  /// because the previous frame is still being processed.
  ///
  /// Normally the frame is analysed at half size (fast, for the live
  /// checker). With [fullSize] the full camera resolution is used
  /// (slower, for the capture burst).
  Future<PoseFrame?> detect(
    CameraImage image,
    int sensorOrientation, {
    bool fullSize = false,
  }) async {
    if (!_ready || _busy) return null;
    if (image.planes.length < 3) {
      throw StateError(
        'Camera frames are not YUV420 (got ${image.planes.length} plane).',
      );
    }

    _busy = true;
    final watch = Stopwatch()..start();
    try {
      final w = image.width;
      final h = image.height;
      final y = image.planes[0];
      final u = image.planes[1];
      final v = image.planes[2];

      final step = fullSize ? 1 : 2;
      final outW = (w ~/ step) & ~1;
      final outH = (h ~/ step) & ~1;

      // WORKAROUND: the plugin's built-in colour conversion mis-reads the
      // U and V planes on most phones (wrong colours). So we build tight
      // planes ourselves and pass a stride that makes the plugin's maths
      // land on the right bytes. Re-check this if the plugin is updated.
      final result = await KwonMediapipeLandmarker.detectFromCamera(
        planes: [
          _shrink(
            y.bytes,
            y.bytesPerRow,
            y.bytesPerPixel ?? 1,
            outW,
            outH,
            step,
          ),
          _shrink(
            u.bytes,
            u.bytesPerRow,
            u.bytesPerPixel ?? 1,
            outW ~/ 2,
            outH ~/ 2,
            step,
          ),
          _shrink(
            v.bytes,
            v.bytesPerRow,
            v.bytesPerPixel ?? 1,
            outW ~/ 2,
            outH ~/ 2,
            step,
          ),
        ],
        width: outW,
        height: outH,
        rotation: sensorOrientation,
        format: 'YUV420',
        bytesPerRow: [outW, outW, outW],
      );
      watch.stop();

      final landmarks = result.pose?.landmarks ?? const <Landmark>[];
      return PoseFrame([
        for (final l in landmarks) BodyPoint(l.x, l.y, l.visibility ?? 0),
      ], watch.elapsedMilliseconds);
    } finally {
      _busy = false;
    }
  }

  Future<void> stop() async {
    _ready = false;
    try {
      await KwonMediapipeLandmarker.dispose();
    } catch (_) {}
  }

  /// Copies every [step]-th sample (in both directions) of a plane into a
  /// tightly packed (outW x outH) plane. With step 1 it is a plain copy
  /// without the row padding. Works for Y and for chroma planes, with or
  /// without interleaved pixels.
  static Uint8List _shrink(
    Uint8List src,
    int rowStride,
    int pixelStride,
    int outW,
    int outH,
    int step,
  ) {
    final out = Uint8List(outW * outH);
    var o = 0;
    for (var r = 0; r < outH; r++) {
      final rowStart = r * step * rowStride;
      for (var c = 0; c < outW; c++) {
        final i = rowStart + c * step * pixelStride;
        out[o++] = i < src.length ? src[i] : 128;
      }
    }
    return out;
  }
}
