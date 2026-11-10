import '../../core/format.dart';
import '../../core/validators.dart';

enum QType { text, date, single, multi, slider, computed }

typedef Answers = Map<String, dynamic>;

class Q {
  final String id;
  final String label;
  final QType type;
  final List<String> options;

  /// Choosing one of these clears the other choices (for example "None").
  final Set<String> exclusive;

  /// Validation for text and date questions:
  /// name, email, phone, address, height, weight, dob, past, text.
  final String kind;
  final String? hint;

  /// The question is shown only when this returns true.
  final bool Function(Answers)? showIf;

  const Q(
    this.id,
    this.label,
    this.type, {
    this.options = const [],
    this.exclusive = const {},
    this.kind = 'text',
    this.hint,
    this.showIf,
  });
}

class QSection {
  final String title;
  final List<Q> questions;
  const QSection(this.title, this.questions);
}

Q _yn(String id, String label, {bool Function(Answers)? showIf}) =>
    Q(id, label, QType.single, options: const ['Yes', 'No'], showIf: showIf);

Q _yns(String id, String label, {bool Function(Answers)? showIf}) => Q(
  id,
  label,
  QType.single,
  options: const ['Yes', 'No', 'Not sure'],
  showIf: showIf,
);

bool Function(Answers) _ifYes(String id) =>
    (a) => a[id] == 'Yes';

