import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/format.dart';
import '../../core/theme.dart';
import '../../models/screening.dart';
import '../../services/api_client.dart';
import '../../services/screening_service.dart';
import '../screening/progress_summary.dart';

/// Clinical referral tab: the latest result and the way to a clinic.
class ReferralScreen extends StatefulWidget {
  const ReferralScreen({super.key});

  @override
  State<ReferralScreen> createState() => _ReferralScreenState();
}

class _ReferralScreenState extends State<ReferralScreen> {
  Screening? _latest;
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
      final list = await ScreeningService().myScreenings();
      if (mounted) setState(() => _latest = list.isEmpty ? null : list.first);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not load your result.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Referral'),
        automaticallyImplyLeading: false,
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
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
    final s = _latest;
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        if (s == null) ...[
          const SizedBox(height: 40),
          const Icon(
            Icons.local_hospital_outlined,
            size: 80,
            color: AppColors.primary,
          ),
          const SizedBox(height: 16),
          const Text(
            'No screening yet',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          Text(
            'Do a screening first. If it shows a risk, you can book a clinic '
            'from here.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: () => context.push('/screening/for'),
            child: const Text('START SCREENING'),
          ),
        ] else ...[
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Latest screening',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: AppColors.primary,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '${s.angle.toStringAsFixed(1)}°  ·  '
                    '${ProgressSummary.levelLabel(s.angle)}',
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    formatDate(s.createdAt),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'A clinician can review your result and decide whether more '
            'tests are needed. Only a doctor can confirm scoliosis.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 20),
          FilledButton(
            onPressed: () => context.push('/clinics'),
            child: const Text('FIND A CLINIC'),
          ),
          const SizedBox(height: 10),
          FilledButton.tonal(
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.tonal,
              foregroundColor: AppColors.primary,
            ),
            onPressed: () => context.push('/appointments'),
            child: const Text('MY APPOINTMENTS'),
          ),
        ],
      ],
    );
  }
}
