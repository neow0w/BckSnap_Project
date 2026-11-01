import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../services/auth_service.dart';
import '../screening/progress_banner.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final user = AuthService().currentUser;
    return Scaffold(
      appBar: AppBar(
        title: const Text('BckSnap'),
        actions: [
          IconButton(
            tooltip: 'Notifications',
            onPressed: () => context.push('/notifications'),
            icon: const Icon(Icons.notifications_outlined),
          ),
          IconButton(
            tooltip: 'My profile',
            onPressed: () => context.push('/profile'),
            icon: const Icon(Icons.person_outline),
          ),
          IconButton(
            tooltip: 'Log out',
            onPressed: () async {
              await AuthService().logout();
              if (context.mounted) context.go('/');
            },
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              const Icon(Icons.accessibility_new, size: 64),
              const SizedBox(height: 12),
              Text(
                user?.displayName == null
                    ? 'Welcome to BckSnap'
                    : 'Welcome, ${user!.displayName}',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              const SizedBox(height: 8),
              const Text(
                'Find a clinic, request an appointment, and keep track of your care.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              const ProgressBanner(),
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: () => context.push('/clinics'),
                icon: const Icon(Icons.search),
                label: const Text('Find a clinic'),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: () => context.push('/appointments'),
                icon: const Icon(Icons.calendar_month_outlined),
                label: const Text('My appointments'),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: () => context.push('/screening/photo'),
                icon: const Icon(Icons.accessibility_new),
                label: const Text('Start a scoliosis screening'),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: () => context.push('/clinics'),
                icon: const Icon(Icons.chat_bubble_outline),
                label: const Text('Message a clinic'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
