import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme.dart';
import '../../services/auth_service.dart';

/// Bottom bar for patients: Home, Referral, Scan, Messages, Profile.
/// Staff on a phone get no bar.
class PatientShell extends StatelessWidget {
  final String location;
  final Widget child;
  const PatientShell({super.key, required this.location, required this.child});

  static const _tabs = {
    '/home': 0,
    '/referral': 1,
    '/messages': 3,
    '/profile': 4,
  };

  @override
  Widget build(BuildContext context) {
    if (AuthService().currentUser?.role != 'user') return child;
    final selected = _tabs[location];
    return Scaffold(
      body: child,
      bottomNavigationBar: Material(
        color: Colors.white,
        elevation: 8,
        child: SafeArea(
          top: false,
          child: SizedBox(
            height: 64,
            child: Row(
              children: [
                _item(
                  context,
                  Icons.home_outlined,
                  'HOME',
                  selected == 0,
                  '/home',
                ),
                _item(
                  context,
                  Icons.local_hospital_outlined,
                  'REFERRAL',
                  selected == 1,
                  '/referral',
                ),
                _scan(context),
                _item(
                  context,
                  Icons.chat_bubble_outline,
                  'MESSAGES',
                  selected == 3,
                  '/messages',
                ),
                _item(
                  context,
                  Icons.person_outline,
                  'PROFILE',
                  selected == 4,
                  '/profile',
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _item(
    BuildContext context,
    IconData icon,
    String label,
    bool active,
    String path,
  ) {
    final color = active ? AppColors.primary : AppColors.hint;
    return Expanded(
      child: InkWell(
        onTap: () => context.go(path),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: color, size: 24),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.w600,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _scan(BuildContext context) {
    return Expanded(
      child: Center(
        child: Transform.translate(
          offset: const Offset(0, -8),
          child: InkResponse(
            onTap: () => context.push('/screening/for'),
            child: Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: AppColors.primary,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 3),
                boxShadow: const [
                  BoxShadow(color: Colors.black26, blurRadius: 6),
                ],
              ),
              child: const Icon(Icons.camera, color: Colors.white, size: 28),
            ),
          ),
        ),
      ),
    );
  }
}
