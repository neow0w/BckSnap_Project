import 'dart:math' as math;

import 'pose_detector.dart';

/// Settings for the capture burst. Tune the numbers here.
class BurstRules {
  // Detections collected before the photo is taken.
  static const int frames = 6;

  // Fewer detections than this means the capture is not reliable.
  static const int minFrames = 4;

  // Analyse the burst at full camera resolution? More detail, but about
  // 3 times slower. The model looks at a small picture anyway.
  static const bool fullSize = false;

  // Above this the patient moved during the burst
  // (standard deviation as a fraction of the image).
  static const double maxSpread = 0.02;

  // Give up on the burst after this long.
  static const int timeoutMs = 5000;
}

/// The body points averaged over a burst of frames.
class AveragedPose {
  final List<BodyPoint>
  points; // averaged landmarks, same numbering as PoseIndex
  final int frames; // how many detections were averaged
  final double spread; // movement of shoulders and hips during the burst
  final double aspect; // width / height of the upright camera image

  const AveragedPose({
    required this.points,
    required this.frames,
    required this.spread,
    this.aspect = 9 / 16,
  });

  BodyPoint? point(int i) => (i >= 0 && i < points.length) ? points[i] : null;
}

/// Collects detections and averages them.
class PoseBurst {
  final List<PoseFrame> _frames = [];

  int get count => _frames.length;

  void add(PoseFrame f) {
    if (f.found) _frames.add(f);
  }

  AveragedPose? average({double aspect = 9 / 16}) {
    if (_frames.isEmpty) return null;
    final n = _frames.length;
    final pointCount = _frames.map((f) => f.points.length).reduce(math.min);

    final points = <BodyPoint>[];
    for (var i = 0; i < pointCount; i++) {
      var sx = 0.0, sy = 0.0, ss = 0.0;
      for (final f in _frames) {
        final p = f.points[i];
        sx += p.x;
        sy += p.y;
        ss += p.score;
      }
      points.add(BodyPoint(sx / n, sy / n, ss / n));
    }

    // Spread: the biggest standard deviation (x and y together)
    // among the shoulders and hips.
    var spread = 0.0;
    for (final i in const [
      PoseIndex.leftShoulder,
      PoseIndex.rightShoulder,
      PoseIndex.leftHip,
      PoseIndex.rightHip,
    ]) {
      if (i >= pointCount) continue;
      final mx = points[i].x;
      final my = points[i].y;
      var v = 0.0;
      for (final f in _frames) {
        final dx = f.points[i].x - mx;
        final dy = f.points[i].y - my;
        v += dx * dx + dy * dy;
      }
      spread = math.max(spread, math.sqrt(v / n));
    }

    return AveragedPose(
      points: points,
      frames: n,
      spread: spread,
      aspect: aspect,
    );
  }
}
