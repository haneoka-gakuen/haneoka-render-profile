import 'dart:typed_data';

import 'projection.dart';

/// Reads Haneoka's existing bundled note-skin projection, preserving tight mesh.
/// Atlas size comes from the actual decoded atlas image, not assumed dimensions.
NativeAtlasRegion readProjectedAtlasRegion(
  Map<String, Object?> document,
  String name,
  int textureWidth,
  int textureHeight,
) {
  if (textureWidth <= 0 || textureHeight <= 0) {
    throw ArgumentError('native_atlas_size');
  }
  Map map(Object? value) =>
      value is Map ? value : throw FormatException('native_atlas_object');
  double number(Object? value) => value is num && value.isFinite
      ? value.toDouble()
      : throw FormatException('native_atlas_number');
  final sprites = map(document['sprites']);
  final sprite = map(map(sprites[name])['data']);
  final key = sprite['m_RenderDataKey'];
  bool sameKey(Object? a, Object? b) {
    if (a is! List ||
        b is! List ||
        a.length != 2 ||
        b.length != 2 ||
        a[0] is! Map ||
        b[0] is! Map) {
      return false;
    }
    for (final field in ['data[0]', 'data[1]', 'data[2]', 'data[3]']) {
      if ((a[0] as Map)[field] != (b[0] as Map)[field]) return false;
    }
    return a[1] == b[1];
  }

  final records = map(map(document['atlas'])['data'])['m_RenderDataMap'];
  if (records is! List) throw FormatException('native_atlas_records');
  Map? packed;
  for (final record in records) {
    if (record is List && record.length == 2 && sameKey(record[0], key)) {
      if (packed != null) throw FormatException('native_atlas_duplicate_key');
      packed = map(record[1]);
    }
  }
  if (packed == null) {
    throw FormatException('native_atlas_sprite_missing:$name');
  }
  final mesh = map(map(sprite['originalRenderData'])['mesh']);
  final positions = mesh['positions'];
  final indices = mesh['indices'];
  if (positions is! List || indices is! List || positions.length > 65535) {
    throw FormatException('native_atlas_mesh');
  }
  final rect = map(sprite['m_Rect']);
  final pivot = map(sprite['m_Pivot']);
  final atlasRect = map(packed['textureRect']);
  final offset = map(packed['textureRectOffset']);
  final ppu = number(sprite['m_PixelsToUnits']);
  final width = number(rect['width']), height = number(rect['height']);
  final rw = number(atlasRect['width']), rh = number(atlasRect['height']);
  if (ppu <= 0 || width <= 0 || height <= 0 || rw <= 0 || rh <= 0) {
    throw FormatException('native_atlas_extent');
  }
  final raw = packed['settingsRaw'];
  if (raw is! int) throw FormatException('native_atlas_packing');
  final rotation = (raw >> 2) & 15;
  if (rotation > 4) throw UnsupportedError('native_atlas_packing:$rotation');
  final tightWidth = rotation == 4 ? rh : rw;
  final tightHeight = rotation == 4 ? rw : rh;
  final xyz = Float32List(positions.length * 3),
      uv = Float32List(positions.length * 2);
  for (var i = 0; i < positions.length; i++) {
    final position = positions[i];
    if (position is! List || position.length != 3) {
      throw FormatException('native_atlas_position');
    }
    final x = number(position[0]), y = number(position[1]);
    xyz[i * 3] = x;
    xyz[i * 3 + 1] = y;
    xyz[i * 3 + 2] = number(position[2]);
    final u =
        (x * ppu + number(pivot['x']) * width - number(offset['x'])) /
        tightWidth;
    final v =
        (y * ppu + number(pivot['y']) * height - number(offset['y'])) /
        tightHeight;
    final cu = u.clamp(0.0, 1.0), cv = v.clamp(0.0, 1.0);
    final (double pu, double pv) = switch (rotation) {
      1 => (1 - cu, cv),
      2 => (cu, 1 - cv),
      3 => (1 - cu, 1 - cv),
      4 => (1 - cv, cu),
      _ => (cu, cv),
    };
    uv[i * 2] = (number(atlasRect['x']) + pu * rw) / textureWidth;
    // Unity atlas coordinates are bottom-up; decoded PNG rows are top-down.
    uv[i * 2 + 1] = 1 - (number(atlasRect['y']) + pv * rh) / textureHeight;
  }
  final triangles = Uint16List(indices.length);
  for (var i = 0; i < indices.length; i++) {
    final index = indices[i];
    if (index is! int || index < 0 || index >= positions.length) {
      throw FormatException('native_atlas_index');
    }
    triangles[i] = index;
  }
  return NativeAtlasRegion(
    geometry: NativeSpriteGeometry(positions: xyz, uv: uv, indices: triangles),
    pixelsPerUnit: ppu,
    tightWidth: tightWidth,
    tightHeight: tightHeight,
    sourceWidth: width,
    sourceHeight: height,
    pivotX: number(pivot['x']),
    pivotY: number(pivot['y']),
    offsetX: number(offset['x']),
    offsetY: number(offset['y']),
    atlasX: number(atlasRect['x']),
    atlasY: number(atlasRect['y']),
    packedWidth: rw,
    packedHeight: rh,
    textureWidth: textureWidth,
    textureHeight: textureHeight,
    rotation: rotation,
    borderLeft: number(map(sprite['m_Border'])['x']),
    borderRight: number(map(sprite['m_Border'])['z']),
  );
}

NativeSpriteGeometry readProjectedAtlasSprite(
  Map<String, Object?> document,
  String name,
  int width,
  int height,
) => readProjectedAtlasRegion(document, name, width, height).geometry;

final class NativeAtlasRegion {
  const NativeAtlasRegion({
    required this.geometry,
    required this.pixelsPerUnit,
    required this.tightWidth,
    required this.tightHeight,
    required this.sourceWidth,
    required this.sourceHeight,
    required this.pivotX,
    required this.pivotY,
    required this.offsetX,
    required this.offsetY,
    required this.atlasX,
    required this.atlasY,
    required this.packedWidth,
    required this.packedHeight,
    required this.textureWidth,
    required this.textureHeight,
    required this.rotation,
    required this.borderLeft,
    required this.borderRight,
  });
  final NativeSpriteGeometry geometry;
  final double pixelsPerUnit,
      tightWidth,
      tightHeight,
      sourceWidth,
      sourceHeight,
      pivotX,
      pivotY,
      offsetX,
      offsetY,
      atlasX,
      atlasY,
      packedWidth,
      packedHeight,
      borderLeft,
      borderRight;
  final int textureWidth, textureHeight, rotation;
  double get width => tightWidth / pixelsPerUnit;
  double get height => tightHeight / pixelsPerUnit;
  double get centerX =>
      (offsetX + tightWidth / 2 - pivotX * sourceWidth) / pixelsPerUnit;
  double get centerY =>
      (offsetY + tightHeight / 2 - pivotY * sourceHeight) / pixelsPerUnit;
  (double, double) uvAt(double u, double v) {
    final (pu, pv) = switch (rotation) {
      1 => (1 - u, v),
      2 => (u, 1 - v),
      3 => (1 - u, 1 - v),
      4 => (1 - v, u),
      _ => (u, v),
    };
    return (
      (atlasX + pu * packedWidth) / textureWidth,
      1 - (atlasY + pv * packedHeight) / textureHeight,
    );
  }
}
