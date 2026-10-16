import 'dart:math' as math;
import 'dart:typed_data';

import 'authored_effect_graph.dart';
import 'projection.dart';

enum NativeParticleRenderMode {
  billboard,
  stretchedBillboard,
  horizontalBillboard,
  verticalBillboard,
  mesh,
}

/// Numeric simulation frame and camera input for particle geometry.
final class NativeParticleFrame {
  NativeParticleFrame({
    required this.matrix,
    required Float64List quaternion,
    required this.scale,
    required this.worldSpace,
  }) {
    final x = quaternion[0],
        y = quaternion[1],
        z = quaternion[2],
        w = quaternion[3];
    // The authored TRS rotation columns round once before double vector math.
    rotation = Float64List.fromList(
      Float32List.fromList([
        1 - 2 * (y * y + z * z),
        2 * (x * y + z * w),
        2 * (x * z - y * w),
        2 * (x * y - z * w),
        1 - 2 * (x * x + z * z),
        2 * (y * z + x * w),
        2 * (x * z + y * w),
        2 * (y * z - x * w),
        1 - 2 * (x * x + y * y),
      ]),
    );
  }

  /// Matrix orientation retains reflections while Local scaling supplies only
  /// the emitter's own signed scale. Each sign participates exactly once.
  NativeParticleFrame.fromAffine({
    required this.matrix,
    required Float64List quaternion,
    required this.scale,
    required this.worldSpace,
  }) {
    Float64List? fallback;
    Float64List fallbackColumn(int axis) {
      final basis = fallback ??= NativeParticleFrame(
        matrix: matrix,
        quaternion: quaternion,
        scale: scale,
        worldSpace: worldSpace,
      ).rotation;
      return Float64List.fromList(basis.sublist(axis * 3, axis * 3 + 3));
    }

    Float64List column(int axis) {
      final sign = scale[axis] < 0 ? -1.0 : 1.0;
      return Float64List.fromList([
        for (var row = 0; row < 3; row++) matrix[axis * 4 + row] * sign,
      ]);
    }

    double dot(Float64List a, Float64List b) =>
        a[0] * b[0] + a[1] * b[1] + a[2] * b[2];
    Float64List normalized(Float64List value, int fallbackAxis) {
      final length = math.sqrt(dot(value, value));
      return length > 1e-12
          ? Float64List.fromList([for (final v in value) v / length])
          : fallbackColumn(fallbackAxis);
    }

    final x = normalized(column(0), 0), rawY = column(1);
    final projection = dot(x, rawY);
    final y = normalized(
      Float64List.fromList([
        for (var i = 0; i < 3; i++) rawY[i] - x[i] * projection,
      ]),
      1,
    );
    final z = Float64List.fromList([
      x[1] * y[2] - x[2] * y[1],
      x[2] * y[0] - x[0] * y[2],
      x[0] * y[1] - x[1] * y[0],
    ]);
    if (dot(z, column(2)) < 0) {
      for (var i = 0; i < 3; i++) z[i] = -z[i];
    }
    rotation = Float64List.fromList([...x, ...y, ...z]);
  }

  final Float32List matrix;
  final Float64List scale;
  final bool worldSpace;
  late final Float64List rotation;
  Float64List rotate(Float64List v) => Float64List.fromList([
    for (var row = 0; row < 3; row++)
      rotation[row] * v[0] +
          rotation[3 + row] * v[1] +
          rotation[6 + row] * v[2],
  ]);
  Float64List inverseRotate(Float64List v) => Float64List.fromList([
    for (var col = 0; col < 3; col++)
      rotation[col * 3] * v[0] +
          rotation[col * 3 + 1] * v[1] +
          rotation[col * 3 + 2] * v[2],
  ]);
  Float64List scaledDirection(Float64List worldDirection) {
    final local = inverseRotate(worldDirection);
    return rotate(
      Float64List.fromList([for (var i = 0; i < 3; i++) local[i] * scale[i]]),
    );
  }

  double scaleAlong(Float64List direction) {
    final v = scaledDirection(direction);
    return math.sqrt(v[0] * v[0] + v[1] * v[1] + v[2] * v[2]);
  }

  Float64List worldOffset(Float64List direction) {
    if (worldSpace) return scaledDirection(direction);
    final v = inverseRotate(direction);
    return Float64List.fromList([
      for (var row = 0; row < 3; row++)
        matrix[row] * v[0] + matrix[4 + row] * v[1] + matrix[8 + row] * v[2],
    ]);
  }

