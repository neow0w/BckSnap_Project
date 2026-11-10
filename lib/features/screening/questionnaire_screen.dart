import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../core/format.dart';
import '../../core/theme.dart';
import '../../core/validators.dart';
import '../../core/widgets.dart';
import '../../services/auth_service.dart';
import '../../services/screening_draft.dart';
import 'questionnaire_data.dart';

/// Asked before the scoliometer. The answers are saved with the screening
/// and shown on the referral.
class QuestionnaireScreen extends StatefulWidget {
  const QuestionnaireScreen({super.key});

  @override
  State<QuestionnaireScreen> createState() => _QuestionnaireScreenState();
}

class _QuestionnaireScreenState extends State<QuestionnaireScreen> {
  final _formKey = GlobalKey<FormState>();
  final _scroll = ScrollController();
  final Answers _a = {};
  final Map<String, TextEditingController> _ctrl = {};
  final Set<String> _missing = {}; // choice questions left unanswered
  int _step = 0;

  @override
  void initState() {
    super.initState();
    _prefill();
  }

  @override
  void dispose() {
    _scroll.dispose();
    for (final c in _ctrl.values) {
      c.dispose();
    }
    super.dispose();
  }

  // ---- data -----------------------------------------------------------------

  void _put(String id, String? v) {
    if (v != null && v.trim().isNotEmpty) _a[id] = v.trim();
  }

  void _prefill() {
    final saved = ScreeningDraft.questionnaire;
    if (saved != null) {
      _a.addAll(saved);
    } else if (ScreeningDraft.forSelf) {
      final u = AuthService().currentUser;
      if (u != null) {
        _put('full_name', u.name);
        _put('email', u.email);
        _put('address', u.address);
        _put('contact', u.phone);
        if (u.dateOfBirth != null) _a['birthday'] = isoDate(u.dateOfBirth!);
      }
    } else {
      final s = ScreeningDraft.subject;
      if (s != null) {
        _put(
          'full_name',
          [
            s['firstName'],
            s['middleName'],
            s['lastName'],
          ].where((e) => e != null && e.toString().trim().isNotEmpty).join(' '),
        );
        final sex = s['sex'];
        if (sex == 'Male' || sex == 'Female') _a['sex'] = sex;
      }
    }
    _recompute();
  }

  /// Age and BMI follow the birthday, height and weight automatically.
  void _recompute() {
    final age = QuestionnaireData.ageFrom(_a['birthday'] as String?);
    if (age == null) {
      _a.remove('age');
    } else {
      _a['age'] = age;
    }
    final bmi = QuestionnaireData.bmiFrom(_a['height'], _a['weight']);
    if (bmi == null) {
      _a.remove('bmi');
    } else {
      _a['bmi'] = bmi;
    }
  }

  TextEditingController _c(Q q) =>
      _ctrl.putIfAbsent(q.id, () => TextEditingController(text: _textOf(q)));

  String _textOf(Q q) {
    final v = _a[q.id];
    if (v == null) return '';
    if (q.type == QType.date) {
      final d = DateTime.tryParse('$v');
      return d == null ? '' : formatDate(d);
    }
    return '$v';
  }

  // ---- navigation -----------------------------------------------------------

  bool _validateSection() {
    final visible = QuestionnaireData.visible(kSections[_step], _a);
    _missing.clear();
    for (final q in visible) {
      if (q.type == QType.single && _a[q.id] == null) _missing.add(q.id);
      if (q.type == QType.multi && ((_a[q.id] as List?)?.isEmpty ?? true)) {
        _missing.add(q.id);
      }
      if (q.type == QType.slider && _a[q.id] == null) _a[q.id] = 0;
    }
    final fieldsOk = _formKey.currentState?.validate() ?? true;
    setState(() {});
    return fieldsOk && _missing.isEmpty;
  }

  void _toTop() => WidgetsBinding.instance.addPostFrameCallback((_) {
    if (_scroll.hasClients) _scroll.jumpTo(0);
  });

  void _next() {
    if (!_validateSection()) {
      _toTop();
      return;
    }
    ScreeningDraft.questionnaire = QuestionnaireData.finalize(_a);
    if (_step < kSections.length - 1) {
      setState(() => _step++);
      _toTop();
    } else {
      context.go('/screening/steps/scoliometer');
    }
  }

