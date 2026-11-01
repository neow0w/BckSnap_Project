import 'posture_analysis.dart';

/// The ATR limits for the result. Confirm them with your adviser.
class ResultRules {
  // At or above this: referral recommended.
  static const double referAtr = 7.0;

  // From here up to referAtr: borderline.
  static const double borderlineAtr = 5.0;
}

enum ResultCategory { refer, borderline, noSign }

class LevelResult {
  final String name;
  final double atr;
  const LevelResult(this.name, this.atr);
}

/// Everything the result screen shows.
class ResultData {
  final double highestAtr;
  final String? highestLevel;
  final List<LevelResult> levels;
  final PostureAnalysis? posture; // null = the photo analysis was not used
  final String? subjectLabel; // set when screening someone else

  const ResultData({
    required this.highestAtr,
    this.highestLevel,
    this.levels = const [],
    this.posture,
    this.subjectLabel,
  });

  factory ResultData.fromAtr(double atr) => ResultData(highestAtr: atr);

  Map<String, dynamic> toJson() => {
    'highest_level': highestLevel,
    'levels': [
      for (final l in levels) {'name': l.name, 'atr': l.atr},
    ],
    'posture': posture?.toJson(),
  };

  /// The ATR decides. A noticeable photo tilt can lift "no sign" to
  /// "borderline", but it can never produce "referral" on its own.
  ResultCategory get category {
    if (highestAtr >= ResultRules.referAtr) return ResultCategory.refer;
    if (highestAtr >= ResultRules.borderlineAtr) {
      return ResultCategory.borderline;
    }
    if (posture?.flagged == true) return ResultCategory.borderline;
    return ResultCategory.noSign;
  }

  /// Borderline only because of the photo (the ATR itself was low).
  bool get borderlineFromPhotoOnly =>
      category == ResultCategory.borderline &&
      highestAtr < ResultRules.borderlineAtr;
}
