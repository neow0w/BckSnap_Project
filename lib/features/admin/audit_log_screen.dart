import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/format.dart';
import '../../services/api_client.dart';
import '../../services/clinic_service.dart';

/// Admin only: who did what, and when (the latest 300 entries).
class AuditLogScreen extends StatefulWidget {
  final bool embedded;
  const AuditLogScreen({super.key, this.embedded = false});

  @override
  State<AuditLogScreen> createState() => _AuditLogScreenState();
}

class _AuditLogScreenState extends State<AuditLogScreen> {
  static const _filters = [
    ('all', 'All'),
    ('staff', 'Staff'),
    ('appointment', 'Appointments'),
    ('access', 'Access'),
    ('clinic', 'Clinic'),
  ];

  final ClinicService _service = ClinicService();
  final TextEditingController _search = TextEditingController();
  List<Map<String, dynamic>> _all = [];
  bool _loading = true;
  String? _error;
  String _filter = 'all';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final list = await _service.auditLogs();
      if (mounted) setState(() => _all = list);
    } on ApiException catch (e) {
      if (mounted) {
        setState(
          () => _error = e.message.contains('failed-precondition')
              ? 'The audit log needs a one-time database index. Create it in '
                    'the Firebase console (Firestore, Indexes), wait until it '
                    'is enabled, then refresh.'
              : e.message,
        );
      }
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not load the audit log.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  bool _inFilter(Map<String, dynamic> e) {
    final a = '${e['action'] ?? ''}';
    return switch (_filter) {
      'staff' =>
        a.startsWith('staff.') ||
            a.startsWith('profile.') ||
            a.startsWith('doctor.'),
      'appointment' => a.startsWith('appointment.'),
      'access' => a == 'login' || a.startsWith('screening.'),
      'clinic' => a.startsWith('clinic.'),
      _ => true,
    };
  }

  String _role(Object? r) => switch ('$r') {
    'user' => 'patient',
    '' || 'null' => 'unknown',
    final other => other,
  };

  String _describe(Map<String, dynamic> e) {
    final who = '${e['actorName'] ?? 'Someone'} (${_role(e['actorRole'])})';
    final t = '${e['targetName'] ?? ''}'.trim();
    final target = t.isEmpty ? 'a record' : t;
    final patient = t.isEmpty ? 'a patient' : t;
    final details = '${e['details'] ?? ''}'.trim();
    return switch ('${e['action']}') {
      'login' => '$who logged in',
      'staff.created' => '$who created the $details account of $target',
      'staff.activated' => '$who activated the account of $target',
      'staff.deactivated' => '$who deactivated the account of $target',
      'clinic.location_updated' =>
        '$who updated the clinic location${details.isEmpty ? '' : ' ($details)'}',
      'appointment.booked' => '$who booked appointment $target',
      'appointment.cancelled' => '$who cancelled appointment $target',
      'appointment.approved' => '$who approved appointment $target',
      'appointment.rejected' => '$who rejected appointment $target',
      'screening.viewed' => '$who viewed the screenings of $patient',
      'screening.photo_viewed' => '$who viewed a back photo of a patient',
      'staff.account_created' =>
        '$who created the clinic staff account $target',
      'profile.created' => '$who created the $details profile of $target',
      'profile.approved' => '$who approved the profile of $target',
      'profile.rejected' => '$who rejected the profile of $target',
      'profile.activated' => '$who activated the profile of $target',
      'profile.deactivated' => '$who deactivated the profile of $target',
      'profile.password_reset' => '$who reset the password of $target',
      'doctor.presence_changed' =>
        '$who marked $target as ${details == 'in' ? 'in the clinic' : 'out of the clinic'}',
      final other => '$who: $other',
    };
  }

  IconData _icon(String action) {
    if (action == 'login') return Icons.login;
    if (action.startsWith('staff.') ||
        action.startsWith('profile.') ||
        action.startsWith('doctor.')) {
      return Icons.badge_outlined;
    }
    if (action.startsWith('appointment.')) return Icons.event_note_outlined;
    if (action.startsWith('screening.')) return Icons.visibility_outlined;
    if (action.startsWith('clinic.')) return Icons.place_outlined;
    return Icons.history;
  }

  @override
  Widget build(BuildContext context) {
    final q = _search.text.trim().toLowerCase();
    final rows = _all.where((e) {
      if (!_inFilter(e)) return false;
      if (q.isEmpty) return true;
      return '${_describe(e)} ${e['action']} ${e['details']}'
          .toLowerCase()
          .contains(q);
    }).toList();

    return Scaffold(
      appBar: widget.embedded
          ? null
          : AppBar(
              title: const Text('Audit log'),
              leading: BackButton(
                onPressed: () =>
                    context.canPop() ? context.pop() : context.go('/admin'),
              ),
            ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 800),
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                  child: TextField(
                    controller: _search,
                    onChanged: (_) => setState(() {}),
                    decoration: const InputDecoration(
                      hintText: 'Search the log',
                      prefixIcon: Icon(Icons.search),
                      isDense: true,
                    ),
                  ),
                ),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    children: [
                      for (final (value, label) in _filters)
                        Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: ChoiceChip(
                            label: Text(label),
                            selected: _filter == value,
                            onSelected: (_) => setState(() => _filter = value),
                          ),
                        ),
                    ],
                  ),
                ),
                if (_loading) const LinearProgressIndicator(),
                if (_error != null)
                  MaterialBanner(
                    content: Text(_error!),
                    actions: [
                      TextButton(onPressed: _load, child: const Text('Retry')),
                    ],
                  ),
                Expanded(
                  key: const ValueKey('body'),
                  child: RefreshIndicator(
                    onRefresh: _load,
                    child: rows.isEmpty && !_loading
                        ? ListView(
                            physics: const AlwaysScrollableScrollPhysics(),
                            children: const [
                              SizedBox(height: 120),
                              Center(child: Text('No entries to show.')),
                            ],
                          )
                        : ListView.separated(
                            physics: const AlwaysScrollableScrollPhysics(),
                            padding: const EdgeInsets.all(12),
                            itemCount: rows.length,
                            separatorBuilder: (_, _) =>
                                const Divider(height: 1),
                            itemBuilder: (context, i) {
                              final e = rows[i];
                              final t = e['createdAt'];
                              final when = t is DateTime
                                  ? '${formatDate(t)}, ${MaterialLocalizations.of(context).formatTimeOfDay(TimeOfDay.fromDateTime(t))}'
                                  : '-';
                              return ListTile(
                                dense: true,
                                leading: Icon(_icon('${e['action']}')),
                                title: Text(_describe(e)),
                                subtitle: Text('$when   ·   ${e['action']}'),
                              );
                            },
                          ),
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.all(8),
                  child: Text(
                    'Entries cannot be edited or deleted from the app.',
                    style: TextStyle(fontSize: 11),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
