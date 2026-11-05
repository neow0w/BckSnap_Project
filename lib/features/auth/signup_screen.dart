import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../core/auth_destination.dart';
import '../../core/format.dart';
import '../../core/password_rules.dart';
import '../../core/validators.dart';
import '../../services/api_client.dart';
import '../../services/auth_service.dart';
import 'privacy_notice.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';

/// Steps:  adults (18+)      details -> consent
///         ages 9 to 17      details -> guardian consent -> minor assent
enum _Step { details, consent, assent }

class SignUpScreen extends StatefulWidget {
  /// Where to go after sign-up (see authDestination). Null = /home.
  final String? next;

  /// true = a Google/Facebook account that still needs a date of birth
  /// and consent (no password step).
  final bool social;
  const SignUpScreen({super.key, this.next, this.social = false});

  @override
  State<SignUpScreen> createState() => _SignUpScreenState();
}

class _SignUpScreenState extends State<SignUpScreen> {
  static const _relationships = ['Mother', 'Father', 'Legal guardian', 'Other'];

  final _detailsKey = GlobalKey<FormState>();
  final _guardianKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _dobCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();
  final _guardianNameCtrl = TextEditingController();
  final _guardianContactCtrl = TextEditingController();
  final _auth = AuthService();

  _Step _step = _Step.details;
  DateTime? _dob;
  String? _relationship;
  bool _hidePassword = true;
  bool _loading = false;
  String? _error;

  // Consent boxes. They are cleared if the age group changes.
  bool? _consentForMinor;
  bool _privacyRead = false;
  bool _healthConsent = false;
  bool _isGuardian = false;
  bool _assent = false;

  int? get _age =>
      _dob == null ? null : Validators.ageOn(_dob!, DateTime.now());
  bool get _isMinor => _age != null && _age! < Validators.adultAge;
  int get _totalSteps => _isMinor ? 3 : 2;

  @override
  void initState() {
    super.initState();
    if (widget.social) {
      _nameCtrl.text = _auth.pendingSocialName ?? '';
      _emailCtrl.text = _auth.pendingSocialEmail ?? '';
    }
  }

  Future<void> _cancelSocial() async {
    await _auth.cancelSocialSignUp();
    if (mounted) context.go('/login');
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    _dobCtrl.dispose();
    _passwordCtrl.dispose();
    _confirmCtrl.dispose();
    _guardianNameCtrl.dispose();
    _guardianContactCtrl.dispose();
    super.dispose();
  }

  // ---- navigation between steps -------------------------------------------

  void _back() {
    if (_loading) return;
    switch (_step) {
      case _Step.details:
        if (widget.social) {
          _cancelSocial();
        } else {
          context.go('/');
        }
      case _Step.consent:
        setState(() {
          _step = _Step.details;
          _error = null;
        });
      case _Step.assent:
        setState(() {
          _step = _Step.consent;
          _error = null;
        });
    }
  }

