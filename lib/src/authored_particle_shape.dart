import 'dart:math' as math;
import 'dart:typed_data';

/// Authored local shape position and direction are distinct. In particular,
/// zero Circle XY scale collapses its position while retaining radial velocity.
final class NativeParticleShapeSample {
  const NativeParticleShapeSample(this.position, this.direction);
  final Float64List position, direction;
}

NativeParticleShapeSample nativeAuthoredParticleShape(
  Map shape,
  List<double> random, {
  double? widthOverride,
  double Function()? nextRandom,
}) {
  if ((nextRandom == null && random.length < 5) ||
      random.any((r) => !r.isFinite || r < 0 || r > 1)) {
    throw ArgumentError('native_particle_shape_random_samples');
  }
  double sample(int index) {
    if (nextRandom == null && index >= random.length) {
      throw ArgumentError('native_particle_shape_random_sample_count');
    }
    final value = nextRandom == null ? random[index] : nextRandom();
    if (!value.isFinite || value < 0 || value > 1) {
      throw ArgumentError('native_particle_shape_random_value');
    }
    return value;
  }

  final position = Float64List(3), direction = Float64List.fromList([0, 0, 1]);
  if (shape['enabled'] != true) {
    return NativeParticleShapeSample(position, direction);
  }
  final scale = shape['m_Scale'] as Map;
  final dimensions = [
    widthOverride ?? (scale['x'] as num).toDouble(),
    (scale['y'] as num).toDouble(),
    (scale['z'] as num).toDouble(),
  ];
  final type = shape['type'] as int;
  switch (type) {
    case 5:
    case 16:
      for (var axis = 0; axis < 3; axis++) {
        position[axis] = sample(axis) - .5;
      }
      final free = math.min(2, (sample(3) * 3).floor());
      if (type == 16) {
        final thickness = shape['boxThickness'] as Map;
        for (var k = 1; k <= 2; k++) {
          final axis = (free + k) % 3;
          final sign = sample(2 + 2 * k) < .5 ? -1 : 1;
          position[axis] =
              sign *
              (.5 -
                  .5 *
                      (thickness[['x', 'y', 'z'][axis]] as num) *
                      sample(3 + 2 * k));
        }
      }
      for (var axis = 0; axis < 3; axis++) {
        position[axis] *= dimensions[axis];
      }
      break;
    case 12:
      final radius = ((shape['radius'] as Map)['value'] as num).toDouble();
      position[0] = (sample(0) * 2 - 1) * radius * dimensions[0];
      direction[1] = 1;
      direction[2] = 0;
      break;
    case 4:
      final arc = shape['arc'] as Map;
      if (arc['mode'] != 0) {
        throw UnsupportedError('particle_cone_arc_mode:${arc['mode']}');
      }
      final angle = sample(0) * (arc['value'] as num) * math.pi / 180;
      final outer = ((shape['radius'] as Map)['value'] as num).toDouble();
      final inner = 1 - (shape['radiusThickness'] as num).toDouble();
      final radius =
          outer * math.sqrt(inner * inner + (1 - inner * inner) * sample(1));
      position[0] = math.cos(angle) * radius * dimensions[0];
      position[1] = math.sin(angle) * radius * dimensions[1];
      final spread =
          (outer > 0 ? radius / outer : 0) *
          math.tan((shape['angle'] as num) * math.pi / 180);
      final length = math.sqrt(spread * spread + 1);
      direction[0] = math.cos(angle) * spread / length;
      direction[1] = math.sin(angle) * spread / length;
      direction[2] = 1 / length;
      break;
    case 10:
      final arc = shape['arc'] as Map;
      if (arc['mode'] != 0) {
        throw UnsupportedError(
          'native_particle_circle_arc_mode:${arc['mode']}',
        );
      }
      final angle = sample(0) * (arc['value'] as num) * math.pi / 180;
      final outer = ((shape['radius'] as Map)['value'] as num).toDouble();
      final inner = outer * (1 - (shape['radiusThickness'] as num));
      final radius = math.sqrt(
        inner * inner + (outer * outer - inner * inner) * sample(1),
      );
      direction[0] = radius > 0 ? math.cos(angle) : 1;
      direction[1] = radius > 0 ? math.sin(angle) : 0;
      direction[2] = 0;
      position[0] = math.cos(angle) * radius * dimensions[0];
      position[1] = math.sin(angle) * radius * dimensions[1];
      break;
    default:
      throw UnsupportedError('native_particle_shape_type:$type');
  }
  for (final field in ['randomDirectionAmount', 'sphericalDirectionAmount']) {
    if (shape[field] != 0) {
      throw UnsupportedError('native_particle_shape_modifier:$field');
    }
  }
  final rotation = shape['m_Rotation'] as Map,
      offset = shape['m_Position'] as Map;
  final radians = (rotation['x'] as num) * math.pi / 180,
      c = math.cos(radians),
      s = math.sin(radians);
  if (rotation['y'] == 0 && rotation['z'] == 0) {
    for (final vector in [position, direction]) {
      final y = vector[1], z = vector[2];
      vector[1] = y * c - z * s;
      vector[2] = y * s + z * c;
    }
  } else {
    // Quaternion.Euler applies Source shape rotation in Z-X-Y order.
    final ry = (rotation['y'] as num) * math.pi / 180,
        rz = (rotation['z'] as num) * math.pi / 180;
    final cy = math.cos(ry),
        sy = math.sin(ry),
        cz = math.cos(rz),
        sz = math.sin(rz);
    for (final vector in [position, direction]) {
      final x = vector[0] * cz - vector[1] * sz,
          y = vector[0] * sz + vector[1] * cz,
          z = vector[2];
      final yy = y * c - z * s, zz = y * s + z * c;
      vector[0] = x * cy + zz * sy;
      vector[1] = yy;
      vector[2] = -x * sy + zz * cy;
    }
  }
  for (var axis = 0; axis < 3; axis++) {
    position[axis] += (offset[['x', 'y', 'z'][axis]] as num).toDouble();
  }
  final randomPosition = (shape['randomPositionAmount'] as num).toDouble();
  if (randomPosition > 0) {
    // Same independent inside-unit-sphere reference used by the particle port.
    final z = sample(2) * 2 - 1, angle = sample(3) * 2 * math.pi;
    final radius = math.pow(sample(4), 1 / 3) * randomPosition;
    final xy = math.sqrt(math.max(0.0, 1 - z * z));
    position[0] += xy * math.cos(angle) * radius;
    position[1] += xy * math.sin(angle) * radius;
    position[2] += z * radius;
  }
  return NativeParticleShapeSample(position, direction);
}
