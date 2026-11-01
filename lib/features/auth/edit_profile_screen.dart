import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/format.dart';
import '../../core/validators.dart';
import '../../services/api_client.dart';
import '../../services/auth_service.dart';
import 'profile_avatar.dart';

/// Edit personal information and the profile picture (all roles).
/// Email and date of birth are shown but cannot be changed here:
/// the date of birth decides whether guardian consent was required.
class EditProfileScreen extends StatefulWidget {
  const EditProfileScreen({super.key});

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  static const int _maxPhotoBytes = 5 * 1024 * 1024;

  final _formKey = GlobalKey<FormState>();
  final _auth = AuthService();
  final _picker = ImagePicker();
  late final TextEditingController _nameCtrl;
  late final TextEditingController _phoneCtrl;
  late final TextEditingController _addressCtrl;

  Uint8List? _currentPhoto; // stored on the server
  Uint8List? _pendingPhoto; // picked, not uploaded yet
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final u = _auth.currentUser;
    _nameCtrl = TextEditingController(text: u?.name ?? '');
    _phoneCtrl = TextEditingController(text: u?.phone ?? '');
    _addressCtrl = TextEditingController(text: u?.address ?? '');
    _loadPhoto();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    _addressCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadPhoto() async {
    final bytes = await _auth.loadMyPhoto();
    if (mounted) setState(() => _currentPhoto = bytes);
  }

  String? get _phoneValue {
    final p = Validators.normalizePhone(_phoneCtrl.text.trim());
    return p.isEmpty ? null : p;
  }

  String? get _addressValue {
    final a = _addressCtrl.text.trim();
    return a.isEmpty ? null : a;
  }

  bool get _dirty {
    final u = _auth.currentUser;
    if (u == null) return false;
    return _pendingPhoto != null ||
        _nameCtrl.text.trim() != (u.name ?? '') ||
        (_phoneValue ?? '') != (u.phone ?? '') ||
        (_addressValue ?? '') != (u.address ?? '');
  }

  void _close(bool changed) {
    if (context.canPop()) {
      context.pop(changed);
    } else {
      context.go('/profile');
    }
  }

  Future<void> _onBack() async {
    if (_saving) return;
    if (!_dirty) {
      _close(false);
      return;
    }
    final leave = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Discard changes?'),
        content: const Text('Your changes have not been saved.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Keep editing'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Discard'),
          ),
        ],
      ),
    );
    if (leave == true && mounted) _close(false);
  }

  // ---- profile picture ------------------------------------------------------

  Future<void> _choosePhoto() async {
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
    if (source != null) await _pickPhoto(source);
  }

  Future<void> _pickPhoto(ImageSource source) async {
    try {
      final picked = await _picker.pickImage(
        source: source,
        imageQuality: 85,
        maxWidth: 800,
        maxHeight: 800,
      );
      if (picked == null) return;
      final bytes = await picked.readAsBytes();
      if (!mounted) return;
      if (bytes.length > _maxPhotoBytes) {
        setState(() => _error = 'That photo is too large (max 5 MB).');
        return;
      }
      setState(() {
        _pendingPhoto = bytes;
        _error = null;
      });
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = 'Could not open the photo. Check the camera and photo permissions.',
        );
      }
    }
  }

  // ---- save -----------------------------------------------------------------

  Future<void> _save() async {
    if (_saving) return;
    if (!_formKey.currentState!.validate()) return;
    if (!_dirty) {
      _close(false);
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final photo = _pendingPhoto;
      if (photo != null) {
        await _auth.uploadPhoto(photo, 'profile.jpg');
        if (!mounted) return;
        setState(() {
          _currentPhoto = photo;
          _pendingPhoto = null;
        });
      }
      await _auth.updateProfile(
        name: _nameCtrl.text.trim(),
        phone: _phoneValue,
        address: _addressValue,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Profile updated.')));
      _close(true);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Something went wrong. Please try again.');
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = _auth.currentUser;
    if (user == null) {
      return const Scaffold(
        body: Center(child: Text('You are not logged in.')),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Edit Profile'),
        leading: BackButton(onPressed: _onBack),
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Form(
                key: _formKey,
                autovalidateMode: AutovalidateMode.onUserInteraction,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Center(
                      child: Stack(
                        children: [
                          ProfileAvatar(
                            bytes: _pendingPhoto ?? _currentPhoto,
                            name: _nameCtrl.text,
                            radius: 56,
                          ),
                          Positioned(
                            right: 0,
                            bottom: 0,
                            child: CircleAvatar(
                              radius: 18,
                              backgroundColor: Theme.of(context)
                                  .colorScheme
                                  .primary,
                              child: IconButton(
                                padding: EdgeInsets.zero,
                                tooltip: 'Change photo',
                                icon: Icon(
                                  Icons.camera_alt,
                                  size: 18,
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onPrimary,
                                ),
                                onPressed: _saving ? null : _choosePhoto,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    TextButton(
                      onPressed: _saving ? null : _choosePhoto,
                      child: Text(
                        _pendingPhoto != null
                            ? 'Choose a different photo'
                            : 'Change profile picture',
                      ),
                    ),
                    if (_pendingPhoto != null)
                      const Text(
                        'The new picture is saved when you tap Save.',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 12),
                      ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _nameCtrl,
                      textCapitalization: TextCapitalization.words,
                      inputFormatters: [LengthLimitingTextInputFormatter(60)],
                      decoration: const InputDecoration(
                        labelText: 'Full name',
                        border: OutlineInputBorder(),
                      ),
                      validator: (v) => Validators.name(v, label: 'full name'),
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _phoneCtrl,
                      keyboardType: TextInputType.phone,
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(
                          RegExp(r'[0-9+\-() ]'),
                        ),
                        LengthLimitingTextInputFormatter(25),
                      ],
                      decoration: const InputDecoration(
                        labelText: 'Phone (optional)',
                        border: OutlineInputBorder(),
                      ),
                      validator: Validators.phone,
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _addressCtrl,
                      minLines: 1,
                      maxLines: 3,
                      inputFormatters: [LengthLimitingTextInputFormatter(200)],
                      decoration: const InputDecoration(
                        labelText: 'Address (optional)',
                        border: OutlineInputBorder(),
                      ),
                      validator: Validators.address,
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      initialValue: user.email ?? '',
                      enabled: false,
                      decoration: const InputDecoration(
                        labelText: 'Email',
                        helperText: 'Email cannot be changed here.',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    if (user.dateOfBirth != null) ...[
                      const SizedBox(height: 16),
                      TextFormField(
                        initialValue: formatDate(user.dateOfBirth!),
                        enabled: false,
                        decoration: const InputDecoration(
                          labelText: 'Date of birth',
                          helperText: 'Date of birth cannot be changed.',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ],
                    if (_error != null) ...[
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.red.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          _error!,
                          style: const TextStyle(color: Colors.red),
                        ),
                      ),
                    ],
                    const SizedBox(height: 24),
                    FilledButton(
                      onPressed: _saving ? null : _save,
                      child: _saving
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('Save'),
                    ),
                    const SizedBox(height: 8),
                    OutlinedButton(
                      onPressed: _saving ? null : _onBack,
                      child: const Text('Cancel'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
