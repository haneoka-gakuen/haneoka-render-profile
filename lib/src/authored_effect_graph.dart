import 'dart:typed_data';

import 'projection.dart';

/// Original serialized-file identity is part of every component key. External
/// PPtrs resolve through their recorded reference, never a rounded JS number.
final class NativeEffectObject {
  NativeEffectObject(this.path, Map row)
    : hash = row['sha256'] as String,
      record = Map<String, Object?>.from(row['record'] as Map) {
    if (row['normalization'] != 'pptr-decimal64-v1') {
      throw FormatException('native_effect_identity_normalization:$path');
    }
  }
  final String path, hash;
  final Map<String, Object?> record;
  String get serializedFile => record['serializedFile'] as String;
  String get id => record['pathId'].toString();
  String get key => '$serializedFile:$id';
  String get type => record['type'] as String;
  Map get data => record['data'] as Map;
}

final class NativeAuthoredEffectGraph {
  NativeAuthoredEffectGraph(Map source) {
    if (source['schema'] != 'haneoka-native-fx-shared-render-data-v1') {
      throw const FormatException('native_effect_graph_schema');
    }
    for (final entry in (source['objects'] as Map).entries) {
      final object = NativeEffectObject(
        entry.key as String,
        entry.value as Map,
      );
      if (objects.containsKey(object.key)) {
        throw FormatException('native_effect_duplicate_identity:${object.key}');
      }
      objects[object.key] = object;
      paths[object.path] = object;
      _index(object);
    }
  }
  final objects = <String, NativeEffectObject>{};
  final paths = <String, NativeEffectObject>{};
  final equivalentSourceHashes = <String, Set<String>>{};
  final _transformsByGameObject = <String, List<NativeEffectObject>>{};
  void _index(NativeEffectObject object) {
    if (object.type != 'Transform' && object.type != 'RectTransform') return;
    final pointer = object.data['m_GameObject'] as Map;
    if (pointer['m_FileID'] != 0 || pointer['m_PathID'] is! String) {
      throw FormatException(
        'native_effect_transform_go_identity:${object.key}',
      );
    }
    (_transformsByGameObject['${object.serializedFile}:${pointer['m_PathID']}'] ??=
            [])
        .add(object);
  }

  void mergeNormalizedRecords(Map rows) {
    for (final entry in rows.entries) {
      final object = NativeEffectObject(
        entry.key as String,
        entry.value as Map,
      );
      final existing = objects[object.key];
      if (existing != null) {
        if (existing.type != object.type ||
            !_sameRecord(existing.record, object.record)) {
          throw StateError(
            'native_effect_shared_source_conflict:${object.key}',
          );
        }
        (equivalentSourceHashes[object.key] ??= {
          existing.hash,
        }).add(object.hash);
        paths[object.path] = existing;
      } else {
        objects[object.key] = object;
        paths[object.path] = object;
        _index(object);
      }
    }
  }

  static bool _sameRecord(Object? a, Object? b) {
    if (a is Map && b is Map) {
      return a.length == b.length &&
          a.keys.every(
            (key) => b.containsKey(key) && _sameRecord(a[key], b[key]),
          );
    }
    if (a is List && b is List) {
      if (a.length != b.length) return false;
      for (var i = 0; i < a.length; i++) {
        if (!_sameRecord(a[i], b[i])) return false;
      }
      return true;
    }
    return a == b;
  }

  NativeEffectObject? reference(NativeEffectObject owner, Map pointer) {
    final id = pointer['m_PathID'];
    if (id is! String) {
      throw FormatException(
        'native_effect_pptr_requires_decimal_string:${owner.key}',
      );
    }
    if (id == '0') return null;
    final fileId = pointer['m_FileID'] as int;
    final external = pointer['reference'] as Map?;
    if (fileId != 0 &&
        (external == null ||
            external['status'] != 'resolved' ||
            external['pathId'] != id)) {
      throw StateError('native_effect_external_identity:${owner.key}:$id');
    }
    final file = fileId == 0
        ? owner.serializedFile
        : external?['serializedFile'] as String?;
    if (file == null) {
      throw StateError(
        'native_effect_external_reference_missing:${owner.key}:$id',
      );
    }
    final found = objects['$file:$id'];
    if (found == null) {
      throw StateError(
        'native_effect_component_not_in_source_closure:$file:$id',
      );
    }
    if (fileId != 0 && external!['type'] != found.type) {
      throw StateError('native_effect_external_type:${owner.key}:$id');
    }
    return found;
  }

  NativeEffectObject gameObject(NativeEffectObject component) =>
      reference(component, component.data['m_GameObject'] as Map)!;

  List<NativeEffectObject> components(NativeEffectObject gameObject) => [
    for (final item in gameObject.data['m_Component'] as List)
      reference(gameObject, (item as Map)['component'] as Map)!,
  ];