  Float64List localOffset(Float64List v) {
    if (worldSpace) {
      return rotate(
        Float64List.fromList([for (var i = 0; i < 3; i++) v[i] * scale[i]]),
      );
    }
    return Float64List.fromList([
      for (var row = 0; row < 3; row++)
        matrix[row] * v[0] + matrix[4 + row] * v[1] + matrix[8 + row] * v[2],
    ]);
  }
}

/// Particle.rotation3D is the inverse Euler angle on each axis (radians here).
/// Transform/Shape Euler degrees use a separate path.
Float64List authoredParticleRotation(double x, double y, double z) {
  final sx = math.sin(-x / 2),
      cx = math.cos(-x / 2),
      sy = math.sin(-y / 2),
      cy = math.cos(-y / 2),
      sz = math.sin(-z / 2),
      cz = math.cos(-z / 2);
  final qx = sx * cy * cz + cx * sy * sz,
      qy = cx * sy * cz - sx * cy * sz,
      qz = cx * cy * sz - sx * sy * cz,
      qw = cx * cy * cz + sx * sy * sz;
  return Float64List.fromList([
    1 - 2 * qy * qy - 2 * qz * qz,
    2 * qx * qy + 2 * qw * qz,
    2 * qx * qz - 2 * qw * qy,
    2 * qx * qy - 2 * qw * qz,
    1 - 2 * qx * qx - 2 * qz * qz,
    2 * qy * qz + 2 * qw * qx,
    2 * qx * qz + 2 * qw * qy,
    2 * qy * qz - 2 * qw * qx,
    1 - 2 * qx * qx - 2 * qy * qy,
  ]);
}

final class NativeParticleRendererSpec {
  NativeParticleRendererSpec(NativeEffectObject object) {
    if (object.type != 'ParticleSystemRenderer') {
      throw ArgumentError('native_particle_renderer_type');
    }
    data = object.data;
    final mode = data['m_RenderMode'] as int;
    if (mode < 0 || mode > 4) {
      throw UnsupportedError('native_particle_render_mode:$mode');
    }
    renderMode = NativeParticleRenderMode.values[mode];
    minimumSize = (data['m_MinParticleSize'] as num).toDouble();
    maximumSize = (data['m_MaxParticleSize'] as num).toDouble();
    sortingOrder = data['m_SortingOrder'] as int;
    final p = data['m_Pivot'] as Map;
    pivot = Float64List.fromList([
      for (final axis in ['x', 'y', 'z']) (p[axis] as num).toDouble(),
    ]);
  }
  late final Map data;
  late final NativeParticleRenderMode renderMode;
  late final double minimumSize, maximumSize;
  late final int sortingOrder;
  late final Float64List pivot;

