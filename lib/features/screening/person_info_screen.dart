import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme.dart';
import '../../core/validators.dart';
import '../../core/widgets.dart';
import '../../services/screening_draft.dart';

/// The information needed when screening someone else.
class PersonInfoScreen extends StatefulWidget {
  const PersonInfoScreen({super.key});

  @override
  State<PersonInfoScreen> createState() => _PersonInfoScreenState();
}

class _PersonInfoScreenState extends State<PersonInfoScreen> {
  static const _sexes = ['Male', 'Female', 'Other'];
  static const _relationships = [
    'Child',
    'Parent',
    'Spouse or partner',
    'Sibling',
    'Other relative',
    'Friend',
    'Other',
  ];

  final _formKey = GlobalKey<FormState>();
  final _first = TextEditingController();
  final _middle = TextEditingController();
  final _last = TextEditingController();
  final _age = TextEditingController();

  bool _noMiddle = false;
  String? _sex;
  String? _relationship;
  bool _consent = false;
  String? _error;

  @override
  void dispose() {
    _first.dispose();
    _middle.dispose();
    _last.dispose();
    _age.dispose();
    super.dispose();
  }

  int? get _ageValue => int.tryParse(_age.text.trim());
  bool get _isMinor => _ageValue != null && _ageValue! < Validators.adultAge;

  String? _ageError(String? v) {
    final n = int.tryParse((v ?? '').trim());
    if (n == null) return 'Please enter the age';
    if (n < Validators.minAge) {
      return 'This app is for ages ${Validators.minAge} and above';
    }
    if (n > 110) return 'Please check the age';
    return null;
  }

  void _save() {
    if (!_formKey.currentState!.validate()) return;
    if (!_consent) {
      setState(
        () => _error =
            'Please confirm you have permission to screen this person.',
      );
      return;
    }
    ScreeningDraft.forSelf = false;
    ScreeningDraft.subject = {
      'firstName': _first.text.trim(),
      'middleName': _noMiddle ? null : _middle.text.trim(),
      'lastName': _last.text.trim(),
      'age': _ageValue,
      'sex': _sex,
      'relationship': _relationship,
      'permissionConfirmed': true,
    };
    context.go('/screening/questionnaire');
  }

  Widget _dropdown({
    required String label,
    required String? value,
    required List<String> items,
    required ValueChanged<String?> onChanged,
    required String error,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Text(
            label,
            style: Theme.of(context).textTheme.bodySmall
                ?.copyWith(fontWeight: FontWeight.w500),
          ),
        ),
        DropdownButtonFormField<String>(
          initialValue: value,
          isExpanded: true,
          decoration: const InputDecoration(hintText: 'Select'),
          items: [
            for (final i in items) DropdownMenuItem(value: i, child: Text(i)),
          ],
          onChanged: onChanged,
          validator: (v) => v == null ? error : null,
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final small = Theme.of(context).textTheme.bodySmall;
    return Scaffold(
      appBar: AppBar(
        title: const Text("Person's Information"),
        leading: BackButton(onPressed: () => context.go('/screening/for')),
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Form(
                key: _formKey,
                autovalidateMode: AutovalidateMode.onUserInteraction,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      "Please provide the person's basic information so the "
                      'screening result is recorded for the right person.',
                      style: small,
                    ),
                    const SizedBox(height: 16),
                    LabeledField(
                      label: 'First Name',
                      hint: 'First name',
                      controller: _first,
                      textCapitalization: TextCapitalization.words,
                      textInputAction: TextInputAction.next,
                      inputFormatters: [LengthLimitingTextInputFormatter(60)],
                      validator: (v) => Validators.name(v, label: 'first name'),
                    ),
                    const SizedBox(height: 16),
                    LabeledField(
                      label: 'Middle Name',
                      hint: 'Middle name',
                      controller: _middle,
                      readOnly: _noMiddle,
                      textCapitalization: TextCapitalization.words,
                      textInputAction: TextInputAction.next,
                      inputFormatters: [LengthLimitingTextInputFormatter(60)],
                      validator: (v) => _noMiddle
                          ? null
                          : Validators.name(v, label: 'middle name'),
                    ),
                    CheckboxListTile(
                      value: _noMiddle,
                      onChanged: (v) => setState(() {
                        _noMiddle = v ?? false;
                        if (_noMiddle) _middle.clear();
                      }),
                      title: const Text(
                        "This person doesn't have a middle name",
                        style: TextStyle(fontSize: 13),
                      ),
                      controlAffinity: ListTileControlAffinity.leading,
                      contentPadding: EdgeInsets.zero,
                    ),
                    LabeledField(
                      label: 'Last Name',
                      hint: 'Last name',
                      controller: _last,
                      textCapitalization: TextCapitalization.words,
                      textInputAction: TextInputAction.next,
                      inputFormatters: [LengthLimitingTextInputFormatter(60)],
                      validator: (v) => Validators.name(v, label: 'last name'),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: LabeledField(
                            label: 'Age',
                            hint: 'Enter age',
                            controller: _age,
                            keyboardType: TextInputType.number,
                            onChanged: (_) => setState(() {}),
                            inputFormatters: [
                              FilteringTextInputFormatter.digitsOnly,
                              LengthLimitingTextInputFormatter(3),
                            ],
                            validator: _ageError,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _dropdown(
                            label: 'Sex',
                            value: _sex,
                            items: _sexes,
                            onChanged: (v) => setState(() => _sex = v),
                            error: 'Select sex',
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    _dropdown(
                      label: 'Relationship To The Person',
                      value: _relationship,
                      items: _relationships,
                      onChanged: (v) => setState(() => _relationship = v),
                      error: 'Select the relationship',
                    ),
                    const SizedBox(height: 8),
                    CheckboxListTile(
                      value: _consent,
                      onChanged: (v) => setState(() {
                        _consent = v ?? false;
                        _error = null;
                      }),
                      title: Text(
                        _isMinor
                            ? 'This person is under 18. I am their parent or '
                                  'legal guardian, or I have their guardian\'s '
                                  'permission to take and save this screening.'
                            : 'I have this person\'s permission to take and '
                                  'save this screening.',
                        style: const TextStyle(fontSize: 13),
                      ),
                      controlAffinity: ListTileControlAffinity.leading,
                      contentPadding: EdgeInsets.zero,
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 8),
                      ErrorBox(_error!),
                    ],
                    const SizedBox(height: 16),
                    FilledButton(
                      onPressed: _save,
                      child: const Text('SAVE AND CONTINUE'),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'The information is kept confidential and only used for '
                      'screening purposes.',
                      textAlign: TextAlign.center,
                      style: small?.copyWith(
                        fontSize: 11,
                        color: AppColors.hint,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
