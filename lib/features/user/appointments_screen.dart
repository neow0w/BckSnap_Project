import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../services/api_client.dart';
import '../../services/clinic_service.dart';
import '../../core/presence_badge.dart';

class AppointmentsScreen extends StatefulWidget {
  const AppointmentsScreen({super.key});

  @override
  State<AppointmentsScreen> createState() => _AppointmentsScreenState();
}

class _AppointmentsScreenState extends State<AppointmentsScreen> {
  final ClinicService _service = ClinicService();
  String? _state;
  String? _error;
  bool _loading = true;
  List<ClinicAppointment> _appointments = [];

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
      final appointments = await _service.appointments(state: _state);
      if (mounted) setState(() => _appointments = appointments);
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  
Future<void> _cancelAppointment(ClinicAppointment appointment) async {
  final controller = TextEditingController();
  final formKey = GlobalKey<FormState>();

  final reason = await showDialog<String>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Cancel appointment?'),
      content: Form(
        key: formKey,
        child: TextFormField(
          controller: controller,
          minLines: 2,
          maxLines: 4,
          maxLength: 1000,
          decoration: const InputDecoration(
            labelText: 'Reason for cancellation',
            border: OutlineInputBorder(),
          ),
          validator: (value) =>
              value == null || value.trim().isEmpty
                  ? 'A cancellation reason is required.'
                  : null,
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext),
          child: const Text('Keep appointment'),
        ),
        FilledButton(
          onPressed: () {
            if (formKey.currentState!.validate()) {
              Navigator.pop(dialogContext, controller.text.trim());
            }
          },
          child: const Text('Confirm cancellation'),
        ),
      ],
    ),
  );

  controller.dispose();

  if (reason == null || !mounted) return;

  try {
    await _service.cancel(appointment.id, reason);

    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Appointment cancelled successfully.'),
        backgroundColor: Colors.green,
      ),
    );

    await _load();
  } on ApiException catch (error) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(error.message)),
    );
  }
}


  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      leading: IconButton(
        tooltip: 'Back',
        icon: const Icon(Icons.arrow_back),
        onPressed: () {
          if (context.canPop()) {
            context.pop();
          } else {
            context.go('/home');
          }
        },
      ),
      title: const Text('My appointments'),
      actions: [
        IconButton(
          tooltip: 'Notifications',
          onPressed: () => context.push('/notifications'),
          icon: const Icon(Icons.notifications_outlined),
        ),
      ],
    ),
    body: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 900),
        child: Column(
          children: [
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.all(12),
              child: Wrap(
                spacing: 8,
                children: [
                  _filter('All', null),
                  _filter('Upcoming', 'upcoming'),
                  _filter('Pending', 'pending'),
                  _filter('Past', 'past'),
                  _filter('Cancelled', 'cancelled'),
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
              child: _loading && _appointments.isEmpty
                  ? const Center(child: CircularProgressIndicator())
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: _appointments.isEmpty
                          ? ListView(
                              physics: const AlwaysScrollableScrollPhysics(),
                              children: [const SizedBox(height: 80), _empty()],
                            )
                          : ListView.separated(
                              physics: const AlwaysScrollableScrollPhysics(),
                              padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
                              itemCount: _appointments.length,
                              separatorBuilder: (_, _) =>
                                  const SizedBox(height: 8),
                              itemBuilder: (context, index) =>
                                  _appointmentCard(_appointments[index]),
                            ),
                    ),
            ),
          ],
        ),
      ),
    ),
  );

  Widget _filter(String label, String? value) => ChoiceChip(
    label: Text(label),
    selected: _state == value,
    onSelected: (_) {
      setState(() => _state = value);
      _load();
    },
  );

  bool _showPresence(ClinicAppointment a) =>
      a.doctorId != null &&
      !a.isDemo &&
      (a.status == 'pending' || a.status == 'approved');

  Widget _appointmentCard(ClinicAppointment appointment) => Card(
    child: ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      leading: CircleAvatar(
        child: Icon(
          appointment.mode == 'online' ? Icons.videocam_outlined : Icons.event,
        ),
      ),
      title: Text(
        appointment.clinicName ?? 'Clinic information unavailable',
        style: const TextStyle(fontWeight: FontWeight.w600),
      ),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (appointment.doctorName != null)
              Text('Doctor: ${appointment.doctorName}'),
            if (_showPresence(appointment))
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: DoctorPresenceLive(doctorId: appointment.doctorId!),
              ),
            Text(
              'Type: ${appointment.mode == 'online'
                  ? (appointment.isDemo ? 'Online — SIMULATED DEMO ONLY' : 'Online')
                  : appointment.mode == 'physical'
                  ? (appointment.isDemo ? 'In person — DEMO ONLY' : 'In person')
                  : 'Unavailable'}',
            ),
            if (appointment.scheduledAt != null)
              Text(
                _formatDateTime(context, appointment.scheduledAt!.toLocal()),
              ),
            if (appointment.reference != null)
              Text('Reference: ${appointment.reference}'),
            if (appointment.isDemo)
              const Padding(
                padding: EdgeInsets.only(top: 4),
                child: Text(
                  'DEMO APPOINTMENT — fictional development data; online consultation is simulated only.',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
            const SizedBox(height: 6),
            _status(appointment.status),
          ],
        ),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
    if (appointment.canCancel)
      IconButton(
        tooltip: 'Cancel appointment',
        onPressed: () => _cancelAppointment(appointment),
          icon: const Icon(
            Icons.event_busy_outlined,
            color: Colors.red,
            ),
          ),
          const Icon(Icons.chevron_right),
        ],
      ),
      onTap: () => context.push('/appointments/${appointment.id}'),
    ),
  );

  Widget _empty() => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.event_note_outlined, size: 44),
          const SizedBox(height: 12),
          const Text('No appointments in this view.'),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: () => context.go('/clinics'),
            icon: const Icon(Icons.search),
            label: const Text('Find a clinic'),
          ),
        ],
      ),
    ),
  );
}

