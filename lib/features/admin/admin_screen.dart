import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/profile_crypto.dart';
import '../../core/validators.dart';
import '../../models/staff_profile.dart';
import '../../services/api_client.dart';
import '../../services/auth_service.dart';
import '../../services/profile_service.dart';
import '../receptionist/add_profile_dialog.dart';

/// The clinic administrator's home: the shared staff account, the profiles
/// of the receptionist and doctors, and the approval of new doctor profiles.
class AdminScreen extends StatefulWidget {
  final bool embedded; // true inside the website frame
  const AdminScreen({super.key, this.embedded = false});

  @override
  State<AdminScreen> createState() => _AdminScreenState();
}

class _AdminScreenState extends State<AdminScreen> {
  final ProfileService _service = ProfileService();
  Map<String, dynamic>? _account;
  List<StaffProfile> _profiles = [];
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
      final account = await _service.staffAccount();
      final profiles = await _service.profiles();
      if (mounted) {
        setState(() {
          _account = account;
          _profiles = profiles;
        });
      }
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Could not load the staff profiles.');
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _snack(String text) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

  /// Runs an admin action, then reloads the lists.
  Future<void> _run(String id, Future<void> Function() action) async {
    setState(() {
      _workingId = id;
      _error = null;
    });
    try {
      await action();
      await _load();
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _workingId = null);
    }
  }

  Future<void> _createAccount() async {
    final creds = await showDialog<({String email, String password})>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const _StaffAccountDialog(),
    );
    if (creds == null || !mounted) return;
    await _run('account', () async {
      await AuthService().createStaffAccount(
        email: creds.email,
        password: creds.password,
      );
      if (mounted) _snack('Clinic staff account created.');
    });
  }

  Future<void> _sendReset() async {
    final email = _account?['email'] as String?;
    if (email == null) return;
    try {
      await AuthService().resetPassword(email);
      if (mounted) _snack('Password reset email sent to $email.');
    } on ApiException catch (e) {
      if (mounted) _snack(e.message);
    }
  }

  Future<void> _addProfile() async {
    final msg = await showAddProfileDialog(context);
    if (msg == null || !mounted) return;
    _snack(msg);
    _load();
  }

  Future<void> _toggle(StaffProfile p) async {
    final active = p.isActive;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          active ? 'Deactivate this profile?' : 'Activate this profile?',
        ),
        content: Text(
          active
              ? '${p.name} will no longer appear on the profile screen'
                    '${p.isDoctor ? ' or be booked by patients' : ''}.'
              : '${p.name} will appear on the profile screen again.',
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
    await _run(p.id, () => _service.setActive(p, !active));
  }

  Future<void> _resetPassword(StaffProfile p) async {
    final pw = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _NewPasswordDialog(name: p.name),
    );
    if (pw == null || !mounted) return;
    await _run(p.id, () async {
      await _service.resetPassword(p, pw);
      if (mounted) _snack('Password changed for ${p.name}.');
    });
  }

  @override
  Widget build(BuildContext context) {
    final pending = _profiles.where((p) => p.isPending).toList();
    final others = _profiles.where((p) => !p.isPending).toList();
    return Scaffold(
      appBar: widget.embedded
          ? null
          : AppBar(
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
              ],
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addProfile,
        icon: const Icon(Icons.person_add_alt_1),
        label: const Text('Add profile'),
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
                        _accountCard(),
                        if (pending.isNotEmpty) ...[
                          const SizedBox(height: 16),
                          Text(
                            'Waiting for approval (${pending.length})',
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 8),
                          for (final p in pending) _pendingCard(p),
                        ],
                        const SizedBox(height: 16),
                        _section(
                          'Receptionist profiles',
                          'Manage receptionist accounts.',
                          others
                              .where((p) => p.role == 'receptionist')
                              .toList(),
                        ),
                        const SizedBox(height: 16),
                        _section(
                          'Physical Therapist profiles',
                          'Manage physical therapist accounts.',
                          others.where((p) => p.role == 'pt').toList(),
                        ),
                        const SizedBox(height: 16),
                        _section(
                          'Doctor profiles',
                          'Patients can book appointments with active doctors.',
                          others.where((p) => p.isDoctor).toList(),
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

  Widget _accountCard() {
    final email = _account?['email'] as String?;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Clinic staff account',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            const Text(
              'One email and password for the whole clinic staff. After '
              'logging in, each person opens their own profile.',
              style: TextStyle(fontSize: 12),
            ),
            const SizedBox(height: 12),
            if (_account == null && !_loading)
              FilledButton.icon(
                onPressed: _workingId == 'account' ? null : _createAccount,
                icon: const Icon(Icons.add),
                label: const Text('Create staff account'),
              )
            else if (_account != null) ...[
              Row(
                children: [
                  const Icon(Icons.email_outlined, size: 18),
                  const SizedBox(width: 8),
                  Expanded(child: Text(email ?? '')),
                ],
              ),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  onPressed: _sendReset,
                  child: const Text('Send password reset email'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _pendingCard(StaffProfile p) {
    final working = _workingId == p.id;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              p.name,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            Text(
              '${p.roleLabel}'
              '${p.professions.isEmpty ? '' : ' · ${p.professions.join(', ')}'}',
            ),
            Text(
              'Created by ${p.createdByName ?? 'a receptionist'}',
              style: const TextStyle(fontSize: 12),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                FilledButton.icon(
                  onPressed: working
                      ? null
                      : () =>
                            _run(p.id, () => _service.review(p, approve: true)),
                  icon: const Icon(Icons.check),
                  label: const Text('Approve'),
                ),
                OutlinedButton.icon(
                  onPressed: working
                      ? null
                      : () => _run(
                          p.id,
                          () => _service.review(p, approve: false),
                        ),
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
        ),
      ),
    );
  }

  Widget _section(String title, String help, List<StaffProfile> items) {
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
              child: Text('None yet. Tap "Add profile" to create one.'),
            ),
          ),
        for (final p in items) _tile(p),
      ],
    );
  }

  Widget _tile(StaffProfile p) {
    final manageable = p.status == 'active' || p.status == 'inactive';
    return Card(
      child: ListTile(
        leading: CircleAvatar(
          child: Icon(
            p.isDoctor ? Icons.medical_services_outlined : Icons.support_agent,
          ),
        ),
        title: Text(p.name),
        subtitle: Text(
          [
            p.statusLabel,
            if (p.professions.isNotEmpty) p.professions.join(', '),
          ].join('\n'),
        ),
        isThreeLine: p.professions.isNotEmpty,
        trailing: _workingId == p.id
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : manageable
            ? PopupMenuButton<String>(
                onSelected: (v) =>
                    v == 'toggle' ? _toggle(p) : _resetPassword(p),
                itemBuilder: (_) => [
                  PopupMenuItem(
                    value: 'toggle',
                    child: Text(p.isActive ? 'Deactivate' : 'Activate'),
                  ),
                  const PopupMenuItem(
                    value: 'password',
                    child: Text('Reset password'),
                  ),
                ],
              )
            : null,
      ),
    );
  }
}

