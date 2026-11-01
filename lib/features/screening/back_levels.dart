/// The back levels that are measured. Edit this list to match your
/// adviser's protocol.
class BackLevel {
  final String id;
  final String name;
  final String where; // where to place the phone
  const BackLevel(this.id, this.name, this.where);
}

class BackLevels {
  static const List<BackLevel> all = [
    BackLevel(
      'upper_thoracic',
      'Upper thoracic',
      'Between the shoulder blades, near the top of the shoulder blades.',
    ),
    BackLevel(
      'mid_thoracic',
      'Mid-thoracic',
      'Over the middle of the shoulder blades, at the most prominent part of the back.',
    ),
    BackLevel(
      'thoracolumbar',
      'Thoracolumbar',
      'At the bottom of the rib cage, where the mid back meets the lower back.',
    ),
    BackLevel('lumbar', 'Lumbar', 'Over the lower back, at about belt level.'),
  ];
}

class LevelReading {
  final BackLevel level;
  final double angle; // signed, degrees
  final double range; // how much the phone moved during the reading
  const LevelReading(this.level, this.angle, this.range);

  /// The angle of trunk rotation (ATR) is the size of the tilt.
  double get atr => angle.abs();
}
