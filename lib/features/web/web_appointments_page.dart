import 'package:firebase_core/firebase_core.dart' show FirebaseException;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/format.dart';
import '../../services/api_client.dart';
import '../../services/clinic_service.dart';
import 'staff_web_shell.dart';

/// Receptionist: all appointment requests, with approve / reject.
/// Doctor: their own appointments (read only).
class WebAppointmentsPage extends StatefulWidget {
  const WebAppointmentsPage({super.key, required this.isReception});

  final bool isReception;

  @override
  State<WebAppointmentsPage> createState() => _WebAppointmentsPageState();
}

class _WebAppointmentsPageState extends State<WebAppointmentsPage> {
  static const _filters = [
    ('all', 'All'),
    ('pending', 'Pending'),
    ('approved', 'Approved'),
    ('rejected', 'Rejected'),
    ('cancelled', 'Cancelled'),
  ];

  final ClinicService _service = ClinicService();
  late final Stream<List<ClinicAppointment>> _stream = _service
      .staffAppointmentsStream();
  final TextEditingController _search = TextEditingController();
  late String _filter = widget.isReception ? 'pending' : 'all';
  String? _workingId;
  String? _actionError;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  bool _matches(ClinicAppointment a, String filter) => switch (filter) {
    'all' => true,
    'rejected' => a.status == 'rejected' || a.status == 'declined',
    _ => a.status == filter,
  };

  Future<void> _review(ClinicAppointment a, bool approve) async {
    setState(() {
      _workingId = a.id;
      _actionError = null;
    });
    try {
      await _service.reviewAppointment(a.id, approve: approve);
    } on ApiException catch (e) {
      if (mounted) setState(() => _actionError = e.message);
    } finally {
      if (mounted) setState(() => _workingId = null);
    }
  }

