import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/format.dart';
import '../../models/screening.dart';
import '../../services/api_client.dart';
import '../../services/screening_service.dart';
import 'progress_summary.dart';
import 'screening_result.dart';

class ProgressScreen extends StatefulWidget {
  const ProgressScreen({super.key});

  @override
  State<ProgressScreen> createState() => _ProgressScreenState();
}

class _ProgressScreenState extends State<ProgressScreen> {
  ProgressSummary? _summary;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final list = await ScreeningService().myScreenings();
      if (mounted) setState(() => _summary = ProgressSummary(list));
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not load your progress.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _deg(double v) => '${v.toStringAsFixed(1)}°';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('My Progress'),
        leading: BackButton(
          onPressed: () =>
              context.canPop() ? context.pop() : context.go('/home'),
        ),
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: _body(),
          ),
        ),
      ),
    );
  }

  Widget _body() {
    if (_loading && _summary == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_error!, textAlign: TextAlign.center),
              const SizedBox(height: 12),
              FilledButton(onPressed: _load, child: const Text('Retry')),
            ],
          ),
        ),
      );
    }
    final s = _summary;
    if (s == null || s.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.show_chart, size: 56),
              const SizedBox(height: 12),
              const Text(
                'No screenings yet',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              const Text(
                'Do your first screening. Repeat it every month and your '
                'progress will show here.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () => context.push('/screening/for'),
                child: const Text('Start my first screening'),
              ),
            ],
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        children: [
          _trendCard(s),
          const SizedBox(height: 12),
          _nextCard(s),
          const SizedBox(height: 12),
          _chartCard(s),
          const SizedBox(height: 12),
          _historyCard(s),
          const SizedBox(height: 12),
          const Text(
            'This is a screening aid, not a medical diagnosis. Only a doctor '
            'can confirm scoliosis or tell you whether it has changed. If '
            'your result is in the referral range, or you notice uneven '
            'shoulders, a prominent shoulder blade or back pain, ask a clinician.',
            textAlign: TextAlign.center,
            style: TextStyle(fontStyle: FontStyle.italic, fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _trendCard(ProgressSummary s) {
    final latest = s.latest!;
    final (
      IconData icon,
      Color color,
      String title,
      String text,
    ) = switch (s.trend) {
      Trend.first => (
        Icons.flag_outlined,
        Colors.blueGrey,
        'First screening saved',
        'Your highest trunk rotation was ${_deg(latest.angle)}. Screen '
            'again in a month to see how it changes.',
      ),
      Trend.improved => (
        Icons.trending_down,
        Colors.green,
        'Improving',
        'Your highest trunk rotation went down by ${_deg(-s.change!)} '
            '(${_deg(s.previous!.angle)} to ${_deg(latest.angle)}).',
      ),
      Trend.worse => (
        Icons.trending_up,
        Colors.deepOrange,
        'Higher than last time',
        'Your highest trunk rotation went up by ${_deg(s.change!)} '
            '(${_deg(s.previous!.angle)} to ${_deg(latest.angle)}). '
            'Repeat the screening to confirm'
            '${latest.angle >= ResultRules.referAtr ? ', and please see a clinic' : ''}.',
      ),
      Trend.same => (
        Icons.trending_flat,
        Colors.amber.shade800,
        'About the same',
        'It changed by ${_deg(s.change!.abs())}, less than '
            '${ProgressRules.meaningfulChange.toStringAsFixed(0)}°, which is '
            'within the normal variation between measurements.',
      ),
    };
    return Card(
      color: color.withValues(alpha: 0.12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Icon(icon, size: 48, color: color),
            const SizedBox(height: 8),
            Text(
              title,
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 6),
            Text(text, textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }

  Widget _nextCard(ProgressSummary s) {
    final due = s.isDue;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  due
                      ? Icons.notifications_active_outlined
                      : Icons.event_available_outlined,
                  color: due ? Colors.deepOrange : Colors.green,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    due
                        ? 'Time for your monthly check-up'
                        : 'Next check-up in ${s.daysLeft} days',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              due
                  ? 'Last screened on ${formatDate(s.latest!.createdAt)}.'
                  : 'Around ${formatDate(s.nextDue!)}.',
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: () => context.push('/screening/for'),
              child: Text(due ? 'Start screening' : 'Screen now'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _chartCard(ProgressSummary s) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Highest trunk rotation over time',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            if (s.entries.length < 2)
              const Text('The chart appears after your second screening.')
            else
              SizedBox(
                height: 170,
                width: double.infinity,
                child: CustomPaint(
                  painter: _ChartPainter([
                    for (final e in s.entries.reversed) e.angle,
                  ], Theme.of(context).colorScheme.primary),
                ),
              ),
            const SizedBox(height: 4),
            Text(
              'Lines: ${ResultRules.borderlineAtr.toStringAsFixed(0)}° borderline, '
              '${ResultRules.referAtr.toStringAsFixed(0)}° referral.',
              style: const TextStyle(fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }

  Widget _historyCard(ProgressSummary s) {
    final entries = s.entries;
    return Card(
      child: Column(
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 16, 16, 4),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'History',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          ),
          for (var i = 0; i < entries.length; i++) _historyTile(entries, i),
        ],
      ),
    );
  }

  Widget _historyTile(List<Screening> entries, int i) {
    final e = entries[i];
    final older = i + 1 < entries.length ? entries[i + 1] : null;
    final diff = older == null ? null : e.angle - older.angle;
    Widget? trailing;
    if (diff != null) {
      final improved = diff <= -ProgressRules.meaningfulChange;
      final worse = diff >= ProgressRules.meaningfulChange;
      trailing = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            improved
                ? Icons.arrow_downward
                : worse
                ? Icons.arrow_upward
                : Icons.remove,
            size: 16,
            color: improved
                ? Colors.green
                : worse
                ? Colors.deepOrange
                : Colors.grey,
          ),
          Text('${diff.abs().toStringAsFixed(1)}°'),
        ],
      );
    }
    return ListTile(
      dense: true,
      leading: const Icon(Icons.straighten),
      title: Text(
        '${_deg(e.angle)}  ·  ${ProgressSummary.levelLabel(e.angle)}',
      ),
      subtitle: Text(formatDate(e.createdAt)),
      trailing: trailing,
    );
  }
}

/// A small line chart with the 5° and 7° guide lines.
class _ChartPainter extends CustomPainter {
  final List<double> values; // oldest first
  final Color lineColor;
  const _ChartPainter(this.values, this.lineColor);

  @override
  void paint(Canvas canvas, Size size) {
    if (values.isEmpty) return;
    const left = 34.0, right = 12.0, top = 10.0, bottom = 10.0;
    final w = size.width - left - right;
    final h = size.height - top - bottom;
    final maxY = math.max(10.0, values.reduce(math.max) + 2);
    double y(double v) => top + h * (1 - v / maxY);

    void guide(double v, Color c) {
      canvas.drawLine(
        Offset(left, y(v)),
        Offset(left + w, y(v)),
        Paint()
          ..color = c.withValues(alpha: 0.6)
          ..strokeWidth = 1,
      );
      final tp = TextPainter(
        text: TextSpan(
          text: '${v.toStringAsFixed(0)}°',
          style: TextStyle(color: c, fontSize: 10),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(0, y(v) - tp.height / 2));
    }

    guide(ResultRules.borderlineAtr, Colors.amber.shade800);
    guide(ResultRules.referAtr, Colors.red);

    Offset point(int i) => Offset(
      left + (values.length == 1 ? w / 2 : w * i / (values.length - 1)),
      y(values[i]),
    );

    final path = Path()..moveTo(point(0).dx, point(0).dy);
    for (var i = 1; i < values.length; i++) {
      path.lineTo(point(i).dx, point(i).dy);
    }
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..color = lineColor,
    );
    for (var i = 0; i < values.length; i++) {
      canvas.drawCircle(point(i), 5, Paint()..color = lineColor);
    }
  }

  @override
  bool shouldRepaint(covariant _ChartPainter old) =>
      old.values != values || old.lineColor != lineColor;
}
