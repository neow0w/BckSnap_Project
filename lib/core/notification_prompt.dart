import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:permission_handler/permission_handler.dart';

import 'theme.dart';

class NotificationPrompt {
  static const _key = 'notification_prompt_shown';
  static const _storage = FlutterSecureStorage();

  /// Asks "Turn on notifications?" once. Safe to call on every home visit.
  static Future<void> maybeAsk(BuildContext context) async {
    if (kIsWeb) return;
    try {
      if (await Permission.notification.isGranted) return;
      if (await _storage.read(key: _key) == 'yes') return;
      if (!context.mounted) return;

      final turnOn = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          icon: const Icon(
            Icons.notifications_active_outlined,
            size: 40,
            color: AppColors.primary,
          ),
          title: const Text('Turn on notifications?'),
          content: const Text(
            'Get a reminder for your monthly check-up and updates about '
            'your appointments.',
            textAlign: TextAlign.center,
          ),
          actionsAlignment: MainAxisAlignment.center,
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Not now'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(minimumSize: const Size(110, 44)),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('TURN ON'),
            ),
          ],
        ),
      );

      await _storage.write(key: _key, value: 'yes');
      if (turnOn != true) return;

      final status = await Permission.notification.request();
      if (status.isPermanentlyDenied && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Notifications are turned off for this app.'),
            action: SnackBarAction(
              label: 'Settings',
              onPressed: openAppSettings,
            ),
          ),
        );
      }
    } catch (_) {
      // Never block the app because of a permission prompt.
    }
  }
}
