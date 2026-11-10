import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/format.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../../services/auth_service.dart';
import '../../services/clinic_service.dart';
import '../../services/screening_service.dart';
import '../screening/progress_summary.dart';
import '../screening/screening_result.dart';
import '../../core/notification_prompt.dart';

/// The patient's dashboard: latest screening, next check-up,
/// next appointment and recent notifications.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final ClinicService _clinics = ClinicService();
  ProgressSummary? _summary;
  ClinicAppointment? _next;
  List<ClinicNotification> _notes = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
    // Ask once whether to turn on notifications, after the screen is drawn.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) NotificationPrompt.maybeAsk(context);
    });
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    String? problem;

    try {
      final list = await ScreeningService().myScreenings();
      final summary = ProgressSummary(list);
      // Time for the monthly check: leave a reminder notification (once).
      if (summary.isDue && summary.latest != null) {
        await ScreeningService().createDueReminder(summary.latest!);
      }
      if (mounted) setState(() => _summary = summary);
    } catch (_) {
      problem = 'Could not load your screenings.';
    }

    try {
      final all = await _clinics.appointments();
      final now = DateTime.now().toUtc();
      final upcoming =
          all
              .where(
                (a) =>
                    (a.status == 'pending' || a.status == 'approved') &&
                    a.scheduledAt != null &&
                    a.scheduledAt!.isAfter(now),
              )
              .toList()
            ..sort((a, b) => a.scheduledAt!.compareTo(b.scheduledAt!));
      if (mounted) {
        setState(() => _next = upcoming.isEmpty ? null : upcoming.first);
      }
    } catch (_) {
      problem ??= 'Could not load your appointments.';
    }

    try {
      final n = await _clinics.notifications();
      if (mounted) setState(() => _notes = n);
    } catch (_) {
      problem ??= 'Could not load your notifications.';
    }

    if (!mounted) return;
    setState(() {
      _error = problem;
      _loading = false;
    });
  }

  Future<void> _openNotifications() async {
    await context.push('/notifications');
    if (mounted) _load();
  }

  Color _levelColor(double atr) {
    if (atr >= ResultRules.referAtr) return AppColors.high;
    if (atr >= ResultRules.borderlineAtr) return AppColors.mild;
    return AppColors.normal;
  }

  @override
  Widget build(BuildContext context) {
    final user = AuthService().currentUser;
    final first = (user?.name ?? '').trim().split(' ').first;
    final unread = _notes.where((n) => !n.isRead).length;

    return Scaffold(
      appBar: AppBar(
        title: const Text('BckSnap'),
        actions: [
          IconButton(
            tooltip: 'Notifications',
            onPressed: _openNotifications,
            icon: Badge(
              isLabelVisible: unread > 0,
              label: Text('$unread'),
              child: const Icon(Icons.notifications_outlined),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                children: [
                  _greeting(first),
                  if (_error != null) ...[
                    ErrorBox(_error!),
                    const SizedBox(height: 12),
                  ],
                  _title('Your screening'),
                  _screeningCard(),
                  const SizedBox(height: 16),
                  _title('Next appointment'),
                  _appointmentCard(),
                  if (_notes.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    _title('Recent notifications'),
                    _notificationsCard(),
                  ],
                  const SizedBox(height: 20),
                  Text(
                    'BckSnap is a screening aid, not a medical diagnosis. '
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
          ),
        ),
      ),
    );
  }

  // ---- pieces ---------------------------------------------------------------

  Widget _greeting(String first) => Padding(
    padding: const EdgeInsets.fromLTRB(4, 8, 4, 16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          first.isEmpty ? 'Welcome!' : 'Hi, $first',
          style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 2),
        Text(
          formatDate(DateTime.now()),
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    ),
  );

  Widget _title(String text) => Padding(
    padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
    child: Text(
      text,
      style: const TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w700,
        color: AppColors.primary,
      ),
    ),
  );

  Widget _tapCard({required VoidCallback onTap, required Widget child}) => Card(
    clipBehavior: Clip.antiAlias,
    child: InkWell(
      onTap: onTap,
      child: Padding(padding: const EdgeInsets.all(16), child: child),
    ),
  );

  Widget _pill(String text, Color color) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.15),
      borderRadius: BorderRadius.circular(12),
    ),
    child: Text(
      text,
      style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: color),
    ),
  );

  Widget _screeningCard() {
    final s = _summary;
    if (s == null) {
      return _loading
          ? const Card(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator()),
              ),
            )
          : const SizedBox.shrink();
    }

    if (s.isEmpty) {
      return _tapCard(
        onTap: () => context.push('/screening/for'),
        child: Row(
          children: [
            const Icon(Icons.flag_outlined, size: 40, color: AppColors.primary),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'No screening yet',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Take your first back screening. Repeat it every month '
                    'to track your progress.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right),
          ],
        ),
      );
    }

    final latest = s.latest!;
    final color = _levelColor(latest.angle);
    final change = s.change;
    final (
      IconData trendIcon,
      Color trendColor,
      String trendText,
    ) = switch (s.trend) {
      Trend.first => (Icons.flag_outlined, Colors.blueGrey, 'First screening'),
      Trend.improved => (
        Icons.trending_down,
        AppColors.normal,
        'Down ${(-change!).toStringAsFixed(1)}°',
      ),
      Trend.worse => (
        Icons.trending_up,
        Colors.deepOrange,
        'Up ${change!.toStringAsFixed(1)}°',
      ),
      Trend.same => (Icons.trending_flat, Colors.grey, 'About the same'),
    };

    final due = s.isDue;
    final nextColor = due ? Colors.deepOrange : AppColors.normal;
    final nextText = due
        ? 'Time for your monthly check-up'
        : 'Next check-up in ${s.daysLeft} days';
    final nextSub = due
        ? 'Last screened on ${formatDate(latest.createdAt)}'
        : 'Around ${formatDate(s.nextDue!)}';

    final values = [
      for (final e in s.entries.take(8).toList().reversed) e.angle,
    ];

    return _tapCard(
      onTap: () => context.push('/progress'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'LATEST SCREENING',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: AppColors.primary,
            ),
          ),
          const SizedBox(height: 6),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '${latest.angle.toStringAsFixed(1)}°',
                style: TextStyle(
                  fontSize: 40,
                  fontWeight: FontWeight.w800,
                  color: color,
                  height: 1,
                ),
              ),
              const SizedBox(width: 10),
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: _pill(ProgressSummary.levelLabel(latest.angle), color),
              ),
              const Spacer(),
              Icon(trendIcon, color: trendColor, size: 20),
              const SizedBox(width: 4),
              Text(
                trendText,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: trendColor,
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            'Highest trunk rotation · ${formatDate(latest.createdAt)}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          if (values.length >= 2) ...[
            const SizedBox(height: 12),
            SizedBox(
              height: 80,
              width: double.infinity,
              child: CustomPaint(painter: _SparklinePainter(values, color)),
            ),
          ],
          const Divider(height: 24),
          Row(
            children: [
              Icon(
                due
                    ? Icons.notifications_active_outlined
                    : Icons.event_available_outlined,
                color: nextColor,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      nextText,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(nextSub, style: Theme.of(context).textTheme.bodySmall),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _appointmentCard() {
    final a = _next;
    if (a == null) {
      return _tapCard(
        onTap: () => context.push('/clinics'),
        child: Row(
          children: [
            const Icon(
              Icons.calendar_month_outlined,
              size: 32,
              color: AppColors.primary,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'No upcoming appointment',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Tap to find a clinic and book one.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right),
          ],
        ),
      );
    }

    final approved = a.status == 'approved';
    return _tapCard(
      onTap: () => context.push('/appointments/${a.id}'),
      child: Row(
        children: [
          CircleAvatar(
            backgroundColor: AppColors.tonal,
            child: Icon(
              a.mode == 'online' ? Icons.videocam_outlined : Icons.event,
              color: AppColors.primary,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  a.clinicName ?? 'Clinic',
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (a.doctorName != null)
                  Text(
                    'Doctor: ${a.doctorName}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                Text(
                  formatDateTime(a.scheduledAt!.toLocal()),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 6),
                _pill(
                  approved ? 'Approved' : 'Pending approval',
                  approved ? AppColors.normal : AppColors.mild,
                ),
              ],
            ),
          ),
          const Icon(Icons.chevron_right),
        ],
      ),
    );
  }

  Widget _notificationsCard() {
    final latest = _notes.take(3).toList();
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: _openNotifications,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final n in latest)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Icon(
                          Icons.circle,
                          size: 8,
                          color: n.isRead
                              ? Colors.transparent
                              : AppColors.primary,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              n.title,
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: n.isRead
                                    ? FontWeight.w500
                                    : FontWeight.w700,
                              ),
                            ),
                            Text(
                              n.message,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(
                                    fontSize: 12,
                                    color: AppColors.hint,
                                  ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        formatDate(n.createdAt.toLocal()),
                        style: const TextStyle(
                          fontSize: 11,
                          color: AppColors.hint,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A small line chart of the last screenings, with the 5° and 7° lines.
class _SparklinePainter extends CustomPainter {
  final List<double> values; // oldest first
  final Color color;
  const _SparklinePainter(this.values, this.color);

  @override
  void paint(Canvas canvas, Size size) {
    if (values.length < 2) return;
    const pad = 6.0;
    final w = size.width - pad * 2;
    final h = size.height - pad * 2;
    final maxY = math.max(10.0, values.reduce(math.max) + 2);
    double y(double v) => pad + h * (1 - v / maxY);

    void guide(double v, Color c) {
      canvas.drawLine(
        Offset(0, y(v)),
        Offset(size.width, y(v)),
        Paint()
          ..color = c.withValues(alpha: 0.5)
          ..strokeWidth = 1,
      );
    }

    guide(ResultRules.borderlineAtr, AppColors.mild);
    guide(ResultRules.referAtr, AppColors.high);

    Offset point(int i) =>
        Offset(pad + w * i / (values.length - 1), y(values[i]));

    final path = Path()..moveTo(point(0).dx, point(0).dy);
    for (var i = 1; i < values.length; i++) {
      path.lineTo(point(i).dx, point(i).dy);
    }
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..color = color,
    );
    for (var i = 0; i < values.length; i++) {
      canvas.drawCircle(point(i), 4, Paint()..color = color);
    }
  }

  @override
  bool shouldRepaint(covariant _SparklinePainter old) =>
      old.values != values || old.color != color;
}
