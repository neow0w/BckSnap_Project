import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:image_picker/image_picker.dart';

import '../../services/api_client.dart';
import '../../services/profile_service.dart';
import '../../core/format.dart';
import '../../core/home_for.dart';
import '../../core/theme.dart';
import '../../core/theme_controller.dart';
import '../../services/auth_service.dart';
import 'profile_avatar.dart';

String _roleLabel(String role) {
  switch (role) {
    case 'admin':
      return 'Administrator';
    case 'doctor':
      return 'Doctor';
    case 'pt':
      return 'Physical Therapist';
    case 'receptionist':
      return 'Receptionist';
    default:
      return 'Patient';
  }
}

/// Soft background for icon circles / tonal buttons, adapted to the theme.
Color _tonalOf(BuildContext context) {
  final theme = Theme.of(context);
  return theme.brightness == Brightness.dark
      ? theme.colorScheme.surfaceContainerHighest
      : AppColors.tonal;
}

/// Accent color for icons / tonal button text, adapted to the theme.
Color _accentOf(BuildContext context) {
  final theme = Theme.of(context);
  return theme.brightness == Brightness.dark
      ? theme.colorScheme.primary
      : AppColors.primary;
}

/// Profile tab: a menu like the inspiration, in the BckSnap look.
/// Shared by all roles (patient, receptionist, doctor).
class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final _auth = AuthService();
  Uint8List? _photo;
  bool _loggingOut = false;
  final _picker = ImagePicker();
  bool _savingPhoto = false;

  @override
  void initState() {
    super.initState();
    _loadPhoto();
  }

  Future<void> _loadPhoto() async {
    final bytes = await loadMyAvatarBytes();
    if (mounted) setState(() => _photo = bytes);
  }

  void _snack(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _changePhoto() async {
    if (_savingPhoto) return;
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Wrap(
          children: [
            if (!kIsWeb)
              ListTile(
                leading: const Icon(Icons.photo_camera),
                title: const Text('Take a photo'),
                onTap: () => Navigator.pop(ctx, ImageSource.camera),
              ),
            ListTile(
              leading: const Icon(Icons.photo_library),
              title: const Text('Choose from gallery'),
              onTap: () => Navigator.pop(ctx, ImageSource.gallery),
            ),
          ],
        ),
      ),
    );
    if (source == null) return;

    setState(() => _savingPhoto = true);
    try {
      final picked = await _picker.pickImage(
        source: source,
        imageQuality: 85,
        maxWidth: 800,
        maxHeight: 800,
      );
      if (picked == null) return;
      final bytes = await picked.readAsBytes();
      if (bytes.length > 5 * 1024 * 1024) {
        _snack('That photo is too large (max 5 MB).');
        return;
      }
      if (_auth.isStaffAccount) {
        final p = _auth.activeProfile;
        if (p == null) {
          _snack('Open a profile first.');
          return;
        }
        await ProfileService().saveProfilePhoto(p, bytes);
      } else {
        await _auth.uploadPhoto(bytes, 'profile.jpg');
      }
      if (mounted) setState(() => _photo = bytes);
      AvatarRefresh.notify();
      _snack('Profile photo updated.');
    } on ApiException catch (e) {
      _snack(e.message);
    } catch (_) {
      _snack('Could not update the photo. Please try again.');
    } finally {
      if (mounted) setState(() => _savingPhoto = false);
    }
  }

  Future<void> _viewProfile() async {
    await Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => const ProfileDetailsScreen()));
    if (mounted) {
      await _loadPhoto();
      if (mounted) setState(() {}); // pick up any edited details
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
    try {
      await _auth.logout();
    } finally {
      if (mounted) setState(() => _loggingOut = false);
    }
    if (!mounted) return;
    context.go('/'); // back to the landing page
  }

  @override
  Widget build(BuildContext context) {
    final user = _auth.currentUser;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Profile'),
        leading: BackButton(
          onPressed: () {
            if (context.canPop()) {
              context.pop();
            } else {
              context.go(user == null ? '/' : homeFor(user.role));
            }
          },
        ),
      ),
      body: SafeArea(
        child: user == null
            ? const Center(child: Text('You are not logged in.'))
            : Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 420),
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                    children: [
                      _headerCard(user.name, user.role),
                      const SizedBox(height: 12),
                      _row(
                        icon: Icons.privacy_tip_outlined,
                        title: 'Privacy notice',
                        onTap: () => context.push('/privacy'),
                      ),
                      _themeRow(),
                      if (_auth.isStaffAccount)
                        _row(
                          icon: Icons.switch_account_outlined,
                          title: 'Switch profile',
                          onTap: () {
                            _auth.leaveProfile();
                            context.go('/profiles');
                          },
                        ),
                      _row(
                        icon: Icons.logout,
                        title: 'Log out',
                        chevron: false,
                        busy: _loggingOut,
                        onTap: _loggingOut ? null : _logout,
                      ),
                    ],
                  ),
                ),
              ),
      ),
    );
  }

  Widget _headerCard(String? name, String role) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              children: [
                GestureDetector(
                  onTap: _savingPhoto ? null : _changePhoto,
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      ProfileAvatar(bytes: _photo, name: name, radius: 28),
                      Positioned(
                        right: -2,
                        bottom: -2,
                        child: CircleAvatar(
                          radius: 11,
                          backgroundColor: AppColors.primary,
                          child: _savingPhoto
                              ? const SizedBox(
                                  width: 10,
                                  height: 10,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Icon(
                                  Icons.camera_alt,
                                  size: 12,
                                  color: Colors.white,
                                ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name ?? 'No name',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        _roleLabel(role),
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const Divider(height: 24),
            SizedBox(
              width: double.infinity,
              child: FilledButton.tonalIcon(
                style: FilledButton.styleFrom(
                  backgroundColor: _tonalOf(context),
                  foregroundColor: _accentOf(context),
                ),
                onPressed: _viewProfile,
                icon: const Icon(Icons.account_circle_outlined),
                label: const Text('View profile'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Light / dark switch, wired to the app-wide [ThemeController].
  Widget _themeRow() {
    return ListenableBuilder(
      listenable: ThemeController.instance,
      builder: (context, _) {
        final isDark = ThemeController.instance.isDark(context);
        return InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => ThemeController.instance.toggle(context),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 22,
                  backgroundColor: _tonalOf(context),
                  child: Icon(
                    isDark
                        ? Icons.dark_mode_outlined
                        : Icons.light_mode_outlined,
                    color: _accentOf(context),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    isDark ? 'Dark mode' : 'Light mode',
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                Switch(
                  value: isDark,
                  onChanged: (value) => ThemeController.instance.setMode(
                    value ? ThemeMode.dark : ThemeMode.light,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _row({
    required IconData icon,
    required String title,
    required VoidCallback? onTap,
    bool chevron = true,
    bool busy = false,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
        child: Row(
          children: [
            CircleAvatar(
              radius: 22,
              backgroundColor: _tonalOf(context),
              child: busy
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Icon(icon, color: _accentOf(context)),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                title,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            if (chevron) const Icon(Icons.chevron_right, color: AppColors.hint),
          ],
        ),
      ),
    );
  }
}

/// "View profile": the personal details (opened from the menu above).
class ProfileDetailsScreen extends StatefulWidget {
  const ProfileDetailsScreen({super.key});

  @override
  State<ProfileDetailsScreen> createState() => _ProfileDetailsScreenState();
}

class _ProfileDetailsScreenState extends State<ProfileDetailsScreen> {
  final _auth = AuthService();
  Uint8List? _photo;

  @override
  void initState() {
    super.initState();
    _loadPhoto();
  }

  Future<void> _loadPhoto() async {
    final bytes = await loadMyAvatarBytes();
    if (mounted) setState(() => _photo = bytes);
  }

  Future<void> _edit() async {
    final changed = await context.push<bool>('/profile/edit');
    if (changed == true) {
      await _loadPhoto();
      AvatarRefresh.notify();
      if (mounted) setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = _auth.currentUser;

    return Scaffold(
      appBar: AppBar(
        title: const Text('My Profile'),
        actions: [
          if (user != null && !_auth.isStaffAccount)
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
                        if (!_auth.isStaffAccount)
                          FilledButton.tonalIcon(
                            style: FilledButton.styleFrom(
                              backgroundColor: _tonalOf(context),
                              foregroundColor: _accentOf(context),
                            ),
                            onPressed: _edit,
                            icon: const Icon(Icons.edit),
                            label: const Text('Edit profile'),
                          ),
                        const SizedBox(height: 16),
                        Card(
                          child: Column(
                            children: [
                              _info(
                                Icons.email_outlined,
                                'Email',
                                user.email ?? 'Not set',
                              ),
                              const Divider(height: 1),
                              _info(
                                Icons.phone_outlined,
                                'Phone',
                                user.phone ?? 'Not set',
                              ),
                              const Divider(height: 1),
                              _info(
                                Icons.cake_outlined,
                                'Date of birth',
                                user.dateOfBirth == null
                                    ? 'Not set'
                                    : '${formatDate(user.dateOfBirth!)} '
                                          '(age ${user.age})',
                              ),
                              const Divider(height: 1),
                              _info(
                                Icons.home_outlined,
                                'Address',
                                user.address ?? 'Not set',
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
      ),
    );
  }

  Widget _info(IconData icon, String label, String value) => ListTile(
    leading: Icon(icon, color: _accentOf(context)),
    title: Text(label),
    subtitle: Text(value),
  );
}
