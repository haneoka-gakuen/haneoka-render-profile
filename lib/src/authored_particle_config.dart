import 'authored_curve.dart';
import 'authored_gradient.dart';
import 'authored_particle_uv.dart';

/// Immutable authored modules are resolved once for a source ParticleSystem.
/// Animated birth values remain separate from these lifetime modules.
final class NativeAuthoredParticleConfig {
  factory NativeAuthoredParticleConfig(Map system) =>
      _configs[system] ??= NativeAuthoredParticleConfig._(system);
  NativeAuthoredParticleConfig._(Map system) {
    final colorModule = system['ColorModule'] as Map;
    color = colorModule['enabled'] == true
        ? NativeAuthoredMinMaxGradient(colorModule['gradient'] as Map)
        : null;
    final sizeModule = system['SizeModule'] as Map;
    size = sizeModule['enabled'] == true
        ? NativeParticleSizeConfig(sizeModule)
        : null;
    final velocityModule = system['VelocityModule'] as Map;
    velocity = velocityModule['enabled'] == true
        ? NativeParticleVelocityConfig(velocityModule)
        : null;
    final limitModule = system['ClampVelocityModule'] as Map;
    limit = limitModule['enabled'] == true
        ? NativeParticleLimitConfig(limitModule)
        : null;
    final uv = system['UVModule'] as Map?;
    textureSheet = uv != null && uv['enabled'] == true
        ? NativeParticleTextureSheet(uv)
        : null;
  }
  late final NativeAuthoredMinMaxGradient? color;
  late final NativeParticleSizeConfig? size;
  late final NativeParticleVelocityConfig? velocity;
  late final NativeParticleLimitConfig? limit;
  late final NativeParticleTextureSheet? textureSheet;
}

final class NativeParticleSizeConfig {
  NativeParticleSizeConfig(Map module)
    : x = NativeAuthoredMinMaxCurve(module['curve'] as Map),
      y = module['separateAxes'] == true
          ? NativeAuthoredMinMaxCurve(module['y'] as Map)
          : null,
      z = module['separateAxes'] == true
          ? NativeAuthoredMinMaxCurve(module['z'] as Map)
          : null;
  final NativeAuthoredMinMaxCurve x;
  final NativeAuthoredMinMaxCurve? y, z;
}

final class NativeParticleVelocityConfig {
  NativeParticleVelocityConfig(Map module)
    : axes = List.unmodifiable([
        for (final axis in const ['x', 'y', 'z'])
          NativeAuthoredMinMaxCurve(module[axis] as Map),
      ]),
      speedModifier = NativeAuthoredMinMaxCurve(module['speedModifier'] as Map),
      worldSpace = module['inWorldSpace'] == true {
    String? unsupported;
    for (final key in const [
      'orbitalX',
      'orbitalY',
      'orbitalZ',
      'orbitalOffsetX',
      'orbitalOffsetY',
      'orbitalOffsetZ',
      'radial',
    ]) {
      final value = module[key] as Map;
      if (value['minMaxState'] != 0 || value['scalar'] != 0) {
        unsupported = key;
        break;
      }
    }
    unsupportedOrbital = unsupported;
  }
  final List<NativeAuthoredMinMaxCurve> axes;
  final NativeAuthoredMinMaxCurve speedModifier;
  final bool worldSpace;
  late final String? unsupportedOrbital;
}

final class NativeParticleLimitConfig {
  NativeParticleLimitConfig(Map module)
    : separateAxes = module['separateAxis'] == true,
      worldSpace = module['inWorldSpace'] == true,
      dampen = (module['dampen'] as num).toDouble().clamp(0.0, 1.0),
      axes = module['separateAxis'] == true
          ? List.unmodifiable([
              for (final axis in const ['x', 'y', 'z'])
                NativeAuthoredMinMaxCurve(module[axis] as Map),
            ])
          : null,
      magnitude = module['separateAxis'] == true
          ? null
          : NativeAuthoredMinMaxCurve(module['magnitude'] as Map),
      drag = NativeAuthoredMinMaxCurve(module['drag'] as Map),
      multiplyDragByParticleSize = module['multiplyDragByParticleSize'] == true,
      multiplyDragByParticleVelocity =
          module['multiplyDragByParticleVelocity'] == true;
  final bool separateAxes, worldSpace;
  final double dampen;
  final List<NativeAuthoredMinMaxCurve>? axes;
  final NativeAuthoredMinMaxCurve? magnitude;
  final NativeAuthoredMinMaxCurve drag;
  final bool multiplyDragByParticleSize, multiplyDragByParticleVelocity;
}

final _configs = Expando<NativeAuthoredParticleConfig>(
  'native-authored-particle-config',
);