class _StaffAccountDialog extends StatefulWidget {
  const _StaffAccountDialog();

  @override
  State<_StaffAccountDialog> createState() => _StaffAccountDialogState();
}

class _StaffAccountDialogState extends State<_StaffAccountDialog> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _hidden = true;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Create clinic staff account'),
      content: SizedBox(
        width: 400,
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'This one login is shared by the receptionist and the '
                  'doctors. Each of them then opens their own profile.',
                  style: TextStyle(fontSize: 12),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _email,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(
                    labelText: 'Staff account email',
                    border: OutlineInputBorder(),
                  ),
                  validator: Validators.email,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _password,
                  obscureText: _hidden,
                  decoration: InputDecoration(
                    labelText: 'Staff account password',
                    border: const OutlineInputBorder(),
                    suffixIcon: IconButton(
                      icon: Icon(
                        _hidden ? Icons.visibility_off : Icons.visibility,
                      ),
                      onPressed: () => setState(() => _hidden = !_hidden),
                    ),
                  ),
                  validator: Validators.password,
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            if (!_formKey.currentState!.validate()) return;
            Navigator.of(context)
                .pop((email: _email.text.trim(), password: _password.text));
          },
          child: const Text('Create'),
        ),
      ],
    );
  }
}

class _NewPasswordDialog extends StatefulWidget {
  final String name;
  const _NewPasswordDialog({required this.name});

  @override
  State<_NewPasswordDialog> createState() => _NewPasswordDialogState();
}

class _NewPasswordDialogState extends State<_NewPasswordDialog> {
  final _formKey = GlobalKey<FormState>();
  final _password = TextEditingController();
  bool _hidden = true;

  @override
  void dispose() {
    _password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('New password for ${widget.name}'),
      content: Form(
        key: _formKey,
        child: TextFormField(
          controller: _password,
          obscureText: _hidden,
          autofocus: true,
          decoration: InputDecoration(
            labelText: 'New profile password',
            border: const OutlineInputBorder(),
            suffixIcon: IconButton(
              icon: Icon(_hidden ? Icons.visibility_off : Icons.visibility),
              onPressed: () => setState(() => _hidden = !_hidden),
            ),
          ),
          validator: ProfileCrypto.validate,
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            if (!_formKey.currentState!.validate()) return;
            Navigator.of(context).pop(_password.text);
          },
          child: const Text('Save'),
        ),
      ],
    );
  }
}
