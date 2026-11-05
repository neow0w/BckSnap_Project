import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../services/api_client.dart';
import '../../services/clinic_service.dart';
import '../../core/format.dart';
import '../../services/auth_service.dart';

/// Shared by the receptionist (Fig 9, isReception: true) and the doctor
/// (Fig 10, isReception: false).
class StaffAppointmentsScreen extends StatefulWidget {
  const StaffAppointmentsScreen({super.key, required this.isReception});

  final bool isReception;

  @override
  State<StaffAppointmentsScreen> createState() =>
      _StaffAppointmentsScreenState();
}

class _StaffAppointmentsScreenState extends State<StaffAppointmentsScreen> {
  final ClinicService _service = ClinicService();
  List<ClinicAppointment> _appointments = [];
  bool _loading = true;
  String? _workingId;
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
      final appointments = await _service.staffAppointments(
        state: widget.isReception ? 'pending' : null,
      );
      if (mounted) setState(() => _appointments = appointments);
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _review(ClinicAppointment appointment, bool approve) async {
    setState(() {
      _workingId = appointment.id;
      _error = null;
    });
    try {
      await _service.reviewAppointment(appointment.id, approve: approve);
      await _load();
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _workingId = null);
    }
  }

  Future<void> _completeAppointment(
    ClinicAppointment appointment,
    ) async {
      final confirm = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Complete appointment?'),
          content: Text(
            'Mark the appointment for ${appointment.patientName ?? 'this patient'} as completed?',
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
        _workingId = appointment.id;
        _error = null;
      });

      try {
        await _service.completeAppointment(appointment.id);
        await _load();
      } on ApiException catch (error) {
        if (mounted) {
          setState(() => _error = error.message);
        }
      } finally {
        if (mounted) {
          setState(() => _workingId = null);
        }
      }
  }

  Future<void> _joinMeeting(ClinicAppointment appointment) async {
    setState(() {
      _workingId = appointment.id;
      _error = null;
    });

    try {
      await _service.startInstantMeeting(appointment.id);

      final credentials = await _service.consultation(appointment.id);

      if (!mounted) return;

      await context.push('/consultation/${appointment.id}', extra: credentials);
    } on ApiException catch (error) {
      if (mounted) {
        setState(() => _error = error.message);
      }
    } finally {
      if (mounted) {
        setState(() => _workingId = null);
      }
    }
  }

  Future<void> _openConsultationChat(ClinicAppointment appointment) async {
    if (widget.isReception) return;

    await context.push('/consultation-chat/${appointment.id}');
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(
        widget.isReception
            ? 'Clinic appointment requests'
            : 'Clinic appointments',
      ),
      actions: [
        if (widget.isReception)
          IconButton(
            tooltip: 'Messages',
            onPressed: () => context.push('/reception/inbox'),
            icon: const Icon(Icons.inbox_outlined),
          ),
        if (widget.isReception)
          IconButton(
            tooltip: 'Doctor profiles',
            onPressed: () => context.push('/reception/doctors'),
            icon: const Icon(Icons.medical_services_outlined),
          ),
        if (AuthService().isStaffAccount)
          IconButton(
            tooltip: 'Switch profile',
            onPressed: () {
              AuthService().leaveProfile();
              context.go('/profiles');
            },
            icon: const Icon(Icons.switch_account_outlined),
          ),
        IconButton(
          tooltip: 'My profile',
          onPressed: () => context.push('/profile'),
          icon: const Icon(Icons.person_outline),
        ),
      ],
    ),
    body: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 900),
        child: Column(
          children: [
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
              child: _loading && _appointments.isEmpty
                  ? const Center(child: CircularProgressIndicator())
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: _appointments.isEmpty
                          ? ListView(
                              physics: const AlwaysScrollableScrollPhysics(),
                              children: [
                                const SizedBox(height: 120),
                                Center(
                                  child: Text(
                                    widget.isReception
                                        ? 'There are no pending appointment requests.'
                                        : 'There are no clinic appointments.',
                                  ),
                                ),
                              ],
                            )
                          : ListView.separated(
                              physics: const AlwaysScrollableScrollPhysics(),
                              padding: const EdgeInsets.all(12),
                              itemCount: _appointments.length,
                              separatorBuilder: (_, _) =>
                                  const SizedBox(height: 8),
                              itemBuilder: (context, index) =>
                                  _card(context, _appointments[index]),
                            ),
                    ),
            ),
          ],
        ),
      ),
    ),
  );

  Widget _card(BuildContext context, ClinicAppointment appointment) {
    final working = _workingId == appointment.id;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              appointment.clinicName ?? 'Clinic information unavailable',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text('Patient: ${appointment.patientName ?? appointment.userId}'),
            if (appointment.doctorName != null)
              Text('Doctor: ${appointment.doctorName}'),
            if (appointment.scheduledAt != null)
              Text(
                'Time: ${formatDateTime(appointment.scheduledAt!.toLocal())}',
              ),
            Text(
              'Type: ${appointment.mode == 'online' ? 'Online' : 'In person'}',
            ),
            Text('Reference: ${appointment.reference ?? 'Unavailable'}'),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              children: [
                if (widget.isReception && appointment.status == 'pending') ...[
                  FilledButton.icon(
                    onPressed: working
                        ? null
                        : () => _review(appointment, true),
                    icon: const Icon(Icons.check),
                    label: const Text('Approve'),
                  ),
                  OutlinedButton.icon(
                    onPressed: working
                        ? null
                        : () => _review(appointment, false),
                    icon: const Icon(Icons.close),
                    label: const Text('Reject'),
                  ),
                ] else
                  Chip(label: Text(appointmentStatusLabel(appointment.status))),
                  if (!widget.isReception &&
                    appointment.status == 'approved') ...[
                      FilledButton.icon(
                        onPressed: working
                          ? null
                          : () => _completeAppointment(appointment),
                        icon: const Icon(Icons.check_circle_outline),
                        label: const Text('Mark as Completed'),
                      ),
                    ],
                  if (!widget.isReception &&
                    appointment.status == 'approved' &&
                    appointment.mode == 'online') ...[
                  FilledButton.icon(
                    onPressed: working ? null : () => _joinMeeting(appointment),
                    icon: const Icon(Icons.video_call),
                    label: const Text('Start Instant Meeting'),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => _openConsultationChat(appointment),
                    icon: const Icon(Icons.chat),
                    label: const Text('Chat'),
                  ),
                ],
                if (working)
                  const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
