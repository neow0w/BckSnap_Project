import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/home_for.dart';
import '../../core/theme.dart';
import '../../core/theme_controller.dart';
import '../../core/widgets.dart';
import '../../models/staff_profile.dart';
import '../../services/api_client.dart';
import '../../services/auth_service.dart';
import '../../services/profile_service.dart';
import '../receptionist/add_profile_dialog.dart';

/// "Who is using BckSnap?" Shown after logging in with the clinic staff
/// account. Each profile has its own password.
class ProfilePickerScreen extends StatefulWidget {
  const ProfilePickerScreen({super.key});

  @override
  State<ProfilePickerScreen> createState() => _ProfilePickerScreenState();
}

class _ProfilePickerScreenState extends State<ProfilePickerScreen> {
  final _auth = AuthService();
  final _service = ProfileService();

  List<StaffProfile> _profiles = [];
  Map<String, Uint8List> _photos = {};
  bool _loading = true;
  String? _error;

  int _failures = 0;
  DateTime? _lockedUntil;

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
      final list = await _service.profiles(activeOnly: true);
      if (mounted) setState(() => _profiles = list);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not load the profiles.');
    }
    try {
      final photos = await _service.profilePhotos();
      if (mounted) setState(() => _photos = photos);
    } catch (_) {
      // Photos are optional: the icons are shown instead.
    }
    if (mounted) setState(() => _loading = false);
  }

  /// Returns an error message, or null when the password was right.
  Future<String?> _tryPassword(StaffProfile p, String password) async {
    final until = _lockedUntil;
    if (until != null && DateTime.now().isBefore(until)) {
      final s = until.difference(DateTime.now()).inSeconds + 1;
      return 'Too many wrong passwords. Try again in $s seconds.';
    }
    try {
      await _auth.chooseProfile(p, password);
      _failures = 0;
      return null;
    } on ApiException catch (e) {
      if (e.statusCode == 401) {
        _failures++;
        if (_failures >= 5) {
          _failures = 0;
          _lockedUntil = DateTime.now().add(const Duration(seconds: 30));
          return 'Too many wrong passwords. Try again in 30 seconds.';
        }
      }
      return e.message;
    }
  }

  Future<void> _open(StaffProfile p) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) =>
          _PasswordDialog(profile: p, onSubmit: (pw) => _tryPassword(p, pw)),
    );
    if (ok == true && mounted) {
      context.go(homeFor(_auth.currentUser?.role ?? 'user'));
    }
  }

  Future<void> _addProfile() async {
    final msg = await showAddProfileDialog(context);
    if (msg == null || !mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    _load();
  }

  Future<void> _logout() async {
    await _auth.logout();
    if (mounted) context.go('/');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Profiles'),
        automaticallyImplyLeading: false,
        actions: [
          const ThemeModeButton(),
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
            constraints: const BoxConstraints(maxWidth: 560),
            child: _body(context),
          ),
        ),
      ),
    );
  }

  Widget _body(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        const Center(child: BrandLogo(size: 90)),
        const SizedBox(height: 16),
        const Text(
          'Who Is Using BckSnap?',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: AppColors.primary,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Select a profile to continue',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 24),
        if (_error != null) ...[
          ErrorBox(_error!),
          const SizedBox(height: 12),
          Center(
            child: FilledButton(onPressed: _load, child: const Text('Retry')),
          ),
        ] else if (_profiles.isEmpty)
          Text(
            'There are no active profiles yet. Ask the clinic administrator '
            'to create or approve a staff profile.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall,
          )
        else
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 16,
            runSpacing: 16,
            children: [for (final p in _profiles) _tile(p)],
          ),
        const SizedBox(height: 32),
        Center(
          child: OutlinedButton.icon(
            onPressed: _addProfile,
            icon: const Icon(Icons.person_add_alt_1),
            label: const Text('Add staff profile'),
          ),
        ),
      ],
    );
  }

  Widget _tile(StaffProfile p) {
    final photo = _photos[p.id];
    final primary = Theme.of(context).colorScheme.primary;
    return SizedBox(
      width: 130,
      height: 160,
      child: Card(
        margin: EdgeInsets.zero,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => _open(p),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                CircleAvatar(
                  radius: 34,
                  backgroundColor: primary.withValues(alpha: 0.15),
                  backgroundImage: photo == null ? null : MemoryImage(photo),
                  child: photo != null
                      ? null
                      : Icon(
                          switch (p.role) {
                            'doctor' => Icons.medical_services,
                            'pt' => Icons.accessibility_new,
                            _ => Icons.support_agent,
                          },
                          size: 32,
                          color: primary,
                        ),
                ),
                const SizedBox(height: 10),
                Text(
                  p.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  p.roleLabel,
                  style: const TextStyle(fontSize: 11, color: AppColors.hint),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PasswordDialog extends StatefulWidget {
  final StaffProfile profile;
  final Future<String?> Function(String password) onSubmit;
  const _PasswordDialog({required this.profile, required this.onSubmit});

  @override
  State<_PasswordDialog> createState() => _PasswordDialogState();
}

class _PasswordDialogState extends State<_PasswordDialog> {
  final _ctrl = TextEditingController();
  bool _hidden = true;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy) return;
    if (_ctrl.text.isEmpty) {
      setState(() => _error = 'Please enter the password');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final err = await widget.onSubmit(_ctrl.text);
    if (!mounted) return;
    if (err == null) {
      Navigator.of(context).pop(true);
    } else {
      setState(() {
        _busy = false;
        _error = err;
        _ctrl.clear();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.profile.name),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.profile.roleLabel,
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _ctrl,
            autofocus: true,
            obscureText: _hidden,
            onSubmitted: (_) => _submit(),
            decoration: InputDecoration(
              hintText: 'Profile password',
              errorText: _error,
              errorMaxLines: 3,
              suffixIcon: IconButton(
                icon: Icon(_hidden ? Icons.visibility_off : Icons.visibility),
                onPressed: () => setState(() => _hidden = !_hidden),
              ),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _busy ? null : _submit,
          child: _busy
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Text('Enter'),
        ),
      ],
    );
  }
}
