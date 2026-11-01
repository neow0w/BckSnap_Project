import 'package:flutter/material.dart';

import 'validators.dart';

/// Live checklist shown under a "new password" field.
class PasswordRules extends StatelessWidget {
  final String password;
  const PasswordRules({super.key, required this.password});

  String _cap(String s) => s[0].toUpperCase() + s.substring(1);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final c in Validators.passwordChecks(password))
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 1),
              child: Row(
                children: [
                  Icon(
                    c.ok ? Icons.check_circle : Icons.circle_outlined,
                    size: 16,
                    color: c.ok ? Colors.green : Colors.grey,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    _cap(c.label),
                    style: TextStyle(
                      fontSize: 12,
                      color: c.ok ? Colors.green : Colors.grey.shade700,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
