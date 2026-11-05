import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../../services/api_client.dart';
import '../../services/auth_service.dart';

/// Shown after sign-up (and after login) until the patient confirms their
/// email by opening the link Firebase sent.
class VerifyEmailScreen extends StatefulWidget {
  const VerifyEmailScreen({super.key});

  @override
  State<VerifyEmailScreen> createState() => _VerifyEmailScreenState();
}

class _VerifyEmailScreenState extends State<VerifyEmailScreen> {
  static const int _cooldownSeconds = 60;

  final _auth = AuthService();
  Timer? _poll;
  Timer? _cooldownTimer;
  int _cooldown = 0;
  bool _checking = false;
  bool _sending = false;
  String? _error;
  String? _info;

  @override
  void initState() {
    super.initState();
    // Check quietly, so the screen moves on by itself after the link is opened.
    _poll = Timer.periodic(
      const Duration(seconds: 5),
      (_) => _check(silent: true),
    );
  }

  @override
  void dispose() {
    _poll?.cancel();
    _cooldownTimer?.cancel();
    super.dispose();
  }

  Future<void> _check({bool silent = false}) async {
    if (_checking) return;
    _checking = true;
    if (!silent) {
      setState(() {
        _error = null;
        _info = null;
      });
    }
    try {
      final ok = await _auth.refreshEmailVerified();
      if (!mounted) return;
      if (ok) {
        _poll?.cancel();
        context.go('/home');
        return;
      }
      if (!silent) {
        setState(
          () => _info =
              'Your email is not confirmed yet. Open the link in the email, '
              'then tap this button again.',
        );
      }
    } on ApiException catch (e) {
      if (mounted && !silent) setState(() => _error = e.message);
    } catch (_) {
      if (mounted && !silent) {
        setState(() => _error = 'Something went wrong. Please try again.');
      }
    } finally {
      _checking = false;
      if (mounted && !silent) setState(() {});
    }
  }

  void _startCooldown() {
    _cooldownTimer?.cancel();
    setState(() => _cooldown = _cooldownSeconds);
    _cooldownTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      setState(() => _cooldown--);
      if (_cooldown <= 0) t.cancel();
    });
  }

  Future<void> _resend() async {
    setState(() {
      _sending = true;
      _error = null;
      _info = null;
    });
    try {
      await _auth.sendVerificationEmail();
      if (!mounted) return;
      setState(
        () => _info = 'A new link was sent. Check your inbox and spam folder.',
      );
      _startCooldown();
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Something went wrong. Please try again.');
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _useAnotherAccount() async {
    _poll?.cancel();
    await _auth.logout();
    if (mounted) context.go('/login');
  }

  @override
  Widget build(BuildContext context) {
    final email = _auth.currentUser?.email ?? 'your email';
    return Scaffold(
      appBar: AppBar(
        title: const Text('Verify Email'),
        automaticallyImplyLeading: false,
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
                  Expanded(
                    child: SingleChildScrollView(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const SizedBox(height: 40),
                          const Icon(
                            Icons.mark_email_unread_outlined,
                            size: 88,
                            color: AppColors.primary,
                          ),
                          const SizedBox(height: 16),
                          const Text(
                            'Check Your Email',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                              color: AppColors.primary,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'We sent a confirmation link to $email.\n'
                            'Open the link, then come back and tap the button '
                            'below. Check your spam folder if you do not see it.',
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
                                onPressed: (_sending || _cooldown > 0)
                                    ? null
                                    : _resend,
                                style: TextButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 4,
                                  ),
                                  minimumSize: const Size(0, 32),
                                  tapTargetSize:
                                      MaterialTapTargetSize.shrinkWrap,
                                ),
                                child: Text(
                                  _cooldown > 0
                                      ? 'Resend (${_cooldown}s)'
                                      : 'Resend',
                                ),
                              ),
                            ],
                          ),
                          if (_info != null) ...[
                            const SizedBox(height: 12),
                            Text(
                              _info!,
                              textAlign: TextAlign.center,
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ],
                          if (_error != null) ...[
                            const SizedBox(height: 12),
                            ErrorBox(_error!),
                          ],
                        ],
                      ),
                    ),
                  ),
                  FilledButton(
                    onPressed: _checking ? null : () => _check(),
                    child: _checking
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Text("I'VE CONFIRMED MY EMAIL"),
                  ),
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: _useAnotherAccount,
                    child: const Text('Wrong email? Log out'),
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
