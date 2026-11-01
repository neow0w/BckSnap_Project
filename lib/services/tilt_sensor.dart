import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:sensors_plus/sensors_plus.dart';

/// Settings for the tilt measurement. Tune the numbers here.
class TiltRules {
  // How the phone lies on the back:
  // true  = LONG edge ACROSS the spine (landscape). The reading is the
  //         see-saw tilt about the short edge, like a scoliometer.
  // false = LONG edge ALONG the spine (portrait).
  static const bool longEdgeAcrossSpine = true;

  // About 50 sensor readings per second.
  static const Duration samplingPeriod = SensorInterval.gameInterval;

  // How much the gyroscope is trusted at each step (0..1).
  static const double gyroWeight = 0.98;

  // Accelerometer readings are ignored while the phone is being shaken:
  // the total acceleration must stay close to gravity.
  static const double gravity = 9.81;
  static const double gravityTolerance = 1.5;

  // A reading averages the angle over this long...
  static const Duration captureWindow = Duration(milliseconds: 1000);

  // ...and is rejected if the phone moved more than this (degrees).
  static const double maxRange = 1.0;

  // The "Steady" indicator needs less movement than this (degrees).
  static const double steadyRange = 0.6;

  // Fewer samples than this means the sensor is not delivering data.
  static const int minSamples = 10;
}

class TiltReading {
  final double angle; // degrees, after the zero offset (signed)
  final double range; // how much the phone moved during the reading
  final int samples;
  const TiltReading(this.angle, this.range, this.samples);
}

class _Sample {
  final int us; // time in microseconds
  final double angle; // fused angle before the zero offset
  const _Sample(this.us, this.angle);
}

/// Measures the tilt of the phone from the accelerometer and the gyroscope.
class TiltSensor {
  StreamSubscription<AccelerometerEvent>? _accSub;
  StreamSubscription<GyroscopeEvent>? _gyroSub;

  /// The live angle in degrees, zeroed. Updated about 20 times per second.
  final ValueNotifier<double> angle = ValueNotifier<double>(0);

  double _accAngle = 0;
  double _angle = 0;
  double _zeroOffset = 0;
  bool _hasAcc = false;
  bool _hasGyro = false;
  int _lastGyroUs = 0;
  int _lastPublishUs = 0;
  final List<_Sample> _history = [];

  // Test mode (no sensor, e.g. in a browser): the angle comes from a slider.
  bool testMode = false;
  double _simulated = 0;

  bool get hasAccelerometer => _hasAcc;
  bool get hasGyroscope => _hasGyro;

  void start() {
    try {
      _accSub = accelerometerEventStream(
        samplingPeriod: TiltRules.samplingPeriod,
      ).listen(_onAcc, onError: (_) {});
    } catch (_) {}
    try {
      _gyroSub = gyroscopeEventStream(samplingPeriod: TiltRules.samplingPeriod)
          .listen(_onGyro, onError: (_) {});
    } catch (_) {}
  }

  void dispose() {
    _accSub?.cancel();
    _gyroSub?.cancel();
    angle.dispose();
  }

  // The angle that gravity gives: 0 when the phone lies flat, screen up.
  void _onAcc(AccelerometerEvent e) {
    final magnitude = math.sqrt(e.x * e.x + e.y * e.y + e.z * e.z);
    if ((magnitude - TiltRules.gravity).abs() > TiltRules.gravityTolerance) {
      return; // the phone is being shaken: do not trust this reading
    }
    _accAngle =
        (TiltRules.longEdgeAcrossSpine
            ? math.atan2(e.y, e.z)
            : math.atan2(e.x, e.z)) *
        180 /
        math.pi;

    if (!_hasAcc) {
      _hasAcc = true;
      _angle = _accAngle;
    }
    if (!_hasGyro) {
      // No gyroscope: smooth the accelerometer on its own.
      _angle = _angle * 0.8 + _accAngle * 0.2;
      _publish();
    }
  }

