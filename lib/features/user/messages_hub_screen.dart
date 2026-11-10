import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme.dart';
import '../../models/message.dart';
import '../../services/api_client.dart';
import '../../services/clinic_service.dart';
import '../../services/message_service.dart';

/// Messages tab, like a messenger: one row per clinic with the last message
/// under the name, the time, and a badge with the unread count.
class MessagesHubScreen extends StatefulWidget {
  const MessagesHubScreen({super.key});

  @override
  State<MessagesHubScreen> createState() => _MessagesHubScreenState();
}

class _MessagesHubScreenState extends State<MessagesHubScreen> {
  final _clinics = ClinicService();
  late final Stream<List<PatientThread>> _threads = MessageService()
      .myThreadsStream();
  final Map<String, String> _names = {}; // clinic id -> name
  final Set<String> _asked = {};
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadClinics();
  }

  Future<void> _loadClinics() async {
    setState(() => _error = null);
    try {
      final list = await _clinics.appointments();
      for (final a in list) {
        final id = a.clinicId;
        if (id != null) _names.putIfAbsent(id, () => a.clinicName ?? 'Clinic');
      }
    } on ApiException catch (e) {
      _error = e.message;
    } catch (_) {
      _error = 'Could not load your clinics.';
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// The clinic name; looks it up once when it is not known yet.
  String _nameOf(String id) {
    final known = _names[id];
    if (known != null) return known;
    if (_asked.add(id)) {
      _clinics
          .clinic(id)
          .then((c) {
            if (mounted) setState(() => _names[id] = c.name);
          })
          .catchError((_) {});
    }
    return 'Clinic';
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<PatientThread>>(
      stream: _threads,
      builder: (context, snap) {
        final threads = snap.data ?? const <PatientThread>[];
        final byClinic = {for (final t in threads) t.clinicId: t};
        final unread = threads.fold<int>(0, (s, t) => s + t.unread);

        final ids = <String>{...byClinic.keys, ..._names.keys}.toList()
          ..sort((a, b) {
            final ta = byClinic[a]?.lastAt;
            final tb = byClinic[b]?.lastAt;
            if (ta != null && tb != null) return tb.compareTo(ta);
            if (ta != null) return -1;
            if (tb != null) return 1;
            return (_names[a] ?? '').toLowerCase().compareTo(
              (_names[b] ?? '').toLowerCase(),
            );
          });

        return Scaffold(
          appBar: AppBar(
            automaticallyImplyLeading: false,
            title: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Messages'),
                if (unread > 0) ...[const SizedBox(width: 8), _badge(unread)],
              ],
            ),
          ),
          body: SafeArea(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 600),
                child: _body(context, ids, byClinic, snap),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _body(
    BuildContext context,
    List<String> ids,
    Map<String, PatientThread> byClinic,
    AsyncSnapshot<List<PatientThread>> snap,
  ) {
    if (_loading && !snap.hasData) {
      return const Center(child: CircularProgressIndicator());
    }
    if (ids.isEmpty) {
      return RefreshIndicator(
        onRefresh: _loadClinics,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(24),
          children: [
            const SizedBox(height: 80),
            const Icon(Icons.chat_bubble_outline, size: 56),
            const SizedBox(height: 12),
            Text(_error ?? 'No conversations yet', textAlign: TextAlign.center),
            const SizedBox(height: 6),
            Text(
              _error != null
                  ? 'Pull down to try again.'
                  : 'Open a clinic to send it a message.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 16),
            Center(
              child: FilledButton(
                onPressed: () => context.push('/clinics'),
                child: const Text('FIND A CLINIC'),
              ),
            ),
          ],
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _loadClinics,
      child: ListView.separated(
        physics: const AlwaysScrollableScrollPhysics(),
        itemCount: ids.length,
        separatorBuilder: (_, _) => const Divider(height: 1, indent: 84),
        itemBuilder: (context, i) => _row(context, ids[i], byClinic[ids[i]]),
      ),
    );
  }

  Widget _row(BuildContext context, String id, PatientThread? t) {
    final unread = t?.unread ?? 0;
    final hasUnread = unread > 0;
    final preview = t == null
        ? 'No messages yet. Tap to start.'
        : '${t.lastFromPatient == true ? 'You: ' : ''}${t.lastMessage}';

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      leading: CircleAvatar(
        radius: 26,
        backgroundColor: AppColors.primary.withValues(alpha: 0.15),
        child: const Icon(Icons.local_hospital, color: AppColors.primary),
      ),
      title: Text(
        _nameOf(id),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontWeight: hasUnread ? FontWeight.w800 : FontWeight.w600,
        ),
      ),
      subtitle: Text(
        preview,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontWeight: hasUnread ? FontWeight.w700 : FontWeight.w400,
          color: hasUnread ? null : AppColors.hint,
        ),
      ),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (t?.lastAt != null)
            Text(
              shortTimeLabel(t!.lastAt!),
              style: TextStyle(
                fontSize: 11,
                color: hasUnread ? AppColors.primary : AppColors.hint,
              ),
            ),
          if (hasUnread) ...[const SizedBox(height: 4), _badge(unread)],
        ],
      ),
      onTap: () => context.push('/message/$id'),
    );
  }

  Widget _badge(int n) => Container(
    constraints: const BoxConstraints(minWidth: 20, minHeight: 20),
    padding: const EdgeInsets.symmetric(horizontal: 6),
    alignment: Alignment.center,
    decoration: BoxDecoration(
      color: AppColors.primary,
      borderRadius: BorderRadius.circular(10),
    ),
    child: Text(
      n > 99 ? '99+' : '$n',
      style: const TextStyle(
        color: Colors.white,
        fontSize: 11,
        fontWeight: FontWeight.w700,
      ),
    ),
  );
}
