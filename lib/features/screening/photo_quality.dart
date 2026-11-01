import '../../services/pose_burst.dart';
import '../../services/pose_detector.dart';
import 'guide_checker.dart';

/// How strict the photo quality check is. Tune the numbers here.
class QualityRules {
  // How many of the latest analysed frames are judged (about 1 second).
  static const int windowFrames = 6;

  // Fewer frames than this is not enough to judge.
  static const int minFrames = 2;

  // Average landmark score needed for the shoulders and for the hips.
  static const double goodScore = 0.6;

  // Share of frames in which the person must have been detected.
  static const double minFoundRatio = 0.8;

  // Share of frames in which the patient must have been inside the guidelines.
  static const double minGuidelineRatio = 0.6;

  // A guideline problem is reported when it affected at least this share of frames.
  static const double problemShare = 0.5;
}

class PhotoQuality {
  final bool good;
  final double averageScore; // 0..1 over shoulders and hips
  final int frames; // how many frames were judged
  final List<String> problems; // reasons shown to the user
  final AveragedPose? burst; // the averaged capture burst, if there was one

  const PhotoQuality({
    required this.good,
    required this.averageScore,
    required this.frames,
    required this.problems,
    this.burst,
  });

  /// Adds the result of the capture burst: the patient must have been found
  /// in enough frames and must have held still.
  PhotoQuality withBurst(AveragedPose? avg) {
    final extra = <String>[];
    if (avg == null || avg.frames < BurstRules.minFrames) {
      extra.add('The patient was not detected during the capture.');
    } else if (avg.spread > BurstRules.maxSpread) {
      extra.add('The patient moved during the capture. Hold still.');
    }
    return PhotoQuality(
      good: problems.isEmpty && extra.isEmpty,
      averageScore: averageScore,
      frames: frames,
      problems: [...problems, ...extra],
      burst: avg,
    );
  }

  /// Judges the recent detection results and the live guideline checks.
  static PhotoQuality assess(
    List<PoseFrame> frames,
    List<GuideStatus> statuses,
  ) {
    if (frames.length < QualityRules.minFrames) {
      return const PhotoQuality(
        good: false,
        averageScore: 0,
        frames: 0,
        problems: [
          'Not enough pose data yet. Wait a moment before taking the photo.',
        ],
      );
    }

    // Average score of some landmarks over all frames.
    // A frame where nobody was found counts as 0.
    double average(List<int> ids) {
      var sum = 0.0;
      var n = 0;
      for (final f in frames) {
        for (final i in ids) {
          sum += f.point(i)?.score ?? 0;
          n++;
        }
      }
      return n == 0 ? 0 : sum / n;
    }

    final shoulders = average([
      PoseIndex.leftShoulder,
      PoseIndex.rightShoulder,
    ]);
    final hips = average([PoseIndex.leftHip, PoseIndex.rightHip]);
    final foundRatio = frames.where((f) => f.found).length / frames.length;

    String pct(double v) => '${(v * 100).round()}%';

    final problems = <String>[];

    // 1. Were the body points clear?
    if (foundRatio < QualityRules.minFoundRatio) {
      problems.add('The person was not detected steadily.');
    }
    if (shoulders < QualityRules.goodScore) {
      problems.add(
        'Shoulders are not clear (${pct(shoulders)}). Check the lighting.',
      );
    }
    if (hips < QualityRules.goodScore) {
      problems.add(
        'Hips are not clear (${pct(hips)}). Make sure they are fully in view.',
      );
    }

    // 2. Was the patient inside the guidelines?
    // "Still" is ignored, because pressing the shutter moves the phone.
    bool positionOk(GuideStatus s) =>
        s.items.where((i) => i.label != 'Still').every((i) => i.ok);

    if (statuses.isNotEmpty) {
      final okShare = statuses.where(positionOk).length / statuses.length;
      if (okShare < QualityRules.minGuidelineRatio) {
        final counts = <String, int>{};
        for (final s in statuses) {
          for (final i in s.items) {
            final p = i.problem;
            if (p != null) counts[p] = (counts[p] ?? 0) + 1;
          }
        }
        final common =
            counts.entries
                .where(
                  (e) => e.value / statuses.length >= QualityRules.problemShare,
                )
                .toList()
              ..sort((a, b) => b.value.compareTo(a.value));
        for (final e in common) {
          problems.add('${e.key}.');
        }
        if (common.isEmpty && problems.isEmpty) {
          problems.add('The patient was not inside the photo guidelines.');
        }
      }
    }

    return PhotoQuality(
      good: problems.isEmpty,
      averageScore: (shoulders + hips) / 2,
      frames: frames.length,
      problems: problems,
    );
  }
}
