import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/format.dart';
import '../../services/screening_service.dart';
import 'progress_summary.dart';

/// The monthly-check card on the home screen.
class ProgressBanner extends StatefulWidget {
  const ProgressBanner({super.key});

  @override
  State<ProgressBanner> createState() => _ProgressBannerState();
}

class _ProgressBannerState extends State<ProgressBanner> {
  ProgressSummary? _summary;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final list = await ScreeningService().myScreenings();
      if (!mounted) return;
      final summary = ProgressSummary(list);
      setState(() {
        _summary = summary;
        _loading = false;
      });
      // Time for the monthly check: leave a notification (once).
      if (summary.isDue && summary.latest != null) {
        ScreeningService().createDueReminder(summary.latest!);
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _trendText(ProgressSummary s) {
    final c = s.change;
    switch (s.trend) {
      case Trend.first:
        return 'Latest highest trunk rotation: ${s.latest!.angle.toStringAsFixed(1)}°';
      case Trend.improved:
        return 'Improving: down ${(-c!).toStringAsFixed(1)}° since last time';
      case Trend.worse:
        return 'Up ${c!.toStringAsFixed(1)}° since last time';
      case Trend.same:
        return 'About the same as last time';
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Center(child: CircularProgressIndicator()),
        ),
      );
    }
    final s = _summary;
    if (s == null || s.isEmpty) {
      return _card(
        context,
        icon: Icons.flag_outlined,
        color: Theme.of(context).colorScheme.primary,
        title: 'Start your first screening',
        text: 'Take a scoliometer reading. Repeat it every month to see how you are doing.',
        primary: 'Start screening',
      );
    }
    if (s.isDue) {
      return _card(
        context,
        icon: Icons.notifications_active_outlined,
        color: Colors.deepOrange,
        title: 'Time for your monthly check-up',
        text:
            'Your last screening was on ${formatDate(s.latest!.createdAt)}. '
            '${_trendText(s)}.',
        primary: 'Start screening',
      );
    }
    return _card(
      context,
      icon: Icons.event_available_outlined,
      color: Colors.green,
      title: 'Next check-up in ${s.daysLeft} days',
      text: '${_trendText(s)}. Around ${formatDate(s.nextDue!)}.',
      primary: null,
    );
  }

  Widget _card(
    BuildContext context, {
    required IconData icon,
    required Color color,
    required String title,
    required String text,
    required String? primary,
  }) {
    return Card(
      color: color.withValues(alpha: 0.10),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: color),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(text),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              children: [
                if (primary != null)
                  FilledButton(
                    onPressed: () => context.push('/screening/for'),
                    child: Text(primary),
                  ),
                if (_summary != null && !_summary!.isEmpty)
                  OutlinedButton(
                    onPressed: () => context.push('/progress'),
                    child: const Text('View my progress'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
