import 'dart:math' as math;
import 'dart:typed_data';

import 'authored_curve.dart';
import 'authored_effect_graph.dart';
import 'authored_effect_material.dart';
import 'authored_effect_animation.dart';
import 'authored_particle_state.dart';
import 'authored_emission.dart';
import 'authored_particle_renderer.dart';
import 'authored_particle_shape.dart';
import 'authored_gradient.dart';
import 'authored_random.dart';
import 'authored_particle_noise.dart';
import 'projection.dart';

abstract interface class AuthoredParticleSource {
  NativeAuthoredEffectGraph get graph;
  Map<String, String> get materialTextureKeys;
  NativeEffectObject component(String path);
  NativeAuthoredRandom randomFor(NativeEffectObject system);
}

final class AuthoredParticleSystem {
  AuthoredParticleSystem(
    this.source,
    this.reference, {
    Float64List? projectGravity,
    this.onBirth,
    this.noise,
    NativeParticleMaterial Function(NativeEffectObject)? materialResolver,
    this.prewarm = false,
    bool customDataUnusedByMaterial = false,
  }) : gravity = projectGravity ?? _zeroGravity {
    object = source.component(reference['metadataUrl'] as String);
    _particleConfig = NativeAuthoredParticleConfig(object.data);
    final initialData = object.data['InitialModule'] as Map;
    if (initialData['randomizeRotationDirection'] != 0 ||
        (object.data['ShapeModule'] as Map)['alignToDirection'] == true) {
      throw UnsupportedError(
        'native_effect_spin_or_shape_alignment_birth_domain:${object.key}',
      );
    }
    const supported = {
      'InitialModule',
      'EmissionModule',
      'ShapeModule',
      'ColorModule',
      'SizeModule',
      'VelocityModule',
      'ClampVelocityModule',
      'UVModule',
    };
    for (final entry in object.data.entries) {
      if (entry.value is Map &&
          (entry.value as Map)['enabled'] == true &&
          !supported.contains(entry.key) &&
          !(entry.key == 'SubModule' && onBirth != null) &&
          !(entry.key == 'NoiseModule' && noise != null) &&
          !(entry.key == 'CustomDataModule' && customDataUnusedByMaterial)) {
        throw UnsupportedError('native_effect_active_module:${entry.key}');
      }
    }

    if (projectGravity == null) {
      final modifier =
          (object.data['InitialModule'] as Map)['gravityModifier'] as Map;
      if (modifier['minMaxState'] != 0 || modifier['scalar'] != 0) {
        throw UnsupportedError('native_effect_requires_actual_project_gravity');
      }
    }
    transform = source.graph.transform(object);
    final renderers = source.graph.selectedComponents(
      source.graph.gameObject(object),
      type: 'ParticleSystemRenderer',
    );
    if (renderers.length != 1) {
      throw StateError('native_effect_particle_renderer_count:${object.key}');
    }
    renderer = renderers.single;
    if ((renderer.data['m_Flip'] as Map).values.any((value) => value != 0)) {
      throw UnsupportedError(
        'native_effect_renderer_flip_birth_domain:${object.key}',
      );
    }
    spec = NativeParticleRendererSpec(renderer);
    material = source.graph.reference(
      renderer,
      (renderer.data['m_Materials'] as List).single as Map,
    )!;
    materialProperties =
        materialResolver?.call(material) ??
        NativeParticleMaterial.mobileHdr(NativeMobileHdrMaterial(material));
    texture = source.materialTextureKeys[material.key]!;
    if (spec.renderMode == NativeParticleRenderMode.mesh) {
      final mesh = source.graph.reference(
        renderer,
        renderer.data['m_Mesh'] as Map,
      )!;
      meshGeometry = source.graph.spriteGeometry(mesh);
    }
    random = source.randomFor(object);
  }
  final AuthoredParticleSource source;
  final Map reference;
  late final NativeEffectObject object, transform, renderer, material;
  late final NativeParticleRendererSpec spec;
  late final NativeParticleMaterial materialProperties;
  NativeMobileHdrMaterial get hdr =>
      materialProperties.hdr ??
      (throw StateError('particle_material_is_not_hdr:${material.key}'));
  late final String texture;
  NativeSpriteGeometry? meshGeometry;
  late final NativeAuthoredRandom random;
  late final NativeAuthoredParticleConfig _particleConfig;
  static final _zeroGravity = Float64List(3);
  final Float64List gravity;
  final AuthoredParticleNoise? noise;
  final bool prewarm;
  final void Function(NativeAuthoredParticle particle, Float32List matrix)?
  onBirth;
  NativeAuthoredEmission? _emitter;
  final particles = <NativeAuthoredParticle>[];
  int _tick = -1;
  bool _active = false;
  bool _prewarmPending = false;
  Float64List? _lastOrigin;
  int births = 0;
  int _lastSubsteps = 0;
  bool sourceWidthBound = false;
  double? shapeWidthOverride;
  Float64List? localScaleOverride;
  final Float32List _scalar = Float32List(1);
  int get alive => particles.length;
  bool get active => _active;
  Map<String, Object?> get diagnostic => {
    'source': object.key,
    'tick': _tick,
    'active': _active,
    'simulationSeconds': _emitter?.simulationSeconds,
    'delay': _emitter?.delay,
    'births': births,
    'alive': alive,
    'simulationSubsteps': _lastSubsteps,
    if (noise != null) 'noiseScrollOffset': noise!.scrollOffset,
  };

