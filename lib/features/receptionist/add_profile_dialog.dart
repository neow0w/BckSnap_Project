import 'package:flutter/material.dart';

import '../../core/profile_crypto.dart';
import '../../core/validators.dart';
import '../../services/api_client.dart';
import '../../services/auth_service.dart';
import '../../services/profile_service.dart';

/// Returns a message to show when a profile was created, or null if cancelled.
/// Admin: doctor or receptionist, active at once.
/// Receptionist: doctor only, sent to the admin for approval.
Future<String?> showAddProfileDialog(BuildContext context) =>
    showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const _AddProfileDialog(),
    );

class _AddProfileDialog extends StatefulWidget {
  const _AddProfileDialog();

  @override
  State<_AddProfileDialog> createState() => _AddProfileDialogState();
}

class _AddProfileDialogState extends State<_AddProfileDialog> {
  final _formKey = GlobalKey<FormState>();
  final _first = TextEditingController();
  final _last = TextEditingController();
  final _profession = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  final _professions = <String>{};

  final bool _isAdmin = AuthService().currentUser?.role == 'admin';
  String _role = 'doctor';
  String _professionalType = 'Doctor';
  bool _hidden = true;
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _first.dispose();
    _last.dispose();
    _profession.dispose();
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  void _addProfession() {
    final p = _profession.text.trim();
    if (p.isEmpty) return;
    setState(() {
      _professions.add(p);
      _profession.clear();
    });
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (_role == 'doctor') {
      _addProfession();
      if (_professions.isEmpty) {
        setState(() => _error = 'Add at least one profession.');
        return;
      }
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ProfileService().createProfile(
        name: '${_first.text.trim()} ${_last.text.trim()}',
        role: _role,
        password: _password.text,
        professionalType: _professionalType,
        professions: _role == 'doctor' ? _professions.toList() : [],
      );
      if (!mounted) return;
      Navigator.of(context).pop(
        !_isAdmin
            ? 'Doctor profile sent to the administrator for approval.'
            : _role == 'doctor'
            ? 'Doctor profile created.'
            : 'Receptionist profile created.',
      );
    } on ApiException catch (e) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = e.message;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = 'Could not create the profile. Please try again.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Add staff profile'),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  initialValue: _role,
                  decoration: const InputDecoration(
                    labelText: 'Profile role',
                    border: OutlineInputBorder(),
                  ),
                  items: const [
                    DropdownMenuItem(value: 'doctor', child: Text('Doctor')),
                    DropdownMenuItem(
                      value: 'pt',
                      child: Text('Physical Therapist'),
                    ),
                    DropdownMenuItem(
                      value: 'receptionist',
                      child: Text('Receptionist'),
                    ),
                  ],
                  onChanged: _saving
                      ? null
                      : (v) => setState(() {
                          _role = v ?? 'doctor';
                          _professions.clear();
                        }),
                ),
                const SizedBox(height: 12),
                if (!_isAdmin) ...[
                  const Text(
                    'This profile will remain pending until an administrator '
                    'approves it.',
                    style: TextStyle(fontSize: 12),
                  ),
                  const SizedBox(height: 12),
                ],
                TextFormField(
                  controller: _first,
                  decoration: const InputDecoration(
                    labelText: 'First name',
                    border: OutlineInputBorder(),
                  ),
                  validator: (v) => Validators.name(v, label: 'first name'),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _last,
                  decoration: const InputDecoration(
                    labelText: 'Last name',
                    border: OutlineInputBorder(),
                  ),
                  validator: (v) => Validators.name(v, label: 'last name'),
                ),
                if (_role == 'doctor') ...[
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: _professionalType,
                    decoration: const InputDecoration(
                      labelText: 'Professional type',
                      border: OutlineInputBorder(),
                    ),
                    items: const [
                      DropdownMenuItem(value: 'Doctor', child: Text('Doctor')),
                      DropdownMenuItem(
                        value: 'Physical Therapist',
                        child: Text('Physical Therapist'),
                      ),
                    ],
                    onChanged: _saving
                        ? null
                        : (value) {
                            setState(() {
                              _professionalType = value ?? 'Doctor';
                              _professions.clear();
                            });
                          },
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _profession,
                    decoration: const InputDecoration(
                      labelText: 'Profession',
                      hintText: 'e.g. Cardiologist, Orthopedic Doctor',
                      border: OutlineInputBorder(),
                    ),
                    onFieldSubmitted: (_) => _addProfession(),
                  ),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton.icon(
                      onPressed: _saving ? null : _addProfession,
                      icon: const Icon(Icons.add),
                      label: const Text('Add profession'),
                    ),
                  ),
                  Wrap(
                    spacing: 8,
                    children: [
                      for (final p in _professions)
                        InputChip(
                          label: Text(p),
                          onDeleted: _saving
                              ? null
                              : () => setState(() => _professions.remove(p)),
                        ),
                    ],
                  ),
                ],
                const SizedBox(height: 12),
                TextFormField(
                  controller: _password,
                  obscureText: _hidden,
                  decoration: InputDecoration(
                    labelText: 'Profile password',
                    border: const OutlineInputBorder(),
                    suffixIcon: IconButton(
                      icon: Icon(
                        _hidden ? Icons.visibility_off : Icons.visibility,
                      ),
                      onPressed: () => setState(() => _hidden = !_hidden),
                    ),
                  ),
                  validator: ProfileCrypto.validate,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _confirm,
                  obscureText: _hidden,
                  decoration: const InputDecoration(
                    labelText: 'Confirm password',
                    border: OutlineInputBorder(),
                  ),
                  validator: (v) =>
                      v == _password.text ? null : 'Passwords do not match',
                ),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(_error!, style: const TextStyle(color: Colors.red)),
                ],
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: _saving
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(_isAdmin ? 'Create Profile' : 'Submit for Approval'),
        ),
      ],
    );
  }
}
