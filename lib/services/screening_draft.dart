import 'dart:typed_data';

import 'pose_burst.dart';

/// Holds the capture results between screens, so they can be saved together.
class ScreeningDraft {
  static Uint8List? photoBytes;
  static String? photoName;
  static AveragedPose? landmarks; // averaged body points from the capture burst
  static bool photoQualityGood = false; // did the photo pass the quality check?

  /// Who is being screened: true = the account holder.
  static bool forSelf = true;

  /// The other person's information (only when [forSelf] is false).
  static Map<String, dynamic>? subject;

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
    photoBytes = null;
    photoName = null;
    landmarks = null;
    photoQualityGood = false;
    forSelf = true;
    subject = null;
  }
}
