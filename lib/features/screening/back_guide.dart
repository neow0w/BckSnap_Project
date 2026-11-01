import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Where the back should sit in the camera preview.
/// All values are fractions of the preview (0.0 to 1.0), so they work on
/// any screen size. The live checker uses these same numbers, so moving
/// them here moves the guide and the checks together.
///
/// To make the guide bigger or smaller: keep the middle of the two Y values
/// where you want the torso, and widen or narrow the gap between them.
class BackGuide {
  // The four torso points must stay inside this box (used by the checker).
  static const Rect box = Rect.fromLTRB(0.15, 0.08, 0.85, 0.92);

  static const double centerX = 0.5;

  // The shoulder joints and the hip joints of the silhouette.
  // The gap between them (here 0.435) sets the size of the whole figure:
  // with a 16:9 camera picture the arms then reach to about 6% from the
  // side edges.
  static const double shoulderY = 0.41;
  static const double hipY = 0.845;

  // Half-widths of the joints, in "torso units" (1.0 = the distance from
  // the shoulder line to the hip line).
  static const double shoulderHalf = 0.38;
  static const double hipHalf = 0.32;

  // Darken everything outside the silhouette, like a stencil.
  static const bool dimOutside = false;

  // Dash pattern of the outline, in pixels.
  static const double dashLength = 14;
  static const double dashGap = 9;
}

/// Draws a person-shaped guide, upper body only (head to hips), back view,
/// with a broken (dashed) outline. The patient should stand so that their
/// shoulders and hips land on the four dots. [color] changes to green when
/// the position matches.
class AlignmentOverlayPainter extends CustomPainter {
  final Color color;
  const AlignmentOverlayPainter({this.color = Colors.white});

  @override
  void paint(Canvas canvas, Size size) {
    final cx = BackGuide.centerX * size.width;
    final shoulderPx = BackGuide.shoulderY * size.height;
    final t = (BackGuide.hipY - BackGuide.shoulderY) * size.height;

    // A point in torso units: x to the right of the centre line, y down
    // from the shoulder line. 1.0 = the shoulder-to-hip distance in pixels.
    Offset p(double x, double y) => Offset(cx + x * t, shoulderPx + y * t);

    final shapes = _shapes(p, t);

    if (BackGuide.dimOutside) {
      final scrim = Path()
        ..fillType = PathFillType.evenOdd
        ..addRect(Offset.zero & size)
        ..addPath(shapes.fill, Offset.zero);
      canvas.drawPath(
        scrim,
        Paint()..color = Colors.black.withValues(alpha: 0.35),
      );
    }

    canvas.drawPath(
      shapes.fill,
      Paint()..color = color.withValues(alpha: 0.10),
    );

    final outline = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round
      ..color = color.withValues(alpha: 0.95);
    _dashed(canvas, shapes.body, outline);
    _dashed(canvas, shapes.head, outline);

    // Dashed centre line: the spine should follow it.
    final spine = Paint()
      ..color = color.withValues(alpha: 0.6)
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    final top = p(0, 0.06).dy;
    final bottom = p(0, 1.0).dy;
    for (var y = top; y < bottom - 8; y += 16) {
      canvas.drawLine(Offset(cx, y), Offset(cx, y + 8), spine);
    }

    // The four joints that the checker looks at.
    void dot(Offset o) {
      canvas.drawCircle(o, 7, Paint()..color = color);
      canvas.drawCircle(
        o,
        7,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5
          ..color = Colors.black54,
      );
    }

    dot(p(-BackGuide.shoulderHalf, 0));
    dot(p(BackGuide.shoulderHalf, 0));
    dot(p(-BackGuide.hipHalf, 1));
    dot(p(BackGuide.hipHalf, 1));

    void label(String text, Offset center) {
      final tp = TextPainter(
        text: TextSpan(
          text: text,
          style: TextStyle(
            color: color,
            fontSize: 12,
            fontWeight: FontWeight.w600,
            shadows: const [Shadow(blurRadius: 4, color: Colors.black)],
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, center - Offset(tp.width / 2, tp.height / 2));
    }

    label('Shoulders', p(0, 0.13));
    label('Hips', p(0, 0.88));
  }

  // Draws a path as short strokes with gaps between them.
  void _dashed(Canvas canvas, Path path, Paint paint) {
    for (final metric in path.computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        final end = math.min(distance + BackGuide.dashLength, metric.length);
        canvas.drawPath(metric.extractPath(distance, end), paint);
        distance += BackGuide.dashLength + BackGuide.dashGap;
      }
    }
  }

  // The head, the body outline (an open path, so no line is drawn across
  // the neck) and the shape that is filled.
  ({Path head, Path body, Path fill}) _shapes(
    Offset Function(double, double) p,
    double t,
  ) {
    final head = Path()
      ..addOval(
        Rect.fromCenter(center: p(0, -0.37), width: 0.38 * t, height: 0.52 * t),
      );

    final body = Path();
    void m(double x, double y) {
      final o = p(x, y);
      body.moveTo(o.dx, o.dy);
    }

    void l(double x, double y) {
      final o = p(x, y);
      body.lineTo(o.dx, o.dy);
    }

    void c(double x1, double y1, double x2, double y2, double x, double y) {
      final a = p(x1, y1);
      final b = p(x2, y2);
      final o = p(x, y);
      body.cubicTo(a.dx, a.dy, b.dx, b.dy, o.dx, o.dy);
    }

    // Down the left side: neck, shoulder, outer arm, hand, inner arm up to
    // the armpit, then the side of the torso down to the hips.
    m(-0.10, -0.145);
    l(-0.135, -0.09);
    c(-0.26, -0.095, -0.39, -0.07, -0.43, -0.008);
    l(-0.60, 0.85);
    c(-0.61, 0.93, -0.56, 0.995, -0.50, 0.99);
    c(-0.47, 0.985, -0.44, 0.955, -0.425, 0.915);
    l(-0.30, 0.386);
    l(-0.36, 1.04);

    // Across the bottom, just below the hips.
    l(0.36, 1.04);

    // Up the right side: the same shape, mirrored and in reverse.
    l(0.30, 0.386);
    l(0.425, 0.915);
    c(0.44, 0.955, 0.47, 0.985, 0.50, 0.99);
    c(0.56, 0.995, 0.61, 0.93, 0.60, 0.85);
    l(0.43, -0.008);
    c(0.39, -0.07, 0.26, -0.095, 0.135, -0.09);
    l(0.10, -0.145);

    final fill = Path.combine(
      PathOperation.union,
      Path.from(body)..close(),
      head,
    );
    return (head: head, body: body, fill: fill);
  }

  @override
  bool shouldRepaint(covariant AlignmentOverlayPainter old) =>
      old.color != color;
}
