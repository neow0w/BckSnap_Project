import 'dart:typed_data';

import 'package:firebase_core/firebase_core.dart' show FirebaseException;
import 'package:flutter/material.dart';

import '../../core/format.dart';
import '../../models/screening.dart';
import '../../services/api_client.dart';
import '../../services/clinic_service.dart';
import '../../services/screening_service.dart';
import '../screening/progress_summary.dart';
import 'staff_web_shell.dart';

class _Patient {
  final String id;
  final String name;
  int visits = 0;
  DateTime? last;
  _Patient(this.id, this.name);
}

/// Doctor: patients with an approved appointment, and their saved screenings
/// (read only). The screening itself can only be done in the mobile app.
class WebPatientsPage extends StatefulWidget {
  const WebPatientsPage({super.key});

  @override
  State<WebPatientsPage> createState() => _WebPatientsPageState();
}

class _WebPatientsPageState extends State<WebPatientsPage> {
  final ClinicService _service = ClinicService();
  late final Stream<List<ClinicAppointment>> _stream = _service
      .staffAppointmentsStream();
  _Patient? _selected;
  Future<List<Screening>>? _future;

  void _select(_Patient p) {
    setState(() {
      _selected = p;
      _future = ScreeningService().screeningsOf(p.id);
    });
  }

  List<_Patient> _patients(List<ClinicAppointment> list) {
    final map = <String, _Patient>{};
    for (final a in list) {
      if (a.status != 'approved' && a.status != 'completed') continue;
      final p = map.putIfAbsent(
        a.userId,
        () => _Patient(a.userId, a.patientName ?? 'Patient'),
      );
      p.visits++;
      final t = a.scheduledAt;
      if (t != null && (p.last == null || t.isAfter(p.last!))) p.last = t;
    }
    final out = map.values.toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return out;
  }

  String _errorText(Object? e) {
    if (e is FirebaseException) return apiErrorFrom(e).message;
    if (e is ApiException) return e.message;
    return 'Could not load the data.';
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const WebPageHeader(
            title: 'Patients',
            subtitle: 'Patients with an approved appointment. Screening results are read only.',
          ),
          const SizedBox(height: 16),
          Expanded(
            child: Card(
              clipBehavior: Clip.antiAlias,
              child: Row(
                children: [
                  SizedBox(width: 320, child: _patientList()),
                  const VerticalDivider(width: 1),
                  Expanded(
                    child: _selected == null
                        ? const Center(child: Text('Select a patient.'))
                        : _detail(_selected!),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _patientList() {
    return StreamBuilder<List<ClinicAppointment>>(
      stream: _stream,
      builder: (context, snap) {
        if (snap.hasError) return Center(child: Text(_errorText(snap.error)));
        if (!snap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final patients = _patients(snap.data!);
        if (patients.isEmpty) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                'No patients yet. They appear here once you have an approved appointment.',
                textAlign: TextAlign.center,
              ),
            ),
          );
        }
        return ListView.separated(
          itemCount: patients.length,
          separatorBuilder: (_, _) => const Divider(height: 1),
          itemBuilder: (context, i) {
            final p = patients[i];
            return ListTile(
              selected: _selected?.id == p.id,
              leading: CircleAvatar(
                child: Text(p.name.isEmpty ? '?' : p.name[0].toUpperCase()),
              ),
              title: Text(p.name),
              subtitle: Text(
                '${p.visits} appointment${p.visits == 1 ? '' : 's'}'
                '${p.last == null ? '' : ' · last ${formatDate(p.last!.toLocal())}'}',
              ),
              onTap: () => _select(p),
            );
          },
        );
      },
    );
  }

  String _trendText(ProgressSummary s) {
    final c = s.change;
    return switch (s.trend) {
      Trend.first =>
        'First screening on record: highest trunk rotation ${s.latest!.angle.toStringAsFixed(1)}°.',
      Trend.improved =>
        'Improved by ${(-c!).toStringAsFixed(1)}° since the previous screening.',
      Trend.worse =>
        'Higher by ${c!.toStringAsFixed(1)}° since the previous screening.',
      Trend.same =>
        'About the same as the previous screening (${c!.abs().toStringAsFixed(1)}° difference).',
    };
  }

  Widget _detail(_Patient p) {
    return FutureBuilder<List<Screening>>(
      future: _future,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snap.hasError) return Center(child: Text(_errorText(snap.error)));
        final list = (snap.data ?? []).where((s) => s.forSelf).toList();
        final summary = ProgressSummary(list);
        return ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Text(
              p.name,
              style: Theme.of(context).textTheme.headlineSmall
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            if (list.isEmpty)
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: Text('This patient has no saved screenings yet.'),
                ),
              )
            else ...[
              Card(
                color: Theme.of(context).colorScheme.primary
                    .withValues(alpha: 0.08),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(_trendText(summary)),
                ),
              ),
              for (var i = 0; i < list.length; i++) _screeningCard(list, i),
            ],
            const SizedBox(height: 8),
            const Text(
              'Screening results are a screening aid, not a diagnosis. '
              'Screenings are done in the mobile app.',
              style: TextStyle(fontSize: 12, fontStyle: FontStyle.italic),
            ),
          ],
        );
      },
    );
  }

  Widget _screeningCard(List<Screening> list, int i) {
    final s = list[i];
    final older = i + 1 < list.length ? list[i + 1] : null;
    final diff = older == null ? null : s.angle - older.angle;
    final levels = (s.details?['levels'] as List? ?? const [])
        .whereType<Map>()
        .toList();
    String deg(dynamic v) => v is num ? '${v.toStringAsFixed(1)}°' : '-';

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    formatDate(s.createdAt),
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                Chip(
                  label: Text(ProgressSummary.levelLabel(s.angle)),
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
            Text(
              'Highest trunk rotation: ${s.angle.toStringAsFixed(1)}°'
              '${s.details?['highest_level'] == null ? '' : ' (${s.details!['highest_level']})'}'
              '${diff == null ? '' : '   ${diff >= 0 ? '+' : '-'}${diff.abs().toStringAsFixed(1)}° vs previous'}',
              style: const TextStyle(fontSize: 16),
            ),
            if (levels.isNotEmpty) ...[
              const SizedBox(height: 8),
              for (final l in levels) Text('${l['name']}: ${deg(l['atr'])}'),
            ],
            if (s.hasPhoto) ...[
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: () => _showPhoto(s),
                icon: const Icon(Icons.photo_outlined),
                label: const Text('View back photo'),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _showPhoto(Screening s) {
    return showDialog<void>(
      context: context,
      builder: (ctx) => Dialog(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520, maxHeight: 720),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: FutureBuilder<Uint8List?>(
                  future: ScreeningService().photoOf(s.id),
                  builder: (context, snap) {
                    if (snap.connectionState != ConnectionState.done) {
                      return const Padding(
                        padding: EdgeInsets.all(40),
                        child: CircularProgressIndicator(),
                      );
                    }
                    final bytes = snap.data;
                    if (snap.hasError || bytes == null) {
                      return const Padding(
                        padding: EdgeInsets.all(40),
                        child: Text('The photo is not available.'),
                      );
                    }
                    return InteractiveViewer(
                      child: Image.memory(bytes, fit: BoxFit.contain),
                    );
                  },
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(8),
                child: TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Close'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