  void simulateFrame(
    double age, {
    required double frameDelta,
    double? activeAge,
    required int pathHash,
    required double nativeWidth,
    required bool Function(double) activeAt,
    required NativeEffectAnimationFrame Function(double) frameAt,
    required Float32List Function(double) matrixAt,
  }) {
    _tick++;
    final at = age, active = activeAt(at);
    if (!active) {
      particles.clear();
      _emitter = null;
      _active = false;
      _prewarmPending = false;
      _lastOrigin = null;
      return;
    }
    final justActivated = !_active;
    if (justActivated) {
      noise?.reset();
      if (object.data['autoRandomSeed'] != true) {
        random.reseed(object.data['randomSeed'] as int);
      }
      _emitter = NativeAuthoredEmission(object.data, random.nextDouble);
      _active = true;
      _prewarmPending = prewarm && object.data['prewarm'] == true;
    }
    final frame = frameAt(at),
        matrix = matrixAt(at),
        policy = scalePolicy(matrix, nativeWidth);
    final own = transform.data['m_LocalScale'] as Map;
    final scale = Float64List.fromList([
      for (var axis = 0; axis < 3; axis++)
        object.data['scalingMode'] == 1
            ? (localScaleOverride?[axis] ??
                  (own[['x', 'y', 'z'][axis]] as num).toDouble())
            : math.sqrt(
                policy[axis * 4] * policy[axis * 4] +
                    policy[axis * 4 + 1] * policy[axis * 4 + 1] +
                    policy[axis * 4 + 2] * policy[axis * 4 + 2],
              ),
    ]);
    final numericFrame = NativeParticleFrame.fromAffine(
      matrix: policy,
      quaternion: source.graph.worldRotation(transform),
      scale: scale,
      worldSpace: object.data['moveWithTransform'] == 1,
    );
    Float64List localToWorldVector(Float64List value) => numericFrame.rotate(
      Float64List.fromList([for (var i = 0; i < 3; i++) value[i] * scale[i]]),
    );
    Float64List worldToLocalVector(Float64List value) {
      final rotated = numericFrame.inverseRotate(value);
      return Float64List.fromList([
        for (var i = 0; i < 3; i++)
          scale[i].abs() > 1e-12 ? rotated[i] / scale[i] : 0,
      ]);
    }

    final origin = Float64List.fromList([matrix[12], matrix[13], matrix[14]]);
    final distance = _lastOrigin == null
        ? 0.0
        : math.sqrt(
            [
              for (var axis = 0; axis < 3; axis++)
                math.pow(origin[axis] - _lastOrigin![axis], 2),
            ].fold<num>(0, (a, b) => a + b),
          );
    final previousOrigin = _lastOrigin ?? origin;
    _lastOrigin = origin;
    final rate =
        frame.scalar(pathHash, NativeEffectProperty.simulationSpeed) ??
        (object.data['simulationSpeed'] as num).toDouble();
    var elapsed = justActivated && activeAge != null
        ? math.min(frameDelta, math.max(0.0, activeAge))
        : frameDelta;
    if (_prewarmPending && elapsed > 0) {
      elapsed += (object.data['lengthInSec'] as num).toDouble();
      _prewarmPending = false;
    }
    _scalar[0] = elapsed * rate;
    final delta = _scalar[0];
    _lastSubsteps = 0;
    if (!(delta > 0)) return;
    final substeps = math.max(
      1,
      (delta / nativeMaximumParticleTimestep).ceil(),
    );
    final stepDelta = delta / substeps;
    _lastSubsteps = substeps;
    Float64List fromModule(Float64List vector, bool world) {
      final storageWorld = object.data['moveWithTransform'] == 1;
      if (storageWorld == world) return Float64List.fromList(vector);
      return storageWorld
          ? localToWorldVector(vector)
          : worldToLocalVector(vector);
    }

    Float64List toModule(Float64List vector, bool world) {
      final storageWorld = object.data['moveWithTransform'] == 1;
      if (storageWorld == world) return Float64List.fromList(vector);
      return storageWorld
          ? worldToLocalVector(vector)
          : localToWorldVector(vector);
    }

    final simulationGravity =
        object.data['moveWithTransform'] == 1 ||
            identical(gravity, _zeroGravity) ||
            gravity.every((value) => value == 0)
        ? gravity
        : worldToLocalVector(gravity);
    for (var step = 0; step < substeps; step++) {
      noise?.advance(
        (_emitter!.simulationSeconds / (object.data['lengthInSec'] as num))
            .clamp(0.0, 1.0),
        stepDelta,
      );
      final frameRemainder = delta - (step + 1) * stepDelta;
      for (var index = 0; index < particles.length;) {
        final particle = particles[index];
        particle.advance(
          stepDelta,
          object.data,
          configuration: _particleConfig,
          noiseVelocity: noise?.velocity(
            particle.position,
            particle.age + stepDelta,
            particle.lifetime,
          ),
          gravity: simulationGravity,
          moduleToSimulation: fromModule,
          simulationToModule: toModule,
        );
        if (particle.alive) {
          index++;
        } else {
          particles[index] = particles.last;
          particles.removeLast();
        }
      }
      void emit(NativeParticleEmission emission) {
        if (particles.length >=
            (object.data['InitialModule'] as Map)['maxNumParticles']) {
          return;
        }
        final bornAt = rate > 0
                ? at - (frameRemainder + emission.ageAtStepEnd) / rate
                : at,
            bornFrame = frame,
            bornMatrix = matrix;
        final initial = bornFrame.initialAtBirth(
          pathHash,
          object.data['InitialModule'] as Map,
        );
        double sample(String field) =>
            NativeAuthoredMinMaxCurve(initial[field] as Map)
                .sample(emission.systemPhase, random.nextDouble());
        final lifetime = sample('startLifetime');
        if (!(lifetime > 0)) return;
        final speed = sample('startSpeed'), sizeX = sample('startSize');
        final size = Float64List.fromList([
          sizeX,
          initial['size3D'] == true ? sample('startSizeY') : sizeX,
          initial['size3D'] == true ? sample('startSizeZ') : sizeX,
        ]);
        final angles = Float64List.fromList([
          initial['rotation3D'] == true ? sample('startRotationX') : 0,
          initial['rotation3D'] == true ? sample('startRotationY') : 0,
          sample('startRotation'),
        ]);
        final fraction = (initial['randomizeRotationDirection'] as num)
            .toDouble();
        if (fraction > 0 && random.nextDouble() < fraction) {
          for (var axis = 0; axis < 3; axis++) {
            angles[axis] = -angles[axis];
          }
        }
        final color = NativeAuthoredMinMaxGradient(initial['startColor'] as Map)
            .sample(emission.systemPhase, random.nextDouble())
            .map(quantizeAuthoredParticleChannel)
            .toList();
        final shape = nativeAuthoredParticleShape(
          object.data['ShapeModule'] as Map,
          const [],
          nextRandom: random.nextDouble,
          widthOverride: sourceWidthBound
              ? shapeWidthOverride
              : reference['shapeWidthOffset'] is num
              ? math.max(
                  0,
                  nativeWidth + (reference['shapeWidthOffset'] as num),
                )
              : null,
        );
        final samples = [for (var i = 0; i < 43; i++) random.nextDouble()];
        final flip = renderer.data['m_Flip'] as Map;
        for (final axis in ['x', 'y', 'z']) {
          if ((flip[axis] as num) > 0) random.nextDouble();
        }
        // Stable shader channels consume four values even if this material does
        // not read them. Keep the source stream order across later particles.
        for (var i = 0; i < 4; i++) {
          random.nextDouble();
        }
        final uvRandom = _particleConfig.textureSheet == null
            ? null
            : [random.nextDouble(), random.nextDouble()];
        final velocity = Float64List.fromList([
          for (final value in shape.direction) value * speed,
        ]);
        final world = object.data['moveWithTransform'] == 1;
        if (object.data['moveWithTransform'] != 0 && !world) {
          throw UnsupportedError('native_effect_custom_simulation_space');
        }
        final bornPolicy = scalePolicy(bornMatrix, nativeWidth);
        final birthPosition = world
            ? point(bornPolicy, shape.position)
            : shape.position;
        if (world) {
          final fraction =
              (1 - (frameRemainder + emission.ageAtStepEnd) / delta).clamp(
                0.0,
                1.0,
              );
          for (var axis = 0; axis < 3; axis++) {
            birthPosition[axis] +=
                previousOrigin[axis] +
                (origin[axis] - previousOrigin[axis]) * fraction -
                origin[axis];
          }
        }
        final particle = NativeAuthoredParticle(
          initial: initial,
          position: birthPosition,
          velocity: world ? localToWorldVector(velocity) : velocity,
          randomValues: samples,
          birthMatrix: bornMatrix,
          birthSeconds: bornAt,
          systemPhase: emission.systemPhase,
          birthValues: NativeParticleBirthValues(
            lifetime: lifetime,
            size: size,
            rotation: angles,
            color: color,
          ),
          textureSheetRandom: uvRandom,
        );
        onBirth?.call(particle, bornMatrix);
        final remainder = math.max(0.0, emission.ageAtStepEnd);
        particle.advance(
          remainder,
          object.data,
          configuration: _particleConfig,
          noiseVelocity: noise?.velocity(
            particle.position,
            particle.age + remainder,
            particle.lifetime,
          ),
          gravity: simulationGravity,
          moduleToSimulation: fromModule,
          simulationToModule: toModule,
        );
        if (particle.alive) {
          particles.add(particle);
          births++;
        }
      }

      _emitter!.advance(
        stepDelta,
        emitterDistance: distance / substeps,
        rateOverTimeOverride: frame.scalar(
          pathHash,
          NativeEffectProperty.emissionTimeScalar,
        ),
        rateOverDistanceOverride: frame.scalar(
          pathHash,
          NativeEffectProperty.emissionDistanceScalar,
        ),
        onEmission: emit,
      );
    }
  }

