import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme.dart';
import '../../services/screening_draft.dart';

/// Asked before every screening: for myself, or for someone else?
class ScreeningForScreen extends StatefulWidget {
  const ScreeningForScreen({super.key});

  @override
  State<ScreeningForScreen> createState() => _ScreeningForScreenState();
}

class _ScreeningForScreenState extends State<ScreeningForScreen> {
  bool _forSelf = true;

  @override
  void initState() {
    super.initState();
    ScreeningDraft.clear(); // every screening starts fresh
  }

  void _continue() {
    ScreeningDraft.forSelf = _forSelf;
    ScreeningDraft.subject = null;
    context.go(_forSelf ? '/screening/questionnaire' : '/screening/person');
  }

  Widget _option({
    required bool value,
    required IconData icon,
    required String title,
    required String text,
  }) {
    final selected = _forSelf == value;
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: () => setState(() => _forSelf = value),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: selected ? AppColors.fieldFill : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: selected ? AppColors.primary : AppColors.border,
            width: selected ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            Icon(icon, size: 40, color: AppColors.primary),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(text, style: Theme.of(context).textTheme.bodySmall),
                ],
              ),
            ),
            Icon(
              selected
                  ? Icons.radio_button_checked
                  : Icons.radio_button_unchecked,
              color: AppColors.primary,
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Start Screening'),
        leading: BackButton(onPressed: () => context.go('/home')),
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 16),
                  const Text(
                    'Who is this screening for?',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      color: AppColors.primary,
                    ),
                  ),
                  const SizedBox(height: 24),
                  _option(
                    value: true,
                    icon: Icons.person_outline,
                    title: 'Myself',
                    text: 'Screen any time with your account.',
                  ),
                  const SizedBox(height: 12),
                  _option(
                    value: false,
                    icon: Icons.people_outline,
                    title: 'Someone else',
                    text: "You will enter the person's information first.",
                  ),
                  const Spacer(),
                  FilledButton(
                    onPressed: _continue,
                    child: const Text('CONTINUE'),
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
