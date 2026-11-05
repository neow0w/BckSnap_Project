import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../services/api_client.dart';
import '../../services/clinic_service.dart';
import '../../core/presence_badge.dart';

class ClinicDetailsScreen extends StatefulWidget {
  const ClinicDetailsScreen({required this.clinicId, super.key});

  final String clinicId;

  @override
  State<ClinicDetailsScreen> createState() => _ClinicDetailsScreenState();
}

class _ClinicDetailsScreenState extends State<ClinicDetailsScreen> {
  final ClinicService _service = ClinicService();
  ClinicInfo? _clinic;
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
      final clinic = await _service.clinic(widget.clinicId);
      if (mounted) setState(() => _clinic = clinic);
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final clinic = _clinic;
    return Scaffold(
      appBar: AppBar(title: const Text('Clinic details')),
      body: _loading && clinic == null
          ? const Center(child: CircularProgressIndicator())
          : _error != null && clinic == null
          ? _errorView()
          : clinic == null
          ? const Center(child: Text('Clinic information is unavailable.'))
          : Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 840),
                child: ListView(
                  padding: const EdgeInsets.all(20),
                  children: [
                    if (clinic.doctors.any((doctor) => doctor.isDemo) ||
                        clinic.demoAppointmentTypes.isNotEmpty)
                      Card(
                        color: Theme.of(context).colorScheme.tertiaryContainer,
                        child: const Padding(
                          padding: EdgeInsets.all(16),
                          child: Text(
                            'Providers, specialties, schedules, and appointment options marked DEMO are fictional and are not real clinic services.',
                          ),
                        ),
                      ),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const CircleAvatar(
                          radius: 30,
                          child: Icon(Icons.local_hospital_outlined, size: 30),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                clinic.name,
                                style: Theme.of(context)
                                    .textTheme
                                    .headlineSmall,
                              ),
                              const SizedBox(height: 8),
                              Text(clinic.address),
                              if (clinic.description != null &&
                                  clinic.description!.trim().isNotEmpty) ...[
                                const SizedBox(height: 12),
                                Text(clinic.description!),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Card(
                      child: Column(
                        children: [
                          if (clinic.phone != null)
                            ListTile(
                              leading: const Icon(Icons.phone_outlined),
                              title: const Text('Phone'),
                              subtitle: Text(clinic.phone!),
                            ),
                          if (clinic.email != null)
                            ListTile(
                              leading: const Icon(Icons.email_outlined),
                              title: const Text('Email'),
                              subtitle: Text(clinic.email!),
                            ),
                          if (clinic.latitude != null &&
                              clinic.longitude != null)
                            ListTile(
                              leading: const Icon(Icons.map_outlined),
                              title: const Text('Verified map location'),
                              subtitle: Text(
                                '${clinic.latitude}, ${clinic.longitude}',
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    _section(
                      context,
                      title: 'Services',
                      icon: Icons.medical_services_outlined,
                      child: clinic.services.isEmpty
                          ? const Text('No services have been listed yet.')
                          : Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                for (final service in clinic.services)
                                  Chip(label: Text(service)),
                              ],
                            ),
                    ),
                    const SizedBox(height: 12),
                    _section(
                      context,
                      title: 'Doctors',
                      icon: Icons.person_outline,
                      child: clinic.doctors.isEmpty
                          ? const Text('No doctors are currently listed.')
                          : Column(
                              children: [
                                for (final doctor in clinic.doctors)
                                  ListTile(
                                    contentPadding: EdgeInsets.zero,
                                    leading: const CircleAvatar(
                                      child: Icon(Icons.person),
                                    ),
                                    title: Text(
                                      doctor.name ?? 'Doctor name unavailable',
                                    ),
                                    trailing: doctor.isDemo
                                        ? null
                                        : PresenceBadge(
                                            present: doctor.isPresentToday,
                                          ),
                                    subtitle: Text(
                                      [
                                        if (doctor.specializations.isNotEmpty)
                                          doctor.specializations
                                              .map(
                                                (specialization) =>
                                                    doctor.isDemo
                                                    ? 'DEMO — $specialization'
                                                    : specialization,
                                              )
                                              .join(', '),
                                        if (doctor.professionalInfo != null &&
                                            doctor.professionalInfo!
                                                .trim()
                                                .isNotEmpty)
                                          doctor.professionalInfo!,
                                      ].join('\n'),
                                    ),
                                  ),
                              ],
                            ),
                    ),
                    const SizedBox(height: 12),
                    _section(
                      context,
                      title: 'Operating hours',
                      icon: Icons.schedule_outlined,
                      child: clinic.operatingHours.isEmpty
                          ? const Text('Operating hours are not listed.')
                          : Column(
                              children: [
                                for (final day in const [
                                  'monday',
                                  'tuesday',
                                  'wednesday',
                                  'thursday',
                                  'friday',
                                  'saturday',
                                  'sunday',
                                ])
                                  if (clinic.operatingHours[day] != null)
                                    ListTile(
                                      dense: true,
                                      contentPadding: EdgeInsets.zero,
                                      title: Text(
                                        '${day[0].toUpperCase()}${day.substring(1)}',
                                      ),
                                      trailing: Text(
                                        _formatHours(
                                          clinic.operatingHours[day],
                                        ),
                                      ),
                                    ),
                              ],
                            ),
                    ),
                    if (clinic.demoOperatingHours.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      _section(
                        context,
                        title: 'Demo booking hours',
                        icon: Icons.developer_mode_outlined,
                        child: Column(
                          children: [
                            for (final day in const [
                              'monday',
                              'tuesday',
                              'wednesday',
                              'thursday',
                              'friday',
                              'saturday',
                              'sunday',
                            ])
                              if (clinic.demoOperatingHours[day] is List)
                                ListTile(
                                  dense: true,
                                  contentPadding: EdgeInsets.zero,
                                  title: Text(
                                    '${day[0].toUpperCase()}${day.substring(1)}',
                                  ),
                                  trailing: Text(
                                    _formatDemoHours(
                                      clinic.demoOperatingHours[day] as List,
                                    ),
                                  ),
                                ),
                            const Text(
                              'Fictional development schedule only; it does not represent the clinic’s verified hours.',
                            ),
                          ],
                        ),
                      ),
                    ],
                    const SizedBox(height: 12),
                    _section(
                      context,
                      title: 'Appointment types',
                      icon: Icons.event_available_outlined,
                      child: Wrap(
                        spacing: 8,
                        children: [
                          if (clinic.supportsPhysical)
                            const Chip(label: Text('In person')),
                          if (clinic.supportsOnline)
                            const Chip(label: Text('Online')),
                          for (final appointmentType
                              in clinic.demoAppointmentTypes)
                            Chip(
                              avatar: const Icon(
                                Icons.developer_mode,
                                size: 18,
                              ),
                              label: Text(appointmentType.name),
                            ),
                          if (!clinic.supportsPhysical &&
                              !clinic.supportsOnline &&
                              clinic.demoAppointmentTypes.isEmpty)
                            const Text('No appointment types are listed.'),
                        ],
                      ),
                    ),
                    if (clinic.doctors.isEmpty ||
                        (!clinic.supportsPhysical &&
                            !clinic.supportsOnline &&
                            clinic.demoAppointmentTypes.isEmpty)) ...[
                      const SizedBox(height: 12),
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Text(
                            clinic.doctors.isEmpty
                                ? 'Appointments are not yet available because no doctors have been configured for this clinic.'
                                : 'Appointments are not yet available because no appointment types have been confirmed for this clinic.',
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 20),

                    OutlinedButton.icon(
                      onPressed: () => context.push('/message/${clinic.id}'),
                      icon: const Icon(Icons.chat_bubble_outline),
                      label: const Text('Chat with Clinic'),
                    ),

                    const SizedBox(height: 12),
                    FilledButton.icon(
                      onPressed:
                          clinic.doctors.isEmpty ||
                              (!clinic.supportsPhysical &&
                                  !clinic.supportsOnline &&
                                  clinic.demoAppointmentTypes.isEmpty)
                          ? null
                          : () => context.push(
                              '/clinics/${clinic.id}/book',
                              extra: clinic,
                            ),
                      icon: const Icon(Icons.calendar_month_outlined),
                      label: const Text('Choose a doctor and appointment time'),
                    ),
                    if (_error != null)
                      TextButton.icon(
                        onPressed: _load,
                        icon: const Icon(Icons.refresh),
                        label: const Text('Refresh details'),
                      ),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _section(
    BuildContext context, {
    required String title,
    required IconData icon,
    required Widget child,
  }) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon),
              const SizedBox(width: 8),
              Text(title, style: Theme.of(context).textTheme.titleMedium),
            ],
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    ),
  );

  String _formatDemoHours(List intervals) => intervals.isEmpty
      ? 'Closed'
      : intervals
            .whereType<Map>()
            .map((item) => '${item['open']}–${item['close']}')
            .join(', ');

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

  String _formatHours(dynamic value) {
    if (value is! Map) return 'Hours unavailable';
    if (value['closed'] == true) return 'Closed';
    final opens = value['open'];
    final closes = value['close'];
    if (opens is! String || closes is! String) return 'Hours unavailable';
    return '$opens – $closes';
  }
}
