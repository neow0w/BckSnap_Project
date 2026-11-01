import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme.dart';
import '../../core/validators.dart';
import '../../core/widgets.dart';
import '../../services/api_client.dart';
import '../../services/auth_service.dart';

/// Reset password: find the account, then "Check your email".
/// Firebase emails a reset LINK, so there is no code step.
class ResetPasswordScreen extends StatefulWidget {
  const ResetPasswordScreen({super.key});

  @override
  State<ResetPasswordScreen> createState() => _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends State<ResetPasswordScreen> {
  static const int _cooldownSeconds = 60;

  final _formKey = GlobalKey<FormState>();
  final _emailCtrl = TextEditingController();
  final _auth = AuthService();

  bool _loading = false;
  bool _sent = false;
  String? _error;
  String _sentTo = '';

  Timer? _timer;
  int _cooldown = 0; // seconds until "Resend" is allowed again

  @override
  void dispose() {
    _timer?.cancel();
    _emailCtrl.dispose();
    super.dispose();
  }

  void _startCooldown() {
    _timer?.cancel();
    setState(() => _cooldown = _cooldownSeconds);
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      setState(() => _cooldown--);
      if (_cooldown <= 0) t.cancel();
    });
  }

  Future<void> _send({required String email}) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await _auth.resetPassword(email);
      if (!mounted) return;
      setState(() {
        _sent = true;
        _sentTo = email;
      });
      _startCooldown();
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

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    _send(email: _emailCtrl.text.trim());
  }

  /// "example@gmail.com" -> "ex***le@gmail.com"
  String _mask(String email) {
    final at = email.indexOf('@');
    if (at <= 0) return email;
    final local = email.substring(0, at);
    final domain = email.substring(at);
    if (local.length <= 4) return '${local[0]}***$domain';
    return '${local.substring(0, 2)}***'
        '${local.substring(local.length - 2)}$domain';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_sent ? 'Email Sent' : 'Email Verification'),
        leading: BackButton(
          onPressed: () {
            if (_sent) {
              setState(() {
                _sent = false;
                _error = null;
              });
            } else {
              context.go('/login');
            }
          },
        ),
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
              child: _sent ? _buildSent() : _buildForm(),
            ),
          ),
        ),
      ),
    );
  }

  Widget _heading(String text) => Text(
    text,
    textAlign: TextAlign.center,
    style: const TextStyle(
      fontSize: 18,
      fontWeight: FontWeight.w700,
      color: AppColors.primary,
    ),
  );

  Widget _buildForm() {
    return Form(
      key: _formKey,
      autovalidateMode: AutovalidateMode.onUserInteraction,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 40),
                  const Icon(Icons.search, size: 88, color: AppColors.primary),
                  const SizedBox(height: 16),
                  _heading('Find Your Account'),
                  const SizedBox(height: 8),
                  Text(
                    'Please enter your registered email address',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 24),
                  TextFormField(
                    controller: _emailCtrl,
                    keyboardType: TextInputType.emailAddress,
                    autofillHints: const [AutofillHints.email],
                    inputFormatters: [
                      FilteringTextInputFormatter.deny(RegExp(r'\s')),
                      LengthLimitingTextInputFormatter(254),
                    ],
                    decoration: const InputDecoration(
                      hintText: 'example@example.com',
                    ),
                    validator: Validators.email,
                    onFieldSubmitted: (_) => _loading ? null : _submit(),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'You may receive notifications from us for security '
                    'and login purposes',
                    style: Theme.of(context).textTheme.bodySmall
                        ?.copyWith(fontSize: 11, color: AppColors.hint),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 16),
                    ErrorBox(_error!),
                  ],
                ],
              ),
            ),
          ),
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
                : const Text('CONTINUE'),
          ),
        ],
      ),
    );
  }

  Widget _buildSent() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 40),
                const Icon(
                  Icons.mark_email_read_outlined,
                  size: 88,
                  color: AppColors.primary,
                ),
                const SizedBox(height: 16),
                _heading('Check Your Email'),
                const SizedBox(height: 8),
                Text(
                  'We sent a password reset link to ${_mask(_sentTo)}.\n'
                  'Open the link, choose a new password, then log in.',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      "You didn't receive the email?",
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    TextButton(
                      onPressed: (_loading || _cooldown > 0)
                          ? null
                          : () => _send(email: _sentTo),
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        minimumSize: const Size(0, 32),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      child: Text(
                        _cooldown > 0 ? 'Resend (${_cooldown}s)' : 'Resend',
                      ),
                    ),
                  ],
                ),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  ErrorBox(_error!),
                ],
              ],
            ),
          ),
        ),
        FilledButton(
          onPressed: () => context.go('/login'),
          child: const Text('BACK TO LOGIN'),
        ),
      ],
    );
  }
}
