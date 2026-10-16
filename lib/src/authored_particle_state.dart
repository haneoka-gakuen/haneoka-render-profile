import 'dart:math' as math;
import 'dart:typed_data';

import 'authored_curve.dart';
import 'authored_gradient.dart';
import 'authored_particle_config.dart';

export 'authored_particle_config.dart';

/// Formal Intl TimeManager.Maximum Particle Timestep, in simulation seconds.
const nativeMaximumParticleTimestep = 0.029999999329447746;

/// Values sampled in the emitter's birth phase before shape and stable slots.
final class NativeParticleBirthValues {
  const NativeParticleBirthValues({
    required this.lifetime,
    required this.size,
    required this.rotation,
    required this.color,
  });
  final double lifetime;
  final Float64List size, rotation;
  final List<double> color;
}

/// A born particle retains its actual sampled random values and birth transform.
/// The scene producer owns emission scheduling and original local/world space.
final class NativeAuthoredParticle {
  NativeAuthoredParticle({
    required this.initial,
    required Float64List position,
    required Float64List velocity,
    required List<double> randomValues,
    required Float32List birthMatrix,
    required this.birthSeconds,
    required double systemPhase,
    NativeParticleBirthValues? birthValues,
    List<double>? textureSheetRandom,
  }) : position = Float64List.fromList(position),
       velocity = Float64List.fromList(velocity),
       randomValues = List.unmodifiable(randomValues),
       birthMatrix = Float32List.fromList(birthMatrix),
       textureSheetRandom = textureSheetRandom == null
           ? null
           : List.unmodifiable(textureSheetRandom) {
    if (position.length != 3 ||
        velocity.length != 3 ||
        birthMatrix.length != 16 ||
        randomValues.length < 19) {
      throw ArgumentError('native_particle_birth_components');
    }
    double curve(String field, int randomIndex) =>
        NativeAuthoredMinMaxCurve(initial[field] as Map)
            .sample(systemPhase, randomValues[randomIndex]);
    _gravityModifier = NativeAuthoredMinMaxCurve(
      initial['gravityModifier'] as Map,
    );
    _formalBirth = birthValues != null;
    if (_formalBirth && randomValues.length != 43) {
      throw ArgumentError('native_particle_stable_random_slots');
    }
    lifetime = birthValues?.lifetime ?? curve('startLifetime', 0);
    startSize = birthValues == null
        ? Float64List.fromList([
            curve('startSize', 1),
            initial['size3D'] == true
                ? curve('startSizeY', 2)
                : curve('startSize', 1),
            initial['size3D'] == true
                ? curve('startSizeZ', 3)
                : curve('startSize', 1),
          ])
        : Float64List.fromList(birthValues.size);
    rotation = birthValues?.rotation[2] ?? curve('startRotation', 4);
    final angles = birthValues?.rotation;
    _rotation3D =
        initial['rotation3D'] == true &&
            angles != null &&
            (angles[0] != 0 || angles[1] != 0)
        ? Float64List.fromList(angles)
        : null;
    startColor = birthValues == null
        ? NativeAuthoredMinMaxGradient(initial['startColor'] as Map)
              .sample(systemPhase, randomValues[5])
        : List.unmodifiable(birthValues.color);
  }
  final Map initial;
  final Float64List position, velocity;
  final List<double> randomValues;
  final Float32List birthMatrix;
  final double birthSeconds;
  final List<double>? textureSheetRandom;
  late final double lifetime, rotation;
  late final Float64List? _rotation3D;
  double get rotationX => _rotation3D?[0] ?? 0;
  double get rotationY => _rotation3D?[1] ?? 0;
  late final bool _formalBirth;
  late final NativeAuthoredMinMaxCurve _gravityModifier;
  final Float32List _scalar = Float32List(1);
  double _f(double value) {
    _scalar[0] = value;
    return _scalar[0];
  }

  int _slot(int formal, int legacy) => _formalBirth ? formal : legacy;
  late final Float64List startSize;
  late final List<double> startColor;
  double age = 0;
  bool get alive => age < lifetime && lifetime > 0;
  double get normalizedAge => lifetime > 0
      ? (_formalBirth ? _f(age / lifetime) : age / lifetime).clamp(0.0, 1.0)
      : 1;

  List<double> color(
    Map system, {
    NativeAuthoredParticleConfig? configuration,
  }) {
    final module =
        (configuration ?? NativeAuthoredParticleConfig(system)).color;
    if (module == null) return startColor;
    final gradient = module.sample(normalizedAge, randomValues[_slot(19, 6)]);
    return [
      for (var channel = 0; channel < 4; channel++)
        _formalBirth
            ? quantizeAuthoredParticleChannel(
                startColor[channel] * gradient[channel],
              )
            : startColor[channel] * gradient[channel],
    ];
  }

  Float64List size(Map system, {NativeAuthoredParticleConfig? configuration}) {
    final module = (configuration ?? NativeAuthoredParticleConfig(system)).size;
    if (module == null) return Float64List.fromList(startSize);
    final x = module.x.sample(normalizedAge, randomValues[_slot(16, 7)]);
    return Float64List.fromList([
      startSize[0] * x,
      startSize[1] *
          (module.y != null
              ? module.y!.sample(normalizedAge, randomValues[_slot(17, 8)])
              : x),
      startSize[2] *
          (module.z != null
              ? module.z!.sample(normalizedAge, randomValues[_slot(18, 9)])
              : x),
    ]);
  }

