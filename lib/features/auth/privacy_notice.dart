import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

// ---------------------------------------------------------------------------
// BCKSNAP PRIVACY NOTICE
// Data Privacy Act of 2012 (R.A. 10173)
//
// Before deployment:
//   1. Confirm the effective date.
//   2. Verify that the described security and anonymization measures
//      are implemented in your actual system.
//   3. Confirm the retention and deletion procedures with your adviser.
//   4. Have the notice reviewed for compliance with applicable privacy laws.
// ---------------------------------------------------------------------------

class NoticeSection {
  final String title;
  final String body;

  const NoticeSection(this.title, this.body);
}

class PrivacyNotice {
  static const String version = '2.0';
  static const String effectiveDate = '[EFFECTIVE DATE]';
  static const String organization = 'BckSnap';

  /// Short version shown on the consent step.
  static const List<String> summary = [
    'BckSnap collects your age, sex, profile details, screening results, '
        'and evaluation questionnaire responses.',
    'Your information is used for scoliosis screening, trunk rotation '
        'assessment, clinic referrals, and academic system evaluation '
        'under the ISO/IEC 25010 framework.',
    'Your personal identity is separated from screening records using '
        'a unique participant code. Data is accessible only to authorized '
        'researchers and the research adviser.',
    'You may access, correct, or request deletion of your personal data. '
        'You may also withdraw your consent before dataset consolidation.',
    'Your personal information will be securely deleted after the'
        'capstone project is completed, defended, '
        'and approved.',
  ];

  static const List<NoticeSection> sections = [
    NoticeSection(
      '1. Introduction',
      'We respect every individual\'s right to privacy as much as we aim '
          'to ensure the safety and security of everyone participating '
          'in our evaluation sessions. Please take the time to read this '
          'Privacy Notice explaining how we process the information we '
          'collect from or generate about you when you use the BckSnap '
          'application, in accordance with the Data Privacy Act of 2012 '
          '(R.A. 10173).\n\n'
          'Those who undergo our app-assisted screening or system '
          'evaluation will have been shown a similar Notice before or '
          'around the time their session or data collection begins.',
    ),

    NoticeSection(
      '2. What We Collect',
      'To perform screening, compute trunk rotation metrics, '
          'and facilitate clinic referrals, BckSnap collects the '
          'following categories of data:\n\n'
          '• Account and Profile Details: Your age, sex, and basic '
          'profile identifiers collected during registration or screening.\n\n'
          '• Screening Data: Trunk rotation (ATR) readings at each back level, '
          'the resulting risk classification, and the date of each screening.\n\n'
          '• Evaluation Data: Responses provided through the ISO/IEC 25010 '
          'system evaluation questionnaires by user beneficiaries '
          'and clinic staff.',
    ),

    NoticeSection(
      '3. How BckSnap Uses Your Data',
      'Your data is processed within the app environment and research '
          'pipeline for the following purposes:\n\n'
          '• Reading the phone\'s motion sensor to compute trunk rotation '
          '(ATR) measurements.\n\n'
          '• Generating screening risk assessments and connecting you '
          'with local partner clinics if a referral is needed.\n\n'
          '• Evaluating app usability and software quality under the '
          'ISO/IEC 25010 framework to improve our capstone project.',
    ),

    NoticeSection(
      '4. Anonymity and Data Security',
      'Anonymization: All personal identities are decoupled from raw '
          'screening records. Each participant is assigned a unique '
          'participant code to ensure that data handled during analysis '
          'remains anonymous.\n\n'
          'Encryption and Storage: All digital files, photographs, and '
          'records are stored in secure, password-protected cloud storage '
          'and encrypted digital folders accessible only by authorized '
          'researchers and the research adviser.\n\n'
          'Physical Privacy: Screening sessions are conducted in private, '
          'quiet areas within partner clinics to respect your personal '
          'space and dignity.',
    ),

    NoticeSection(
      '5. Data Retention and Disposal',
      'Personal records, screening photographs, and evaluation data '
          'will be retained only for the duration of the academic '
          'capstone project.\n\n'
          'Once the research has been completed, defended, and approved, '
          'all raw image files and personally identifiable information '
          'will be permanently and securely deleted from all mobile '
          'devices, local drives, and cloud repositories.',
    ),

    NoticeSection(
      '6. Your Rights as a Data Subject',
      'In accordance with the Data Privacy Act of 2012 (R.A. 10173), '
          'you have the following rights as a data subject:\n\n'
          '• Right to Be Informed: You have the right to know how your '
          'personal data is collected, used, stored, and processed.\n\n'
          '• Right to Access: You may request access to your personal data.\n\n'
          '• Right to Object and Withdraw Consent: You may object to '
          'or withdraw your consent at any time prior to dataset '
          'consolidation, without penalty or loss of benefits.\n\n'
          '• Right to Rectification: You may request the correction '
          'of inaccurate or incomplete personal information.\n\n'
          '• Right to Erasure or Blocking: You may request the deletion '
          'of your personal records, subject to applicable legal '
          'requirements and the stage of research processing.',
    ),

    NoticeSection(
      '7. Contact Us and Privacy Concerns',
      'If you have any questions, concerns, or requests regarding '
          'this Privacy Notice or how your data is handled, you may '
          'contact any member of our research team through the '
          'following contact details:\n\n'
          'Jana Beatrice B. Agustin\n'
          'Email: janabeatrice@gmail.com\n'
          'Contact Number: 0995-364-9868\n\n'
          'Peavey Iya J. Carpaccio\n'
          'Email: peaveycapacio@gmail.com\n'
          'Contact Number: 0975-891-6089\n\n'
          'Joseph Ismael C. Desalit\n'
          'Email: josephdesalit628@gmail.com\n'
          'Contact Number: 0992-621-0697\n\n'
          'Eliand John N. Penus\n'
          'Email: meetjhay08@gmail.com\n'
          'Contact Number: 0960-412-3893\n\n'
          'Earl Michael B. Perucho\n'
          'Email: earlmichaelperucho@gmail.com\n'
          'Contact Number: 0991-580-0564',
    ),
  ];
}

/// The full notice (route: /privacy).
/// Public: reachable before login.
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
                  '${PrivacyNotice.organization} · '
                  'Version ${PrivacyNotice.version}\n'
                  'Effective ${PrivacyNotice.effectiveDate}',
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                ),
                const SizedBox(height: 20),

                for (final section in PrivacyNotice.sections) ...[
                  Text(
                    section.title,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    section.body,
                    textAlign: TextAlign.justify,
                    style: const TextStyle(fontSize: 14, height: 1.6),
                  ),
                  const SizedBox(height: 20),
                ],

                const Divider(),
                const SizedBox(height: 8),
                const Text(
                  'BckSnap Privacy Notice · Version '
                  '${PrivacyNotice.version}',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 11, color: Colors.grey),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