final List<QSection> kSections = [
  QSection('Patient information', [
    Q(
      'full_name',
      'Full name',
      QType.text,
      kind: 'name',
      hint: 'Juan Dela Cruz',
    ),
    Q('email', 'Email', QType.text, kind: 'email', hint: 'example@example.com'),
    Q('address', 'Address', QType.text, kind: 'address'),
    Q(
      'contact',
      'Contact number',
      QType.text,
      kind: 'phone',
      hint: '09123456789',
    ),
    Q('birthday', 'Birthday', QType.date, kind: 'dob'),
    Q('age', 'Age', QType.computed),
    Q('sex', 'Sex', QType.single, options: ['Male', 'Female']),
    Q('height', 'Height (m)', QType.text, kind: 'height', hint: '1.60'),
    Q('weight', 'Weight (kg)', QType.text, kind: 'weight', hint: '55'),
    Q('bmi', 'BMI', QType.computed),
  ]),
  QSection('Emergency contact', [
    Q('ec_name', 'Emergency contact name', QType.text, kind: 'name'),
    Q('ec_phone', 'Phone', QType.text, kind: 'phone'),
    Q('ec_relationship', 'Relationship', QType.text, hint: 'e.g. Mother'),
  ]),
  QSection('Family history', [
    _yns(
      'fam_scoliosis',
      'Does anyone in the patient’s family have scoliosis?',
    ),
    Q(
      'fam_who',
      'If yes, who?',
      QType.multi,
      options: [
        'Parent',
        'Sibling',
        'Grandparent',
        'Aunt or Uncle',
        'Cousin',
        'Other',
      ],
      showIf: _ifYes('fam_scoliosis'),
    ),
    _yns(
      'fam_treatment',
      'Did that person need a brace or surgery?',
      showIf: _ifYes('fam_scoliosis'),
    ),
  ]),
  QSection('How the curve was noticed', [
    _yns(
      'noticed_uneven',
      'Has anyone noticed that the back, shoulders, or waist look uneven?',
    ),
    Q(
      'noticed_what',
      'If yes, what was noticed?',
      QType.multi,
      options: [
        'One shoulder higher',
        'One shoulder blade sticks out',
        'Uneven waist or hips',
        'A bump on one side of the back when bending',
        'Head not centered',
        'Clothes hang unevenly',
        'Other',
      ],
      showIf: _ifYes('noticed_uneven'),
    ),
    Q(
      'first_noticed',
      'When was it first noticed?',
      QType.single,
      options: [
        'Less than 3 months ago',
        '3 to 12 months ago',
        'More than 1 year ago',
        'Not sure',
      ],
      showIf: _ifYes('noticed_uneven'),
    ),
    _yns(
      'got_worse',
      'Has it seemed to get worse?',
      showIf: _ifYes('noticed_uneven'),
    ),
    _yn('xray_before', 'Has the patient had a spine X-ray before?'),
    Q(
      'xray_result',
      'If yes, what was the result?',
      QType.text,
      showIf: _ifYes('xray_before'),
    ),
    Q(
      'xray_date',
      'When was it done?',
      QType.date,
      kind: 'past',
      showIf: _ifYes('xray_before'),
    ),
  ]),
  QSection('Pain level', [
    _yn('back_pain', 'Does the patient have back pain?'),
    Q(
      'pain_where',
      'Where is the pain?',
      QType.multi,
      options: ['Upper', 'Middle', 'Lower', 'Left side', 'Right side'],
      showIf: _ifYes('back_pain'),
    ),
    Q(
      'pain_level',
      'How strong is the pain on a scale of 0 to 10?',
      QType.slider,
      showIf: _ifYes('back_pain'),
    ),
    Q(
      'pain_duration',
      'How long has the pain lasted?',
      QType.single,
      options: [
        'Less than 1 week',
        '1 to 4 weeks',
        '1 to 3 months',
        'More than 3 months',
      ],
      showIf: _ifYes('back_pain'),
    ),
    _yn(
      'pain_wakes',
      'Does the pain wake the patient from sleep?',
      showIf: _ifYes('back_pain'),
    ),
    _yn(
      'pain_spreads',
      'Does the pain spread to the hips, buttocks, or legs?',
      showIf: _ifYes('back_pain'),
    ),
    Q(
      'pain_worse',
      'When is it worse?',
      QType.multi,
      options: [
        'With activity',
        'When sitting',
        'When standing',
        'At night',
        'No pattern',
      ],
      exclusive: {'No pattern'},
      showIf: _ifYes('back_pain'),
    ),
    Q(
      'pain_helps',
      'What helps?',
      QType.multi,
      options: ['Rest', 'Medicine', 'Changing position', 'Nothing', 'Other'],
      exclusive: {'Nothing'},
      showIf: _ifYes('back_pain'),
    ),
  ]),
  QSection('Nerve and body-function symptoms', [
    _yn(
      'numbness',
      'Does the patient have numbness, tingling, or weakness in the arms or legs?',
    ),
    _yn(
      'walking_changed',
      'Has the patient’s walking, balance, or coordination changed recently?',
    ),
    _yn(
      'bladder_bowel',
      'Has there been any change in bladder or bowel control?',
    ),
    _yn('headaches', 'Does the patient often have headaches or dizziness?'),
    _yn(
      'short_breath',
      'Does the patient get short of breath or tired more easily than other '
          'children or people of the same age?',
    ),
  ]),
  QSection('Medical history', [
    _yn(
      'born_early',
      'Was the patient born early (before 37 weeks) or were there problems at birth?',
    ),
    _yn(
      'late_milestones',
      'Did the patient start sitting or walking later than other children?',
    ),
    Q(
      'conditions',
      'Has a doctor ever said the patient has any of these?',
      QType.multi,
      options: [
        'Neurofibromatosis',
        'Marfan syndrome',
        'Ehlers-Danlos syndrome',
        'Cerebral palsy',
        'Muscular dystrophy or other muscle disease',
        'Spina bifida',
        'Heart or kidney condition present from birth',
        'Other',
        'None',
        'Not sure',
      ],
      exclusive: {'None', 'Not sure'},
    ),
    _yn(
      'skin_marks',
      'Does the patient have brown birthmark spots on the skin (more than '
          'about 5), or a tuft of hair or dimple on the lower back?',
    ),
    _yn(
      'spine_surgery',
      'Has the patient had surgery on the spine, chest, or heart, or '
          'radiation treatment to the chest or spine?',
    ),
    _yn(
      'flexible',
      'Is the patient very flexible, for example, can bend the thumb back to '
          'the wrist or bend the elbows or knees backward?',
    ),
    _yn(
      'medicine',
      'Is the patient taking any regular medicine or supplements?',
    ),
    Q(
      'medicine_text',
      'Which medicine or supplements?',
      QType.text,
      showIf: _ifYes('medicine'),
    ),
  ]),
  QSection('Leg length, feet, and others', [
    _yn(
      'leg_surgery',
      'Has the patient ever broken a leg, or had hip, knee, or foot surgery?',
    ),
    _yn('limp', 'Does the patient limp or walk unevenly?'),
    _yn(
      'hem_uneven',
      'Does one pant leg or skirt hem always look longer than the other?',
    ),
    _yn('shoe_lift', 'Does the patient use a shoe lift or special insole?'),
    _yn(
      'flat_feet',
      'Does the patient have flat feet or another foot problem?',
    ),
    _yn(
      'back_injury',
      'Has the patient had a recent injury, strain, or muscle spasm in the back?',
    ),
    _yn(
      'one_sided',
      'Does the patient usually carry a heavy bag on one shoulder, or play a '
          'sport that uses one side mostly (for example, tennis or badminton)?',
    ),
  ]),
];