  /// Camera basis and system-frame scaling remain independent of billboard axes.
  NativeSpriteGeometry billboard({
    required Float64List center,
    required Float64List size,
    required Float64List cameraPosition,
    required Float64List cameraRight,
    required Float64List cameraUp,
    required Float64List cameraForward,
    required double projectionY,
    required NativeParticleFrame frame,
    required double rotation,
    double rotationX = 0,
    double rotationY = 0,
    required Float32List clipFromWorld,
    double? orthographicSize,
    Float64List? worldVelocity,
  }) {
    if (renderMode == NativeParticleRenderMode.stretchedBillboard) {
      if (worldVelocity == null) {
        throw ArgumentError('particle_stretch_requires_world_velocity');
      }
      return _stretched(
        center: center,
        size: size,
        velocity: worldVelocity,
        cameraPosition: cameraPosition,
        right: cameraRight,
        up: cameraUp,
        forward: cameraForward,
        frame: frame,
        projectionY: projectionY,
        orthographicSize: orthographicSize,
      );
    }
    Float64List cross(Float64List a, Float64List b) => Float64List.fromList([
      a[1] * b[2] - a[2] * b[1],
      a[2] * b[0] - a[0] * b[2],
      a[0] * b[1] - a[1] * b[0],
    ]);
    Float64List unit(Float64List v) {
      final length = math.sqrt(v[0] * v[0] + v[1] * v[1] + v[2] * v[2]);
      return Float64List.fromList([
        for (final x in v) length > 0 ? x / length : 0,
      ]);
    }

    var right = Float64List.fromList(cameraRight),
        up = Float64List.fromList(cameraUp),
        normal = Float64List.fromList([for (final x in cameraForward) -x]);
    switch (renderMode) {
      case NativeParticleRenderMode.verticalBillboard:
        up = Float64List.fromList([0, 1, 0]);
        right = unit(cross(up, cameraForward));
        if (right.every((x) => x == 0)) {
          right = Float64List.fromList(cameraRight);
        }
        normal = cross(up, right);
        break;
      case NativeParticleRenderMode.horizontalBillboard:
        right = Float64List.fromList([1, 0, 0]);
        up = Float64List.fromList([0, 0, 1]);
        normal = Float64List.fromList([0, 1, 0]);
        break;
      case NativeParticleRenderMode.billboard:
        switch (data['m_RenderAlignment']) {
          case 0:
            break;
          case 1:
            right = Float64List.fromList([1, 0, 0]);
            up = Float64List.fromList([0, 1, 0]);
            normal = Float64List.fromList([0, 0, -1]);
            break;
          case 2:
            right = Float64List.fromList(frame.rotation.sublist(0, 3));
            up = Float64List.fromList(frame.rotation.sublist(3, 6));
            normal = Float64List.fromList([
              for (final x in frame.rotation.sublist(6, 9)) -x,
            ]);
            break;
          case 3:
            final facing = unit(
              Float64List.fromList([
                for (var i = 0; i < 3; i++) center[i] - cameraPosition[i],
              ]),
            );
            right = unit(cross(cameraUp, facing));
            up = cross(facing, right);
            normal = Float64List.fromList([for (final x in facing) -x]);
            break;
          default:
            throw UnsupportedError(
              'native_particle_alignment:${data['m_RenderAlignment']}',
            );
        }
        break;
      case NativeParticleRenderMode.mesh:
        throw StateError(
          'native_particle_mesh_requires_original_mesh_geometry',
        );
      case NativeParticleRenderMode.stretchedBillboard:
        throw UnsupportedError(
          'native_stretched_billboard_requires_actual_velocity_frame',
        );
    }
    final c = math.cos(rotation), sine = math.sin(rotation);
    var r2 = Float64List.fromList([
      for (var i = 0; i < 3; i++) right[i] * c - up[i] * sine,
    ]);
    var u2 = Float64List.fromList([
      for (var i = 0; i < 3; i++) right[i] * sine + up[i] * c,
    ]);
    Float64List? forward3D;
    if (rotationX != 0 || rotationY != 0) {
      final columns = authoredParticleRotation(rotationX, rotationY, rotation);
      Float64List axis(int column) => Float64List.fromList([
        for (var i = 0; i < 3; i++)
          right[i] * columns[column * 3] +
              up[i] * columns[column * 3 + 1] -
              normal[i] * columns[column * 3 + 2],
      ]);
      r2 = axis(0);
      u2 = axis(1);
      forward3D = axis(2);
    }
    var sx = size[0], sy = size[1];
    final depth = [
      for (var i = 0; i < 3; i++)
        (center[i] - cameraPosition[i]) * cameraForward[i],
    ].reduce((a, b) => a + b);
    final viewportHeight = orthographicSize == null
        ? 2 * depth / projectionY
        : 2 * orthographicSize;
    final extent = math.max(
      sx.abs() * frame.scaleAlong(r2),
      sy.abs() * frame.scaleAlong(u2),
    );
    if ((maximumSize > 0 || minimumSize > 0) &&
        extent > 0 &&
        viewportHeight > 0) {
      var factor = 1.0;
      if (extent > maximumSize * viewportHeight) {
        factor = maximumSize * viewportHeight / extent;
      } else if (extent < minimumSize * viewportHeight) {
        factor = minimumSize * viewportHeight / extent;
      }
      sx *= factor;
      sy *= factor;
    }
    final flip = data['m_Flip'] as Map;
    if (flip['x'] != 0 || flip['y'] != 0 || flip['z'] != 0) {
      throw UnsupportedError(
        'native_particle_random_renderer_flip_requires_birth_state',
      );
    }
    final positions = Float32List(12);
    for (var vertex = 0; vertex < 4; vertex++) {
      final x = (((vertex & 1) == 0 ? -.5 : .5) + pivot[0]) * sx;
      final y = ((vertex < 2 ? -.5 : .5) + pivot[1]) * sy;
      final z = pivot[2] * size[2];
      final offset = frame.worldOffset(
        Float64List.fromList([
          for (var i = 0; i < 3; i++)
            forward3D == null
                ? r2[i] * x + u2[i] * y - normal[i] * z
                : r2[i] * x + u2[i] * y + forward3D[i] * z,
        ]),
      );
      for (var i = 0; i < 3; i++) {
        positions[vertex * 3 + i] = center[i] + offset[i];
      }
    }
    return NativeSpriteGeometry(
      positions: positions,
      uv: Float32List.fromList([0, 1, 1, 1, 0, 0, 1, 0]),
      indices: Uint16List.fromList([0, 1, 2, 2, 1, 3]),
    );
  }

