import 'dart:math' as math;

import '../../services/pose_detector.dart';
import 'back_guide.dart';

/// How strict each check is. Positions are fractions of the preview (0..1).
/// All the numbers live here so you can tune them in one place.
class GuideRules {
  // A landmark must score at least this to count as "visible".
  static const double minScore = 0.5;

  // Distance: the shoulders-to-hips height should match the guide.
  static const double spanTarget = BackGuide.hipY - BackGuide.shoulderY;
  static const double spanTol = 0.08;

  // Height and centering of the torso inside the preview.
  static const double midYTarget = (BackGuide.shoulderY + BackGuide.hipY) / 2;
  static const double midYTol = 0.08;
  static const double centerTol = 0.08;

  // All four torso points must stay inside the guide box (with a margin).
  static const double boxMargin = 0.01;

  // Facing: shoulder width divided by torso height. Squarely facing the
  // camera (front or back) I expect about 0.7 to 0.9, turned 45 degrees
  // about 0.55, sideways close to 0. Confirm with the numbers on screen.
  static const double minWidthRatio = 0.5;

  // Phone held upright, in degrees.
  static const double rollTol = 4;
  static const double pitchTol = 6;

  // Hold still: maximum movement between two results (fraction of preview).
  static const double stillTol = 0.015;

  // Everything must stay OK for this long before we say "ready".
  static const int holdMs = 800;

  // A short glitch (less than this) does not restart the hold timer.
  static const int graceMs = 400;
}

/// How the phone is held, in degrees (0 = perfectly upright).
class PhoneTilt {
  final double rollDeg; // leaning left or right
  final double pitchDeg; // leaning forward or back
  const PhoneTilt(this.rollDeg, this.pitchDeg);
}

class CheckItem {
  final String label;
  final bool ok;
  final String? problem; // what went wrong, in plain words (null when OK)
  const CheckItem(this.label, this.ok, [this.problem]);
}

class GuideStatus {
  final List<CheckItem> items;
  final String hint; // what the user should do next
  final bool allOk; // every check passes right now
  final double progress; // 0..1, how long everything has been OK
  final bool ready; // OK for long enough: good moment to take the photo

  // For tuning only (shown in the small grey line):
  final double widthRatio; // shoulder width / torso height
  final double noseScore; // nose visibility, 0..1
  final bool leftOnImageLeft; // left shoulder drawn left of the right shoulder

  const GuideStatus({
    required this.items,
    required this.hint,
    required this.allOk,
    required this.progress,
    required this.ready,
    this.widthRatio = 0,
    this.noseScore = 0,
    this.leftOnImageLeft = false,
  });
}

/// Decides, from the detected body points and the phone's tilt, whether the
/// patient is inside the guidelines. Call [update] for every analysed frame.
class GuideChecker {
  List<double>?
  _smooth; // smoothed [x,y] of: L shoulder, R shoulder, L hip, R hip
  List<double>? _prev;
  int? _okSince;
  int? _failSince;

  void reset() {
    _smooth = null;
    _prev = null;
    _okSince = null;
    _failSince = null;
  }

