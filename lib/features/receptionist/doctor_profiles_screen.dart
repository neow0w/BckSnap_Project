import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../models/staff_profile.dart';
import '../../services/api_client.dart';
import '../../services/profile_service.dart';
import 'add_profile_dialog.dart';

/// Receptionist: the clinic's doctor profiles. New ones wait for the
/// administrator's approval.
class DoctorProfilesScreen extends StatefulWidget {
  final bool embedded; // true inside the website frame
  const DoctorProfilesScreen({super.key, this.embedded = false});

  @override
  State<DoctorProfilesScreen> createState() => _DoctorProfilesScreenState();
}

class _DoctorProfilesScreenState extends State<DoctorProfilesScreen> {
  final _service = ProfileService();
  List<StaffProfile> _doctors = [];
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
      final all = await _service.profiles();
      if (mounted) {
        setState(() => _doctors = all.where((p) => p.isDoctor).toList());
      }
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Could not load the doctor profiles.');
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _add() async {
    final msg = await showAddProfileDialog(context);
    if (msg == null || !mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    _load();
  }

  (IconData, Color) _statusLook(String status) => switch (status) {
    'active' => (Icons.check_circle_outline, Colors.green),
    'pending' => (Icons.hourglass_top, Colors.orange),
    'rejected' => (Icons.cancel_outlined, Colors.red),
    _ => (Icons.pause_circle_outline, Colors.grey),
  };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: widget.embedded
          ? null
          : AppBar(
              title: const Text('Doctor profiles'),
              leading: BackButton(
                onPressed: () =>
                    context.canPop() ? context.pop() : context.go('/reception'),
              ),
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _add,
        icon: const Icon(Icons.person_add_alt_1),
        label: const Text('Add doctor'),
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
                  key: const ValueKey('body'),
                  child: RefreshIndicator(
                    onRefresh: _load,
                    child: ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
                      children: [
                        if (widget.embedded)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: Text(
                              'Doctor profiles',
                              style: Theme.of(context).textTheme.headlineSmall
                                  ?.copyWith(fontWeight: FontWeight.bold),
                            ),
                          ),
                        const Card(
                          child: Padding(
                            padding: EdgeInsets.all(16),
                            child: Text(
                              'A new doctor profile is sent to the clinic '
                              'administrator. It can be used and booked by '
                              'patients only after it is approved.',
                              style: TextStyle(fontSize: 12),
                            ),
                          ),
                        ),
                        if (_doctors.isEmpty && !_loading)
                          const Card(
                            child: Padding(
                              padding: EdgeInsets.all(16),
                              child: Text('No doctor profiles yet.'),
                            ),
                          ),
                        for (final d in _doctors) _tile(d),
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

  Widget _tile(StaffProfile d) {
    final (icon, color) = _statusLook(d.status);
    return Card(
      child: ListTile(
        leading: const CircleAvatar(
          child: Icon(Icons.medical_services_outlined),
        ),
        title: Text(d.name),
        subtitle: Text(
          [
            d.statusLabel,
            if (d.professions.isNotEmpty) d.professions.join(', '),
          ].join('\n'),
        ),
        isThreeLine: d.professions.isNotEmpty,
        trailing: Icon(icon, color: color),
      ),
    );
  }
}