  void _prev() {
    if (_step == 0) {
      context.go(
        ScreeningDraft.forSelf ? '/screening/for' : '/screening/person',
      );
    } else {
      setState(() => _step--);
      _toTop();
    }
  }

  // ---- validators -----------------------------------------------------------

  String? _validateText(Q q, String? v) {
    final s = (v ?? '').trim();
    switch (q.kind) {
      case 'name':
        return Validators.name(s, label: q.label.toLowerCase());
      case 'email':
        return Validators.email(s);
      case 'phone':
        return Validators.phone(s, required: true);
      case 'address':
        if (s.length < 5) return 'Please enter the full address';
        if (s.length > 200) return 'Address is too long (max 200 characters)';
        return null;
      case 'height':
        final h = QuestionnaireData.parseDecimal(s);
        return (h == null || h < 0.5 || h > 2.5)
            ? 'Enter the height in metres, for example 1.60'
            : null;
      case 'weight':
        final w = QuestionnaireData.parseDecimal(s);
        return (w == null || w < 10 || w > 300)
            ? 'Enter the weight in kilograms, for example 55'
            : null;
      default:
        if (s.isEmpty) return 'Please answer this question';
        if (s.length > 100) {
          return 'That answer is too long (max 100 characters)';
        }
        return null;
    }
  }

  String? _validateDate(Q q) {
    final d = DateTime.tryParse('${_a[q.id] ?? ''}');
    if (q.kind == 'dob') return Validators.dateOfBirth(d);
    return d == null ? 'Please select the date' : null;
  }

  Future<void> _pickDate(Q q) async {
    final now = DateTime.now();
    final current = DateTime.tryParse('${_a[q.id] ?? ''}');
    final picked = await showDatePicker(
      context: context,
      initialDate:
          current ??
          (q.kind == 'dob' ? DateTime(now.year - 15, now.month, now.day) : now),
      firstDate: DateTime(1900),
      lastDate: now,
    );
    if (picked == null) return;
    setState(() {
      _a[q.id] = isoDate(picked);
      _c(q).text = formatDate(picked);
      _recompute();
    });
  }

  // ---- question widgets -----------------------------------------------------

  Widget _question(Q q) {
    switch (q.type) {
      case QType.text:
        return _textField(q);
      case QType.date:
        return _dateField(q);
      case QType.single:
        return _singleChoice(q);
      case QType.multi:
        return _multiChoice(q);
      case QType.slider:
        return _slider(q);
      case QType.computed:
        return _computed(q);
    }
  }

  Widget _textField(Q q) {
    final phone = q.kind == 'phone';
    final email = q.kind == 'email';
    final decimal = q.kind == 'height' || q.kind == 'weight';
    return LabeledField(
      key: ValueKey(q.id),
      label: q.label,
      hint: q.hint,
      controller: _c(q),
      keyboardType: phone
          ? TextInputType.phone
          : decimal
          ? const TextInputType.numberWithOptions(decimal: true)
          : email
          ? TextInputType.emailAddress
          : TextInputType.text,
      textCapitalization: email
          ? TextCapitalization.none
          : (q.kind == 'name' || q.kind == 'address')
          ? TextCapitalization.words
          : TextCapitalization.sentences,
      inputFormatters: [
        if (phone) FilteringTextInputFormatter.allow(RegExp(r'[0-9+\-() ]')),
        if (decimal) FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
        if (email) FilteringTextInputFormatter.deny(RegExp(r'\s')),
        LengthLimitingTextInputFormatter(
          q.kind == 'address'
              ? 200
              : phone
              ? 25
              : email
              ? 254
              : 100,
        ),
      ],
      validator: (v) => _validateText(q, v),
      onChanged: (v) {
        _a[q.id] = v;
        if (decimal) setState(_recompute);
      },
    );
  }

  Widget _dateField(Q q) => LabeledField(
    key: ValueKey(q.id),
    label: q.label,
    hint: 'Select date',
    controller: _c(q),
    readOnly: true,
    suffixIcon: const Icon(
      Icons.calendar_today_outlined,
      size: 20,
      color: AppColors.hint,
    ),
    onTap: () => _pickDate(q),
    validator: (_) => _validateDate(q),
  );

