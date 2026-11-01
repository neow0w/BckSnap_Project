import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'posture_analysis.dart';
import 'screening_result.dart';

class ResultScreen extends StatelessWidget {
  final ResultData data;
  const ResultScreen({super.key, required this.data});

  // "Did the user use the app as a guest?"
  // YES -> Sign up, NO -> User Home (connector A)
  // Everyone is logged in now: go to the user home (connector A).
  void _goToReferral(BuildContext context) => context.go('/home');

  String _deg(double v) => '${v.toStringAsFixed(1)}°';

  @override
  Widget build(BuildContext context) {
    final category = data.category;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Screening Result'),
        automaticallyImplyLeading: false,
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: Column(
              children: [
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      if (data.subjectLabel != null) ...[
                        Card(
                          child: ListTile(
                            leading: const Icon(Icons.person_outline),
                            title: const Text('Screened person'),
                            subtitle: Text(data.subjectLabel!),
                          ),
                        ),
                        const SizedBox(height: 12),
                      ],
                      _headline(category),
                      const SizedBox(height: 12),
                      _atrCard(),
                      const SizedBox(height: 12),
                      _postureCard(),
                      const SizedBox(height: 12),
                      const Text(
                        'This is a screening result, not a medical diagnosis. '
                        'Only a doctor can confirm scoliosis.',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontStyle: FontStyle.italic),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  child: _actions(context, category),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ---- headline ---------------------------------------------------------------

  Widget _headline(ResultCategory category) {
    final Color color;
    final IconData icon;
    final String title;
    final String message;

    switch (category) {
      case ResultCategory.refer:
        color = Colors.deepOrange;
        icon = Icons.warning_amber_rounded;
        title = 'Possible scoliosis: referral recommended';
        message =
            'The highest trunk rotation was ${_deg(data.highestAtr)}'
            '${data.highestLevel == null ? '' : ' at the ${data.highestLevel!.toLowerCase()} level'}. '
            'A reading of ${ResultRules.referAtr.toStringAsFixed(0)}° or more '
            'is the usual reason to be checked by a clinician, who may confirm '
            'it with an X-ray.';
      case ResultCategory.borderline:
        color = Colors.amber.shade800;
        icon = Icons.info_outline;
        title = 'Borderline result: please check again';
        message = data.borderlineFromPhotoOnly
            ? 'The trunk rotation was low (${_deg(data.highestAtr)}), but the '
                  'photo showed a noticeable shoulder or hip tilt. Repeat the '
                  'screening, and ask a clinician if it stays the same or you '
                  'have concerns.'
            : 'The highest trunk rotation was ${_deg(data.highestAtr)}, between '
                  '${ResultRules.borderlineAtr.toStringAsFixed(0)}° and '
                  '${ResultRules.referAtr.toStringAsFixed(0)}°. Repeat the '
                  'screening, and ask a clinician if it stays the same or you '
                  'have concerns.';
      case ResultCategory.noSign:
        color = Colors.green;
        icon = Icons.check_circle_outline;
        title = 'No sign of scoliosis detected';
        message =
            'The highest trunk rotation was ${_deg(data.highestAtr)}, below '
            '${ResultRules.borderlineAtr.toStringAsFixed(0)}°. This screening '
            'does not rule out scoliosis. If you notice uneven shoulders, a '
            'prominent shoulder blade, or back pain, ask a clinician.';
    }

    return Card(
      color: color.withValues(alpha: 0.15),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Icon(icon, size: 56, color: color),
            const SizedBox(height: 8),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(message, textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }

  // ---- trunk rotation (the deciding measurement) -----------------------------

  Widget _atrCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Trunk rotation (scoliometer)',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Text(
              'Highest: ${_deg(data.highestAtr)}',
              style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
            ),
            if (data.levels.isNotEmpty) ...[
              const SizedBox(height: 8),
              for (final l in data.levels)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Row(
                    children: [
                      Icon(
                        l.name == data.highestLevel
                            ? Icons.star
                            : Icons.straighten,
                        size: 16,
                        color: l.name == data.highestLevel
                            ? Colors.amber
                            : null,
                      ),
                      const SizedBox(width: 8),
                      Expanded(child: Text(l.name)),
                      Text(_deg(l.atr)),
                    ],
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }

  // ---- photo posture (supporting information) --------------------------------

  String _higherText(HigherSide h) => h == HigherSide.level
      ? 'level'
      : "higher on the patient's ${higherSideLabel(h)}";

  String _leanText(LeanSide s) => s == LeanSide.upright
      ? 'upright'
      : "leaning to the patient's ${leanSideLabel(s)}";

  Widget _postureCard() {
    final p = data.posture;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Posture from the back photo',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            if (p == null)
              const Text(
                'Not used. The photo was not taken with the guided camera, '
                'or it did not pass the quality check.',
              )
            else ...[
              _postureRow(
                'Shoulder tilt',
                _deg(p.shoulderTilt),
                _higherText(p.higherShoulder),
                p.shoulderFlag,
              ),
              _postureRow(
                'Hip tilt',
                _deg(p.hipTilt),
                _higherText(p.higherHip),
                p.hipFlag,
              ),
              _postureRow(
                'Trunk lean',
                _deg(p.trunkLean),
                _leanText(p.leanSide),
                false,
              ),
              const SizedBox(height: 8),
              Text(
                p.flagged
                    ? 'A noticeable tilt was found '
                          '(${PostureRules.shoulderTiltFlag.toStringAsFixed(0)}° '
                          'or more).'
                    : 'Both tilts are below the '
                          '${PostureRules.shoulderTiltFlag.toStringAsFixed(0)}° '
                          'flag level.',
              ),
              const SizedBox(height: 4),
              const Text(
                'Posture is supporting information only. It cannot confirm '
                'or rule out scoliosis, and the side that is higher does not '
                'show which way a curve bends.',
                style: TextStyle(fontSize: 12),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _postureRow(String label, String value, String detail, bool flag) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Icon(
            flag ? Icons.error_outline : Icons.check_circle_outline,
            size: 16,
            color: flag ? Colors.orange : Colors.green,
          ),
          const SizedBox(width: 8),
          Expanded(child: Text(label)),
          Text('$value  ($detail)'),
        ],
      ),
    );
  }

  // ---- buttons (Fig 7: "Does the patient have scoliosis?") ---------------------

  Widget _actions(BuildContext context, ResultCategory category) {
    if (category == ResultCategory.noSign) {
      // Scoliosis = NO: "Does the patient still wish to proceed to referral?"
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Do you still wish to proceed to the clinic referral option?',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          FilledButton(
            onPressed: () => _goToReferral(context),
            child: const Text('Yes, proceed to referral'),
          ),
          const SizedBox(height: 8),
          OutlinedButton(
            onPressed: () => context.go('/'),
            child: const Text('No, back to start'),
          ),
        ],
      );
    }
    // Scoliosis = YES (or borderline)
    return FilledButton(
      onPressed: () => _goToReferral(context),
      child: const Text('Continue to clinic referral'),
    );
  }
}
