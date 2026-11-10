/// Holds the screening choices between screens, so they can be saved together.
class ScreeningDraft {
  /// Who is being screened: true = the account holder.
  static bool forSelf = true;

  /// The other person's information (only when [forSelf] is false).
  static Map<String, dynamic>? subject;

  /// The patient questionnaire answers (see questionnaire_data.dart).
  static Map<String, dynamic>? questionnaire;

  static String? get subjectLabel {
    final s = subject;
    if (s == null) return null;
    final name = [
      s['firstName'],
      s['middleName'],
      s['lastName'],
    ].where((e) => e != null && e.toString().trim().isNotEmpty).join(' ');
    return '$name (age ${s['age']}, ${s['sex']}) · ${s['relationship']}';
  }

  static void clear() {
    forSelf = true;
    subject = null;
    questionnaire = null;
  }
}
