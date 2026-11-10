import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme.dart';

class _StepInfo {
  final IconData icon;
  final String title;
  final String text;
  const _StepInfo(this.icon, this.title, this.text);
}

const _scolioSteps = [
  _StepInfo(
    Icons.accessibility_new,
    'Bend Forward At The Waist',
    'Stand with feet together and knees straight. Bend forward at the waist '
        'until your back is flat (horizontal), letting your arms hang '
        'loosely down.',
  ),
  _StepInfo(
    Icons.phone_android,
    'Place Phone Flat Across The Back',
    'Hold your phone sideways. Gently place the long edge flat across the '
        'back at the highest point of the rib or lumbar hump.',
  ),
  _StepInfo(
    Icons.straighten,
    'Keep Still The Scoliometer',
    'Hold steady and keep the phone level until the angle appears on the '
        'screen. The reading is taken automatically.',
  ),
];

/// Three tutorial pages for the chosen method, then the capture screen.
class ScreeningStepsScreen extends StatefulWidget {
  final String method; // 'pose' or 'scoliometer'
  const ScreeningStepsScreen({super.key, required this.method});

  @override
  State<ScreeningStepsScreen> createState() => _ScreeningStepsScreenState();
}

class _ScreeningStepsScreenState extends State<ScreeningStepsScreen> {
  final _pages = PageController();
  int _index = 0;

  List<_StepInfo> get _steps => _scolioSteps;

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  void _finish() => context.go('/screening/test');

  void _back() => context.go('/screening/questionnaire');

  void _next() {
    if (_index >= _steps.length - 1) {
      _finish();
    } else {
      _pages.nextPage(
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final last = _index == _steps.length - 1;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Scoliometer'),
        leading: BackButton(onPressed: _back),
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
              child: Column(
                children: [
                  Expanded(
                    child: PageView.builder(
                      controller: _pages,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: _steps.length,
                      onPageChanged: (i) => setState(() => _index = i),
                      itemBuilder: (context, i) {
                        final s = _steps[i];
                        return Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(s.icon, size: 150, color: AppColors.primary),
                            const SizedBox(height: 28),
                            Text(
                              s.title,
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w700,
                                color: AppColors.primary,
                              ),
                            ),
                            const SizedBox(height: 12),
                            Text(
                              s.text,
                              textAlign: TextAlign.center,
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      for (var i = 0; i < _steps.length; i++)
                        Container(
                          width: 7,
                          height: 7,
                          margin: const EdgeInsets.symmetric(horizontal: 3),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: i == _index
                                ? AppColors.primary
                                : AppColors.border,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: _next,
                      child: Text(last ? 'START' : 'NEXT'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
