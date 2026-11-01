import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/format.dart';
import '../../core/router.dart' show homeFor;
import '../../services/auth_service.dart';
import 'profile_avatar.dart';

/// Shared by all three roles (patient, receptionist, doctor).
class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final _auth = AuthService();
  Uint8List? _photo;
  bool _loggingOut = false;

  @override
  void initState() {
    super.initState();
    _loadPhoto();
  }

  Future<void> _loadPhoto() async {
    final bytes = await _auth.loadMyPhoto();
    if (mounted) setState(() => _photo = bytes);
  }

  String _roleLabel(String role) {
    switch (role) {
      case 'admin':
        return 'Administrator';
      case 'doctor':
        return 'Doctor';
      case 'receptionist':
        return 'Receptionist';
      default:
        return 'Patient';
    }
  }

  Future<void> _edit() async {
    final changed = await context.push<bool>('/profile/edit');
    if (changed == true) {
      await _loadPhoto();
      if (mounted) setState(() {}); // pick up the updated user details
    }
  }

  Future<void> _logout() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Log out?'),
        content: const Text('You will need to log in again to continue.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Log out'),
          ),
        ],
      ),
    );
    if (ok != true) return;

    setState(() => _loggingOut = true);
    await _auth.logout();
    if (!mounted) return;
    context.go('/'); // back to the landing page (Fig 7 start)
  }

  @override
  Widget build(BuildContext context) {
    final user = _auth.currentUser;

    return Scaffold(
      appBar: AppBar(
        title: const Text('My Profile'),
        leading: BackButton(
          onPressed: () {
            if (context.canPop()) {
              context.pop();
            } else {
              context.go(user == null ? '/' : homeFor(user.role));
            }
          },
        ),
        actions: [
          if (user != null)
            IconButton(
              tooltip: 'Edit profile',
              icon: const Icon(Icons.edit),
              onPressed: _edit,
            ),
        ],
      ),
      body: SafeArea(
        child: user == null
            ? const Center(child: Text('You are not logged in.'))
            : Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 420),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Center(
                          child: ProfileAvatar(
                            bytes: _photo,
                            name: user.name,
                            radius: 52,
                          ),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          user.name ?? 'No name',
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Center(child: Chip(label: Text(_roleLabel(user.role)))),
                        const SizedBox(height: 8),
                        FilledButton.tonalIcon(
                          onPressed: _edit,
                          icon: const Icon(Icons.edit),
                          label: const Text('Edit profile'),
                        ),
                        const SizedBox(height: 16),
                        Card(
                          child: Column(
                            children: [
                              _row(
                                Icons.email_outlined,
                                'Email',
                                user.email ?? 'Not set',
                              ),
                              const Divider(height: 1),
                              _row(
                                Icons.phone_outlined,
                                'Phone',
                                user.phone ?? 'Not set',
                              ),
                              const Divider(height: 1),
                              _row(
                                Icons.cake_outlined,
                                'Date of birth',
                                user.dateOfBirth == null
                                    ? 'Not set'
                                    : '${formatDate(user.dateOfBirth!)} '
                                          '(age ${user.age})',
                              ),
                              const Divider(height: 1),
                              _row(
                                Icons.home_outlined,
                                'Address',
                                user.address ?? 'Not set',
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 8),
                        ListTile(
                          leading: const Icon(Icons.privacy_tip_outlined),
                          title: const Text('Privacy notice'),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () => context.push('/privacy'),
                        ),
                        const SizedBox(height: 16),
                        OutlinedButton.icon(
                          onPressed: _loggingOut ? null : _logout,
                          icon: const Icon(Icons.logout),
                          label: const Text('Log out'),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
      ),
    );
  }

  Widget _row(IconData icon, String label, String value) =>
      ListTile(leading: Icon(icon), title: Text(label), subtitle: Text(value));
}
