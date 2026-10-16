import 'dart:typed_data';

import 'authored_animation.dart';

enum NativeEffectProperty {
  active,
  position,
  colorR,
  colorG,
  colorB,
  colorA,
  sizeX,
  simulationSpeed,
  lifetimeScalar,
  emissionTimeScalar,
  emissionDistanceScalar,
  startMaxR,
  startMaxG,
  startMaxB,
  startMaxA,
  startMinR,
  startMinG,
  startMinB,
  startMinA,
}

/// Typed whitelist covers the actual 26 note-effect clips. Attribute numbers
/// are original CRC32 field identities; they never select executable methods.
final class NativeEffectAnimationFrame {
  NativeEffectAnimationFrame.empty();
  NativeEffectAnimationFrame(
    NativeAuthoredAnimationClip clip,
    double seconds, {
    bool loop = false,
  }) {
    for (final sample in clip.sampleBindingsAt(seconds, loop: loop)) {
      final binding = sample.binding,
          type = binding['typeID'] as int,
          attribute = binding['attribute'] as int,
          path = binding['path'] as int;
      if (sample.values.any((value) => !value.isFinite)) {
        throw FormatException(
          'native_effect_non_finite_animation:$path:$attribute',
        );
      }
      final property = switch (type) {
        1 when attribute == 2086281974 => NativeEffectProperty.active,
        4 when attribute == 1 => NativeEffectProperty.position,
        212 => _spriteProperties[attribute],
        198 => _particleProperties[attribute],
        _ => null,
      };
      if (property == null) {
        throw UnsupportedError(
          'native_effect_animation_binding:$type:$attribute',
        );
      }
      final values = channels.putIfAbsent(path, () => {});
      if (values.containsKey(property)) {
        throw FormatException(
          'native_effect_duplicate_binding:$path:$property',
        );
      }
      values[property] = sample.values.asUnmodifiableView();
    }
  }
  final channels = <int, Map<NativeEffectProperty, Float32List>>{};
  static const _spriteProperties = {
    2526845255: NativeEffectProperty.colorR,
    4215373228: NativeEffectProperty.colorG,
    2334886179: NativeEffectProperty.colorB,
    304273561: NativeEffectProperty.colorA,
    4197328169: NativeEffectProperty.sizeX,
  };
  static const _particleProperties = {
    1451932078: NativeEffectProperty.simulationSpeed,
    3063797154: NativeEffectProperty.lifetimeScalar,
    2883525743: NativeEffectProperty.emissionTimeScalar,
    1589456374: NativeEffectProperty.emissionDistanceScalar,
    4078873663: NativeEffectProperty.startMaxR,
    2663598292: NativeEffectProperty.startMaxG,
    4004101211: NativeEffectProperty.startMaxB,
    2007035361: NativeEffectProperty.startMaxA,
    4061279883: NativeEffectProperty.startMinR,
    2681197152: NativeEffectProperty.startMinG,
    4020578031: NativeEffectProperty.startMinB,
    1991014229: NativeEffectProperty.startMinA,
  };
  double? scalar(int path, NativeEffectProperty property) =>
      channels[path]?[property]?.single;
  bool active(int path, bool original) =>
      scalar(path, NativeEffectProperty.active)?.isFinite == true
      ? scalar(path, NativeEffectProperty.active)! > .5
      : original;
  Float32List color(int path, List<double> original) => Float32List.fromList([
    for (var channel = 0; channel < 4; channel++)
      scalar(
            path,
            [
              NativeEffectProperty.colorR,
              NativeEffectProperty.colorG,
              NativeEffectProperty.colorB,
              NativeEffectProperty.colorA,
            ][channel],
          ) ??
          original[channel],
  ]);

  Map initialAtBirth(int path, Map original) {
    final initial = Map.of(original),
        gradient = Map.of(original['startColor'] as Map);
    initial['startColor'] = gradient;
    for (final (name, properties) in [
      (
        'maxColor',
        [
          NativeEffectProperty.startMaxR,
          NativeEffectProperty.startMaxG,
          NativeEffectProperty.startMaxB,
          NativeEffectProperty.startMaxA,
        ],
      ),
      (
        'minColor',
        [
          NativeEffectProperty.startMinR,
          NativeEffectProperty.startMinG,
          NativeEffectProperty.startMinB,
          NativeEffectProperty.startMinA,
        ],
      ),
    ]) {
      final color = Map.of(gradient[name] as Map);
      gradient[name] = color;
      for (var channel = 0; channel < 4; channel++) {
        final value = scalar(path, properties[channel]);
        if (value != null) color[['r', 'g', 'b', 'a'][channel]] = value;
      }
    }
    final lifetime = scalar(path, NativeEffectProperty.lifetimeScalar);
    if (lifetime != null) {
      initial['startLifetime'] = {
        ...(initial['startLifetime'] as Map),
        'scalar': lifetime,
      };
    }
    return initial;
  }
}

int nativeEffectPathHash(String path) {
  var checksum = 0xffffffff;
  // The selected original hierarchy names are ASCII. A source outside this
  // verified contract must supply its original encoded path bytes explicitly.
  for (final unit in path.codeUnits) {
    if (unit > 127) throw UnsupportedError('native_effect_non_ascii_path');
    checksum ^= unit;
    for (var bit = 0; bit < 8; bit++) {
      checksum = (checksum >> 1) ^ ((checksum & 1) == 0 ? 0 : 0xedb88320);
    }
  }
  return (checksum ^ 0xffffffff) & 0xffffffff;
}