  GeometryBuffer? buildMesh({
    required Float32List matrix,
    required double nativeWidth,
    required Float32List clipFromWorld,
    required double fieldOfViewRadians,
    required List<double> cameraPosition,
    required double cameraXDegrees,
    bool bakeEnabled = false,
    double? orthographicSize,
  }) {
    if (particles.isEmpty ||
        (!bakeEnabled && renderer.data['m_Enabled'] != true)) {
      return null;
    }
    if (orthographicSize != null &&
        (!orthographicSize.isFinite || orthographicSize <= 0)) {
      throw ArgumentError.value(orthographicSize, 'orthographicSize');
    }
    final policy = scalePolicy(matrix, nativeWidth);
    final vertices = <double>[], indices = <int>[];
    final angle = cameraXDegrees * math.pi / 180;
    final camera = cameraPosition;
    final cameraRight = Float64List.fromList([1, 0, 0]),
        cameraUp = Float64List.fromList([0, math.cos(angle), math.sin(angle)]);
    final ownScale = transform.data['m_LocalScale'] as Map;
    final scaling = Float64List.fromList([
      for (var axis = 0; axis < 3; axis++)
        object.data['scalingMode'] == 1
            ? (localScaleOverride?[axis] ??
                  (axis == 0 &&
                          spec.renderMode == NativeParticleRenderMode.mesh &&
                          !sourceWidthBound
                      ? nativeWidth
                      : (ownScale[['x', 'y', 'z'][axis]] as num).toDouble()))
            : math.sqrt(
                policy[axis * 4] * policy[axis * 4] +
                    policy[axis * 4 + 1] * policy[axis * 4 + 1] +
                    policy[axis * 4 + 2] * policy[axis * 4 + 2],
              ),
    ]);
    final particleFrame = NativeParticleFrame.fromAffine(
      matrix: policy,
      quaternion: source.graph.worldRotation(transform),
      scale: scaling,
      worldSpace: object.data['moveWithTransform'] == 1,
    );
    final cameraForward = Float64List.fromList([
      0,
      -math.sin(angle),
      math.cos(angle),
    ]);
    for (final particle in particles) {
      final world = object.data['moveWithTransform'] == 1;
      final center = world
          ? particle.position
          : point(policy, particle.position);
      final size = particle.size(object.data, configuration: _particleConfig);
      NativeSpriteGeometry shape;
      if (meshGeometry != null) {
        final raw = meshGeometry!,
            positions = Float32List(raw.positions.length),
            c = math.cos(particle.rotation),
            s = math.sin(particle.rotation);
        for (var vertex = 0; vertex < raw.positions.length ~/ 3; vertex++) {
          final x = (raw.positions[vertex * 3] + spec.pivot[0]) * size[0],
              y = (raw.positions[vertex * 3 + 1] + spec.pivot[1]) * size[1],
              z = (raw.positions[vertex * 3 + 2] + spec.pivot[2]) * size[2];
          final Float64List rotated;
          if (particle.rotationX != 0 || particle.rotationY != 0) {
            final angles = authoredParticleRotation(
              particle.rotationX,
              particle.rotationY,
              particle.rotation,
            );
            rotated = Float64List.fromList([
              for (var axis = 0; axis < 3; axis++)
                angles[axis] * x + angles[3 + axis] * y + angles[6 + axis] * z,
            ]);
          } else {
            rotated = Float64List.fromList([x * c - y * s, x * s + y * c, z]);
          }
          final alignment = spec.data['m_RenderAlignment'];
          Float64List oriented;
          if (alignment == 2) {
            oriented = particleFrame.localOffset(rotated);
          } else {
            var right = cameraRight, up = cameraUp, forward = cameraForward;
            if (alignment == 1) {
              right = Float64List.fromList([1, 0, 0]);
              up = Float64List.fromList([0, 1, 0]);
              forward = Float64List.fromList([0, 0, 1]);
            } else if (alignment == 3) {
              Float64List unit(Float64List v) {
                final length = math.sqrt(
                  v[0] * v[0] + v[1] * v[1] + v[2] * v[2],
                );
                return Float64List.fromList([
                  for (final n in v) length > 0 ? n / length : 0,
                ]);
              }

              Float64List cross(Float64List a, Float64List b) =>
                  Float64List.fromList([
                    a[1] * b[2] - a[2] * b[1],
                    a[2] * b[0] - a[0] * b[2],
                    a[0] * b[1] - a[1] * b[0],
                  ]);
              forward = unit(
                Float64List.fromList([
                  for (var k = 0; k < 3; k++) center[k] - camera[k],
                ]),
              );
              right = unit(cross(cameraUp, forward));
              up = cross(forward, right);
            } else if (alignment != 0) {
              throw UnsupportedError(
                'native_particle_mesh_alignment:$alignment',
              );
            }
            oriented = particleFrame.worldOffset(
              Float64List.fromList([
                for (var k = 0; k < 3; k++)
                  right[k] * rotated[0] +
                      up[k] * rotated[1] +
                      forward[k] * rotated[2],
              ]),
            );
          }
          final offset = oriented;
          for (var axis = 0; axis < 3; axis++) {
            positions[vertex * 3 + axis] = center[axis] + offset[axis];
          }
        }
        shape = NativeSpriteGeometry(
          positions: positions,
          uv: raw.uv,
          indices: raw.indices,
        );
      } else {
        final Float64List? worldVelocity;
        if (spec.renderMode == NativeParticleRenderMode.stretchedBillboard) {
          if (_particleConfig.velocity != null || noise != null) {
            throw UnsupportedError('particle_stretch_animated_velocity');
          }
          worldVelocity = world
              ? particle.velocity
              : particleFrame.rotate(
                  Float64List.fromList([
                    for (var i = 0; i < 3; i++)
                      particle.velocity[i] * scaling[i],
                  ]),
                );
        } else {
          worldVelocity = null;
        }
        shape = spec.billboard(
          center: center,
          size: size,
          cameraPosition: Float64List.fromList(camera),
          cameraRight: cameraRight,
          cameraUp: cameraUp,
          cameraForward: cameraForward,
          projectionY: 1 / math.tan(fieldOfViewRadians / 2),
          frame: particleFrame,
          rotation: particle.rotation,
          rotationX: particle.rotationX,
          rotationY: particle.rotationY,
          clipFromWorld: clipFromWorld,
          orthographicSize: orthographicSize,
          worldVelocity: worldVelocity,
        );
      }
      final color = materialProperties.vertexColor(
        particle.color(object.data, configuration: _particleConfig),
        authoredTintOverride: reference['materialTint'] is List
            ? (reference['materialTint'] as List)
                  .map((v) => (v as num).toDouble())
                  .toList()
            : null,
      );
      final tile = _particleConfig.textureSheet?.tile(
        particle.normalizedAge,
        particle.textureSheetRandom!,
      );
      final st = materialProperties.textureTransform;
      final transformTexture =
          materialProperties.hdr == null &&
          (st[0] != 1 || st[1] != 1 || st[2] != 0 || st[3] != 0);
      if (tile != null || transformTexture) {
        final uv = Float32List(shape.uv.length);
        for (var vertex = 0; vertex < uv.length ~/ 2; vertex++) {
          var u = shape.uv[vertex * 2], v = shape.uv[vertex * 2 + 1];
          if (tile != null) {
            u = tile[0] + u * tile[2];
            v = tile[1] + v * tile[3];
          }
          if (transformTexture) {
            u = u * st[0] + st[2];
            v = v * st[1] + (1 - st[1] - st[3]);
          }
          uv[vertex * 2] = u;
          uv[vertex * 2 + 1] = v;
        }
        shape = NativeSpriteGeometry(
          positions: shape.positions,
          uv: uv,
          indices: shape.indices,
        );
      }
      final mesh = projectSprite(shape, clipFromWorld, color),
          base = vertices.length ~/ 10;
      if (base + mesh.vertices.length ~/ 10 > 65535) {
        throw StateError('native_particle_batch_index_capacity');
      }
      vertices.addAll(mesh.vertices);
      indices.addAll([for (final index in mesh.indices) base + index]);
    }
    return GeometryBuffer(
      Float32List.fromList(vertices),
      Uint16List.fromList(indices),
    );
  }