  NativeEffectObject transform(NativeEffectObject component) {
    final go = component.type == 'GameObject'
        ? component
        : gameObject(component);
    final matching =
        _transformsByGameObject[go.key] ?? const <NativeEffectObject>[];
    if (matching.length != 1) {
      throw StateError(
        'native_effect_transform_count:${go.key}:${matching.length}',
      );
    }
    final listed = (go.data['m_Component'] as List).any((raw) {
      final pointer = (raw as Map)['component'] as Map;
      return pointer['m_FileID'] == 0 &&
          pointer['m_PathID'] == matching.single.id;
    });
    if (!listed) {
      throw StateError('native_effect_transform_not_listed:${go.key}');
    }
    return matching.single;
  }

  List<NativeEffectObject> selectedComponents(
    NativeEffectObject go, {
    String? type,
  }) {
    if (go.type != 'GameObject') {
      throw ArgumentError('native_effect_component_owner_type');
    }
    final selected = <NativeEffectObject>[];
    for (final raw in go.data['m_Component'] as List) {
      final pointer = (raw as Map)['component'] as Map;
      if (pointer['m_FileID'] != 0) {
        throw UnsupportedError('native_effect_external_component_owner');
      }
      final object = objects['${go.serializedFile}:${pointer['m_PathID']}'];
      if (object != null && (type == null || object.type == type)) {
        selected.add(object);
      }
    }
    return List.unmodifiable(selected);
  }

  NativeEffectObject rootTransform(NativeEffectObject component) {
    var node =
        component.type == 'Transform' || component.type == 'RectTransform'
        ? component
        : transform(component);
    final seen = <String>{};
    while (seen.add(node.key)) {
      final parent = reference(node, node.data['m_Father'] as Map);
      if (parent == null) return node;
      node = parent;
    }
    throw StateError('native_effect_transform_cycle:${node.key}');
  }

  String relativePath(NativeEffectObject node, NativeEffectObject root) {
    final names = <String>[], seen = <String>{};
    while (node.key != root.key && seen.add(node.key)) {
      names.add(gameObject(node).data['m_Name'] as String);
      final parent = reference(node, node.data['m_Father'] as Map);
      if (parent == null) {
        throw StateError('native_effect_node_outside_root:${node.key}');
      }
      node = parent;
    }
    if (node.key != root.key) {
      throw StateError('native_effect_transform_cycle:${node.key}');
    }
    return names.reversed.join('/');
  }

  List<NativeEffectObject> descendants(NativeEffectObject root) {
    final result = <NativeEffectObject>[], seen = <String>{}, pending = [root];
    while (pending.isNotEmpty) {
      final node = pending.removeLast();
      if (!seen.add(node.key)) {
        throw StateError('native_effect_transform_cycle:${node.key}');
      }
      result.add(node);
      final children = [
        for (final pointer in node.data['m_Children'] as List)
          reference(node, pointer as Map)!,
      ];
      pending.addAll(children.reversed);
    }
    return List.unmodifiable(result);
  }

  Float32List localMatrix(
    NativeEffectObject transform, {
    Float32List? positionOverride,
    Float32List? scaleOverride,
  }) {
    final data = transform.data;
    final position = data['m_LocalPosition'] as Map,
        scale = data['m_LocalScale'] as Map,
        rotation = data['m_LocalRotation'] as Map;
    double n(Map value, String field) => (value[field] as num).toDouble();
    final x = n(rotation, 'x'),
        y = n(rotation, 'y'),
        z = n(rotation, 'z'),
        w = n(rotation, 'w'),
        sx = scaleOverride?[0] ?? n(scale, 'x'),
        sy = scaleOverride?[1] ?? n(scale, 'y'),
        sz = scaleOverride?[2] ?? n(scale, 'z');
    return Float32List.fromList([
      (1 - 2 * y * y - 2 * z * z) * sx,
      (2 * x * y + 2 * w * z) * sx,
      (2 * x * z - 2 * w * y) * sx,
      0,
      (2 * x * y - 2 * w * z) * sy,
      (1 - 2 * x * x - 2 * z * z) * sy,
      (2 * y * z + 2 * w * x) * sy,
      0,
      (2 * x * z + 2 * w * y) * sz,
      (2 * y * z - 2 * w * x) * sz,
      (1 - 2 * x * x - 2 * y * y) * sz,
      0,
      positionOverride?[0] ?? n(position, 'x'),
      positionOverride?[1] ?? n(position, 'y'),
      positionOverride?[2] ?? n(position, 'z'),
      1,
    ]);
  }

  Float32List worldMatrix(
    NativeEffectObject transform, {
    Map<String, Float32List> positions = const {},
    Map<String, Float32List> scales = const {},
  }) {
    final visited = <String>{};
    Float32List walk(NativeEffectObject node) {
      if (!visited.add(node.key)) {
        throw StateError('native_effect_transform_cycle:${node.key}');
      }
      final local = localMatrix(
        node,
        positionOverride: positions[node.key],
        scaleOverride: scales[node.key],
      );
      final parent = reference(node, node.data['m_Father'] as Map);
      return parent == null ? local : multiply(walk(parent), local);
    }

    return walk(transform);
  }

