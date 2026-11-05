import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../services/api_client.dart';
import '../services/auth_service.dart';
import 'home_for.dart';
import 'theme.dart';

/// The BckSnap logo. Shows a simple stand-in until assets/images/logo.png exists.
class BrandLogo extends StatelessWidget {
  final double size;
  final bool white;
  const BrandLogo({super.key, this.size = 160, this.white = false});

  @override
  Widget build(BuildContext context) {
    final color = white ? Colors.white : AppColors.primary;
    return Image.asset(
      white ? 'assets/images/logo_white.png' : 'assets/images/logo.png',
      width: size,
      fit: BoxFit.contain,
      errorBuilder: (context, error, stack) => SizedBox(
        width: size,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.camera, size: size * 0.55, color: color),
            SizedBox(height: size * 0.04),
            Text(
              'BckSnap',
              style: TextStyle(
                fontSize: size * 0.18,
                fontWeight: FontWeight.w800,
                fontStyle: FontStyle.italic,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A text field with its label ABOVE it, like in the mockups.
class LabeledField extends StatelessWidget {
  final String label;
  final TextEditingController? controller;
  final String? hint;
  final bool obscureText;
  final bool readOnly;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final TextCapitalization textCapitalization;
  final String? Function(String?)? validator;
  final Widget? suffixIcon;
  final String? helperText;
  final String? errorText;
  final List<TextInputFormatter>? inputFormatters;
  final Iterable<String>? autofillHints;
  final VoidCallback? onTap;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;

  const LabeledField({
    super.key,
    required this.label,
    this.controller,
    this.hint,
    this.obscureText = false,
    this.readOnly = false,
    this.keyboardType,
    this.textInputAction,
    this.textCapitalization = TextCapitalization.none,
    this.validator,
    this.suffixIcon,
    this.helperText,
    this.errorText,
    this.inputFormatters,
    this.autofillHints,
    this.onTap,
    this.onChanged,
    this.onSubmitted,
  });

  @override
  Widget build(BuildContext context) {
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
        TextFormField(
          controller: controller,
          obscureText: obscureText,
          readOnly: readOnly,
          keyboardType: keyboardType,
          textInputAction: textInputAction,
          textCapitalization: textCapitalization,
          validator: validator,
          inputFormatters: inputFormatters,
          autofillHints: autofillHints,
          onTap: onTap,
          onChanged: onChanged,
          onFieldSubmitted: onSubmitted,
          decoration: InputDecoration(
            hintText: hint,
            suffixIcon: suffixIcon,
            helperText: helperText,
            helperMaxLines: 2,
            errorText: errorText,
          ),
        ),
      ],
    );
  }
}

/// A password field with the show/hide eye.
class PasswordField extends StatefulWidget {
  final String label;
  final TextEditingController? controller;
  final String? hint;
  final String? Function(String?)? validator;
  final TextInputAction? textInputAction;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;

  const PasswordField({
    super.key,
    this.label = 'Password',
    this.controller,
    this.hint = '••••••••••',
    this.validator,
    this.textInputAction,
    this.onChanged,
    this.onSubmitted,
  });

  @override
  State<PasswordField> createState() => _PasswordFieldState();
}

class _PasswordFieldState extends State<PasswordField> {
  bool _hidden = true;

  @override
  Widget build(BuildContext context) {
    return LabeledField(
      label: widget.label,
      controller: widget.controller,
      hint: widget.hint,
      obscureText: _hidden,
      validator: widget.validator,
      textInputAction: widget.textInputAction,
      onChanged: widget.onChanged,
      onSubmitted: widget.onSubmitted,
      autofillHints: const [AutofillHints.password],
      suffixIcon: IconButton(
        icon: Icon(_hidden ? Icons.visibility_off : Icons.visibility),
        color: AppColors.hint,
        onPressed: () => setState(() => _hidden = !_hidden),
      ),
    );
  }
}

/// A red message box for errors.
class ErrorBox extends StatelessWidget {
  final String message;
  const ErrorBox(this.message, {super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.high.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(message, style: const TextStyle(color: AppColors.high)),
    );
  }
}

/// "or continue with"
class OrDivider extends StatelessWidget {
  final String text;
  const OrDivider({super.key, this.text = 'or continue with'});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(text, style: Theme.of(context).textTheme.bodySmall),
    );
  }
}

/// The Google and Facebook buttons.
class SocialSignInRow extends StatefulWidget {
  const SocialSignInRow({super.key});

  @override
  State<SocialSignInRow> createState() => _SocialSignInRowState();
}

class _SocialSignInRowState extends State<SocialSignInRow> {
  bool _busy = false;

  void _snack(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _run(Future<SocialResult> Function() signIn) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final result = await signIn();
      if (!mounted) return;
      switch (result) {
        case SocialResult.cancelled:
          break;
        case SocialResult.needsProfile:
          context.go('/complete-profile');
        case SocialResult.signedIn:
          context.go(homeFor(AuthService().currentUser?.role ?? 'user'));
      }
    } on ApiException catch (e) {
      _snack(e.message);
    } catch (_) {
      _snack('Sign-in failed. Please try again.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _circle(String letter, Color color, VoidCallback onTap) {
    return InkWell(
      customBorder: const CircleBorder(),
      onTap: onTap,
      child: CircleAvatar(
        radius: 20,
        backgroundColor: color,
        child: Text(
          letter,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w700,
            fontSize: 16,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_busy) {
      return const Center(
        child: SizedBox(
          height: 40,
          width: 40,
          child: CircularProgressIndicator(strokeWidth: 3),
        ),
      );
    }
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _circle(
          'G',
          AppColors.google,
          () => _run(AuthService().signInWithGoogle),
        ),
        const SizedBox(width: 16),
        _circle(
          'f',
          AppColors.facebook,
          () => _run(AuthService().signInWithFacebook),
        ),
      ],
    );
  }
}

/// "Don't have an account? Sign Up"
class LinkRow extends StatelessWidget {
  final String text;
  final String linkText;
  final VoidCallback onTap;
  const LinkRow({
    super.key,
    required this.text,
    required this.linkText,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(text, style: Theme.of(context).textTheme.bodySmall),
        TextButton(
          onPressed: onTap,
          style: TextButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            minimumSize: const Size(0, 32),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          child: Text(linkText),
        ),
      ],
    );
  }
}