  /// Native integration is supplied the real simulation delta; source cadence
  /// and simulationSpeed are applied by the emitter exactly once.
  void advance(
    double seconds,
    Map system, {
    NativeAuthoredParticleConfig? configuration,
    Float64List? noiseVelocity,
    required Float64List gravity,
    required Float64List Function(Float64List, bool) moduleToSimulation,
    required Float64List Function(Float64List, bool) simulationToModule,
  }) {
    if (!seconds.isFinite || seconds < 0) {
      throw ArgumentError('native_particle_delta');
    }
    if (!alive || seconds == 0) return;
    final config = configuration ?? NativeAuthoredParticleConfig(system);
    final dt = _formalBirth ? seconds : math.min(seconds, lifetime - age);
    final phase = _formalBirth
        ? normalizedAge
        : ((age + dt) / lifetime).clamp(0.0, 1.0);
    final modifier = _gravityModifier.sample(
      phase,
      randomValues[_slot(36, 10)],
    );
    if (_formalBirth) {
      for (var axis = 0; axis < 3; axis++) {
        velocity[axis] += gravity[axis] * modifier * dt;
      }
    }
    final velocityModule = config.velocity;
    var animated = Float64List(3);
    if (velocityModule != null) {
      if (velocityModule.unsupportedOrbital case final key?) {
        throw UnsupportedError('native_particle_velocity_orbital:$key');
      }
      animated = moduleToSimulation(
        Float64List.fromList([
          for (var axis = 0; axis < 3; axis++)
            velocityModule.axes[axis].sample(
              phase,
              randomValues[_slot(axis, 11 + axis)],
            ),
        ]),
        velocityModule.worldSpace,
      );
    }
    final total = Float64List.fromList([
      for (var axis = 0; axis < 3; axis++) velocity[axis] + animated[axis],
    ]);
    final limit = config.limit;
    if (limit != null) {
      final local = _formalBirth && !limit.separateAxes
          ? Float64List.fromList(total)
          : simulationToModule(total, limit.worldSpace);
      final damp = 1 - math.pow(1 - limit.dampen, dt.abs() * 30);
      if (limit.separateAxes) {
        for (var axis = 0; axis < 3; axis++) {
          final maximum = limit.axes![axis].sample(
            phase,
            randomValues[_slot(12 + axis, 15 + axis)],
          );
          final magnitude = local[axis].abs();
          if (magnitude > maximum) {
            local[axis] =
                local[axis].sign * (magnitude - (magnitude - maximum) * damp);
          }
        }
      } else {
        final maximum = limit.magnitude!.sample(
          phase,
          randomValues[_slot(11, 15)],
        );
        final magnitude = math.sqrt(local.fold<double>(0, (s, v) => s + v * v));
        if (magnitude > maximum && magnitude > 0) {
          final factor = (magnitude - (magnitude - maximum) * damp) / magnitude;
          for (var axis = 0; axis < 3; axis++) {
            local[axis] *= factor;
          }
        }
      }
      final limited = _formalBirth && !limit.separateAxes
          ? local
          : moduleToSimulation(local, limit.worldSpace);
      var drag = limit.drag
          .sample(phase, randomValues[_slot(15, 14)])
          .clamp(0.0, double.infinity);
      final speed = math.sqrt(limited.fold<double>(0, (s, v) => s + v * v));
      if (limit.multiplyDragByParticleSize) {
        drag *= size(system, configuration: config).reduce(math.max);
      }
      if (limit.multiplyDragByParticleVelocity) drag *= speed * speed;
      final retain = speed > 0 ? math.max(0.0, speed - drag * dt) / speed : 0.0;
      for (var axis = 0; axis < 3; axis++) {
        total[axis] = limited[axis] * retain;
        velocity[axis] = total[axis] - animated[axis];
      }
    }
    var speedModifier = 1.0;
    if (velocityModule != null) {
      speedModifier = velocityModule.speedModifier.sample(
        phase,
        randomValues[_slot(10, 18)],
      );
    }
    if (noiseVelocity == null) {
      for (var axis = 0; axis < 3; axis++) {
        position[axis] = _formalBirth
            ? _f(position[axis] + total[axis] * speedModifier * dt)
            : position[axis] + total[axis] * speedModifier * dt;
        if (!_formalBirth) velocity[axis] += gravity[axis] * modifier * dt;
      }
    } else {
      for (var axis = 0; axis < 3; axis++) {
        final displacement =
            (total[axis] * speedModifier + noiseVelocity[axis]) * dt;
        position[axis] = _formalBirth
            ? _f(position[axis] + displacement)
            : position[axis] + displacement;
        if (!_formalBirth) velocity[axis] += gravity[axis] * modifier * dt;
      }
    }
    age = _formalBirth ? _f(age + dt) : age + dt;
  }

  Map<String, Object?> snapshot() => {
    'birthSeconds': birthSeconds,
    'age': age,
    'position': position.toList(),
    'velocity': velocity.toList(),
    'randomValues': randomValues,
    'birthMatrix': birthMatrix.toList(),
    'lifetime': lifetime,
    'startSize': startSize.toList(),
    'startColor': startColor,
    'rotation': rotation,
    if (textureSheetRandom != null) 'textureSheetRandom': textureSheetRandom,
  };
}