class QuestionnaireData {
  static List<Q> visible(QSection s, Answers a) =>
      s.questions.where((q) => q.showIf == null || q.showIf!(a)).toList();

  static double? parseDecimal(String? s) =>
      double.tryParse((s ?? '').trim().replaceAll(',', '.'));

  static int? ageFrom(String? iso) {
    final d = DateTime.tryParse(iso ?? '');
    if (d == null) return null;
    final age = Validators.ageOn(d, DateTime.now());
    return (age < 0 || age > 110) ? null : age;
  }

  /// BMI = weight (kg) / height (m)². Null until both values look real.
  static double? bmiFrom(Object? height, Object? weight) {
    final h = parseDecimal(height?.toString());
    final w = parseDecimal(weight?.toString());
    if (h == null || w == null) return null;
    if (h < 0.5 || h > 2.5 || w < 10 || w > 300) return null;
    return double.parse((w / (h * h)).toStringAsFixed(1));
  }

  /// Keeps only the answers of the questions that are shown, and turns the
  /// height and weight into numbers.
  static Answers finalize(Answers a) {
    final out = <String, dynamic>{};
    for (final s in kSections) {
      for (final q in visible(s, a)) {
        final v = a[q.id];
        if (v == null) continue;
        out[q.id] = v is String ? v.trim() : v;
      }
    }
    final h = parseDecimal(out['height']?.toString());
    final w = parseDecimal(out['weight']?.toString());
    if (h != null) out['height'] = h;
    if (w != null) out['weight'] = w;
    return out;
  }

  /// The answer as text, or null when there is nothing to show.
  static String? format(Q q, dynamic v) {
    if (v == null) return null;
    switch (q.type) {
      case QType.date:
        final d = DateTime.tryParse('$v');
        return d == null ? null : formatDate(d);
      case QType.multi:
        if (v is! List) return null;
        final list = v.map((e) => '$e').toList();
        return list.isEmpty ? null : list.join(', ');
      case QType.slider:
        return '$v / 10';
      default:
        final s = '$v'.trim();
        if (s.isEmpty) return null;
        return switch (q.id) {
          'height' => '$s m',
          'weight' => '$s kg',
          'age' => '$s years',
          'bmi' => '$s kg/m²',
          _ => s,
        };
    }
  }

  /// Section title and (question, answer) rows, for the referral and the PDF.
  static List<(String, List<(String, String)>)> summarize(Answers a) {
    final result = <(String, List<(String, String)>)>[];
    for (final s in kSections) {
      final rows = <(String, String)>[];
      for (final q in visible(s, a)) {
        final text = format(q, a[q.id]);
        if (text != null) rows.add((q.label, text));
      }
      if (rows.isNotEmpty) result.add((s.title, rows));
    }
    return result;
  }
}
