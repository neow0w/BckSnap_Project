import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme.dart';
import 'screening_result.dart';

class ResultScreen extends StatelessWidget {
  final ResultData data;
  const ResultScreen({super.key, required this.data});

  String _deg(double v) => '${v.toStringAsFixed(1)}°';

  ({Color color, String label, String message, String next}) get _style {
    switch (data.category) {
      case ResultCategory.refer:
        return (
          color: AppColors.high,
          label: 'HIGH RISK',
          message:
              'The highest trunk rotation was ${_deg(data.highestAtr)}'
              '${data.highestLevel == null ? '' : ' at the ${data.highestLevel!.toLowerCase()} level'}. '
              'A reading of ${ResultRules.referAtr.toStringAsFixed(0)}° or '
              'more is the usual reason to be checked by a clinician.',
          next:
              'Book a clinic appointment so a clinician can review these '
              'findings. They may confirm it with an X-ray.',
        );
      case ResultCategory.borderline:
        return (
          color: AppColors.mild,
          label: 'MILD RISK',
          message:
              'The highest trunk rotation was ${_deg(data.highestAtr)}, '
              'between ${ResultRules.borderlineAtr.toStringAsFixed(0)}° '
              'and ${ResultRules.referAtr.toStringAsFixed(0)}°.',
          next:
              'Repeat the screening in a few weeks. Ask a clinician if the '
              'result stays the same or you have concerns.',
        );
      case ResultCategory.noSign:
        return (
          color: AppColors.normal,
          label: 'NORMAL',
          message:
              'The highest trunk rotation was ${_deg(data.highestAtr)}, '
              'below ${ResultRules.borderlineAtr.toStringAsFixed(0)}°. No '
              'immediate concern was found.',
          next:
              'Repeat the screening every month. If you notice uneven '
              'shoulders, a prominent shoulder blade or back pain, ask a '
              'clinician.',
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = _style;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Screening Result'),
        automaticallyImplyLeading: false,
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Column(
              children: [
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(24, 8, 24, 8),
                    children: [
                      Center(
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 5,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.tonal,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: const Text(
                            'DIGITAL SCOLIOMETER',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              color: AppColors.primary,
                            ),
                          ),
                        ),
                      ),
                      if (data.subjectLabel != null) ...[
                        const SizedBox(height: 10),
                        Text(
                          'Screened person: ${data.subjectLabel}',
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                      const SizedBox(height: 16),
                      Center(
                        child: SizedBox(
                          width: 220,
                          height: 125,
                          child: CustomPaint(
                            painter: _GaugePainter(data.highestAtr, s.color),
                          ),
                        ),
                      ),
                      Text(
                        s.label,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                          color: s.color,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        s.message,
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'TRUNK ROTATION FINDINGS',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: AppColors.primary,
                        ),
                      ),
                      const SizedBox(height: 6),
                      _findings(context),
                      const SizedBox(height: 14),
                      const Text(
                        'Recommended next step',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: AppColors.primary,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        s.next,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'This is a screening result, not a medical diagnosis. '
                        'Only a doctor can confirm scoliosis.',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          fontStyle: FontStyle.italic,
                          fontSize: 11,
                          color: AppColors.hint,
                        ),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      FilledButton(
                        onPressed: () => context.go('/referral'),
                        child: const Text('PROCEED TO CLINIC REFERRAL'),
                      ),
                      const SizedBox(height: 10),
                      FilledButton.tonal(
                        style: FilledButton.styleFrom(
                          backgroundColor: AppColors.tonal,
                          foregroundColor: AppColors.primary,
                        ),
                        onPressed: () => context.go('/home'),
                        child: const Text('BACK TO HOME'),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ---- findings box -----------------------------------------------------
  Widget _findings(BuildContext context) {
    final rows = <Widget>[
      for (final l in data.levels)
        _row(l.name, _deg(l.atr), bold: l.name == data.highestLevel),
      _row('Highest rotation (ATR)', _deg(data.highestAtr), bold: true),
    ];
    return Container(
      decoration: BoxDecoration(
        color: AppColors.fieldFill.withValues(alpha: 0.5),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.5)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          for (var i = 0; i < rows.length; i++) ...[
            if (i > 0) const Divider(height: 1),
            rows[i],
          ],
        ],
      ),
    );
  }

  Widget _row(String label, String value, {bool bold = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: bold ? FontWeight.w700 : FontWeight.w400,
              ),
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: 12,
              fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

/// Half-circle gauge: green below 5°, amber 5° to 7°, red from 7°.
class _GaugePainter extends CustomPainter {
  final double atr;
  final Color needle;
  const _GaugePainter(this.atr, this.needle);

  static const double _max = 12;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height - 10);
    final radius = math.min(size.width / 2, size.height) - 12;
    final rect = Rect.fromCircle(center: center, radius: radius);

    void arc(double from, double to, Color color) {
      canvas.drawArc(
        rect,
        math.pi + math.pi * (from / _max),
        math.pi * ((to - from) / _max),
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 16
          ..color = color,
      );
    }

    arc(0, ResultRules.borderlineAtr, AppColors.normal);
    arc(ResultRules.borderlineAtr, ResultRules.referAtr, AppColors.mild);
    arc(ResultRules.referAtr, _max, AppColors.high);

    final a = math.pi + math.pi * (math.min(atr, _max) / _max);
    final tip = center + Offset(math.cos(a), math.sin(a)) * (radius - 22);
    canvas.drawLine(
      center,
      tip,
      Paint()
        ..color = needle
        ..strokeWidth = 4
        ..strokeCap = StrokeCap.round,
    );
    canvas.drawCircle(center, 8, Paint()..color = needle);
    canvas.drawCircle(center, 3, Paint()..color = Colors.white);
  }

  @override
  bool shouldRepaint(covariant _GaugePainter old) =>
      old.atr != atr || old.needle != needle;
}
