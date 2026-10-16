import 'dart:math' as math;
import 'dart:typed_data';

import 'authored_curve.dart';

final class NativeParticleEmission {
  const NativeParticleEmission(
    this.index,
    this.simulationSeconds,
    this.systemPhase,
    this.ageAtStepEnd,
  );
  final int index;
  final double simulationSeconds, systemPhase, ageAtStepEnd;
}

/// A persistent emitter advances once over a supplied simulation interval.
/// Emission callbacks preserve the random stream order across birth and rates.
final class NativeAuthoredEmission {
  NativeAuthoredEmission(this.system, this.randomValue) {
    delay = math.max(
      0,
      NativeAuthoredMinMaxCurve(system['startDelay'] as Map)
          .sample(0, randomValue()),
    );
    _delayRemaining = delay;
    _burstsDone = List.filled(
      ((system['EmissionModule'] as Map)['m_Bursts'] as List).length,
      0,
    );
  }
  final Map system;
  final double Function() randomValue;
  late final double delay;
  late double _delayRemaining;
  late final List<int> _burstsDone;
  double simulationSeconds = 0, _time = 0;
  double _timeRemainder = 0, _distanceRemainder = 0;
  int _nextIndex = 0, loopCount = 0;
  final Float32List _scalar = Float32List(1);
  double _f(double value) {
    _scalar[0] = value;
    return _scalar[0];
  }

  double get systemTime => _time;
  bool get durationEnded =>
      system['looping'] != true && _time >= (system['lengthInSec'] as num);

  List<NativeParticleEmission> advance(
    double simulationDelta, {
    required double emitterDistance,
    double? rateOverTimeOverride,
    double? rateOverDistanceOverride,
    void Function(NativeParticleEmission)? onEmission,
  }) {
    if (!simulationDelta.isFinite ||
        simulationDelta < 0 ||
        !emitterDistance.isFinite ||
        emitterDistance < 0) {
      throw ArgumentError('native_particle_emission_interval');
    }
    if (!(simulationDelta > 0)) return const [];
    final module = system['EmissionModule'] as Map;
    final length = (system['lengthInSec'] as num).toDouble();
    if (!(length > 0)) {
      throw const FormatException('native_particle_emission_duration');
    }
    final totalStart = simulationSeconds;
    simulationSeconds += simulationDelta;
    var budget = simulationDelta, delayed = 0.0;
    if (_delayRemaining > 0) {
      delayed = math.min(_delayRemaining, budget);
      _delayRemaining = _f(_delayRemaining - delayed);
      budget = _f(budget - delayed);
      if (!(budget > 0)) return const [];
    }
    final output = <NativeParticleEmission>[];
    final birthPhase = math.min(_time / length, 1.0);
    void emit(int count, double segmentOffset, {double? phase}) {
      final age = _f(simulationDelta - segmentOffset);
      for (var i = 0; i < count; i++) {
        final event = NativeParticleEmission(
          _nextIndex++,
          totalStart + segmentOffset,
          phase ?? birthPhase,
          age,
        );
        if (onEmission == null) {
          output.add(event);
        } else {
          onEmission(event);
        }
      }
    }

    var time = _time, used = 0.0;
    final startTime = time;
    final looping = system['looping'] == true;
    var guard = 0;
    while (budget - used > 1e-9 && guard++ < 10000) {
      if (!looping && time >= length) break;
      final interval = math.min(budget - used, length - time);
      final end = time + interval;
      final offset = delayed + used;
      if (module['enabled'] == true) {
        // Bursts run before rate over time; each birth consumes its own stream
        // values before the next event or curve samples that stream.
        for (final (index, raw) in (module['m_Bursts'] as List).indexed) {
          final burst = raw as Map;
          final repeats = burst['cycleCount'] as int;
          final spacing = (burst['repeatInterval'] as num).toDouble();
          final limit = repeats > 0
              ? repeats
              : spacing > 0
              ? null
              : 1;
          var burstGuard = 0;
          while (burstGuard++ < 100000 &&
              (limit == null || _burstsDone[index] < limit)) {
            final at = _f(
              (burst['time'] as num).toDouble() + _burstsDone[index] * spacing,
            );
            if (at >= end) break;
            _burstsDone[index]++;
            if (at < time) continue;
            final probability = (burst['probability'] as num).toDouble();
            if (probability < 1 && !(randomValue() < probability)) continue;
            final count = NativeAuthoredMinMaxCurve(burst['countCurve'] as Map)
                .sample(at / length, randomValue())
                .round();
            emit(math.max(0, count), offset + (at - time));
          }
        }
        // A rate sample occurs even when its curve is constant or evaluates 0.
        final sampledRate =
            NativeAuthoredMinMaxCurve(module['rateOverTime'] as Map).sample(
              (time + end) * .5 / length,
              randomValue(),
              scalarOverride: rateOverTimeOverride,
            );
        final rate = sampledRate;
        if (rate > 0 && interval > 0) {
          final previous = _timeRemainder, total = previous + rate * interval;
          final count = total.floor();
          for (var n = 1; n <= count; n++) {
            final afterStart = (n - previous) / rate;
            emit(1, offset + afterStart);
          }
          _timeRemainder = total - count;
        }
      }
      used += interval;
      time = end;
      if (time >= length) {
        if (looping) {
          time = 0;
          loopCount++;
          _burstsDone.fillRange(0, _burstsDone.length, 0);
        } else {
          time = length;
          break;
        }
      }
    }
    _time = _f(time);
    if (module['enabled'] == true && emitterDistance > 0) {
      final sampledRate =
          NativeAuthoredMinMaxCurve(module['rateOverDistance'] as Map).sample(
            startTime / length,
            randomValue(),
            scalarOverride: rateOverDistanceOverride,
          );
      final rate = sampledRate;
      if (rate > 0) {
        final previous = _distanceRemainder,
            total = previous + rate * emitterDistance;
        final count = total.floor();
        for (var n = 1; n <= count; n++) {
          final fraction = ((n - previous) / (rate * emitterDistance)).clamp(
            0.0,
            1.0,
          );
          emit(
            1,
            simulationDelta * fraction,
            phase: math.min(_time / length, 1),
          );
        }
        _distanceRemainder = total - count;
      }
    }
    return output;
  }
}
