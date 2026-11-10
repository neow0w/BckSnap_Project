import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme.dart';
import '../../services/auth_service.dart';
import '../../services/message_service.dart';

/// Bottom bar for patients: Home, Referral, Scan, Messages, Profile.
/// Staff on a phone get no bar.
class PatientShell extends StatefulWidget {
  final String location;
  final Widget child;
  const PatientShell({super.key, required this.location, required this.child});

  @override
  State<PatientShell> createState() => _PatientShellState();
}

class _PatientShellState extends State<PatientShell> {
  static const _tabs = {
    '/home': 0,
    '/referral': 1,
    '/messages': 3,
    '/profile': 4,
  };

  Stream<int>? _unread;

  @override
  void initState() {
    super.initState();
    if (AuthService().currentUser?.role == 'user') {
      _unread = MessageService().unreadCountStream();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (AuthService().currentUser?.role != 'user') return widget.child;
    final selected = _tabs[widget.location];
    return Scaffold(
      body: widget.child,
      bottomNavigationBar: Material(
        color: Theme.of(context).colorScheme.surface,
        elevation: 8,
        child: SafeArea(
          top: false,
          child: SizedBox(
            height: 64,
            child: Row(
              children: [
                _item(Icons.home_outlined, 'HOME', selected == 0, '/home'),
                _item(
                  Icons.local_hospital_outlined,
                  'REFERRAL',
                  selected == 1,
                  '/referral',
                ),
                _scan(context),
                _item(
                  Icons.chat_bubble_outline,
                  'MESSAGES',
                  selected == 3,
                  '/messages',
                  badges: _unread,
                ),
                _item(
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
    IconData icon,
    String label,
    bool active,
    String path, {
    Stream<int>? badges,
  }) {
    final color = active ? AppColors.primary : AppColors.hint;
    final iconWidget = Icon(icon, color: color, size: 24);
    return Expanded(
      child: InkWell(
        onTap: () => context.go(path),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            badges == null
                ? iconWidget
                : StreamBuilder<int>(
                    stream: badges,
                    builder: (context, snap) {
                      final n = snap.data ?? 0;
                      return Badge(
                        isLabelVisible: n > 0,
                        label: Text(n > 99 ? '99+' : '$n'),
                        child: iconWidget,
                      );
                    },
                  ),
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
                border: Border.all(
                  color: Theme.of(context).colorScheme.surface,
                  width: 3,
                ),
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
