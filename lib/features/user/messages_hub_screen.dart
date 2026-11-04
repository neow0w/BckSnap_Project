import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../services/api_client.dart';
import '../../services/clinic_service.dart';

/// Messages tab: the clinics the patient has an appointment with.
class MessagesHubScreen extends StatefulWidget {
  const MessagesHubScreen({super.key});

  @override
  State<MessagesHubScreen> createState() => _MessagesHubScreenState();
}

class _MessagesHubScreenState extends State<MessagesHubScreen> {
  final _service = ClinicService();
  Map<String, String> _clinics = {}; // id -> name
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final list = await _service.appointments();
      final map = <String, String>{};
      for (final a in list) {
        final id = a.clinicId;
        if (id != null) map.putIfAbsent(id, () => a.clinicName ?? 'Clinic');
      }
      if (mounted) setState(() => _clinics = map);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not load your clinics.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Messages'),
        automaticallyImplyLeading: false,
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 600),
            child: _body(context),
          ),
        ),
      ),
    );
  }

  Widget _body(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_error!),
            const SizedBox(height: 12),
            FilledButton(onPressed: _load, child: const Text('Retry')),
          ],
        ),
      );
    }
    if (_clinics.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.chat_bubble_outline, size: 56),
              const SizedBox(height: 12),
              const Text('No conversations yet'),
              const SizedBox(height: 6),
              Text(
                'Open a clinic to send it a message.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () => context.push('/clinics'),
                child: const Text('FIND A CLINIC'),
              ),
            ],
          ),
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        children: [
          for (final e in _clinics.entries)
            ListTile(
              leading: const CircleAvatar(child: Icon(Icons.local_hospital)),
              title: Text(e.value),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.push('/message/${e.key}'),
            ),
        ],
      ),
    );
  }
}
