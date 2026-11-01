import '../../models/screening.dart';
import 'screening_result.dart';

/// Settings for the monthly check. Confirm the numbers with your adviser.
class ProgressRules {
  // A new screening is suggested this many days after the last one.
  static const int intervalDays = 30;

  // A change in the highest ATR smaller than this counts as "about the
  // same" (scoliometer readings vary a little from one measurement to the next).
  static const double meaningfulChange = 2.0;
}

enum Trend { first, improved, worse, same }

class ProgressSummary {
  final List<Screening> entries; // newest first
  const ProgressSummary(this.entries);

  bool get isEmpty => entries.isEmpty;
  Screening? get latest => entries.isEmpty ? null : entries.first;
  Screening? get previous => entries.length < 2 ? null : entries[1];

  /// Latest minus previous highest ATR (negative = lower = better).
  double? get change {
    final a = latest;
    final b = previous;
    return (a == null || b == null) ? null : a.angle - b.angle;
  }

  Trend get trend {
    final c = change;
    if (c == null) return Trend.first;
    if (c <= -ProgressRules.meaningfulChange) return Trend.improved;
    if (c >= ProgressRules.meaningfulChange) return Trend.worse;
    return Trend.same;
  }

  DateTime? get nextDue =>
      latest?.createdAt.add(const Duration(days: ProgressRules.intervalDays));

  bool get isDue => nextDue != null && !DateTime.now().isBefore(nextDue!);

  int get daysLeft {
    final d = nextDue?.difference(DateTime.now()).inDays ?? 0;
    return d < 0 ? 0 : d;
  }

  static String levelLabel(double atr) {
    if (atr >= ResultRules.referAtr) return 'Referral range';
    if (atr >= ResultRules.borderlineAtr) return 'Borderline';
    return 'Low';
  }
}
