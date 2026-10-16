import 'dart:math' as math;
import 'dart:typed_data';

import 'projection.dart';

/// Original Sprite borders remain fixed in source units; only its centre
/// stretches. Target boxes smaller than opposing borders shrink them together.
NativeSpriteGeometry nativeAuthoredSlicedSprite(
  Map source, {
  required double width,
  required double height,
  required int textureWidth,
  required int textureHeight,
  bool fillCenter = true,
}) {
  if (width < 0 || height < 0 || textureWidth <= 0 || textureHeight <= 0) {
    throw ArgumentError('native_sliced_sprite_dimensions');
  }
  final rect = source['m_Rect'] as Map,
      rd = source['m_RD'] as Map,
      tr = rd['textureRect'] as Map,
      offset = rd['textureRectOffset'] as Map;
  final border = source['m_Border'] as Map, pivot = source['m_Pivot'] as Map;
  final units = (source['m_PixelsToUnits'] as num).toDouble();
  if (units <= 0) throw const FormatException('native_sprite_pixels_to_units');
  double b(String field) => (border[field] as num).toDouble();
  final l = b('x') / units,
      bottom = b('y') / units,
      r = b('z') / units,
      t = b('w') / units;
  final sx = l + r > 0 ? math.min(1.0, width / (l + r)) : 1.0,
      sy = bottom + t > 0 ? math.min(1.0, height / (bottom + t)) : 1.0;
  final x0 = -(pivot['x'] as num) * width, y0 = -(pivot['y'] as num) * height;
  final xs = [x0, x0 + l * sx, x0 + width - r * sx, x0 + width],
      ys = [y0, y0 + bottom * sy, y0 + height - t * sy, y0 + height];
  final fullWidth = (rect['width'] as num).toDouble(),
      fullHeight = (rect['height'] as num).toDouble();
  final sourceX = [0.0, b('x'), fullWidth - b('z'), fullWidth],
      sourceY = [0.0, b('y'), fullHeight - b('w'), fullHeight];
  final trimX = (offset['x'] as num).toDouble(),
      trimY = (offset['y'] as num).toDouble(),
      trimRight = trimX + (tr['width'] as num),
      trimTop = trimY + (tr['height'] as num);
  final positions = <double>[], uv = <double>[], indices = <int>[];
  for (var row = 0; row < 3; row++) {
    for (var col = 0; col < 3; col++) {
      if (!fillCenter && row == 1 && col == 1) continue;
      final left = math.max(sourceX[col], trimX),
          right = math.min(sourceX[col + 1], trimRight),
          bottom = math.max(sourceY[row], trimY),
          top = math.min(sourceY[row + 1], trimTop);
      if (right <= left || top <= bottom) continue;
      double map(
        double value,
        List<double> original,
        List<num> target,
        int cell,
      ) =>
          target[cell] +
          (target[cell + 1] - target[cell]) *
              (value - original[cell]) /
              (original[cell + 1] - original[cell]);
      final xLeft = map(left, sourceX, xs, col),
          xRight = map(right, sourceX, xs, col),
          yBottom = map(bottom, sourceY, ys, row),
          yTop = map(top, sourceY, ys, row);
      if (xRight <= xLeft || yTop <= yBottom) continue;
      final uLeft = ((tr['x'] as num) + left - trimX) / textureWidth,
          uRight = ((tr['x'] as num) + right - trimX) / textureWidth,
          vBottom = 1 - ((tr['y'] as num) + bottom - trimY) / textureHeight,
          vTop = 1 - ((tr['y'] as num) + top - trimY) / textureHeight;
      final base = positions.length ~/ 3;
      positions.addAll([
        xLeft,
        yBottom,
        0,
        xRight,
        yBottom,
        0,
        xLeft,
        yTop,
        0,
        xRight,
        yTop,
        0,
      ]);
      uv.addAll([uLeft, vBottom, uRight, vBottom, uLeft, vTop, uRight, vTop]);
      indices.addAll([base, base + 1, base + 2, base + 2, base + 1, base + 3]);
    }
  }
  return NativeSpriteGeometry(
    positions: Float32List.fromList(positions),
    uv: Float32List.fromList(uv),
    indices: Uint16List.fromList(indices),
  );
}
