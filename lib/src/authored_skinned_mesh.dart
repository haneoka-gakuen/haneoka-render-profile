import 'dart:typed_data';

import 'authored_effect_graph.dart';
import 'projection.dart';

/// A source mesh's packed channels, inverse binds and linear skin weights.
final class AuthoredSkinnedMesh {
  AuthoredSkinnedMesh(Map<String, Object?> source) {
    final vertex = source['m_VertexData'] as Map;
    final count = vertex['m_VertexCount'] as int;
    if (count <= 0 || count > 65535) {
      throw UnsupportedError('authored_skin_vertex_count:$count');
    }
    final channels = (vertex['m_Channels'] as List).cast<Map>();
    final data = ByteData.sublistView(
      Uint8List.fromList((vertex['m_DataSize'] as List).cast<int>()),
    );
    final strides = <int, int>{};
    for (final channel in channels) {
      final dimensions = channel['dimension'] as int;
      if (dimensions == 0) continue;
      final format = channel['format'] as int,
          stream = channel['stream'] as int,
          offset = channel['offset'] as int;
      if ((format != 0 && format != 10) ||
          dimensions < 1 ||
          dimensions > 4 ||
          stream < 0 ||
          offset < 0) {
        throw UnsupportedError('authored_skin_vertex_channel');
      }
      final end = offset + dimensions * 4;
      if (end > (strides[stream] ?? 0)) strides[stream] = end;
    }
    final starts = <int, int>{};
    var cursor = 0;
    for (final stream in strides.keys.toList()..sort()) {
      cursor = (cursor + 15) & ~15;
      starts[stream] = cursor;
      cursor += count * strides[stream]!;
    }
    if (cursor > data.lengthInBytes) {
      throw const FormatException('authored_skin_vertex_bytes');
    }

    Float32List floats(int index, int dimensions) {
      final channel = channels[index];
      if (channel['format'] != 0 || channel['dimension'] != dimensions) {
        throw FormatException('authored_skin_float_channel:$index');
      }
      final stream = channel['stream'] as int,
          offset = channel['offset'] as int,
          values = Float32List(count * dimensions);
      for (var vertex = 0; vertex < count; vertex++) {
        for (var component = 0; component < dimensions; component++) {
          final value = data.getFloat32(
            starts[stream]! +
                vertex * strides[stream]! +
                offset +
                component * 4,
            Endian.little,
          );
          if (!value.isFinite) {
            throw const FormatException('authored_skin_nonfinite_vertex');
          }
          values[vertex * dimensions + component] = value;
        }
      }
      return values;
    }

    _positions = floats(0, 3);
    _uv = floats(4, 2);
    for (var index = 1; index < _uv.length; index += 2) {
      _uv[index] = 1 - _uv[index];
    }
    _influences = channels[12]['dimension'] as int;
    _weights = floats(12, _influences);
    final indicesChannel = channels[13];
    if (indicesChannel['format'] != 10 ||
        indicesChannel['dimension'] != _influences) {
      throw const FormatException('authored_skin_bone_channel');
    }
    _bones = Uint32List(count * _influences);
    final stream = indicesChannel['stream'] as int,
        offset = indicesChannel['offset'] as int;
    for (var vertex = 0; vertex < count; vertex++) {
      for (var influence = 0; influence < _influences; influence++) {
        _bones[vertex * _influences + influence] = data.getUint32(
          starts[stream]! + vertex * strides[stream]! + offset + influence * 4,
          Endian.little,
        );
      }
    }
    _binds = [
      for (final matrix in (source['m_BindPose'] as List).cast<Map>())
        Float32List.fromList([
          for (var column = 0; column < 4; column++)
            for (var row = 0; row < 4; row++)
              (matrix['e$row$column'] as num).toDouble(),
        ]),
    ];
    for (var index = 0; index < _bones.length; index++) {
      if (_weights[index] < 0 ||
          (_weights[index] > 0 && _bones[index] >= _binds.length)) {
        throw const FormatException('authored_skin_bone_reference');
      }
    }
    final submeshes = (source['m_SubMeshes'] as List).cast<Map>();
    if (submeshes.length != 1 || submeshes.single['topology'] != 0) {
      throw UnsupportedError('authored_skin_submeshes');
    }
    final submesh = submeshes.single, format = source['m_IndexFormat'] as int;
    if (format != 0 && format != 1) {
      throw UnsupportedError('authored_skin_index_format:$format');
    }
    final width = format == 0 ? 2 : 4,
        firstByte = submesh['firstByte'] as int,
        indexCount = submesh['indexCount'] as int,
        baseVertex = submesh['baseVertex'] as int,
        indices = ByteData.sublistView(
          Uint8List.fromList((source['m_IndexBuffer'] as List).cast<int>()),
        );
    if (firstByte < 0 ||
        indexCount < 0 ||
        indexCount % 3 != 0 ||
        firstByte + indexCount * width > indices.lengthInBytes) {
      throw const FormatException('authored_skin_index_range');
    }
    _indices = Uint16List(indexCount);
    for (var index = 0; index < indexCount; index++) {
      final offset = firstByte + index * width;
      final value =
          baseVertex +
          (format == 0
              ? indices.getUint16(offset, Endian.little)
              : indices.getUint32(offset, Endian.little));
      if (value < 0 || value >= count) {
        throw const FormatException('authored_skin_index_vertex');
      }
      _indices[index] = value;
    }
  }

  late final Float32List _positions, _uv, _weights;
  late final Uint32List _bones;
  late final Uint16List _indices;
  late final List<Float32List> _binds;
  late final int _influences;

  int get boneCount => _binds.length;

  /// World matrices use the serialized SkinnedMeshRenderer bone order.
  NativeSpriteGeometry pose(List<Float32List> boneWorldMatrices) {
    if (boneWorldMatrices.length != _binds.length) {
      throw const FormatException('authored_skin_pose_count');
    }
    final matrices = [
      for (var index = 0; index < _binds.length; index++)
        NativeAuthoredEffectGraph.multiply(
          boneWorldMatrices[index],
          _binds[index],
        ),
    ];
    final positions = Float32List(_positions.length);
    for (var vertex = 0; vertex < positions.length ~/ 3; vertex++) {
      final offset = vertex * 3,
          x = _positions[offset],
          y = _positions[offset + 1],
          z = _positions[offset + 2];
      var sum = 0.0, sx = 0.0, sy = 0.0, sz = 0.0;
      for (var influence = 0; influence < _influences; influence++) {
        final index = vertex * _influences + influence,
            weight = _weights[index];
        if (weight == 0) continue;
        final matrix = matrices[_bones[index]];
        sum += weight;
        sx +=
            weight *
            (matrix[0] * x + matrix[4] * y + matrix[8] * z + matrix[12]);
        sy +=
            weight *
            (matrix[1] * x + matrix[5] * y + matrix[9] * z + matrix[13]);
        sz +=
            weight *
            (matrix[2] * x + matrix[6] * y + matrix[10] * z + matrix[14]);
      }
      if (!sum.isFinite || sum <= 0) {
        throw const FormatException('authored_skin_vertex_weights');
      }
      positions[offset] = sx / sum;
      positions[offset + 1] = sy / sum;
      positions[offset + 2] = sz / sum;
    }
    return NativeSpriteGeometry(
      positions: positions,
      uv: _uv,
      indices: _indices,
    );
  }
}