  Future<void> _pickDob() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _dob ?? DateTime(now.year - 15, now.month, now.day),
      firstDate: DateTime(now.year - 110),
      lastDate: now,
      helpText: 'Date of birth',
      initialDatePickerMode: DatePickerMode.year,
    );
    if (picked == null) return;
    setState(() {
      _dob = picked;
      _dobCtrl.text = formatDate(picked);
    });
  }

  void _continueFromDetails() {
    if (!_detailsKey.currentState!.validate()) return;
    final minor = _isMinor;
    setState(() {
      _error = null;
      if (_consentForMinor != minor) {
        _privacyRead = false;
        _healthConsent = false;
        _isGuardian = false;
        _assent = false;
      }
      _consentForMinor = minor;
      _step = _Step.consent;
    });
  }

  void _continueFromGuardian() {
    if (!_guardianKey.currentState!.validate()) return;
    if (!(_isGuardian && _privacyRead && _healthConsent)) {
      setState(() => _error = 'Please tick all three boxes to continue.');
      return;
    }
    setState(() {
      _error = null;
      _step = _Step.assent;
    });
  }

  // ---- create the account ---------------------------------------------------

  Future<void> _submit() async {
    final minor = _isMinor;
    final consentOk = minor
        ? (_isGuardian && _privacyRead && _healthConsent && _assent)
        : (_privacyRead && _healthConsent);
    if (!consentOk || _dob == null) {
      setState(() => _error = 'Consent is required to create an account.');
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      if (widget.social) {
        await _auth.completeSocialSignUp(
          name: _nameCtrl.text.trim(),
          dateOfBirth: _dob!,
          privacyVersion: PrivacyNotice.version,
          guardianName: minor ? _guardianNameCtrl.text.trim() : null,
          guardianRelationship: minor ? _relationship : null,
          guardianContact: minor ? _guardianContactCtrl.text.trim() : null,
          guardianConsent: minor,
          minorAssent: minor,
        );
      } else {
        await _auth.signUp(
          name: _nameCtrl.text.trim(),
          email: _emailCtrl.text.trim(),
          password: _passwordCtrl.text,
          dateOfBirth: _dob!,
          privacyVersion: PrivacyNotice.version,
          guardianName: minor ? _guardianNameCtrl.text.trim() : null,
          guardianRelationship: minor ? _relationship : null,
          guardianContact: minor ? _guardianContactCtrl.text.trim() : null,
          guardianConsent: minor,
          minorAssent: minor,
        );
      }
      if (!mounted) return;
      // Unconfirmed emails are sent to /verify-email by the router.
      context.go(authDestination(widget.next));
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        // Email already used / invalid data: let them fix it on step 1.
        if (e.statusCode == 409 || e.statusCode == 422) {
          _step = _Step.details;
        }
      });
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Something went wrong. Please try again.');
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  // ---- UI -------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.social ? 'Complete Profile' : 'Sign Up'),
        leading: BackButton(onPressed: _back),
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: switch (_step) {
                _Step.details => _buildDetails(),
                _Step.consent =>
                  _isMinor ? _buildGuardianConsent() : _buildAdultConsent(),
                _Step.assent => _buildAssent(),
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _header(int index, String title) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(
        'Step ${index + 1} of $_totalSteps',
        style: const TextStyle(fontSize: 12),
      ),
      const SizedBox(height: 4),
      LinearProgressIndicator(value: (index + 1) / _totalSteps),
      const SizedBox(height: 16),
      Text(
        title,
        textAlign: TextAlign.center,
        style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
      ),
      const SizedBox(height: 16),
    ],
  );

  Widget _errorBox() {
    if (_error == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.red.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(_error!, style: const TextStyle(color: Colors.red)),
      ),
    );
  }

  Widget _check(bool value, String text, ValueChanged<bool> onChanged) =>
      CheckboxListTile(
        value: value,
        onChanged: (v) => setState(() => onChanged(v ?? false)),
        title: Text(text, style: const TextStyle(fontSize: 14)),
        controlAffinity: ListTileControlAffinity.leading,
        contentPadding: EdgeInsets.zero,
      );

  Widget _noticeSummary() => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Privacy notice (summary)',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          for (final line in PrivacyNotice.summary)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text('• $line', style: const TextStyle(fontSize: 14)),
            ),
        ],
      ),
    ),
  );

  Widget _fullNoticeLink() => Align(
    alignment: Alignment.centerLeft,
    child: TextButton.icon(
      onPressed: () => context.push('/privacy'),
      icon: const Icon(Icons.article_outlined),
      label: const Text('Read the full Privacy Notice'),
    ),
  );

  String? _dobHelper() {
    final a = _age;
    if (a == null) {
      return 'Ages 9 to 17 need a parent or guardian\'s consent.';
    }
    if (a < Validators.minAge) return null; // the error text explains it
    if (a < Validators.adultAge) {
      return 'Age $a: a parent or guardian will give consent in the next step.';
    }
    return 'Age $a';
  }

  // ---- step 1: details ------------------------------------------------------

  Widget _buildDetails() {
    final social = widget.social;
    return Form(
      key: _detailsKey,
      autovalidateMode: AutovalidateMode.onUserInteraction,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (social) ...[
            Text(
              'Almost done! Confirm your name and enter your date of birth '
              'to finish creating your account.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 16),
          ],
          LabeledField(
            label: 'Full Name',
            hint: 'Juan Dela Cruz',
            controller: _nameCtrl,
            textCapitalization: TextCapitalization.words,
            textInputAction: TextInputAction.next,
            autofillHints: const [AutofillHints.name],
            inputFormatters: [LengthLimitingTextInputFormatter(60)],
            validator: (v) => Validators.name(v, label: 'full name'),
          ),
          const SizedBox(height: 16),
          if (!social) ...[
            LabeledField(
              label: 'Password',
              hint: '••••••••••',
              controller: _passwordCtrl,
              obscureText: _hidePassword,
              textInputAction: TextInputAction.next,
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
            PasswordRules(password: _passwordCtrl.text),
            const SizedBox(height: 16),
          ],
          LabeledField(
            label: 'Email',
            hint: 'example@example.com',
            controller: _emailCtrl,
            readOnly: social,
            keyboardType: TextInputType.emailAddress,
            textInputAction: TextInputAction.next,
            autofillHints: const [AutofillHints.email],
            inputFormatters: [
              FilteringTextInputFormatter.deny(RegExp(r'\s')),
              LengthLimitingTextInputFormatter(254),
            ],
            validator: Validators.email,
          ),
          const SizedBox(height: 16),
          LabeledField(
            label: 'Date of Birth',
            hint: 'DD / MM / YYYY',
            controller: _dobCtrl,
            readOnly: true,
            onTap: _pickDob,
            suffixIcon: const Icon(Icons.calendar_today, color: AppColors.hint),
            helperText: _dobHelper(),
            errorText: _dob != null ? Validators.dateOfBirth(_dob) : null,
            validator: (_) => Validators.dateOfBirth(_dob),
          ),
          _errorBox(),
          const SizedBox(height: 20),
          Wrap(
            alignment: WrapAlignment.center,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                'In the next step you will review our ',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              TextButton(
                onPressed: () => context.push('/privacy'),
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  minimumSize: const Size(0, 32),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: const Text('Privacy Notice'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          FilledButton(
            onPressed: _continueFromDetails,
            child: const Text('CONTINUE'),
          ),
          if (!social) ...[
            const SizedBox(height: 20),
            const OrDivider(),
            const SizedBox(height: 12),
            const SocialSignInRow(),
            const SizedBox(height: 20),
            LinkRow(
              text: 'Already have an account?',
              linkText: 'Log In',
              onTap: () => context.go('/login'),
            ),
          ],
        ],
      ),
    );
  }
  // ---- step 2 (adults): privacy notice and consent --------------------------

  Widget _buildAdultConsent() {
    final ok = _privacyRead && _healthConsent;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _header(1, 'Privacy notice and consent'),
        _noticeSummary(),
        _fullNoticeLink(),
        const SizedBox(height: 8),
        _check(
          _privacyRead,
          'I have read and understood the Privacy Notice.',
          (v) => _privacyRead = v,
        ),
        _check(
          _healthConsent,
          'I consent to the collection and use of my health-related '
          'information (back photo and screening results) for screening and '
          'clinic referral, as described in the Privacy Notice.',
          (v) => _healthConsent = v,
        ),
        _errorBox(),
        const SizedBox(height: 16),
        FilledButton(
          onPressed: (ok && !_loading) ? _submit : null,
          child: _loading
              ? const SizedBox(
                  height: 20,
                  width: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Create account'),
        ),
      ],
    );
  }

  // ---- step 2 (ages 9-17): guardian consent --------------------------------

  Widget _buildGuardianConsent() {
    final child = _nameCtrl.text.trim().isEmpty
        ? 'the child'
        : _nameCtrl.text.trim();
    return Form(
      key: _guardianKey,
      autovalidateMode: AutovalidateMode.onUserInteraction,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _header(1, 'Parent or guardian consent'),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.secondaryContainer,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              '$child is under 18. A parent or legal guardian must read '
              'this page and give consent. Please hand the device to them.',
            ),
          ),
          const SizedBox(height: 16),
          _noticeSummary(),
          _fullNoticeLink(),
          const SizedBox(height: 8),
          TextFormField(
            controller: _guardianNameCtrl,
            textCapitalization: TextCapitalization.words,
            inputFormatters: [LengthLimitingTextInputFormatter(60)],
            decoration: const InputDecoration(
              labelText: 'Guardian full name',
              border: OutlineInputBorder(),
            ),
            validator: (v) => Validators.name(v, label: 'full name'),
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<String>(
            initialValue: _relationship,
            isExpanded: true,
            decoration: const InputDecoration(
              labelText: 'Relationship to the child',
              border: OutlineInputBorder(),
            ),
            items: [
              for (final r in _relationships)
                DropdownMenuItem(value: r, child: Text(r)),
            ],
            onChanged: (v) => setState(() => _relationship = v),
            validator: (v) => v == null ? 'Please choose a relationship' : null,
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _guardianContactCtrl,
            keyboardType: TextInputType.emailAddress,
            inputFormatters: [LengthLimitingTextInputFormatter(254)],
            decoration: const InputDecoration(
              labelText: 'Guardian email or phone number',
              border: OutlineInputBorder(),
            ),
            validator: (v) {
              final e = Validators.emailOrPhone(v);
              if (e != null) return e;
              if ((v ?? '').trim().toLowerCase() ==
                  _emailCtrl.text.trim().toLowerCase()) {
                return 'Use the guardian\'s own contact, not the account email';
              }
              return null;
            },
          ),
          const SizedBox(height: 8),
          _check(
            _isGuardian,
            'I am the parent or legal guardian of $child.',
            (v) => _isGuardian = v,
          ),
          _check(
            _privacyRead,
            'I have read and understood the Privacy Notice.',
            (v) => _privacyRead = v,
          ),
          _check(
            _healthConsent,
            'I consent to the collection and use of $child\'s '
            'health-related information (back photo and screening results) '
            'for screening and clinic referral, as described in the Privacy '
            'Notice.',
            (v) => _healthConsent = v,
          ),
          _errorBox(),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _continueFromGuardian,
            child: const Text('Continue'),
          ),
        ],
      ),
    );
  }

  // ---- step 3 (ages 9-17): the young person's own agreement -----------------

  Widget _buildAssent() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _header(2, 'Your agreement'),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: const [
                Text(
                  'Hi there!',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                SizedBox(height: 8),
                Text('This app helps check your back for scoliosis.'),
                SizedBox(height: 8),
                Text(
                  '• You take a photo of your back and measure a bend '
                  'with your phone.',
                ),
                SizedBox(height: 4),
                Text(
                  '• We keep your photo and results safe. Only you, your '
                  'parent or guardian, and the clinic staff who look after '
                  'you can see them.',
                ),
                SizedBox(height: 4),
                Text(
                  '• If the result looks unusual, you can ask a clinic to '
                  'take a look.',
                ),
                SizedBox(height: 4),
                Text('• This is a check, not a diagnosis. A doctor decides.'),
                SizedBox(height: 4),
                Text('• You can say no, ask questions, or stop at any time.'),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        _check(
          _assent,
          'I understand, and I agree to take part.',
          (v) => _assent = v,
        ),
        _errorBox(),
        const SizedBox(height: 16),
        FilledButton(
          onPressed: (_assent && !_loading) ? _submit : null,
          child: _loading
              ? const SizedBox(
                  height: 20,
                  width: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Create account'),
        ),
        const SizedBox(height: 12),
        OutlinedButton(
          onPressed: _loading
              ? null
              : (widget.social ? _cancelSocial : () => context.go('/')),
          child: const Text("I don't want to join"),
        ),
      ],
    );
  }
}