  Float32List scalePolicy(Float32List matrix, double nativeWidth) {
    if (object.data['scalingMode'] == 0) return matrix;
    if (object.data['scalingMode'] != 1) {
      throw UnsupportedError(
        'native_effect_scaling_mode:${object.data['scalingMode']}',
      );
    }
    final own = transform.data['m_LocalScale'] as Map;
    final scale =
        localScaleOverride ??
        Float64List.fromList([
          for (var axis = 0; axis < 3; axis++)
            axis == 0 && spec.renderMode == NativeParticleRenderMode.mesh
                ? (sourceWidthBound
                      ? (own['x'] as num).toDouble()
                      : nativeWidth)
                : (own[['x', 'y', 'z'][axis]] as num).toDouble(),
        ]);
    final rotation = NativeParticleFrame.fromAffine(
      matrix: matrix,
      quaternion: source.graph.worldRotation(transform),
      scale: scale,
      worldSpace: object.data['moveWithTransform'] == 1,
    ).rotation;
    final result = Float32List(16);
    for (var axis = 0; axis < 3; axis++) {
      for (var row = 0; row < 3; row++) {
        result[axis * 4 + row] = rotation[axis * 3 + row] * scale[axis];
      }
    }
    result[12] = matrix[12];
    result[13] = matrix[13];
    result[14] = matrix[14];
    result[15] = 1;
    return result;
  }

