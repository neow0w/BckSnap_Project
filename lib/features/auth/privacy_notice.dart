import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

// ---------------------------------------------------------------------------
// DRAFT TEXT. Before real users see this:
//   1. Replace every [PLACEHOLDER] below.
//   2. Check each statement is true for YOUR system (storage, retention,
//      who has access).
//   3. Have your adviser / school / the clinic review it against the privacy
//      law that applies where you operate.
// If you change the meaning of the notice, raise [version] so the server
// records which text each person agreed to.
// ---------------------------------------------------------------------------

class NoticeSection {
  final String title;
  final String body;
  const NoticeSection(this.title, this.body);
}

class PrivacyNotice {
  static const String version = '1.0';
  static const String effectiveDate = '[EFFECTIVE DATE]';
  static const String organization = '[PROJECT / CLINIC NAME]';
  static const String contact = '[PRIVACY CONTACT EMAIL]';

  /// Short version shown on the consent step.
  static const List<String> summary = [
    'We collect your name, email and date of birth. If you screen, we also '
        'collect a photo of the back and the trunk-rotation reading.',
    'We use it to run the screening, show your result, and support clinic '
        'referral and appointments.',
    'Only you and the clinic staff who handle your care (receptionists and '
        'doctors) can see it.',
    'You can ask to see, correct or delete your data, and you can withdraw '
        'your consent at any time.',
  ];

  static const List<NoticeSection> sections = [
    NoticeSection(
      '1. Who we are',
      '$organization runs this app. Questions about your data can be sent to '
          '$contact.',
    ),
    NoticeSection(
      '2. What we collect',
      '• Account details: name, email, date of birth, and optionally phone '
          'number, address and a profile picture.\n'
          '• Screening data: the photo of the back, the trunk-rotation angle '
          'and the screening result. This is health-related (sensitive) '
          'information.\n'
          '• Care activity: appointment requests, their status, and messages '
          'you send to the clinic.\n'
          '• For people under 18: the parent or guardian\'s name, relationship '
          'and contact details.',
    ),
    NoticeSection(
      '3. Why we use it',
      '• To create and secure your account.\n'
          '• To carry out the scoliosis screening and show you the result.\n'
          '• To let the clinic review your screening, approve appointments '
          'and contact you.\n'
          '• We do not sell your data and do not use it for advertising.',
    ),
    NoticeSection(
      '4. Who can see it',
      'You can see your own data. Clinic receptionists and doctors can see '
          'the information needed to handle your appointment and referral. '
          'Anyone else only sees it if the law requires it.',
    ),
    NoticeSection(
      '5. How we protect it',
      'Your data is kept on a protected server and access is limited by role. '
          '[DESCRIBE YOUR REAL SAFEGUARDS: e.g. encrypted connection, hashed '
          'passwords, access logs.]',
    ),
    NoticeSection(
      '6. How long we keep it',
      '[STATE YOUR RETENTION PERIOD.] When you delete your account, your '
          'data is removed unless the law requires us to keep it.',
    ),
    NoticeSection(
      '7. Your rights',
      'You may ask to access, correct or delete your data, and you may '
          'withdraw your consent at any time. Withdrawing consent does not '
          'affect what was done before, but we may no longer be able to '
          'provide the service. Contact $contact.',
    ),
    NoticeSection(
      '8. Children and teenagers',
      'People aged 9 to 17 need a parent or legal guardian to give consent, '
          'and the young person is also asked to agree (assent) in simple '
          'words. People under 9 cannot create an account.',
    ),
    NoticeSection(
      '9. Screening is not a diagnosis',
      'The result is a screening aid. Only a doctor can confirm scoliosis.',
    ),
  ];
}

/// The full notice (route: /privacy). Public: reachable before login.
class PrivacyNoticeScreen extends StatelessWidget {
  const PrivacyNoticeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Privacy Notice'),
        leading: BackButton(
          onPressed: () => context.canPop() ? context.pop() : context.go('/'),
        ),
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                Text(
                  'Version ${PrivacyNotice.version} · '
                  'Effective ${PrivacyNotice.effectiveDate}',
                  style: const TextStyle(fontSize: 12),
                ),
                const SizedBox(height: 12),
                for (final s in PrivacyNotice.sections) ...[
                  Text(
                    s.title,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(s.body),
                  const SizedBox(height: 16),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
