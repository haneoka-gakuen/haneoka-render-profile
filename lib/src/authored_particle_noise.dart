import 'dart:math' as math;
import 'dart:typed_data';

import 'authored_curve.dart';

/// Parameter-driven coherent gradient field shared with the web implementation.
/// The field kernel is independently authored; it is not Unity's native kernel.
final class AuthoredParticleNoise {
  AuthoredParticleNoise(Map source, {this.fieldSeed = 0})
    : quality = source['quality'] as int,
      frequency = (source['frequency'] as num).toDouble(),
      octaves = source['octaves'] as int,
      octaveMultiplier = (source['octaveMultiplier'] as num).toDouble(),
      octaveScale = (source['octaveScale'] as num).toDouble(),
      damping = source['damping'] == true,
      separateAxes = source['separateAxes'] == true,
      remapEnabled = source['remapEnabled'] == true,
      strength = [
        for (final key in ['strength', 'strengthY', 'strengthZ'])
          NativeAuthoredMinMaxCurve(source[key] as Map),
      ],
      remap = [
        for (final key in ['remap', 'remapY', 'remapZ'])
          NativeAuthoredMinMaxCurve(source[key] as Map),
      ],
      scrollSpeed = NativeAuthoredMinMaxCurve(source['scrollSpeed'] as Map),
      positionAmount = NativeAuthoredMinMaxCurve(
        source['positionAmount'] as Map,
      ) {
    if (source['enabled'] != true ||
        quality < 0 ||
        quality > 2 ||
        octaves < 1 ||
        octaves > 16 ||
        !frequency.isFinite ||
        frequency < 0 ||
        !octaveMultiplier.isFinite ||
        !octaveScale.isFinite ||
        fieldSeed < 0 ||
        fieldSeed > 0xffffffff) {
      throw const FormatException('authored_particle_noise_parameters');
    }
    for (final key in ['rotationAmount', 'sizeAmount']) {
      final curve = source[key] as Map;
      if (curve['minMaxState'] != 0 || curve['scalar'] != 0) {
        throw UnsupportedError('authored_particle_noise:$key');
      }
    }
  }

  final int quality, octaves, fieldSeed;
  final double frequency, octaveMultiplier, octaveScale;
  final bool damping, separateAxes, remapEnabled;
  final List<NativeAuthoredMinMaxCurve> strength, remap;
  final NativeAuthoredMinMaxCurve scrollSpeed, positionAmount;
  double _scroll = 0;
  double get scrollOffset => _scroll;
  void reset() => _scroll = 0;

  void advance(double systemPhase, double delta, {int sourceSeed = 0}) {
    _scroll += scrollSpeed.sample(systemPhase, _random(sourceSeed, 5)) * delta;
  }

  Float64List velocity(
    Float64List position,
    double age,
    double lifetime, {
    int particleSeed = 0,
  }) {
    final phase = (age / lifetime).clamp(0.0, 1.0),
        amount = positionAmount.sample(phase, _random(particleSeed, 5)),
        result = Float64List(3);
    for (var axis = 0; axis < 3; axis++) {
      final random = _random(particleSeed, (separateAxes ? axis : 0) + 1);
      var scale = frequency, amplitude = 1.0, sum = 0.0, normalization = 0.0;
      for (var octave = 0; octave < octaves; octave++) {
        sum +=
            _field(
              position[0] * scale + _scroll,
              position[1] * scale + _scroll,
              position[2] * scale + _scroll,
              _mix(fieldSeed ^ _mul32(axis + 1, 0x85ebca6b)),
              quality + 1,
            ) *
            amplitude;
        normalization += amplitude;
        amplitude *= octaveMultiplier;
        scale *= octaveScale;
      }
      var noise = normalization == 0 ? 0.0 : sum / normalization;
      final channel = separateAxes ? axis : 0;
      if (remapEnabled) {
        noise = remap[channel].sample((noise + 1) / 2, random);
      }
      var gain = strength[channel].sample(phase, random);
      if (damping && frequency > 0) gain /= frequency;
      result[axis] = noise * gain * amount;
    }
    return result;
  }