  static Float64List point(Float32List m, Float64List v) =>
      Float64List.fromList([
        for (var row = 0; row < 3; row++)
          m[row] * v[0] + m[4 + row] * v[1] + m[8 + row] * v[2] + m[12 + row],
      ]);
  static Float64List direction(Float32List m, Float64List v) =>
      Float64List.fromList([
        for (var row = 0; row < 3; row++)
          m[row] * v[0] + m[4 + row] * v[1] + m[8 + row] * v[2],
      ]);
  static Float64List inverseDirection(Float32List m, Float64List v) {
    final a = m[0],
        b = m[4],
        c = m[8],
        d = m[1],
        e = m[5],
        f = m[9],
        g = m[2],
        h = m[6],
        i = m[10];
    final determinant =
        a * (e * i - f * h) - b * (d * i - f * g) + c * (d * h - e * g);
    if (determinant.abs() < 1e-12) {
      throw StateError('native_effect_singular_transform');
    }
    return Float64List.fromList([
      ((e * i - f * h) * v[0] +
              (c * h - b * i) * v[1] +
              (b * f - c * e) * v[2]) /
          determinant,
      ((f * g - d * i) * v[0] +
              (a * i - c * g) * v[1] +
              (c * d - a * f) * v[2]) /
          determinant,
      ((d * h - e * g) * v[0] +
              (b * g - a * h) * v[1] +
              (a * e - b * d) * v[2]) /
          determinant,
    ]);
  }
}