  /// Original quaternion hierarchy, independent of scale and affine shear.
  Float64List worldRotation(NativeEffectObject transform) {
    final visited = <String>{};
    Float64List walk(NativeEffectObject node) {
      if (!visited.add(node.key)) {
        throw StateError('native_effect_transform_cycle:${node.key}');
      }
      final raw = node.data['m_LocalRotation'] as Map;
      final local = Float64List.fromList([
        for (final axis in ['x', 'y', 'z', 'w']) (raw[axis] as num).toDouble(),
      ]);
      final parent = reference(node, node.data['m_Father'] as Map);
      if (parent == null) return local;
      final p = walk(parent), x = p[0], y = p[1], z = p[2], w = p[3];
      final a = local[0], b = local[1], c = local[2], d = local[3];
      return Float64List.fromList([
        w * a + x * d + y * c - z * b,
        w * b - x * c + y * d + z * a,
        w * c + x * b - y * a + z * d,
        w * d - x * a - y * b - z * c,
      ]);
    }

    return walk(transform);
  }

  static Float32List multiply(Float32List a, Float32List b) {
    final result = Float32List(16);
    for (var column = 0; column < 4; column++) {
      for (var row = 0; row < 4; row++) {
        var value = 0.0;
        for (var k = 0; k < 4; k++) {
          value += a[k * 4 + row] * b[column * 4 + k];
        }
        result[column * 4 + row] = value;
      }
    }
    return result;
  }

  /// Vertex channels are decoded from the original byte streams. Each stream
  /// starts on the serialized 16-byte boundary; unsupported formats stay errors.
  NativeSpriteGeometry spriteGeometry(
    NativeEffectObject sprite, {
    (int, int)? textureSize,
  }) {
    final rd = sprite.type == 'Sprite'
        ? sprite.data['m_RD'] as Map
        : sprite.data;
    if (sprite.type != 'Sprite' && sprite.type != 'Mesh') {
      throw ArgumentError('native_effect_geometry_type:${sprite.type}');
    }
    if (sprite.type == 'Mesh' && rd['m_IndexFormat'] != 0) {
      throw UnsupportedError(
        'native_effect_mesh_index_format:${rd['m_IndexFormat']}',
      );
    }
    final vertices = rd['m_VertexData'] as Map;
    final count = vertices['m_VertexCount'] as int,
        channels = vertices['m_Channels'] as List;
    final bytes = Uint8List.fromList(
      (vertices['m_DataSize'] as List).cast<int>(),
    );
    final data = ByteData.sublistView(bytes), strides = <int, int>{};
    for (final raw in channels) {
      final channel = raw as Map,
          dimension = (channel['dimension'] as int) & 15;
      if (dimension == 0) continue;
      if (channel['format'] != 0) {
        throw UnsupportedError(
          'native_sprite_vertex_format:${channel['format']}',
        );
      }
      final stream = channel['stream'] as int,
          end = (channel['offset'] as int) + dimension * 4;
      if (end > (strides[stream] ?? 0)) strides[stream] = end;
    }
    final starts = <int, int>{};
    var cursor = 0;
    for (final stream in strides.keys.toList()..sort()) {
      starts[stream] = cursor;
      cursor = (cursor + strides[stream]! * count + 15) & ~15;
    }
    Float32List read(int index, int dimensions) {
      final channel = channels[index] as Map;
      if (((channel['dimension'] as int) & 15) != dimensions) {
        throw StateError('native_sprite_channel:$index');
      }
      final stream = channel['stream'] as int,
          output = Float32List(count * dimensions);
      for (var vertex = 0; vertex < count; vertex++) {
        for (var axis = 0; axis < dimensions; axis++) {
          output[vertex * dimensions + axis] = data.getFloat32(
            starts[stream]! +
                vertex * strides[stream]! +
                (channel['offset'] as int) +
                axis * 4,
            Endian.little,
          );
        }
      }
      return output;
    }

    final indexBytes = Uint8List.fromList(
      (rd['m_IndexBuffer'] as List).cast<int>(),
    );
    final indices = Uint16List(indexBytes.length ~/ 2),
        indexData = ByteData.sublistView(indexBytes);
    for (var i = 0; i < indices.length; i++) {
      indices[i] = indexData.getUint16(i * 2, Endian.little);
    }
    final positions = read(0, 3), uv = read(4, 2);
    if (sprite.type == 'Sprite') {
      if (textureSize == null || textureSize.$1 <= 0 || textureSize.$2 <= 0) {
        throw ArgumentError('native_authored_sprite_texture_dimensions');
      }
      final transform = rd['uvTransform'] as Map;
      for (var vertex = 0; vertex < count; vertex++) {
        uv[vertex * 2] =
            ((positions[vertex * 3] * (transform['x'] as num)) +
                (transform['y'] as num)) /
            textureSize.$1;
        uv[vertex * 2 + 1] =
            1 -
            ((positions[vertex * 3 + 1] * (transform['z'] as num)) +
                    (transform['w'] as num)) /
                textureSize.$2;
      }
    } else {
      for (var vertex = 0; vertex < count; vertex++) {
        uv[vertex * 2 + 1] = 1 - uv[vertex * 2 + 1];
      }
    }
    return NativeSpriteGeometry(positions: positions, uv: uv, indices: indices);
  }
}
