import 'package:firebase_core/firebase_core.dart' show FirebaseException;
import 'package:flutter/material.dart';

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

  String _errorText(Object? e) => e is FirebaseException
      ? apiErrorFrom(e).message
      : 'Could not load the appointments.';

  String _when(BuildContext context, DateTime? t) {
    if (t == null) return '-';
    final local = t.toLocal();
    final time = MaterialLocalizations.of(context)
        .formatTimeOfDay(TimeOfDay.fromDateTime(local));
    return '${formatDate(local)}, $time';
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
                        if (widget.isReception) DataCell(_actions(a)),
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
}
