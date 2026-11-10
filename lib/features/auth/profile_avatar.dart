import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../services/auth_service.dart';
import '../../services/profile_service.dart';

/// Round profile picture. Shows the first letter of the name when there is
/// no picture.
class ProfileAvatar extends StatelessWidget {
  final Uint8List? bytes;
  final String? name;
  final double radius;
  const ProfileAvatar({super.key, this.bytes, this.name, this.radius = 44});

  @override
  Widget build(BuildContext context) {
    final initial = (name != null && name!.trim().isNotEmpty)
        ? name!.trim()[0].toUpperCase()
        : null;
    return CircleAvatar(
      radius: radius,
      backgroundImage: bytes == null ? null : MemoryImage(bytes!),
      child: bytes != null
          ? null
          : initial != null
          ? Text(initial, style: TextStyle(fontSize: radius * 0.8))
          : Icon(Icons.person, size: radius),
    );
  }
}

/// Tells the small avatars (website menu) to reload after a photo change.
class AvatarRefresh {
  static final ValueNotifier<int> tick = ValueNotifier<int>(0);
  static void notify() => tick.value++;
}

/// The photo of whoever is logged in: the open staff profile's photo for the
/// shared clinic staff account, otherwise the account's own photo.
Future<Uint8List?> loadMyAvatarBytes() async {
  final auth = AuthService();
  try {
    if (auth.isStaffAccount) {
      final p = auth.activeProfile;
      return p == null ? null : await ProfileService().profilePhoto(p.id);
    }
    return await auth.loadMyPhoto();
  } catch (_) {
    return null;
  }
}

/// A small avatar of the current user that loads its own photo.
class MyAvatar extends StatefulWidget {
  final double radius;
  const MyAvatar({super.key, this.radius = 16});

  @override
  State<MyAvatar> createState() => _MyAvatarState();
}

class _MyAvatarState extends State<MyAvatar> {
  Uint8List? _bytes;

  @override
  void initState() {
    super.initState();
    AvatarRefresh.tick.addListener(_load);
    _load();
  }

  @override
  void dispose() {
    AvatarRefresh.tick.removeListener(_load);
    super.dispose();
  }

  Future<void> _load() async {
    final b = await loadMyAvatarBytes();
    if (mounted) setState(() => _bytes = b);
  }

  @override
  Widget build(BuildContext context) => ProfileAvatar(
    bytes: _bytes,
    name: AuthService().currentUser?.name,
    radius: widget.radius,
  );
}
