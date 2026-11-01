import 'dart:typed_data';

import 'package:flutter/material.dart';

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
