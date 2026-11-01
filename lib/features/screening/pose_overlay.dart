import 'package:flutter/material.dart';

import '../../services/pose_detector.dart';

/// Draws the detected body points on top of the camera preview.
/// Colour = landmark score: green (good), orange (weak), red (poor).
class PoseOverlayPainter extends CustomPainter {
  final PoseFrame? frame;
  const PoseOverlayPainter(this.frame);

  static const Map<int, String> _shown = {
    PoseIndex.nose: 'Nose',
    PoseIndex.leftEar: 'Ear',
    PoseIndex.rightEar: 'Ear',
    PoseIndex.leftShoulder: 'Shoulder',
    PoseIndex.rightShoulder: 'Shoulder',
    PoseIndex.leftElbow: 'Elbow',
    PoseIndex.rightElbow: 'Elbow',
    PoseIndex.leftHip: 'Hip',
    PoseIndex.rightHip: 'Hip',
  };

  @override
  void paint(Canvas canvas, Size size) {
    final f = frame;
    if (f == null || !f.found) return;

    Offset? at(int i) {
      final p = f.point(i);
      if (p == null) return null;
      return Offset(p.x * size.width, p.y * size.height);
    }

    final line = Paint()
      ..color = Colors.cyanAccent.withValues(alpha: 0.8)
      ..strokeWidth = 3;

    void connect(int a, int b) {
      final pa = at(a);
      final pb = at(b);
      if (pa != null && pb != null) canvas.drawLine(pa, pb, line);
    }

    connect(PoseIndex.leftShoulder, PoseIndex.rightShoulder);
    connect(PoseIndex.leftHip, PoseIndex.rightHip);
    connect(PoseIndex.leftShoulder, PoseIndex.leftHip);
    connect(PoseIndex.rightShoulder, PoseIndex.rightHip);

    for (final e in _shown.entries) {
      final p = f.point(e.key);
      final o = at(e.key);
      if (p == null || o == null) continue;

      final color = p.score >= 0.6
          ? Colors.greenAccent
          : p.score >= 0.3
          ? Colors.orangeAccent
          : Colors.redAccent;

      canvas.drawCircle(o, 7, Paint()..color = color);
      canvas.drawCircle(
        o,
        7,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = Colors.black,
      );

      final tp = TextPainter(
        text: TextSpan(
          text: '${e.value} ${(p.score * 100).round()}',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 11,
            fontWeight: FontWeight.w600,
            shadows: [Shadow(blurRadius: 4, color: Colors.black)],
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(o.dx + 10, o.dy - tp.height / 2));
    }
  }

  @override
  bool shouldRepaint(covariant PoseOverlayPainter old) => old.frame != frame;
}
