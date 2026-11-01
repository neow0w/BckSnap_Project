import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../services/api_client.dart';
import '../../services/clinic_service.dart';
import '../receptionist/add_staff_dialog.dart';

/// The clinic administrator's home: creates and deactivates staff accounts.
class AdminScreen extends StatefulWidget {
  const AdminScreen({super.key});

  @override
  State<AdminScreen> createState() => _AdminScreenState();
}

class _AdminScreenState extends State<AdminScreen> {
  final ClinicService _service = ClinicService();
  List<Map<String, dynamic>> _staff = [];
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
      final list = await _service.staffList();
      if (mounted) setState(() => _staff = list);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not load the staff list.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _addStaff() async {
    final msg = await showAddStaffDialog(context);
    if (msg == null || !mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    _load();
  }

  Future<void> _toggle(Map<String, dynamic> s) async {
    final active = s['status'] == 'active';
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          active ? 'Deactivate this account?' : 'Activate this account?',
        ),
        content: Text(
          active
              ? '${s['name']} will no longer be able to log in'
                    '${s['role'] == 'doctor' ? ' or be booked by patients' : ''}.'
              : '${s['name']} will be able to log in again.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(active ? 'Deactivate' : 'Activate'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    setState(() {
      _workingId = s['id'] as String;
      _error = null;
    });
    try {
      await _service.setStaffActive(
        s['id'] as String,
        s['role'] as String,
        !active,
        '${s['name'] ?? ''}',
      );
      await _load();
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _workingId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Clinic administration'),
        automaticallyImplyLeading: false,
        actions: [
          IconButton(
            tooltip: 'Audit log',
            onPressed: () => context.push('/admin/audit'),
            icon: const Icon(Icons.history),
          ),
          IconButton(
            tooltip: 'Clinic location',
            onPressed: () => context.push('/admin/clinic-location'),
            icon: const Icon(Icons.place_outlined),
          ),
          IconButton(
            tooltip: 'My profile',
            onPressed: () => context.push('/profile'),
            icon: const Icon(Icons.person_outline),
          ),
          IconButton(
            tooltip: 'Refresh',
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addStaff,
        icon: const Icon(Icons.person_add_alt_1),
        label: const Text('Add staff'),
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 700),
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
                  child: RefreshIndicator(
                    onRefresh: _load,
                    child: ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
                      children: [
                        _section(
                          'Receptionists',
                          'Accept appointment requests and answer patient messages.',
                          'receptionist',
                        ),
                        const SizedBox(height: 16),
                        _section(
                          'Doctors',
                          'Patients can book appointments with active doctors.',
                          'doctor',
                        ),
                      ],
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

  Widget _section(String title, String help, String role) {
    final items = _staff.where((s) => s['role'] == role).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        Text(help, style: const TextStyle(fontSize: 12)),
        const SizedBox(height: 8),
        if (items.isEmpty && !_loading)
          const Card(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Text('None yet. Tap "Add staff" to create one.'),
            ),
          ),
        for (final s in items) _tile(s),
      ],
    );
  }

  Widget _tile(Map<String, dynamic> s) {
    final active = s['status'] == 'active';
    final professions = (s['professions'] as List? ?? const [])
        .map((e) => e.toString())
        .join(', ');
    final id = s['id'] as String;
    return Card(
      child: ListTile(
        leading: CircleAvatar(
          child: Icon(
            s['role'] == 'doctor'
                ? Icons.medical_services_outlined
                : Icons.support_agent,
          ),
        ),
        title: Text((s['name'] ?? 'Unnamed').toString()),
        subtitle: Text(
          [
            (s['email'] ?? '').toString(),
            if (professions.isNotEmpty) professions,
            active ? 'Active' : 'Inactive',
          ].join('\n'),
        ),
        isThreeLine: true,
        trailing: _workingId == id
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : TextButton(
                onPressed: () => _toggle(s),
                child: Text(active ? 'Deactivate' : 'Activate'),
              ),
      ),
    );
  }
}
