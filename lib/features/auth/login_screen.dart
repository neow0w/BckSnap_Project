import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/widgets.dart';
import '../../services/api_client.dart';
import '../../services/auth_service.dart';
import '../../core/home_for.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _auth = AuthService();

  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      await _auth.login(
        email: _emailCtrl.text.trim(),
        password: _passwordCtrl.text,
      );

      if (!mounted) return;

      final role = await _auth.getRole();

      if (!mounted) return;

      context.go(homeFor(role));
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

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) context.go('/');
      },
      child: Scaffold(
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const SizedBox(height: 8),
                      const Center(child: BrandLogo(size: 150)),
                      const SizedBox(height: 28),
                      LabeledField(
                        label: 'Email',
                        hint: 'example@example.com',
                        controller: _emailCtrl,
                        keyboardType: TextInputType.emailAddress,
                        textInputAction: TextInputAction.next,
                        autofillHints: const [AutofillHints.email],
                        validator: (v) => (v == null || v.trim().isEmpty)
                            ? 'Please enter your email'
                            : null,
                      ),
                      const SizedBox(height: 16),
                      PasswordField(
                        controller: _passwordCtrl,
                        textInputAction: TextInputAction.done,
                        onSubmitted: (_) => _loading ? null : _submit(),
                        validator: (v) => (v == null || v.isEmpty)
                            ? 'Please enter your password'
                            : null,
                      ),
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton(
                          onPressed: () => context.go('/reset'),
                          style: TextButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 4),
                            minimumSize: const Size(0, 32),
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                          child: const Text('Forgot Password'),
                        ),
                      ),
                      if (_error != null) ...[
                        const SizedBox(height: 8),
                        ErrorBox(_error!),
                      ],
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
                            : const Text('LOG IN'),
                      ),
                      if (!kIsWeb) ...[
                        const SizedBox(height: 24),
                        const OrDivider(),
                        const SizedBox(height: 12),
                        const SocialSignInRow(),
                        const SizedBox(height: 20),
                        LinkRow(
                          text: "Don't have an account?",
                          linkText: 'Sign Up',
                          onTap: () => context.go('/signup'),
                        ),
                      ],
                      if (kIsWeb) ...[
                        const SizedBox(height: 24),
                        LinkRow(
                          text: 'Own a clinic?',
                          linkText: 'Register your clinic',
                          onTap: () => context.go('/register-clinic'),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