  Future<void> _joinMeeting(ClinicAppointment a) async {
    setState(() {
      _workingId = a.id;
      _actionError = null;
    });

    try {
      await _service.startInstantMeeting(a.id);

      final credentials = await _service.consultation(a.id);

      if (!mounted) return;

      await context.push('/consultation/${a.id}', extra: credentials);
    } on ApiException catch (e) {
      if (mounted) {
        setState(() => _actionError = e.message);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _actionError = 'Could not start the consultation: $e');
      }
    } finally {
      if (mounted) {
        setState(() => _workingId = null);
      }
    }
  }

  Future<void> _completeAppointment(ClinicAppointment a) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Complete appointment?'),
        content: Text(
          'Mark the appointment for ${a.patientName ?? 'this patient'} '
          'as completed?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Confirm'),
          ),
        ],
      ),
    );

    if (confirm != true || !mounted) return;

    setState(() {
      _workingId = a.id;
      _actionError = null;
    });

    try {
      await _service.completeAppointment(a.id);
    } on ApiException catch (e) {
      if (mounted) {
        setState(() => _actionError = e.message);
      }
    } finally {
      if (mounted) {
        setState(() => _workingId = null);
      }
    }
  }

  Future<void> _openConsultationChat(ClinicAppointment a) async {
    debugPrint('CHAT BUTTON CLICKED: ${a.id}');

    try {
      await GoRouter.of(context).push('/consultation-chat/${a.id}');

      debugPrint('CHAT ROUTE CLOSED');
    } catch (e, stackTrace) {
      debugPrint('CHAT NAVIGATION ERROR: $e');
      debugPrintStack(stackTrace: stackTrace);
    }
  }

  String _errorText(Object? e) => e is FirebaseException
      ? apiErrorFrom(e).message
      : 'Could not load the appointments.';

  String _when(BuildContext context, DateTime? t) {
    if (t == null) return '-';
    final localStart = t.toLocal();
    final localEnd = localStart.add(const Duration(minutes: 60));
    final localizations = MaterialLocalizations.of(context);
    final startTime = localizations.formatTimeOfDay(
      TimeOfDay.fromDateTime(localStart),
    );
    final endTime = localizations.formatTimeOfDay(
      TimeOfDay.fromDateTime(localEnd),
    );
    return '${formatDate(localStart)}, $startTime - $endTime';
  }

  Widget _statusChip(String status) {
    final color = switch (status) {
      'pending' => Colors.orange,
      'approved' => Colors.green,
      'rejected' || 'declined' => Colors.red,
      'completed' => Colors.blue,
      _ => Colors.grey,
    };
    return Chip(
      label: Text(appointmentStatusLabel(status)),
      side: BorderSide.none,
      visualDensity: VisualDensity.compact,
      backgroundColor: color.withValues(alpha: 0.15),
      labelStyle: TextStyle(color: color, fontWeight: FontWeight.w600),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          WebPageHeader(
            title: widget.isReception
                ? 'Appointment requests'
                : 'My appointments',
            subtitle: widget.isReception
                ? 'Requests from patients of your clinic. New ones appear automatically.'
                : 'Appointments patients booked with you.',
          ),
          const SizedBox(height: 16),
          Expanded(
            child: StreamBuilder<List<ClinicAppointment>>(
              stream: _stream,
              builder: (context, snap) {
                if (snap.hasError) {
                  return Center(child: Text(_errorText(snap.error)));
                }
                if (!snap.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final all = snap.data!;
                final q = _search.text.trim().toLowerCase();
                final rows = all.where((a) {
                  if (!_matches(a, _filter)) return false;
                  if (q.isEmpty) return true;
                  final hay = [
                    a.patientName,
                    a.reference,
                    a.doctorName,
                  ].whereType<String>().join(' ').toLowerCase();
                  return hay.contains(q);
                }).toList();

                return Column(
                  children: [
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        SizedBox(
                          width: 300,
                          child: TextField(
                            controller: _search,
                            onChanged: (_) => setState(() {}),
                            decoration: const InputDecoration(
                              hintText: 'Search patient, doctor or reference',
                              prefixIcon: Icon(Icons.search),
                              isDense: true,
                            ),
                          ),
                        ),
                        for (final (value, label) in _filters)
                          ChoiceChip(
                            label: Text(
                              '$label (${all.where((a) => _matches(a, value)).length})',
                            ),
                            selected: _filter == value,
                            onSelected: (_) => setState(() => _filter = value),
                          ),
                      ],
                    ),
                    if (_actionError != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(
                          _actionError!,
                          style: const TextStyle(color: Colors.red),
                        ),
                      ),
                    const SizedBox(height: 12),
                    Expanded(
                      child: rows.isEmpty
                          ? const Center(
                              child: Text('No appointments match this view.'),
                            )
                          : _table(context, rows),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _table(BuildContext context, List<ClinicAppointment> rows) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: LayoutBuilder(
        builder: (context, c) => SingleChildScrollView(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: ConstrainedBox(
              constraints: BoxConstraints(minWidth: c.maxWidth),
              child: DataTable(
                columns: [
                  const DataColumn(label: Text('Reference')),
                  const DataColumn(label: Text('Patient')),
                  const DataColumn(label: Text('Doctor')),
                  const DataColumn(label: Text('Date and time')),
                  const DataColumn(label: Text('Type')),
                  const DataColumn(label: Text('Status')),
                  if (widget.isReception)
                    const DataColumn(label: Text('Referral')),
                  const DataColumn(label: Text('Actions')),
                ],
                rows: [
                  for (final a in rows)
                    DataRow(
                      cells: [
                        DataCell(Text(a.reference ?? '-')),
                        DataCell(Text(a.patientName ?? a.userId)),
                        DataCell(Text(a.doctorName ?? '-')),
                        DataCell(Text(_when(context, a.scheduledAt))),
                        DataCell(
                          Text(a.mode == 'online' ? 'Online' : 'In person'),
                        ),
                        DataCell(_statusChip(a.status)),
                        if (widget.isReception)
                          DataCell(_referralAction(a)),
                        DataCell(
                          widget.isReception ? _actions(a) : _doctorActions(a),
                        ),
                      ],
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _viewReferral(ClinicAppointment a) async {
    final bytes = a.referralImageBytes;

    if (bytes == null || bytes.isEmpty) {
      return;
    }

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => Dialog(
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            maxWidth: 850,
            maxHeight: 750,
          ),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Referral document',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Close',
                      onPressed: () => Navigator.pop(dialogContext),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  'Appointment ${a.reference ?? a.id}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 16),
                Flexible(
                  child: InteractiveViewer(
                    minScale: 0.5,
                    maxScale: 4,
                    child: Center(
                      child: Image.memory(
                        bytes,
                        fit: BoxFit.contain,
                        errorBuilder: (context, error, stackTrace) =>
                            const Padding(
                          padding: EdgeInsets.all(24),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.broken_image_outlined,
                                size: 48,
                                color: Colors.grey,
                              ),
                              SizedBox(height: 12),
                              Text(
                                'The referral file could not be displayed. '
                                'Please check that the uploaded file is a '
                                'supported image.',
                                textAlign: TextAlign.center,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _referralAction(ClinicAppointment a) {
    final hasReferral =
        a.referralImageBytes != null && a.referralImageBytes!.isNotEmpty;

    if (!hasReferral) {
      return const Tooltip(
        message: 'No referral uploaded',
        child: Icon(
          Icons.insert_drive_file_outlined,
          color: Colors.grey,
        ),
      );
    }

    return IconButton(
      tooltip: 'View referral',
      onPressed: () => _viewReferral(a),
      icon: const Icon(
        Icons.visibility_outlined,
        color: Colors.blue,
      ),
    );
  }

  Widget _actions(ClinicAppointment a) {
    if (_workingId == a.id) {
      return const SizedBox(
        width: 20,
        height: 20,
        child: CircularProgressIndicator(strokeWidth: 2),
      );
    }
    if (a.status != 'pending') return const Text('-');
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          tooltip: 'Approve',
          onPressed: () => _review(a, true),
          icon: const Icon(Icons.check_circle_outline, color: Colors.green),
        ),
        IconButton(
          tooltip: 'Reject',
          onPressed: () => _review(a, false),
          icon: const Icon(Icons.cancel_outlined, color: Colors.red),
        ),
      ],
    );
  }

  Widget _doctorActions(ClinicAppointment a) {
  if (_workingId == a.id) {
    return const SizedBox(
      width: 24,
      height: 24,
      child: CircularProgressIndicator(strokeWidth: 2),
    );
  }

  if (a.status != 'approved') {
    return const Text('-');
  }

  return Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      IconButton(
        tooltip: 'Mark as Completed',
        onPressed: () => _completeAppointment(a),
        icon: const Icon(
          Icons.check_circle_outline,
          color: Colors.green,
        ),
      ),
      if (a.mode == 'online' && !a.isDemo) ...[
        IconButton(
          tooltip: 'Start Instant Meeting',
          onPressed: () => _joinMeeting(a),
          icon: const Icon(
            Icons.video_call,
            color: Colors.blue,
          ),
        ),
        IconButton(
          tooltip: 'Open Consultation Chat',
          onPressed: () => _openConsultationChat(a),
          icon: const Icon(
            Icons.chat,
            color: Colors.green,
          ),
        ),
      ],
    ],
  );
}
}