  Widget _choiceBlock(Q q, Widget child) {
    return Column(
      key: ValueKey(q.id),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          q.label,
          style: Theme.of(context).textTheme.bodySmall
              ?.copyWith(fontWeight: FontWeight.w500),
        ),
        const SizedBox(height: 8),
        child,
        if (_missing.contains(q.id))
          const Padding(
            padding: EdgeInsets.only(top: 6),
            child: Text(
              'Please choose an answer',
              style: TextStyle(fontSize: 12, color: AppColors.high),
            ),
          ),
      ],
    );
  }

  Widget _singleChoice(Q q) {
    return _choiceBlock(
      q,
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final o in q.options)
            ChoiceChip(
              label: Text(o),
              selected: _a[q.id] == o,
              selectedColor: AppColors.tonal,
              labelStyle: TextStyle(
                fontSize: 13,
                fontWeight: _a[q.id] == o ? FontWeight.w600 : FontWeight.w400,
                color: _a[q.id] == o ? AppColors.primary : AppColors.text,
              ),
              onSelected: (_) => setState(() {
                _a[q.id] = o;
                _missing.remove(q.id);
              }),
            ),
        ],
      ),
    );
  }

  Widget _multiChoice(Q q) {
    final selected = [for (final e in (_a[q.id] as List? ?? const [])) '$e'];
    return _choiceBlock(
      q,
      Column(
        children: [
          for (final o in q.options)
            CheckboxListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              title: Text(o, style: const TextStyle(fontSize: 14)),
              value: selected.contains(o),
              onChanged: (on) => setState(() {
                final next = [...selected];
                if (on == true) {
                  if (q.exclusive.contains(o)) {
                    next.clear();
                  } else {
                    next.removeWhere(q.exclusive.contains);
                  }
                  next.add(o);
                } else {
                  next.remove(o);
                }
                _a[q.id] = next;
                _missing.remove(q.id);
              }),
            ),
        ],
      ),
    );
  }

  Widget _slider(Q q) {
    final v = (_a[q.id] as num?)?.toDouble() ?? 0;
    return _choiceBlock(
      q,
      Column(
        children: [
          Slider(
            value: v,
            min: 0,
            max: 10,
            divisions: 10,
            label: '${v.round()}',
            onChanged: (x) => setState(() => _a[q.id] = x.round()),
          ),
          Text(
            '${v.round()} / 10',
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: AppColors.primary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _computed(Q q) {
    final text = QuestionnaireData.format(q, _a[q.id]) ?? '—';
    return Container(
      key: ValueKey(q.id),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: AppColors.fieldFill,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              '${q.label} (calculated)',
              style: Theme.of(context).textTheme.bodySmall
                  ?.copyWith(fontWeight: FontWeight.w500),
            ),
          ),
          Text(text, style: const TextStyle(fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }

  // ---- screen ---------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final section = kSections[_step];
    final total = kSections.length;
    final last = _step == total - 1;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _prev();
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Patient Questionnaire'),
          leading: BackButton(onPressed: _prev),
        ),
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 4, 24, 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Section ${_step + 1} of $total',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                        const SizedBox(height: 6),
                        LinearProgressIndicator(
                          value: (_step + 1) / total,
                          minHeight: 6,
                          borderRadius: BorderRadius.circular(3),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: SingleChildScrollView(
                      controller: _scroll,
                      padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
                      child: Form(
                        key: _formKey,
                        autovalidateMode: AutovalidateMode.onUserInteraction,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              section.title,
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w700,
                                color: AppColors.primary,
                              ),
                            ),
                            if (_step == 0) ...[
                              const SizedBox(height: 6),
                              Text(
                                'The answers are kept confidential, used only '
                                'for screening, and shown on the referral.',
                                style: Theme.of(context).textTheme.bodySmall
                                    ?.copyWith(
                                      fontSize: 11,
                                      color: AppColors.hint,
                                    ),
                              ),
                            ],
                            const SizedBox(height: 16),
                            for (final q in QuestionnaireData.visible(
                              section,
                              _a,
                            ))
                              Padding(
                                padding: const EdgeInsets.only(bottom: 16),
                                child: _question(q),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        FilledButton(
                          onPressed: _next,
                          child: Text(last ? 'SAVE AND CONTINUE' : 'NEXT'),
                        ),
                        if (_step > 0) ...[
                          const SizedBox(height: 8),
                          OutlinedButton(
                            onPressed: _prev,
                            child: const Text('BACK'),
                          ),
                        ],
                      ],
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
