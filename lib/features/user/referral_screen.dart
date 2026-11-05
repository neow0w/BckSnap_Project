
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/format.dart';
import '../../core/theme.dart';
import '../../models/screening.dart';
import '../../services/api_client.dart';
import '../../services/screening_service.dart';
import '../../services/screening_pdf_service.dart';
import '../screening/posture_analysis.dart';
import '../screening/screening_result.dart';

class ReferralScreen extends StatefulWidget {
    const ReferralScreen({super.key});

    @override
    State<ReferralScreen> createState() => _ReferralScreenState();
}

class _ReferralScreenState extends State<ReferralScreen> {
    Screening? _latest;
    bool _loading = true;
    bool _downloading = false;
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

            if (mounted) {
                setState(() {
                    _latest = list.isEmpty ? null : list.first;
                });
            }
        } on ApiException catch (e) {
            if (mounted) setState(() => _error = e.message);
        } catch (_) {
            if (mounted) {
                setState(() => _error = 'Could not load your result.');
            }
        } finally {
            if (mounted) setState(() => _loading = false);
        }
    }

    Future<void> _downloadPdf(Screening screening) async {
        setState(() => _downloading = true);

        try {
            await ScreeningPdfService.download(screening);
        } catch (e) {
            if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                        content: Text('Could not generate PDF: $e'),
                    ),
                );
            }
        } finally {
            if (mounted) {
                setState(() => _downloading = false);
            }
        }
    }

    @override
    Widget build(BuildContext context) {
        return Scaffold(
            appBar: AppBar(
                title: const Text('Referral'),
                automaticallyImplyLeading: false,
                actions: [
                    IconButton(
                        tooltip: 'Refresh results',
                        onPressed: _loading ? null : _load,
                        icon: const Icon(Icons.refresh),
                    ),
                ],
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
        if (_loading) {
            return const Center(child: CircularProgressIndicator());
        }

        if (_error != null) {
            return Center(
                child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                        Text(_error!),
                        const SizedBox(height: 12),
                        FilledButton(
                            onPressed: _load,
                            child: const Text('Retry'),
                        ),
                    ],
                ),
            );
        }

        final screening = _latest;

        if (screening == null) {
            return _emptyState(context);
        }

        return _results(context, screening);
    }

    Widget _emptyState(BuildContext context) {
        return ListView(
            padding: const EdgeInsets.all(24),
            children: [
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
                    style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                    ),
                ),
                const SizedBox(height: 8),
                Text(
                    'Complete a screening first. Your results will appear here.',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 24),
                FilledButton(
                    onPressed: () => context.push('/screening/for'),
                    child: const Text('START SCREENING'),
                ),
            ],
        );
    }

    Widget _results(BuildContext context, Screening screening) {
        final details = screening.details ?? {};
        final rawLevels = details['levels'];
        final levels = rawLevels is List
            ? rawLevels.whereType<Map>().map(
                (item) => Map<String, dynamic>.from(item),
            ).toList()
            : <Map<String, dynamic>>[];

        final rawPosture = details['posture'];
        final posture = rawPosture is Map
            ? Map<String, dynamic>.from(rawPosture)
            : null;

        final category = _category(screening, posture);

        return ListView(
            padding: const EdgeInsets.all(20),
            children: [
                _resultCard(screening, category),
                const SizedBox(height: 16),
                _personCard(screening),
                const SizedBox(height: 16),
                _measurementCard(screening, levels),
                if (posture != null) ...[
                    const SizedBox(height: 16),
                    _postureCard(posture),
                ],
                const SizedBox(height: 16),
                _disclaimerCard(),
                const SizedBox(height: 20),
                FilledButton.icon(
                    onPressed: _downloading
                        ? null
                        : () => _downloadPdf(screening),
                    icon: _downloading
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                            ),
                        )
                        : const Icon(Icons.picture_as_pdf),
                    label: Text(
                        _downloading
                            ? 'GENERATING PDF...'
                            : 'DOWNLOAD SCREENING REPORT',
                    ),
                ),
                const SizedBox(height: 12),
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
        );
    }

    Widget _resultCard(
        Screening screening,
        ResultCategory category,
    ) {
        final color = _categoryColor(category);

        return Card(
            child: Padding(
                padding: const EdgeInsets.all(18),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                        const Text(
                            'LATEST SCREENING RESULT',
                            style: TextStyle(
                                fontWeight: FontWeight.w700,
                                color: AppColors.primary,
                                letterSpacing: 0.5,
                            ),
                        ),
                        const SizedBox(height: 16),
                        Text(
                            '${screening.angle.toStringAsFixed(1)}°',
                            style: const TextStyle(
                                fontSize: 36,
                                fontWeight: FontWeight.w800,
                            ),
                        ),
                        const Text(
                            'Highest ATR reading',
                            style: TextStyle(color: Colors.grey),
                        ),
                        const SizedBox(height: 14),
                        Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 8,
                            ),
                            decoration: BoxDecoration(
                                color: color.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                                _categoryLabel(category),
                                style: TextStyle(
                                    color: color,
                                    fontWeight: FontWeight.w700,
                                ),
                            ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                            formatDate(screening.createdAt),
                            style: const TextStyle(color: Colors.grey),
                        ),
                    ],
                ),
            ),
        );
    }

    Widget _personCard(Screening screening) {
        final name = screening.forSelf
            ? 'Account holder'
            : (screening.subjectName ?? 'Other screened person');

        return Card(
            child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                        _sectionHeading('Screened person', Icons.person_outline),
                        const SizedBox(height: 12),
                        _detailRow('Name', name),
                        _detailRow(
                            'Screening type',
                            screening.forSelf ? 'Self-screening' : 'Other person',
                        ),
                        _detailRow(
                            'Back photo',
                            screening.hasPhoto ? 'Available' : 'Not available',
                        ),
                    ],
                ),
            ),
        );
    }

    Widget _measurementCard(
        Screening screening,
        List<Map<String, dynamic>> levels,
    ) {
        return Card(
            child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                        _sectionHeading(
                            'Spinal level measurements',
                            Icons.straighten,
                        ),
                        const SizedBox(height: 12),
                        if (levels.isEmpty)
                            const Text(
                                'Individual spinal level readings are not available for this screening.',
                            )
                        else
                            ...levels.map((level) {
                                final name = level['name']?.toString() ?? 'Unknown';
                                final atr = _number(level['atr']);

                                return _detailRow(
                                    name,
                                    '${atr.toStringAsFixed(1)}°',
                                );
                            }),
                    ],
                ),
            ),
        );
    }

    Widget _postureCard(Map<String, dynamic> posture) {
        final shoulder = _number(posture['shoulder_tilt']);
        final hip = _number(posture['hip_tilt']);

        return Card(
            child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                        _sectionHeading(
                            'Photo posture analysis',
                            Icons.accessibility_new,
                        ),
                        const SizedBox(height: 12),
                        _detailRow(
                            'Shoulder tilt',
                            '${shoulder.toStringAsFixed(1)}°',
                        ),
                        _detailRow(
                            'Shoulder status',
                            shoulder >= PostureRules.shoulderTiltFlag
                                ? 'Flagged'
                                : 'Not flagged',
                        ),
                        _detailRow(
                            'Higher shoulder',
                            _label(posture['higher_shoulder']),
                        ),
                        const Divider(),
                        _detailRow(
                            'Hip tilt',
                            '${hip.toStringAsFixed(1)}°',
                        ),
                        _detailRow(
                            'Hip status',
                            hip >= PostureRules.hipTiltFlag
                                ? 'Flagged'
                                : 'Not flagged',
                        ),
                        _detailRow(
                            'Higher hip',
                            _label(posture['higher_hip']),
                        ),
                        const Divider(),
                        _detailRow(
                            'Trunk lean',
                            '${_number(posture['trunk_lean']).toStringAsFixed(1)}°',
                        ),
                        _detailRow(
                            'Lean direction',
                            _label(posture['lean_side']),
                        ),
                    ],
                ),
            ),
        );
    }

    Widget _disclaimerCard() {
        return Card(
            color: AppColors.tonal,
            child: const Padding(
                padding: EdgeInsets.all(16),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                        Text(
                            'Important reminder',
                            style: TextStyle(
                                fontWeight: FontWeight.w700,
                                color: AppColors.primary,
                            ),
                        ),
                        SizedBox(height: 8),
                        Text(
                            'These are preliminary screening results, not a '
                            'medical diagnosis. ATR readings and photo-based '
                            'posture measurements are supporting information. '
                            'Only a qualified healthcare professional can '
                            'confirm scoliosis.',
                        ),
                    ],
                ),
            ),
        );
    }

    Widget _sectionHeading(String title, IconData icon) {
        return Row(
            children: [
                Icon(icon, color: AppColors.primary),
                const SizedBox(width: 8),
                Expanded(
                    child: Text(
                        title,
                        style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 16,
                        ),
                    ),
                ),
            ],
        );
    }

    Widget _detailRow(String label, String value) {
        return Padding(
            padding: const EdgeInsets.symmetric(vertical: 5),
            child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                    Expanded(
                        child: Text(
                            label,
                            style: const TextStyle(color: Colors.grey),
                        ),
                    ),
                    const SizedBox(width: 12),
                    Flexible(
                        child: Text(
                            value,
                            textAlign: TextAlign.end,
                            style: const TextStyle(
                                fontWeight: FontWeight.w600,
                            ),
                        ),
                    ),
                ],
            ),
        );
    }

    ResultCategory _category(
        Screening screening,
        Map<String, dynamic>? posture,
    ) {
        if (screening.angle >= ResultRules.referAtr) {
            return ResultCategory.refer;
        }

        if (screening.angle >= ResultRules.borderlineAtr) {
            return ResultCategory.borderline;
        }

        if (posture != null) {
            final shoulder = _number(posture['shoulder_tilt']);
            final hip = _number(posture['hip_tilt']);

            if (shoulder >= PostureRules.shoulderTiltFlag ||
                hip >= PostureRules.hipTiltFlag) {
                return ResultCategory.borderline;
            }
        }

        return ResultCategory.noSign;
    }

    String _categoryLabel(ResultCategory category) {
        switch (category) {
            case ResultCategory.refer:
                return 'REFERRAL RANGE';
            case ResultCategory.borderline:
                return 'BORDERLINE';
            case ResultCategory.noSign:
                return 'NO SIGN';
        }
    }

    Color _categoryColor(ResultCategory category) {
        switch (category) {
            case ResultCategory.refer:
                return Colors.red;
            case ResultCategory.borderline:
                return Colors.orange.shade800;
            case ResultCategory.noSign:
                return Colors.green.shade700;
        }
    }

    double _number(dynamic value) {
        if (value is num) return value.toDouble();
        return double.tryParse(value?.toString() ?? '') ?? 0;
    }

    String _label(dynamic value) {
        final text = value?.toString() ?? 'Not available';

        if (text.isEmpty) return 'Not available';

        return '${text[0].toUpperCase()}${text.substring(1)}';
    }
}
