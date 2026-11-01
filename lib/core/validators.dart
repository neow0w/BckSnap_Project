/// One rule for one password requirement (used by the live checklist too).
class PasswordCheck {
  final String label; // lower-case, reads after "Password must have ..."
  final bool ok;
  const PasswordCheck(this.label, this.ok);
}

/// Shared input rules, so every form checks things the same way.
/// IMPORTANT: the API must repeat these checks. The app can be bypassed.
class Validators {
  static const int minAge = 9; // youngest allowed user
  static const int adultAge = 18; // below this = guardian consent needed
  static const int passwordMin = 8;
  static const int passwordMax = 64;

  static final RegExp _emailRe = RegExp(
    r"^[A-Za-z0-9._%+\-]+@[A-Za-z0-9\-]+(\.[A-Za-z0-9\-]+)*\.[A-Za-z]{2,}$",
  );
  static final RegExp _nameRe = RegExp(
    r"^\p{L}[\p{L}\p{M} .'\-]*$",
    unicode: true,
  );
  static final RegExp _phoneRe = RegExp(r'^\+?\d{7,15}$');
  static final RegExp _codeRe = RegExp(r'^[A-Za-z0-9\-_.]{6,512}$');

  // ---- text fields ----------------------------------------------------

  static String? email(String? v) {
    final s = (v ?? '').trim();
    if (s.isEmpty) return 'Please enter your email';
    if (s.length > 254) return 'That email is too long';
    if (s.contains('..') || !_emailRe.hasMatch(s)) {
      return 'Please enter a valid email address';
    }
    return null;
  }

  static String? name(String? v, {String label = 'name'}) {
    final s = (v ?? '').trim();
    if (s.isEmpty) return 'Please enter your $label';
    if (s.length < 2) return 'That $label is too short';
    if (s.length > 60) return 'That $label is too long (max 60 characters)';
    if (!_nameRe.hasMatch(s)) {
      return 'Use letters, spaces, hyphens and apostrophes only';
    }
    return null;
  }

  /// Removes spaces, dashes and brackets: "+63 912-345 (6789)" -> "+639123456789"
  static String normalizePhone(String v) =>
      v.replaceAll(RegExp(r'[\s\-()]'), '');

  static String? phone(String? v, {bool required = false}) {
    final s = normalizePhone((v ?? '').trim());
    if (s.isEmpty) return required ? 'Please enter a phone number' : null;
    if (!_phoneRe.hasMatch(s)) {
      return 'Enter a valid phone number (7-15 digits, may start with +)';
    }
    return null;
  }

  static String? emailOrPhone(String? v) {
    final s = (v ?? '').trim();
    if (s.isEmpty) return 'Please enter a contact email or phone number';
    if (s.contains('@')) return email(s);
    return phone(s, required: true);
  }

  static String? address(String? v) {
    final s = (v ?? '').trim();
    if (s.length > 200) return 'Address is too long (max 200 characters)';
    return null;
  }

  // ---- password -------------------------------------------------------

  static List<PasswordCheck> passwordChecks(String p) => [
    PasswordCheck('at least $passwordMin characters', p.length >= passwordMin),
    PasswordCheck('an uppercase letter (A-Z)', RegExp(r'[A-Z]').hasMatch(p)),
    PasswordCheck('a lowercase letter (a-z)', RegExp(r'[a-z]').hasMatch(p)),
    PasswordCheck('a number (0-9)', RegExp(r'[0-9]').hasMatch(p)),
  ];

  static String? password(String? v) {
    final p = v ?? '';
    if (p.isEmpty) return 'Please enter a password';
    if (p.length > passwordMax) {
      return 'Password is too long (max $passwordMax characters)';
    }
    for (final c in passwordChecks(p)) {
      if (!c.ok) return 'Password must have ${c.label}';
    }
    return null;
  }

  static String? confirmPassword(String? v, String original) {
    if (v == null || v.isEmpty) return 'Please confirm your password';
    if (v != original) return 'Passwords do not match';
    return null;
  }

  /// The code/token from the password-reset email.
  static String? resetCode(String? v) {
    final s = (v ?? '').trim();
    if (s.isEmpty) return 'Please enter the code from your email';
    if (!_codeRe.hasMatch(s)) {
      return 'That code does not look right. Copy it exactly from the email';
    }
    return null;
  }

  // ---- date of birth / age -------------------------------------------

  static int ageOn(DateTime dob, DateTime today) {
    var age = today.year - dob.year;
    if (today.month < dob.month ||
        (today.month == dob.month && today.day < dob.day)) {
      age--;
    }
    return age;
  }

  static String? dateOfBirth(DateTime? d, {DateTime? now}) {
    final today = now ?? DateTime.now();
    if (d == null) return 'Please select your date of birth';
    if (d.isAfter(today)) return 'Date of birth cannot be in the future';
    final age = ageOn(d, today);
    if (age > 110) return 'Please check the date of birth';
    if (age < minAge) return 'This app is for ages $minAge and above';
    return null;
  }
}