  // The gyroscope gives smooth changes; the accelerometer slowly corrects
  // its drift.
  void _onGyro(GyroscopeEvent e) {
    final now = DateTime.now().microsecondsSinceEpoch;
    final first = _lastGyroUs == 0;
    final dt = (now - _lastGyroUs) / 1e6;
    _lastGyroUs = now;
    _hasGyro = true;
    if (first || dt <= 0 || dt > 0.5 || !_hasAcc) return;

    final rate = (TiltRules.longEdgeAcrossSpine ? e.x : -e.y) * 180 / math.pi;
    _angle =
        TiltRules.gyroWeight * (_angle + rate * dt) +
        (1 - TiltRules.gyroWeight) * _accAngle;
    _publish();
  }

  void _publish() {
    final now = DateTime.now().microsecondsSinceEpoch;
    _history.add(_Sample(now, _angle));
    final cutoff = now - 3000000; // keep 3 seconds
    while (_history.isNotEmpty && _history.first.us < cutoff) {
      _history.removeAt(0);
    }
    if (now - _lastPublishUs >= 50000) {
      _lastPublishUs = now;
      if (!testMode) angle.value = _angle - _zeroOffset;
    }
  }

  /// Makes the current position the zero (phone flat on a level surface).
  void setZero() {
    if (testMode) {
      _simulated = 0;
      angle.value = 0;
      return;
    }
    final cutoff = DateTime.now().microsecondsSinceEpoch - 1000000;
    final recent = _history.where((s) => s.us >= cutoff).toList();
    _zeroOffset = recent.isEmpty
        ? _angle
        : recent.map((s) => s.angle).reduce((a, b) => a + b) / recent.length;
    angle.value = _angle - _zeroOffset;
  }

  void setSimulated(double value) {
    _simulated = value;
    angle.value = value;
  }

  /// True when the angle changed very little during the last second.
  bool get isSteady {
    if (testMode) return true;
    final cutoff = DateTime.now().microsecondsSinceEpoch - 1000000;
    final recent = _history.where((s) => s.us >= cutoff).toList();
    if (recent.length < TiltRules.minSamples) return false;
    var lo = recent.first.angle;
    var hi = lo;
    for (final s in recent) {
      lo = math.min(lo, s.angle);
      hi = math.max(hi, s.angle);
    }
    return hi - lo <= TiltRules.steadyRange;
  }

  /// Movement (highest minus lowest angle, degrees) over the last [window].
  /// Null when the sensor has not delivered enough data yet.
  double? recentRange([Duration window = const Duration(seconds: 1)]) {
    if (testMode) return 0;
    final cutoff =
        DateTime.now().microsecondsSinceEpoch - window.inMicroseconds;
    final recent = _history.where((s) => s.us >= cutoff).toList();
    if (recent.length < TiltRules.minSamples) return null;
    var lo = recent.first.angle;
    var hi = lo;
    for (final s in recent) {
      lo = math.min(lo, s.angle);
      hi = math.max(hi, s.angle);
    }
    return hi - lo;
  }

  /// Forgets the zero, so the angle shows the raw tilt again.
  void clearZero() {
    _zeroOffset = 0;
    angle.value = _angle;
  }

  /// Takes a reading: the average angle over [TiltRules.captureWindow].
  /// Returns null when the sensor delivered no data.
  Future<TiltReading?> capture() async {
    if (testMode) return TiltReading(_simulated, 0, 1);

    final startUs = DateTime.now().microsecondsSinceEpoch;
    await Future.delayed(TiltRules.captureWindow);

    final samples = _history.where((s) => s.us >= startUs).toList();
    if (samples.length < TiltRules.minSamples) return null;

    var sum = 0.0;
    var lo = samples.first.angle;
    var hi = lo;
    for (final s in samples) {
      sum += s.angle;
      lo = math.min(lo, s.angle);
      hi = math.max(hi, s.angle);
    }
    return TiltReading(
      sum / samples.length - _zeroOffset,
      hi - lo,
      samples.length,
    );
  }
}
