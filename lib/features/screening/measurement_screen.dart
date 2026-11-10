import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../services/screening_draft.dart';
import '../../services/screening_service.dart';
import '../../services/tilt_sensor.dart';
import 'back_levels.dart';
import 'screening_result.dart';

import 'dart:math' as math;

/// Settings for the automatic zero and capture. Tune the numbers here.
class AutoRules {
  // Zero: the phone must lie flat (within this many degrees)...
  static const double flatTolerance = 8.0;
  // ...and stay this still (degrees of movement in the last second)...
  static const double zeroRange = 0.6;
  // ...for this long.
  static const int zeroHoldMs = 1500;

  // Measure: the phone must first be moved (picked up and placed)...
  static const double moveRange = 2.0;
  // ...then stay this still (same limit as a good reading)...
  static const double measureRange = TiltRules.maxRange;
  // ...for this long, before the 1-second reading is taken.
  static const int measureHoldMs = 1200;

  // After a good reading, wait this long before the next level.
  static const int advanceMs = 2500;
  // Each level is read twice in a row. The two readings must agree...
  static const double agreeTolerance = 1.0;
  // ...and a reading above this cannot be a real trunk rotation
  // (the phone is probably not on the back).
  static const double maxPlausible = 40.0;
}

enum _Phase { zero, measure, review }

class MeasurementScreen extends StatefulWidget {
  const MeasurementScreen({super.key});

  @override
  State<MeasurementScreen> createState() => _MeasurementScreenState();
}

class _MeasurementScreenState extends State<MeasurementScreen> {
  final TiltSensor _sensor = TiltSensor();
  final ValueNotifier<double> _progress = ValueNotifier<double>(0);
  Timer? _sensorTimer;
  Timer? _tick;
  Timer? _advanceTimer;

