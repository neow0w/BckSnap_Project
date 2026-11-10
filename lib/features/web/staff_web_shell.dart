import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme.dart';
import '../../services/auth_service.dart';
import '../../core/theme_controller.dart';
import '../auth/profile_avatar.dart';

import 'staff_notification_bell.dart';

class _Dest {
  final String label;
  final IconData icon;
  final String path;
  const _Dest(this.label, this.icon, this.path);
}

const _receptionDests = [
  _Dest('Requests', Icons.event_note_outlined, '/reception'),
  _Dest('Messages', Icons.chat_bubble_outline, '/reception/inbox'),
  _Dest('Doctors', Icons.medical_services_outlined, '/reception/staff'),
];

const _adminDests = [
  _Dest('Staff', Icons.badge_outlined, '/admin'),
  _Dest('Audit log', Icons.history, '/admin/audit'),
  _Dest('Clinic', Icons.place_outlined, '/admin/clinic-location'),
];

const _doctorDests = [
  _Dest('Appointments', Icons.event_note_outlined, '/doctor'),
  _Dest('Patients', Icons.people_outline, '/doctor/patients'),
  _Dest('My Schedule', Icons.calendar_month_outlined, '/doctor/schedule'),
];

const _ptDests = [
  _Dest('Appointments', Icons.event_note_outlined, '/doctor'),
  _Dest('Patients', Icons.people_outline, '/doctor/patients'),
  _Dest('My Schedule', Icons.calendar_month_outlined, '/pt/schedule'),
];

/// The website frame for staff: a side menu with the page next to it.
class StaffWebShell extends StatelessWidget {
  final String location;
  final Widget child;
  const StaffWebShell({super.key, required this.location, required this.child});

  // The destination whose path is the longest match of the current location.
  int _index(List<_Dest> dests) {
    var best = 0;
    var bestLen = -1;
    for (var i = 0; i < dests.length; i++) {
      final p = dests[i].path;
      if ((location == p || location.startsWith('$p/')) && p.length > bestLen) {
        best = i;
        bestLen = p.length;
      }
    }
    return best;
  }

  Future<void> _logout(BuildContext context) async {
    await AuthService().logout();
    if (context.mounted) context.go('/login');
  }

  void _switchProfile(BuildContext context) {
    AuthService().leaveProfile();
    context.go('/profiles');
  }

  @override
  Widget build(BuildContext context) {
    final user = AuthService().currentUser;
    final role = user?.role;
    final dests = switch (role) {
      'doctor' => _doctorDests,
      'pt' => _ptDests,
      'admin' => _adminDests,
      _ => _receptionDests,
    };
    final roleLabel = switch (role) {
      'doctor' => 'Doctor',
      'pt' => 'Physical Therapist',
      'admin' => 'Administrator',
      _ => 'Receptionist',
    };
    final index = _index(dests);

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 900) {
          return Scaffold(
            appBar: AppBar(
              title: Text(dests[index].label),
              actions: [
                const ThemeModeButton(),
                const StaffNotificationBell(),

                if (AuthService().isStaffAccount)
                  IconButton(
                    tooltip: 'Switch profile',
                    onPressed: () => _switchProfile(context),
                    icon: const Icon(Icons.switch_account_outlined),
                  ),
                IconButton(
                  tooltip: 'My profile',
                  onPressed: () => context.push('/profile'),
                  icon: const MyAvatar(radius: 14),
                ),
                IconButton(
                  tooltip: 'Log out',
                  onPressed: () => _logout(context),
                  icon: const Icon(Icons.logout),
                ),
              ],
            ),
            drawer: Drawer(
              child: SafeArea(
                child: ListView(
                  children: [
                    ListTile(
                      title: Text(
                        'BckSnap $roleLabel',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      subtitle: Text(user?.displayName ?? ''),
                    ),
                    const Divider(),
                    for (var i = 0; i < dests.length; i++)
                      ListTile(
                        leading: Icon(dests[i].icon),
                        title: Text(dests[i].label),
                        selected: i == index,
                        onTap: () {
                          Navigator.pop(context);
                          context.go(dests[i].path);
                        },
                      ),
                  ],
                ),
              ),
            ),
            body: child,
          );
        }

        final extended = constraints.maxWidth >= 1200;
        return Scaffold(
          body: Row(
            children: [
              NavigationRail(
                extended: extended,
                minExtendedWidth: 220,
                labelType: extended
                    ? NavigationRailLabelType.none
                    : NavigationRailLabelType.all,
                selectedIndex: index,
                onDestinationSelected: (i) => context.go(dests[i].path),
                leading: Padding(
                  padding: const EdgeInsets.fromLTRB(8, 20, 8, 12),
                  child: Column(
                    children: [
                      const Icon(
                        Icons.accessibility_new,
                        size: 36,
                        color: AppColors.primary,
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        'BckSnap',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: AppColors.primary,
                        ),
                      ),
                      Text(roleLabel, style: const TextStyle(fontSize: 12)),
                    ],
                  ),
                ),
                destinations: [
                  for (final d in dests)
                    NavigationRailDestination(
                      icon: Icon(d.icon),
                      label: Text(d.label),
                    ),
                ],
                trailing: Expanded(
                  child: Align(
                    alignment: Alignment.bottomCenter,
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const ThemeModeButton(),
                          const StaffNotificationBell(),
                          
                          if (extended && user != null)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: Text(
                                user.displayName ?? '',
                                style: const TextStyle(fontSize: 12),
                              ),
                            ),
                          if (AuthService().isStaffAccount)
                            IconButton(
                              tooltip: 'Switch profile',
                              onPressed: () => _switchProfile(context),
                              icon: const Icon(Icons.switch_account_outlined),
                            ),
                          IconButton(
                            tooltip: 'My profile',
                            onPressed: () => context.push('/profile'),
                            icon: const MyAvatar(radius: 14),
                          ),
                          IconButton(
                            tooltip: 'Log out',
                            onPressed: () => _logout(context),
                            icon: const Icon(Icons.logout),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              const VerticalDivider(width: 1),
              Expanded(child: child),
            ],
          ),
        );
      },
    );
  }
}

/// The title row at the top of every website page.
class WebPageHeader extends StatelessWidget {
  final String title;
  final String? subtitle;
  final List<Widget> actions;
  const WebPageHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.actions = const [],
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: Theme.of(context).textTheme.headlineSmall
                    ?.copyWith(fontWeight: FontWeight.bold),
              ),
              if (subtitle != null) ...[
                const SizedBox(height: 4),
                Text(subtitle!),
              ],
            ],
          ),
        ),
        ...actions,
      ],
    );
  }
}