  NativeSpriteGeometry _stretched({
    required Float64List center,
    required Float64List size,
    required Float64List velocity,
    required Float64List cameraPosition,
    required Float64List right,
    required Float64List up,
    required Float64List forward,
    required NativeParticleFrame frame,
    required double projectionY,
    double? orthographicSize,
  }) {
    if (data['m_FreeformStretching'] == true ||
        data['m_CameraVelocityScale'] != 0 ||
        pivot[2] != 0) {
      throw UnsupportedError('particle_stretch_frame');
    }
    final speed = math.sqrt(velocity.fold<double>(0, (a, b) => a + b * b));
    final direction = Float64List.fromList([
      for (final v in velocity) speed * speed > 1e-30 ? v / speed : 0,
    ]);
    final lift = frame.worldOffset(
      Float64List.fromList([for (final v in direction) v * pivot[1] * size[1]]),
    );
    final length = frame.worldOffset(
      Float64List.fromList([
        for (final v in direction) v * (data['m_LengthScale'] as num) * size[1],
      ]),
    );
    final start = Float64List.fromList([
      for (var i = 0; i < 3; i++) center[i] + lift[i],
    ]);
    final end = Float64List.fromList([
      for (var i = 0; i < 3; i++)
        start[i] - velocity[i] * (data['m_VelocityScale'] as num) - length[i],
    ]);
    double dot(Float64List a, Float64List b) =>
        a[0] * b[0] + a[1] * b[1] + a[2] * b[2];
    Float64List view(Float64List p) {
      final v = Float64List.fromList([
        for (var i = 0; i < 3; i++) p[i] - cameraPosition[i],
      ]);
      return Float64List.fromList([
        dot(v, right),
        dot(v, up),
        -dot(v, forward),
      ]);
    }

    final p = view(start), e = view(end);
    var dx = p[2] * e[1] - p[1] * e[2], dy = p[0] * e[2] - p[2] * e[0];
    final sideLength = math.sqrt(dx * dx + dy * dy);
    if (sideLength > 0) {
      dx /= sideLength;
      dy /= sideLength;
    } else {
      dx = dy = 0;
    }
    final across = Float64List.fromList([
      for (var i = 0; i < 3; i++) right[i] * dx + up[i] * dy,
    ]);
    var halfWidth = size[0] * .5;
    final relative = Float64List.fromList([
      for (var i = 0; i < 3; i++) center[i] - cameraPosition[i],
    ]);
    final viewportHeight = orthographicSize == null
        ? 2 * dot(relative, forward) / projectionY
        : 2 * orthographicSize;
    final extent = (2 * halfWidth).abs() * frame.scaleAlong(across);
    if ((maximumSize > 0 || minimumSize > 0) &&
        extent > 0 &&
        viewportHeight > 0) {
      if (extent > maximumSize * viewportHeight) {
        halfWidth *= maximumSize * viewportHeight / extent;
      } else if (extent < minimumSize * viewportHeight) {
        halfWidth *= minimumSize * viewportHeight / extent;
      }
    }
    final side = frame.worldOffset(
      Float64List.fromList([for (final v in across) v * halfWidth]),
    );
    final positions = Float32List(12);
    for (var vertex = 0; vertex < 4; vertex++) {
      final at = vertex == 1 || vertex == 2 ? end : start;
      final sign = vertex < 2 ? 1 : -1;
      for (var i = 0; i < 3; i++) {
        positions[vertex * 3 + i] = at[i] + side[i] * (pivot[0] + sign);
      }
    }
    return NativeSpriteGeometry(
      positions: positions,
      uv: Float32List.fromList([0, 1, 1, 1, 1, 0, 0, 0]),
      indices: Uint16List.fromList([0, 1, 2, 2, 3, 0]),
    );
  }
}