  _Phase _phase = _Phase.zero;
  int _levelIndex = 0;
  bool _fromReview = false; // re-measuring one level from the review screen
  final Map<String, LevelReading> _readings = {};
  LevelReading? _pending; // taken, moving on to the next level soon
  bool _capturing = false;
  bool _armed = false; // the phone was moved since this level started
  int? _steadySince; // when the phone became steady (ms)
  String? _message;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    // The phone lies on the back with its long edge across the spine,
    // so the screen is shown in landscape.
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    _sensor.start();
    // No sensor data after 2 seconds (a computer): test mode with a slider.
    _sensorTimer = Timer(const Duration(seconds: 2), () {
      if (mounted && !_sensor.hasAccelerometer) {
        setState(() => _sensor.testMode = true);
      }
    });
    _tick = Timer.periodic(const Duration(milliseconds: 120), (_) => _onTick());
  }

  @override
  void dispose() {
    _sensorTimer?.cancel();
    _tick?.cancel();
    _advanceTimer?.cancel();
    _progress.dispose();
    _sensor.dispose();
    // Give the other screens their normal rotation back.
    SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    super.dispose();
  }

  // ---- automatic zero and capture --------------------------------------------

  void _resetHold() {
    _steadySince = null;
    if (_progress.value != 0) _progress.value = 0;
  }

  void _onTick() {
    if (!mounted || _capturing || _saving || _pending != null) return;
    if (_phase == _Phase.review) return;

    final range = _sensor.recentRange();
    final now = DateTime.now().millisecondsSinceEpoch;

    if (_phase == _Phase.zero) {
      final flat = _sensor.angle.value.abs() <= AutoRules.flatTolerance;
      final still = range != null && range <= AutoRules.zeroRange;
      if (!(flat && still)) {
        _resetHold();
        return;
      }
      _steadySince ??= now;
      final held = now - _steadySince!;
      _progress.value = (held / AutoRules.zeroHoldMs).clamp(0.0, 1.0);
      if (held >= AutoRules.zeroHoldMs) _setZeroAndStart();
      return;
    }

    // Measuring a level.
    if (range == null) {
      _resetHold();
      return;
    }
    if (!_armed && (_sensor.testMode || range > AutoRules.moveRange)) {
      setState(() => _armed = true);
    }
    if (!_armed || range > AutoRules.measureRange) {
      _resetHold();
      return;
    }
    _steadySince ??= now;
    final held = now - _steadySince!;
    _progress.value = (held / AutoRules.measureHoldMs).clamp(0.0, 1.0);
    if (held >= AutoRules.measureHoldMs) {
      _capture(BackLevels.all[_levelIndex]);
    }
  }

  // ---- logic ----------------------------------------------------------------

  LevelReading? get _highest {
    LevelReading? best;
    for (final r in _readings.values) {
      if (best == null || r.atr > best.atr) best = r;
    }
    return best;
  }

  void _setZeroAndStart() {
    _sensor.setZero();
    _resetHold();
    setState(() {
      _phase = _Phase.measure;
      _levelIndex = 0;
      _fromReview = false;
      _pending = null;
      _armed = false;
      _message = null;
    });
  }

  Future<void> _capture(BackLevel level) async {
    if (_capturing) return;
    _resetHold();
    setState(() {
      _capturing = true;
      _message = null;
    });

    // Two readings in a row (one second each). They must agree.
    final a = await _sensor.capture();
    final b = (a == null || !mounted) ? null : await _sensor.capture();
    if (!mounted) return;

    String? problem;
    LevelReading? good;
    if (a == null || b == null) {
      problem =
          'No motion sensor data. Check that this phone has a '
          'motion sensor and try again.';
    } else {
      final diff = (a.angle - b.angle).abs();
      final angle = (a.angle + b.angle) / 2;
      if (a.range > TiltRules.maxRange || b.range > TiltRules.maxRange) {
        problem =
            'The phone moved during the reading. Hold it steady and it '
            'will try again.';
      } else if (diff > AutoRules.agreeTolerance) {
        problem =
            'The two readings did not agree (${diff.toStringAsFixed(1)}° '
            'apart). Hold it steady and it will try again.';
      } else if (angle.abs() > AutoRules.maxPlausible) {
        problem =
            'That reading is too large to be real. Check that the phone '
            'lies flat on the back, then hold it steady.';
      } else {
        good = LevelReading(
          level,
          angle,
          math.max(math.max(a.range, b.range), diff),
        );
      }
    }

    setState(() {
      _capturing = false;
      _message = problem;
      _pending = good;
    });
    if (good != null) {
      _advanceTimer?.cancel();
      _advanceTimer = Timer(
        const Duration(milliseconds: AutoRules.advanceMs),
        () {
          if (mounted && _pending != null) _keep();
        },
      );
    }
  }

  void _keep() {
    _advanceTimer?.cancel();
    final p = _pending;
    if (p == null) return;
    _readings[p.level.id] = p;
    setState(() {
      _pending = null;
      _message = null;
      _armed = false;
      if (_fromReview || _levelIndex >= BackLevels.all.length - 1) {
        _fromReview = false;
        _phase = _Phase.review;
      } else {
        _levelIndex++;
      }
    });
    _resetHold();
  }

  void _remeasure() {
    _advanceTimer?.cancel();
    _resetHold();
    setState(() {
      _pending = null;
      _message = null;
      _armed = false;
    });
  }

  void _remeasureLevel(int index) {
    _advanceTimer?.cancel();
    _resetHold();
    setState(() {
      _levelIndex = index;
      _fromReview = true;
      _pending = null;
      _armed = false;
      _message = null;
      _phase = _Phase.measure;
    });
  }

  void _measureAgain() {
    _advanceTimer?.cancel();
    _resetHold();
    setState(() {
      _readings.clear();
      _levelIndex = 0;
      _fromReview = false;
      _pending = null;
      _armed = false;
      _message = null;
      _phase = _Phase.measure;
    });
  }

  void _back() {
    _advanceTimer?.cancel();
    _resetHold();
    switch (_phase) {
      case _Phase.zero:
        context.go('/screening/steps/scoliometer');
      case _Phase.measure:
        setState(() {
          _pending = null;
          _message = null;
          _armed = false;
          if (_fromReview) {
            _fromReview = false;
            _phase = _Phase.review;
          } else if (_levelIndex > 0) {
            _levelIndex--;
          } else {
            _phase = _Phase.zero;
            _sensor.clearZero();
          }
        });
      case _Phase.review:
        setState(() {
          _levelIndex = BackLevels.all.length - 1;
          _fromReview = false;
          _armed = false;
          _phase = _Phase.measure;
        });
    }
  }

  // Save the highest ATR, then show the result.
  Future<void> _save() async {
    final highest = _highest;
    if (highest == null) return;
    setState(() => _saving = true);

    // Build the result first: the draft is cleared after saving.
    final result = ResultData(
      highestAtr: highest.atr,
      highestLevel: highest.level.name,
      levels: [
        for (final level in BackLevels.all)
          if (_readings[level.id] != null)
            LevelResult(level.name, _readings[level.id]!.atr),
      ],
      subjectLabel: ScreeningDraft.forSelf ? null : ScreeningDraft.subjectLabel,
    );

    var saved = true;
    try {
      await ScreeningService().saveScreening(
        angle: highest.atr,
        details: {
          ...result.toJson(),
          'questionnaire': ScreeningDraft.questionnaire,
        },
        forSelf: ScreeningDraft.forSelf,
        subject: ScreeningDraft.subject,
      );
      ScreeningDraft.clear();
    } catch (_) {
      saved = false;
    }

    if (!mounted) return;
    setState(() => _saving = false);
    if (!saved) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'The result could not be saved. Check your connection.',
          ),
        ),
      );
    }
    context.go('/screening/result', extra: result);
  }

  // ---- UI -------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final title = switch (_phase) {
      _Phase.zero => 'Set zero',
      _Phase.measure => 'Measure ATR',
      _Phase.review => 'Review readings',
    };
    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 48,
        title: Text(title),
        leading: BackButton(onPressed: _back),
      ),
      body: SafeArea(
        child: Row(
          children: [
            Expanded(flex: 5, child: _buildLeft()),
            const VerticalDivider(width: 1),
            Expanded(
              flex: 6,
              child: switch (_phase) {
                _Phase.zero => _buildZero(),
                _Phase.measure => _buildMeasure(),
                _Phase.review => _buildReview(),
              },
            ),
          ],
        ),
      ),
    );
  }

  /// Left side: the big live reading (or the highest ATR in the review).
  Widget _buildLeft() {
    if (_phase == _Phase.review) return _buildSummary();
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        children: [
          Expanded(child: Center(child: _liveReading())),
          if (_sensor.testMode) _simulatorSlider(),
        ],
      ),
    );
  }

  Widget _liveReading() {
    return ValueListenableBuilder<double>(
      valueListenable: _sensor.angle,
      builder: (context, value, _) {
        final steady = _sensor.isSteady;
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                '${value.abs().toStringAsFixed(1)}°',
                style: const TextStyle(
                  fontSize: 96,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            Text('Angle of trunk rotation  (${value >= 0 ? "+" : "-"})'),
            const SizedBox(height: 8),
            Chip(
              avatar: Icon(
                steady ? Icons.check_circle : Icons.sync,
                size: 18,
                color: steady ? Colors.green : Colors.orange,
              ),
              label: Text(steady ? 'Steady' : 'Moving'),
            ),
          ],
        );
      },
    );
  }

  Widget _simulatorSlider() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text(
          'No motion sensor detected. Test mode: use the slider.',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.orange),
        ),
        ValueListenableBuilder<double>(
          valueListenable: _sensor.angle,
          builder: (context, v, _) => Slider(
            value: v.clamp(-20.0, 20.0).toDouble(),
            min: -20,
            max: 20,
            divisions: 80,
            label: v.toStringAsFixed(1),
            onChanged: _sensor.setSimulated,
          ),
        ),
      ],
    );
  }

  /// Right side layout: scrolling content with the buttons pinned below it.
  Widget _rightPanel({
    required List<Widget> body,
    required List<Widget> actions,
  }) {
    return Column(
      children: [
        Expanded(
          child: ListView(padding: const EdgeInsets.all(12), children: body),
        ),
        if (actions.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: actions,
            ),
          ),
      ],
    );
  }

  Widget _buildZero() {
    return _rightPanel(
      body: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Zero the phone',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                const Text(
                  '1. Put the phone flat on a level table, screen facing up, '
                  'with the long edge pointing left to right.',
                ),
                const SizedBox(height: 6),
                const Text(
                  '2. Check the axis: lift one of the two narrow ends a '
                  'little, like a see-saw. The number should change. '
                  'Lifting a long edge should not.',
                ),
                const SizedBox(height: 6),
                const Text(
                  '3. Put it back flat and keep it still. The zero is set '
                  'automatically after about 1.5 seconds.',
                ),
                const SizedBox(height: 12),
                ValueListenableBuilder<double>(
                  valueListenable: _progress,
                  builder: (context, p, _) => Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        p > 0
                            ? 'Hold still...'
                            : 'Waiting for the phone to lie flat and still',
                        style: const TextStyle(fontSize: 12),
                      ),
                      const SizedBox(height: 4),
                      LinearProgressIndicator(value: p),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
      actions: const [],
    );
  }

  String _statusText() {
    if (_capturing) return 'Taking the reading... hold still.';
    if (!_armed) return "Place the phone on the patient's back at this level.";
    return 'Hold the phone still. The reading is taken automatically.';
  }

  Widget _buildMeasure() {
    final level = BackLevels.all[_levelIndex];
    final pending = _pending;
    final total = BackLevels.all.length;
    final isLast = _fromReview || _levelIndex >= total - 1;

    return _rightPanel(
      body: [
        Text(
          _fromReview
              ? 'Re-measuring: ${level.name}'
              : 'Level ${_levelIndex + 1} of $total',
          style: Theme.of(context).textTheme.labelLarge,
        ),
        Text(level.name, style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 8),
        LinearProgressIndicator(value: _levelIndex / total),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Where: ${level.where}'),
                const SizedBox(height: 8),
                const Text(
                  "The patient bends forward (Adam's forward bend), arms "
                  'hanging. Lay the phone flat across the back, screen up, '
                  'long edge across the spine, and hold it steady.',
                ),
              ],
            ),
          ),
        ),
        if (pending == null)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(_statusText()),
                  const SizedBox(height: 8),
                  ValueListenableBuilder<double>(
                    valueListenable: _progress,
                    builder: (context, p, _) =>
                        LinearProgressIndicator(value: _capturing ? null : p),
                  ),
                ],
              ),
            ),
          ),
        if (_message != null)
          Card(
            color: Colors.orange.withValues(alpha: 0.15),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Text(_message!),
            ),
          ),
        if (pending != null)
          Card(
            color: Colors.green.withValues(alpha: 0.12),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  Text(
                    'Reading: ${pending.atr.toStringAsFixed(1)}°',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    isLast
                        ? 'Saved. Going to the review...'
                        : 'Saved. Moving to the next level...',
                    style: const TextStyle(fontSize: 12),
                  ),
                ],
              ),
            ),
          ),
      ],
      actions: pending == null
          ? const []
          : [
              OutlinedButton(
                onPressed: _remeasure,
                child: const Text('Re-measure this level'),
              ),
            ],
    );
  }

  Widget _buildSummary() {
    final highest = _highest;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: highest == null
            ? const Text('No readings yet. Measure at least one level.')
            : Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('Highest ATR (this is the value saved)'),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      '${highest.atr.toStringAsFixed(1)}°',
                      style: const TextStyle(
                        fontSize: 96,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  Text('at the ${highest.level.name.toLowerCase()} level'),
                ],
              ),
      ),
    );
  }

  Widget _buildReview() {
    final highest = _highest;
    return _rightPanel(
      body: [
        for (var i = 0; i < BackLevels.all.length; i++) _reviewTile(i, highest),
      ],
      actions: [
        FilledButton(
          onPressed: (highest == null || _saving) ? null : _save,
          child: _saving
              ? const SizedBox(
                  height: 20,
                  width: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Confirm and save'),
        ),
        TextButton(
          onPressed: _saving ? null : _measureAgain,
          child: const Text('Measure all levels again'),
        ),
      ],
    );
  }

  Widget _reviewTile(int index, LevelReading? highest) {
    final level = BackLevels.all[index];
    final r = _readings[level.id];
    final isHighest =
        r != null && highest != null && r.level.id == highest.level.id;
    return Card(
      child: ListTile(
        dense: true,
        leading: Icon(
          isHighest ? Icons.star : Icons.straighten,
          color: isHighest ? Colors.amber : null,
        ),
        title: Text(level.name),
        subtitle: Text(
          r == null
              ? 'Not measured'
              : 'ATR ${r.atr.toStringAsFixed(1)}°   (moved ${r.range.toStringAsFixed(1)}°)',
        ),
        trailing: OutlinedButton(
          onPressed: _saving ? null : () => _remeasureLevel(index),
          child: Text(r == null ? 'Measure' : 'Re-measure'),
        ),
      ),
    );
  }
}
