import 'package:firebase_core/firebase_core.dart' show FirebaseException;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/format.dart';
import '../../services/api_client.dart';
import '../../services/auth_service.dart';
import '../../services/clinic_registration_service.dart';
import '../../services/clinic_service.dart';

/// Developer: reviews the clinics that registered on the website.
class DeveloperClinicsPage extends StatefulWidget {
  const DeveloperClinicsPage({super.key});

  @override
  State<DeveloperClinicsPage> createState() => _DeveloperClinicsPageState();
}

class _DeveloperClinicsPageState extends State<DeveloperClinicsPage> {
  static const _filters = [
    ('pending', 'Pending'),
    ('approved', 'Approved'),
    ('rejected', 'Rejected'),
    ('all', 'All'),
  ];

  final _service = ClinicRegistrationService();
  late final Stream<List<ClinicRegistration>> _stream = _service.stream();
  String _filter = 'pending';
  String? _workingId;
  String? _error;

  bool _matches(ClinicRegistration r, String f) => f == 'all' || r.status == f;

  Color _statusColor(String s) => switch (s) {
    'approved' => Colors.green,
    'rejected' => Colors.red,
    _ => Colors.orange,
  };

  String _statusLabel(String s) => switch (s) {
    'approved' => 'Approved',
    'rejected' => 'Rejected',
    _ => 'Pending',
  };

  String _errorText(Object? e) => e is FirebaseException
      ? apiErrorFrom(e).message
      : 'Could not load the registrations.';

  Future<void> _logout() async {
    await AuthService().logout();
    if (mounted) context.go('/login');
  }

  Future<void> _run(String id, Future<void> Function() action) async {
    setState(() {
      _workingId = id;
      _error = null;
    });
    try {
      await action();
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _workingId = null);
    }
  }

  Future<void> _approve(ClinicRegistration r) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Approve this clinic?'),
        content: Text(
          '${r.clinicName} will be added to BckSnap and shown to patients. '
          '${r.applicantName} will be able to log in as its administrator.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Approve'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    double? lat;
    double? lng;
    try {
      final found = await ClinicService().geocode(r.address);
      if (found.isNotEmpty) {
        lat = found.first.latitude;
        lng = found.first.longitude;
      }
    } catch (_) {} // the admin can fix it on the Clinic page
    await _run(r.id, () => _service.approve(r, latitude: lat, longitude: lng));
  }

  Future<void> _reject(ClinicRegistration r) async {
    final ctrl = TextEditingController();
    final reason = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Reject this registration?'),
        content: SizedBox(
          width: 400,
          child: TextField(
            controller: ctrl,
            maxLines: 3,
            maxLength: 300,
            decoration: const InputDecoration(
              labelText: 'Reason (optional)',
              border: OutlineInputBorder(),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text),
            child: const Text('Reject'),
          ),
        ],
      ),
    );
    ctrl.dispose();
    if (reason == null) return;
    await _run(r.id, () => _service.reject(r, reason));
  }

  Widget _line(String label, String? value) {
    if (value == null || value.trim().isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 3),
      child: Text.rich(
        TextSpan(
          children: [
            TextSpan(
              text: '$label: ',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            TextSpan(text: value),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Clinic registrations'),
        actions: [
          IconButton(
            tooltip: 'Log out',
            onPressed: _logout,
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 900),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: StreamBuilder<List<ClinicRegistration>>(
                stream: _stream,
                builder: (context, snap) {
                  if (snap.hasError) {
                    return Center(child: Text(_errorText(snap.error)));
                  }
                  if (!snap.hasData) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  final all = snap.data!;
                  final rows = all.where((r) => _matches(r, _filter)).toList();
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Clinics that asked to join BckSnap. Approving adds the '
                        'clinic and activates its administrator login.',
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final (value, label) in _filters)
                            ChoiceChip(
                              label: Text(
                                '$label (${all.where((r) => _matches(r, value)).length})',
                              ),
                              selected: _filter == value,
                              onSelected: (_) =>
                                  setState(() => _filter = value),
                            ),
                        ],
                      ),
                      if (_error != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Text(
                            _error!,
                            style: const TextStyle(color: Colors.red),
                          ),
                        ),
                      const SizedBox(height: 12),
                      Expanded(
                        child: rows.isEmpty
                            ? const Center(
                                child: Text('No registrations in this view.'),
                              )
                            : ListView.separated(
                                itemCount: rows.length,
                                separatorBuilder: (_, _) =>
                                    const SizedBox(height: 8),
                                itemBuilder: (context, i) => _card(rows[i]),
                              ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _card(ClinicRegistration r) {
    final working = _workingId == r.id;
    final color = _statusColor(r.status);
    final visits = [
      if (r.supportsPhysical) 'In person',
      if (r.supportsOnline) 'Online',
    ].join(', ');
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    r.clinicName,
                    style: Theme.of(context).textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.bold),
                  ),
                ),
                Chip(
                  label: Text(_statusLabel(r.status)),
                  side: BorderSide.none,
                  visualDensity: VisualDensity.compact,
                  backgroundColor: color.withValues(alpha: 0.15),
                  labelStyle: TextStyle(
                    color: color,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            _line('Address', r.address),
            _line('Phone', r.phone),
            _line('Clinic email', r.clinicEmail),
            _line('Services', r.services.join(', ')),
            _line('Visit types', visits),
            _line('License number', r.licenseNumber),
            _line('About', r.description),
            const Divider(height: 24),
            _line('Applicant', '${r.applicantName} · ${r.applicantEmail}'),
            _line(
              'Submitted',
              r.createdAt == null
                  ? null
                  : formatDateTime(r.createdAt!.toLocal()),
            ),
            if (r.status == 'rejected')
              _line('Reason', r.rejectionReason ?? 'No reason given'),
            if (r.status != 'approved') ...[
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  FilledButton.icon(
                    onPressed: working ? null : () => _approve(r),
                    icon: const Icon(Icons.check),
                    label: const Text('Approve'),
                  ),
                  if (r.status == 'pending')
                    OutlinedButton.icon(
                      onPressed: working ? null : () => _reject(r),
                      icon: const Icon(Icons.close),
                      label: const Text('Reject'),
                    ),
                  if (working)
                    const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