class AppointmentDetailsScreen extends StatefulWidget {
  const AppointmentDetailsScreen({required this.appointmentId, super.key});

  final String appointmentId;

  @override
  State<AppointmentDetailsScreen> createState() =>
      _AppointmentDetailsScreenState();
}

class _AppointmentDetailsScreenState extends State<AppointmentDetailsScreen> {
  final ClinicService _service = ClinicService();
  ClinicAppointment? _appointment;
  bool _loading = true;
  bool _actionLoading = false;
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
      final appointment = await _service.appointment(widget.appointmentId);
      if (mounted) setState(() => _appointment = appointment);
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _cancel() async {
    final controller = TextEditingController();
    final formKey = GlobalKey<FormState>();
    final reason = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Cancel appointment?'),
        content: Form(
          key: formKey,
          child: TextFormField(
            controller: controller,
            minLines: 2,
            maxLines: 4,
            maxLength: 1000,
            decoration: const InputDecoration(
              labelText: 'Reason for cancellation',
              border: OutlineInputBorder(),
            ),
            validator: (value) => value == null || value.trim().isEmpty
                ? 'A cancellation reason is required.'
                : null,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Keep appointment'),
          ),
          FilledButton(
            onPressed: () {
              if (formKey.currentState!.validate()) {
                Navigator.pop(dialogContext, controller.text.trim());
              }
            },
            child: const Text('Confirm cancellation'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (reason == null || !mounted) return;
    setState(() {
      _actionLoading = true;
      _error = null;
    });
    try {
      _appointment = await _service.cancel(widget.appointmentId, reason);
      if (mounted) setState(() {});
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _actionLoading = false);
    }
  }

  Future<void> _joinConsultation() async {
    setState(() {
      _actionLoading = true;
      _error = null;
    });

    try {
      final credentials = await _service.consultation(widget.appointmentId);

      if (!mounted) return;

      await context.push(
        '/consultation/${widget.appointmentId}',
        extra: credentials,
      );
    } on ApiException catch (error) {
      if (mounted) {
        setState(() => _error = error.message);
      }
    } finally {
      if (mounted) {
        setState(() => _actionLoading = false);
      }
    }
  }

  Future<void> _openConsultationChat() async {
    await context.push('/consultation-chat/${widget.appointmentId}');
  }

  @override
  Widget build(BuildContext context) {
    final appointment = _appointment;
    return Scaffold(
      appBar: AppBar(title: const Text('Appointment details')),
      body: _loading && appointment == null
          ? const Center(child: CircularProgressIndicator())
          : _error != null && appointment == null
          ? _errorView()
          : appointment == null
          ? const Center(child: Text('Appointment is unavailable.'))
          : RefreshIndicator(
              onRefresh: _load,
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 700),
                  child: ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.all(20),
                    children: [
                      Text(
                        appointment.clinicName ??
                            'Clinic information unavailable',
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                      const SizedBox(height: 16),
                      _status(appointment.status),
                      if (appointment.isDemo) ...[
                        const SizedBox(height: 12),
                        Card(
                          color: Theme.of(context)
                              .colorScheme
                              .tertiaryContainer,
                          child: const Padding(
                            padding: EdgeInsets.all(16),
                            child: Text(
                              'DEMO APPOINTMENT — fictional development data. Online consultation is simulated only; no real meeting link is available.',
                            ),
                          ),
                        ),
                      ],
                      const SizedBox(height: 16),
                      _detail(
                        'Reference',
                        appointment.reference ?? 'Unavailable',
                      ),
                      _detail(
                        'Doctor',
                        appointment.doctorName ?? 'Unavailable',
                      ),
                      _detail(
                        'Appointment type',
                        appointment.mode == 'online'
                            ? appointment.isDemo
                                  ? 'Online — SIMULATED DEMO ONLY'
                                  : 'Online consultation'
                            : appointment.mode == 'physical'
                            ? appointment.isDemo
                                  ? 'In-person — DEMO ONLY'
                                  : 'In-person visit'
                            : 'Unavailable',
                      ),
                      _detail(
                        'Date and time',
                        appointment.scheduledAt == null
                            ? 'Not scheduled'
                            : _formatDateTime(
                                context,
                                appointment.scheduledAt!.toLocal(),
                              ),
                      ),
                      if (appointment.mode == 'physical')
                        _detail(
                          'Clinic address',
                          appointment.clinicAddress ?? 'Address unavailable',
                        ),
                      if (appointment.cancellationReason != null)
                        _detail(
                          'Cancellation reason',
                          appointment.cancellationReason!,
                        ),
                      if (_error != null) ...[
                        const SizedBox(height: 16),
                        Text(
                          _error!,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                      ],
                      if (appointment.status == 'approved' &&
                          appointment.mode == 'online' &&
                          !appointment.isDemo) ...[
                        const SizedBox(height: 20),
                        FilledButton.icon(
                          onPressed: _actionLoading ? null : _joinConsultation,
                          icon: const Icon(Icons.video_call_outlined),
                          label: const Text('Join consultation'),
                        ),
                        const SizedBox(height: 8),
                        OutlinedButton.icon(
                          onPressed: _openConsultationChat,
                          icon: const Icon(Icons.chat_outlined),
                          label: const Text('Open consultation chat'),
                        ),
                      ],
                      if (appointment.canCancel) ...[
                        const SizedBox(height: 12),
                        OutlinedButton.icon(
                          onPressed: _actionLoading ? null : _cancel,
                          icon: const Icon(Icons.event_busy_outlined),
                          label: const Text('Cancel appointment'),
                        ),
                      ],
                      if (_actionLoading)
                        const Padding(
                          padding: EdgeInsets.all(16),
                          child: Center(child: CircularProgressIndicator()),
                        ),
                    ],
                  ),
                ),
              ),
            ),
    );
  }

  Widget _detail(String label, String value) => ListTile(
    contentPadding: EdgeInsets.zero,
    title: Text(label, style: Theme.of(context).textTheme.labelLarge),
    subtitle: Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Text(value),
    ),
  );

  Widget _errorView() => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(_error!, textAlign: TextAlign.center),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: _load,
            icon: const Icon(Icons.refresh),
            label: const Text('Try again'),
          ),
        ],
      ),
    ),
  );
}

Widget _status(String status) {
  final (label, color) = switch (status) {
    'pending' => ('Pending', Colors.orange),
    'approved' => ('Approved', Colors.green),
    'rejected' || 'declined' => ('Rejected', Colors.red),
    'cancelled' => ('Cancelled', Colors.grey),
    'completed' => ('Completed', Colors.blue),
    _ => (status, Colors.grey),
  };
  return Chip(
    label: Text(label),
    side: BorderSide.none,
    backgroundColor: color.withValues(alpha: 0.15),
    labelStyle: TextStyle(color: color, fontWeight: FontWeight.w600),
  );
}

String _formatDateTime(BuildContext context, DateTime value) {
  final local = value.toLocal();
  final date = MaterialLocalizations.of(context).formatMediumDate(local);
  return '$date, ${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
}
