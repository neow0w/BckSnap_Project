import 'dart:math' as math;

/// Plain geometry for body angles. No plugins, so it is easy to test.
///
/// Points are fractions of the image: x across (0..1), y down (0..1).
/// [aspect] is the image's width divided by its height (for example
/// 1080 / 1920 = 0.5625). x is multiplied by it so that one unit of x and
/// one unit of y are the same length, as in the real picture.
class AngleMath {
  static const double _toDegrees = 180 / math.pi;

  /// The angle (degrees) of the line through A and B against the horizontal.
  /// The line is always read from the image's left end to its right end.
  /// 0 = level. Positive = the image-right end is lower.
  static double lineAngle(
    double ax,
    double ay,
    double bx,
    double by,
    double aspect,
  ) {
    var dx = (bx - ax) * aspect;
    var dy = by - ay;
    if (dx < 0) {
      dx = -dx;
      dy = -dy;
    }
    return math.atan2(dy, dx) * _toDegrees;
  }

  /// The angle (degrees) of the line from the hip midpoint up to the
  /// shoulder midpoint, against the vertical.
  /// 0 = upright. Positive = the shoulders lean toward the image's right.
  static double trunkLean(
    double hipX,
    double hipY,
    double shoulderX,
    double shoulderY,
    double aspect,
  ) {
    final dx = (shoulderX - hipX) * aspect;
    final dy = hipY - shoulderY; // positive when the shoulders are above
    return math.atan2(dx, dy) * _toDegrees;
  }
}
