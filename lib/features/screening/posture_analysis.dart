import '../../services/angle_math.dart';
import '../../services/pose_burst.dart';
import '../../services/pose_detector.dart';

/// Settings for the photo posture analysis. Tune the numbers here.
class PostureRules {
  // Shoulder tilt that is flagged as "noticeable". 15 degrees is the value
  // used in the reference paper (Hustinawaty et al., 2025). It is NOT
  // clinically validated, so the app uses it as supporting information only.
  static const double shoulderTiltFlag = 15.0;

  // The paper gives no limit for the hips. Same value as a starting point.
  static const double hipTiltFlag = 15.0;

  // A landmark must score at least this to be used.
  static const double minScore = 0.5;

  // Below this a line counts as level, and the trunk as upright (degrees).
  static const double levelTolerance = 1.0;
}

/// Which side of the PATIENT is higher.
enum HigherSide { left, right, level }

String higherSideLabel(HigherSide s) => switch (s) {
  HigherSide.left => 'left',
  HigherSide.right => 'right',
  HigherSide.level => 'level',
};

/// Which side of the PATIENT the shoulders lean toward.
enum LeanSide { left, right, upright }

String leanSideLabel(LeanSide s) => switch (s) {
  LeanSide.left => 'left',
  LeanSide.right => 'right',
  LeanSide.upright => 'upright',
};

/// Shoulder, hip and trunk angles from the averaged landmarks of the back
/// photo. It assumes the patient has their BACK to the camera, so the
/// patient's left side appears on the right of the image.
class PostureAnalysis {
  final double shoulderTilt; // degrees, 0..90
  final double hipTilt; // degrees, 0..90
  final HigherSide higherShoulder;
  final HigherSide higherHip;
  final double trunkLean; // degrees from the vertical, 0..90
  final LeanSide leanSide;

  // Signed shoulder angle minus signed hip angle: how far the two lines are
  // from being parallel (degrees).
  final double shoulderHipDifference;

  final int frames; // detections averaged
  final double steadiness; // movement during the burst (fraction of image)

  const PostureAnalysis({
    required this.shoulderTilt,
    required this.hipTilt,
    required this.higherShoulder,
    required this.higherHip,
    required this.trunkLean,
    required this.leanSide,
    required this.shoulderHipDifference,
    required this.frames,
    required this.steadiness,
  });

  bool get shoulderFlag => shoulderTilt >= PostureRules.shoulderTiltFlag;
  bool get hipFlag => hipTilt >= PostureRules.hipTiltFlag;

  // The trunk lean is shown but not flagged: it does not change the result.
  bool get flagged => shoulderFlag || hipFlag;

  Map<String, dynamic> toJson() => {
    'shoulder_tilt': shoulderTilt,
    'hip_tilt': hipTilt,
    'trunk_lean': trunkLean,
    'higher_shoulder': higherShoulder.name,
    'higher_hip': higherHip.name,
    'lean_side': leanSide.name,
  };

  /// Returns null when the photo cannot be trusted: no landmarks, the photo
  /// failed the quality check, the patient moved, or the points were weak.
  static PostureAnalysis? from(AveragedPose? pose, {required bool reliable}) {
    if (pose == null || !reliable) return null;
    if (pose.frames < BurstRules.minFrames ||
        pose.spread > BurstRules.maxSpread) {
      return null;
    }

    final ls = pose.point(PoseIndex.leftShoulder);
    final rs = pose.point(PoseIndex.rightShoulder);
    final lh = pose.point(PoseIndex.leftHip);
    final rh = pose.point(PoseIndex.rightHip);
    if (ls == null || rs == null || lh == null || rh == null) return null;
    for (final p in [ls, rs, lh, rh]) {
      if (p.score < PostureRules.minScore) return null;
    }

    final aspect = pose.aspect;

    // Shoulder line and hip line, against the horizontal.
    final shoulderSigned = AngleMath.lineAngle(ls.x, ls.y, rs.x, rs.y, aspect);
    final hipSigned = AngleMath.lineAngle(lh.x, lh.y, rh.x, rh.y, aspect);

    // Trunk: from the hip midpoint to the shoulder midpoint, against the vertical.
    final sx = (ls.x + rs.x) / 2;
    final sy = (ls.y + rs.y) / 2;
    final hx = (lh.x + rh.x) / 2;
    final hy = (lh.y + rh.y) / 2;
    final trunkSigned = AngleMath.trunkLean(hx, hy, sx, sy, aspect);

    return PostureAnalysis(
      shoulderTilt: shoulderSigned.abs(),
      hipTilt: hipSigned.abs(),
      higherShoulder: _higher(shoulderSigned),
      higherHip: _higher(hipSigned),
      trunkLean: trunkSigned.abs(),
      leanSide: _lean(trunkSigned),
      shoulderHipDifference: shoulderSigned - hipSigned,
      frames: pose.frames,
      steadiness: pose.spread,
    );
  }

  // Positive angle = the image-right end is lower = the image-left end is
  // higher. Back view: the image's left side is the patient's RIGHT side.
  static HigherSide _higher(double signedAngle) {
    if (signedAngle.abs() < PostureRules.levelTolerance) {
      return HigherSide.level;
    }
    return signedAngle > 0 ? HigherSide.right : HigherSide.left;
  }

  // Positive angle = the shoulders lean toward the image's right
  // = the patient's LEFT side (back view).
  static LeanSide _lean(double signedAngle) {
    if (signedAngle.abs() < PostureRules.levelTolerance) {
      return LeanSide.upright;
    }
    return signedAngle > 0 ? LeanSide.left : LeanSide.right;
  }
}