  GuideStatus update(
    PoseFrame frame, {
    PhoneTilt? tilt,
    double aspect = 9 / 16, // upright image width / height
  }) {
    final now = DateTime.now().millisecondsSinceEpoch;

    final pts = [
      frame.point(PoseIndex.leftShoulder),
      frame.point(PoseIndex.rightShoulder),
      frame.point(PoseIndex.leftHip),
      frame.point(PoseIndex.rightHip),
    ];

    final personOk = frame.found && pts.every((p) => p != null);
    final shouldersVisible =
        personOk &&
        pts[0]!.score >= GuideRules.minScore &&
        pts[1]!.score >= GuideRules.minScore;
    final hipsVisible =
        personOk &&
        pts[2]!.score >= GuideRules.minScore &&
        pts[3]!.score >= GuideRules.minScore;
    final visibleOk = shouldersVisible && hipsVisible;

    var insideOk = false;
    var distanceOk = false;
    var heightOk = false;
    var centerOk = false;
    var stillOk = false;
    var span = 0.0;
    var facingOk = false;
    var widthRatio = 0.0;
    var leftOnImageLeft = false;
    var midX = 0.0;
    var midY = 0.0;

    if (visibleOk) {
      // Smooth the points a little so the checks do not flicker.
      final cur = [
        for (final p in pts) ...[p!.x, p.y],
      ];
      _prev = _smooth;
      final old = _smooth;
      _smooth = old == null
          ? cur
          : [for (var k = 0; k < 8; k++) old[k] * 0.5 + cur[k] * 0.5];
      final s = _smooth!;

      final shoulderMidX = (s[0] + s[2]) / 2;
      final shoulderMidY = (s[1] + s[3]) / 2;
      final hipMidX = (s[4] + s[6]) / 2;
      final hipMidY = (s[5] + s[7]) / 2;

      final box = BackGuide.box;
      const m = GuideRules.boxMargin;
      insideOk = true;
      for (var k = 0; k < 8; k += 2) {
        if (s[k] < box.left + m ||
            s[k] > box.right - m ||
            s[k + 1] < box.top + m ||
            s[k + 1] > box.bottom - m) {
          insideOk = false;
        }
      }

      span = hipMidY - shoulderMidY;
      // Facing: how wide do the shoulders look compared with the torso
      // height? A patient turned sideways looks narrow. Both are measured
      // in the same units (x is multiplied by the image's width/height).
      widthRatio = span > 0 ? ((s[0] - s[2]).abs() * aspect) / span : 0;
      facingOk = widthRatio >= GuideRules.minWidthRatio;
      leftOnImageLeft = s[0] < s[2];
      distanceOk = (span - GuideRules.spanTarget).abs() <= GuideRules.spanTol;

      // Facing: how wide do the shoulders look compared with the torso
      // height? A patient turned sideways looks narrow. Both are measured
      // in the same units (x is multiplied by the image's width/height).
      widthRatio = span > 0 ? ((s[0] - s[2]).abs() * aspect) / span : 0;
      facingOk = widthRatio >= GuideRules.minWidthRatio;
      leftOnImageLeft = s[0] < s[2];

      midY = (shoulderMidY + hipMidY) / 2;
      heightOk = (midY - GuideRules.midYTarget).abs() <= GuideRules.midYTol;

      midX = (shoulderMidX + hipMidX) / 2;
      centerOk = (midX - BackGuide.centerX).abs() <= GuideRules.centerTol;

      final prev = _prev;
      if (prev != null) {
        var maxMove = 0.0;
        for (var k = 0; k < 8; k += 2) {
          final dx = s[k] - prev[k];
          final dy = s[k + 1] - prev[k + 1];
          maxMove = math.max(maxMove, math.sqrt(dx * dx + dy * dy));
        }
        stillOk = maxMove <= GuideRules.stillTol;
      }
    } else {
      _smooth = null;
      _prev = null;
    }

    final tiltOk =
        tilt == null ||
        (tilt.rollDeg.abs() <= GuideRules.rollTol &&
            tilt.pitchDeg.abs() <= GuideRules.pitchTol);

    final allOk =
        personOk &&
        visibleOk &&
        facingOk &&
        insideOk &&
        distanceOk &&
        heightOk &&
        centerOk &&
        tiltOk &&
        stillOk;

    // How long has everything been OK? Short glitches are forgiven.
    if (allOk) {
      _okSince ??= now;
      _failSince = null;
    } else {
      _failSince ??= now;
      if (now - _failSince! > GuideRules.graceMs) _okSince = null;
    }
    final held = _okSince == null ? 0 : now - _okSince!;
    final ready = allOk && held >= GuideRules.holdMs;
    final progress = allOk ? (held / GuideRules.holdMs).clamp(0.0, 1.0) : 0.0;

    // The one thing to tell the user, most important first.
    String hint;
    if (!personOk) {
      hint = "Point the phone at the patient's back";
    } else if (!facingOk) {
      hint = 'Ask the patient to stand square to the camera, back facing you';
    } else if (!distanceOk) {
      if (!shouldersVisible && !hipsVisible) {
        hint = 'Shoulders and hips are not clear';
      } else if (!shouldersVisible) {
        hint = 'Shoulders are not clear: check the lighting';
      } else {
        hint = 'Hips are not clear: step back so they fit';
      }
    } else if (!facingOk) {
      hint = 'Ask the patient to stand square to the camera, back facing you';
    } else if (!distanceOk) {
      hint = span < GuideRules.spanTarget ? 'Move closer' : 'Step back';
    } else if (!heightOk) {
      // Person too high in the picture means the phone must go up.
      hint = midY < GuideRules.midYTarget
          ? 'Raise the phone'
          : 'Lower the phone';
    } else if (!centerOk) {
      // Person left of centre means the phone must move left.
      hint = midX < BackGuide.centerX
          ? 'Move the phone left'
          : 'Move the phone right';
    } else if (!insideOk) {
      hint = 'Keep the whole back inside the frame';
    } else if (!tiltOk) {
      hint = 'Hold the phone upright and level';
    } else if (!stillOk) {
      hint = 'Hold still';
    } else if (!ready) {
      hint = 'Hold still...';
    } else {
      hint = 'Perfect! Take the photo';
    }

    return GuideStatus(
      items: [
        CheckItem(
          'Person',
          personOk,
          personOk ? null : 'The patient was not in view',
        ),
        CheckItem('Visible', visibleOk),
        CheckItem(
          'Facing',
          facingOk,
          !visibleOk || facingOk ? null : 'The patient was turned sideways',
        ),
        CheckItem(
          'Distance',
          distanceOk,
          !visibleOk || distanceOk
              ? null
              : (span < GuideRules.spanTarget
                    ? 'The patient was too far away'
                    : 'The patient was too close'),
        ),
        CheckItem(
          'Height',
          heightOk,
          !visibleOk || heightOk
              ? null
              : (midY < GuideRules.midYTarget
                    ? 'The patient was too high in the frame'
                    : 'The patient was too low in the frame'),
        ),
        CheckItem(
          'Centered',
          centerOk && insideOk,
          !visibleOk || (centerOk && insideOk)
              ? null
              : (insideOk
                    ? 'The patient was off-center'
                    : 'The back was not fully inside the guide frame'),
        ),
        CheckItem(
          'Level',
          tiltOk,
          tiltOk ? null : 'The phone was not held upright and level',
        ),
        CheckItem('Still', stillOk),
      ],
      hint: hint,
      allOk: allOk,
      progress: progress,
      ready: ready,
      widthRatio: widthRatio,
      noseScore: frame.point(PoseIndex.nose)?.score ?? 0,
      leftOnImageLeft: leftOnImageLeft,
    );
  }
}