  static int _mul32(int a, int b) =>
      ((a & 0xffff) * (b & 0xffff) +
          ((((a & 0xffffffff) >> 16) * (b & 0xffff) +
                      (a & 0xffff) * ((b & 0xffffffff) >> 16)) &
                  0xffff) *
              0x10000) &
      0xffffffff;

  static int _mix(int value) {
    var x = value & 0xffffffff;
    x = _mul32(x ^ (x >> 16), 0x45d9f3b);
    x = _mul32(x ^ (x >> 16), 0x45d9f3b);
    return (x ^ (x >> 16)) & 0xffffffff;
  }

  static double _random(int seed, int salt) =>
      _mix(seed ^ _mul32(salt, 0x9e3779b9)) / 0x100000000;
  static double _fade(double value) =>
      value * value * value * (value * (value * 6 - 15) + 10);
  static double _lerp(double a, double b, double t) => a + (b - a) * t;

  static double _gradient(
    double x,
    double y,
    double z,
    int ix,
    int iy,
    int iz,
    int seed,
    int dimensions,
  ) {
    final hash = _mix(
      seed ^ _mul32(ix, 73856093) ^ _mul32(iy, 19349663) ^ _mul32(iz, 83492791),
    );
    if (dimensions == 1) return hash & 1 != 0 ? x : -x;
    if (dimensions == 2) {
      return switch (hash & 7) {
        0 => x,
        1 => -x,
        2 => y,
        3 => -y,
        4 => (x + y) * math.sqrt1_2,
        5 => (x - y) * math.sqrt1_2,
        6 => (-x + y) * math.sqrt1_2,
        _ => (-x - y) * math.sqrt1_2,
      };
    }
    final axis = hash % 3,
        a = axis == 0
            ? x
            : axis == 1
            ? y
            : z,
        b = axis == 0
            ? y
            : axis == 1
            ? z
            : x;
    return ((hash & 4 != 0 ? -a : a) + (hash & 8 != 0 ? -b : b)) * math.sqrt1_2;
  }

  static double _field(double x, double y, double z, int seed, int dimensions) {
    final ix = x.floor(),
        iy = dimensions > 1 ? y.floor() : 0,
        iz = dimensions > 2 ? z.floor() : 0;
    final dx = x - ix,
        dy = dimensions > 1 ? y - iy : 0.0,
        dz = dimensions > 2 ? z - iz : 0.0;
    final u = _fade(dx), v = _fade(dy), w = _fade(dz);
    final lower = _lerp(
      _gradient(dx, dy, dz, ix, iy, iz, seed, dimensions),
      _gradient(dx - 1, dy, dz, ix + 1, iy, iz, seed, dimensions),
      u,
    );
    if (dimensions == 1) return lower;
    final low = _lerp(
      lower,
      _lerp(
        _gradient(dx, dy - 1, dz, ix, iy + 1, iz, seed, dimensions),
        _gradient(dx - 1, dy - 1, dz, ix + 1, iy + 1, iz, seed, dimensions),
        u,
      ),
      v,
    );
    if (dimensions < 3) return low;
    final high = _lerp(
      _lerp(
        _gradient(dx, dy, dz - 1, ix, iy, iz + 1, seed, dimensions),
        _gradient(dx - 1, dy, dz - 1, ix + 1, iy, iz + 1, seed, dimensions),
        u,
      ),
      _lerp(
        _gradient(dx, dy - 1, dz - 1, ix, iy + 1, iz + 1, seed, dimensions),
        _gradient(
          dx - 1,
          dy - 1,
          dz - 1,
          ix + 1,
          iy + 1,
          iz + 1,
          seed,
          dimensions,
        ),
        u,
      ),
      v,
    );
    return _lerp(low, high, w);
  }
}
