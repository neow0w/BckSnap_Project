import 'package:flutter_bcksnap/services/angle_math.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const aspect = 9 / 16;

  test('level shoulders give 0 degrees', () {
    expect(AngleMath.lineAngle(0.4, 0.3, 0.6, 0.3, aspect), closeTo(0, 1e-9));
  });

  test('shoulder line, image-right end lower', () {
    expect(
      AngleMath.lineAngle(0.40, 0.30, 0.62, 0.34, aspect),
      closeTo(17.91, 0.05),
    );
  });

  test('the order of the two points does not matter', () {
    final a = AngleMath.lineAngle(0.40, 0.30, 0.62, 0.34, aspect);
    final b = AngleMath.lineAngle(0.62, 0.34, 0.40, 0.30, aspect);
    expect(b, closeTo(a, 1e-9));
  });

  test('hip line, image-right end higher is negative', () {
    expect(
      AngleMath.lineAngle(0.43, 0.70, 0.58, 0.69, aspect),
      closeTo(-6.76, 0.05),
    );
  });

  test('upright trunk is 0, leaning to the image right is positive', () {
    expect(AngleMath.trunkLean(0.5, 0.7, 0.5, 0.3, aspect), closeTo(0, 1e-9));
    expect(
      AngleMath.trunkLean(0.505, 0.695, 0.51, 0.32, aspect),
      closeTo(0.43, 0.05),
    );
    expect(AngleMath.trunkLean(0.5, 0.7, 0.6, 0.3, aspect), greaterThan(0));
  });
}
