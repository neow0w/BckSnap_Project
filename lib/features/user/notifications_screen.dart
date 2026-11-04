import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/format.dart';
import '../../core/theme.dart';
import '../../services/api_client.dart';
import '../../services/clinic_service.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  final ClinicService _service = ClinicService();
  List<ClinicNotification> _items = [];
  bool _loading = true;
  bool _marking = false;
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
      final list = await _service.notifications();
      if (mounted) setState(() => _items = list);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not load notifications.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  bool get _hasUnread => _items.any((n) => !n.isRead);

  void _snack(String text) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _markAll() async {
    setState(() => _marking = true);
    try {
      for (final n in _items.where((n) => !n.isRead)) {
        await _service.markNotificationRead(n.id);
      }
      await _load();
    } on ApiException catch (e) {
      if (mounted) _snack(e.message);
    } finally {
      if (mounted) setState(() => _marking = false);
    }
  }

  Future<void> _open(ClinicNotification n) async {
    if (!n.isRead) {
      try {
        await _service.markNotificationRead(n.id);
      } on ApiException catch (e) {
        if (mounted) _snack(e.message);
      }
    }
    if (!mounted) return;
    if (n.eventType == 'screening_due') {
      context.push('/progress');
    } else {
      context.push('/appointments/${n.appointmentId}');
    }
  }

  String _dayLabel(DateTime d) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(d.year, d.month, d.day);
    final diff = today.difference(day).inDays;
    if (diff == 0) return 'Today';
    if (diff == 1) return 'Yesterday';
    return formatDate(d);
  }

  IconData _icon(String type) {
    if (type == 'screening_due') return Icons.straighten;
    if (type.contains('approve')) return Icons.event_available_outlined;
    if (type.contains('reject') || type.contains('declin')) {
      return Icons.event_busy_outlined;
    }
    if (type.contains('cancel')) return Icons.event_busy_outlined;
    return Icons.event_note_outlined;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Notification'),
        leading: BackButton(
          onPressed: () =>
              context.canPop() ? context.pop() : context.go('/home'),
        ),
        actions: [
          TextButton(
            onPressed: (_hasUnread && !_marking) ? _markAll : null,
            child: const Text('Mark all'),
          ),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 600),
            child: _body(),
          ),
        ),
      ),
    );
  }

  Widget _body() {
    if (_loading && _items.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null && _items.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_error!),
            const SizedBox(height: 12),
            FilledButton(onPressed: _load, child: const Text('Retry')),
          ],
        ),
      );
    }
    if (_items.isEmpty) {
      return const Center(child: Text('You have no notifications.'));
    }

    final children = <Widget>[];
    String? lastLabel;
    for (final n in _items) {
      final local = n.createdAt.toLocal();
      final label = _dayLabel(local);
      if (label != lastLabel) {
        lastLabel = label;
        children.add(_dayChip(label));
      }
      children.add(_row(n, local));
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(0, 8, 0, 24),
        children: children,
      ),
    );
  }

  Widget _dayChip(String label) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
          decoration: BoxDecoration(
            color: AppColors.tonal,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: AppColors.primary,
            ),
          ),
        ),
      ),
    );
  }

  Widget _row(ClinicNotification n, DateTime local) {
    return InkWell(
      onTap: () => _open(n),
      child: Container(
        color: n.isRead ? Colors.transparent : AppColors.fieldFill,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: const BoxDecoration(
                color: AppColors.tonal,
                shape: BoxShape.circle,
              ),
              child: Icon(
                _icon(n.eventType),
                size: 20,
                color: AppColors.primary,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    n.title,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: n.isRead ? FontWeight.w500 : FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    n.message,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall
                        ?.copyWith(fontSize: 12, color: AppColors.hint),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Text(
              formatTime(local),
              style: const TextStyle(fontSize: 11, color: AppColors.hint),
            ),
          ],
        ),
      ),
    );
  }
}
