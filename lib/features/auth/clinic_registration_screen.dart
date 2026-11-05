import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../core/password_rules.dart';
import '../../core/theme.dart';
import '../../core/validators.dart';
import '../../core/widgets.dart';
import '../../services/api_client.dart';
import '../../services/auth_service.dart';

/// Website: a clinic asks to join BckSnap. The developer approves it.
class ClinicRegistrationScreen extends StatefulWidget {
  const ClinicRegistrationScreen({super.key});

  @override
  State<ClinicRegistrationScreen> createState() =>
      _ClinicRegistrationScreenState();
}

class _ClinicRegistrationScreenState extends State<ClinicRegistrationScreen> {
  final _formKey = GlobalKey<FormState>();
  final _clinicName = TextEditingController();
  final _address = TextEditingController();
  final _phone = TextEditingController();
  final _clinicEmail = TextEditingController();
  final _services = TextEditingController();
  final _license = TextEditingController();
  final _description = TextEditingController();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();

  bool _physical = true;
  bool _online = false;
  bool _hidePassword = true;
  bool _confirmed = false;
  bool _loading = false;
  bool _done = false;
  String? _error;
  String _submittedEmail = '';

  @override
  void dispose() {
    _clinicName.dispose();
    _address.dispose();
    _phone.dispose();
    _clinicEmail.dispose();
    _services.dispose();
    _license.dispose();
    _description.dispose();
    _name.dispose();
    _email.dispose();
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  List<String> get _serviceList => _services.text
      .split(',')
      .map((s) => s.trim())
      .where((s) => s.isNotEmpty)
      .toList();

  String? _required(String? v, String label, {int min = 2, int max = 100}) {
    final s = (v ?? '').trim();
    if (s.isEmpty) return 'Please enter the $label';
    if (s.length < min) return 'That $label is too short';
    if (s.length > max) return 'That $label is too long (max $max characters)';
    return null;
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (!_physical && !_online) {
      setState(() => _error = 'Choose at least one visit type.');
      return;
    }
    if (!_confirmed) {
      setState(
        () => _error = 'Please confirm that the information is correct.',
      );
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await AuthService().registerClinic(
        applicantName: _name.text,
        email: _email.text,
        password: _password.text,
        clinicName: _clinicName.text,
        address: _address.text,
        phone: Validators.normalizePhone(_phone.text.trim()),
        clinicEmail: _clinicEmail.text,
        services: _serviceList,
        supportsPhysical: _physical,
        supportsOnline: _online,
        description: _description.text,
        licenseNumber: _license.text,
      );
      if (!mounted) return;
      setState(() {
        _submittedEmail = _email.text.trim();
        _done = true;
      });
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Something went wrong. Please try again.');
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Widget _heading(String text) => Padding(
    padding: const EdgeInsets.only(top: 8, bottom: 12),
    child: Text(
      text,
      style: const TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w700,
        color: AppColors.primary,
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Register your clinic'),
        leading: BackButton(onPressed: () => context.go('/login')),
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: _done ? _buildDone() : _buildForm(),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDone() {
    return Column(
      children: [
        const SizedBox(height: 40),
        const Icon(
          Icons.check_circle_outline,
          size: 88,
          color: AppColors.normal,
        ),
        const SizedBox(height: 16),
        const Text(
          'Registration submitted',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        Text(
          'The BckSnap developer will review your clinic. Once it is approved '
          'you can log in with $_submittedEmail.',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 24),
        FilledButton(
          onPressed: () => context.go('/login'),
          child: const Text('BACK TO LOGIN'),
        ),
      ],
    );
  }

  Widget _buildForm() {
    return Form(
      key: _formKey,
      autovalidateMode: AutovalidateMode.onUserInteraction,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Tell us about your clinic and create the administrator login. '
            'The BckSnap developer reviews every registration. You can log in '
            'once it is approved.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          _heading('Clinic information'),
          LabeledField(
            label: 'Clinic name',
            controller: _clinicName,
            textCapitalization: TextCapitalization.words,
            inputFormatters: [LengthLimitingTextInputFormatter(100)],
            validator: (v) => _required(v, 'clinic name'),
          ),
          const SizedBox(height: 16),
          LabeledField(
            label: 'Address',
            controller: _address,
            textCapitalization: TextCapitalization.words,
            inputFormatters: [LengthLimitingTextInputFormatter(200)],
            validator: (v) => _required(v, 'address', min: 5, max: 200),
          ),
          const SizedBox(height: 16),
          LabeledField(
            label: 'Clinic phone number',
            controller: _phone,
            keyboardType: TextInputType.phone,
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[0-9+\-() ]')),
              LengthLimitingTextInputFormatter(25),
            ],
            validator: (v) => Validators.phone(v, required: true),
          ),
          const SizedBox(height: 16),
          LabeledField(
            label: 'Clinic email',
            hint: 'clinic@example.com',
            controller: _clinicEmail,
            keyboardType: TextInputType.emailAddress,
            inputFormatters: [
              FilteringTextInputFormatter.deny(RegExp(r'\s')),
              LengthLimitingTextInputFormatter(254),
            ],
            validator: Validators.email,
          ),
          const SizedBox(height: 16),
          LabeledField(
            label: 'Services',
            hint: 'Scoliosis screening, Physical therapy',
            helperText: 'Separate each service with a comma.',
            controller: _services,
            textCapitalization: TextCapitalization.sentences,
            inputFormatters: [LengthLimitingTextInputFormatter(300)],
            validator: (v) {
              final list = (v ?? '')
                  .split(',')
                  .where((s) => s.trim().isNotEmpty)
                  .toList();
              return list.isEmpty ? 'Enter at least one service' : null;
            },
          ),
          const SizedBox(height: 8),
          CheckboxListTile(
            value: _physical,
            onChanged: (v) => setState(() => _physical = v ?? false),
            title: const Text('In-person visits'),
            controlAffinity: ListTileControlAffinity.leading,
            contentPadding: EdgeInsets.zero,
          ),
          CheckboxListTile(
            value: _online,
            onChanged: (v) => setState(() => _online = v ?? false),
            title: const Text('Online consultations'),
            controlAffinity: ListTileControlAffinity.leading,
            contentPadding: EdgeInsets.zero,
          ),
          const SizedBox(height: 8),
          LabeledField(
            label: 'Business permit or license number (optional)',
            controller: _license,
            inputFormatters: [LengthLimitingTextInputFormatter(60)],
          ),
          const SizedBox(height: 16),
          LabeledField(
            label: 'About the clinic (optional)',
            controller: _description,
            inputFormatters: [LengthLimitingTextInputFormatter(300)],
          ),
          _heading('Administrator login'),
          LabeledField(
            label: 'Your full name',
            hint: 'Juan Dela Cruz',
            controller: _name,
            textCapitalization: TextCapitalization.words,
            inputFormatters: [LengthLimitingTextInputFormatter(60)],
            validator: (v) => Validators.name(v, label: 'full name'),
          ),
          const SizedBox(height: 16),
          LabeledField(
            label: 'Login email',
            hint: 'you@example.com',
            controller: _email,
            keyboardType: TextInputType.emailAddress,
            autofillHints: const [AutofillHints.email],
            inputFormatters: [
              FilteringTextInputFormatter.deny(RegExp(r'\s')),
              LengthLimitingTextInputFormatter(254),
            ],
            validator: Validators.email,
          ),
          const SizedBox(height: 16),
          LabeledField(
            label: 'Password',
            hint: '••••••••••',
            controller: _password,
            obscureText: _hidePassword,
            autofillHints: const [AutofillHints.newPassword],
            onChanged: (_) => setState(() {}),
            inputFormatters: [LengthLimitingTextInputFormatter(64)],
            suffixIcon: IconButton(
              icon: Icon(
                _hidePassword ? Icons.visibility_off : Icons.visibility,
              ),
              color: AppColors.hint,
              onPressed: () => setState(() => _hidePassword = !_hidePassword),
            ),
            validator: Validators.password,
          ),
          PasswordRules(password: _password.text),
          const SizedBox(height: 16),
          LabeledField(
            label: 'Confirm password',
            hint: '••••••••••',
            controller: _confirm,
            obscureText: _hidePassword,
            validator: (v) => Validators.confirmPassword(v, _password.text),
          ),
          const SizedBox(height: 8),
          CheckboxListTile(
            value: _confirmed,
            onChanged: (v) => setState(() => _confirmed = v ?? false),
            title: const Text(
              'I confirm that the information above is correct and that I '
              'am authorized to register this clinic.',
              style: TextStyle(fontSize: 13),
            ),
            controlAffinity: ListTileControlAffinity.leading,
            contentPadding: EdgeInsets.zero,
          ),
          if (_error != null) ...[const SizedBox(height: 8), ErrorBox(_error!)],
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _loading ? null : _submit,
            child: _loading
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Text('SUBMIT REGISTRATION'),
          ),
          const SizedBox(height: 12),
          LinkRow(
            text: 'Already registered?',
            linkText: 'Log In',
            onTap: () => context.go('/login'),
          ),
        ],
      ),
    );
  }
}
