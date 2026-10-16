import 'dart:math' as math;
import 'dart:typed_data';

import 'authored_gradient.dart';
import 'projection.dart';

/// Source UIGradientImage colours vertices while retaining Sprite UV/alpha.
/// Triangle splits preserve independent colour/alpha key boundaries.
GeometryBuffer projectNativeCanvasGradient({
  required NativeSpriteGeometry shape,
  required Float32List clip,
  required Map source,
  required List<double> imageColor,
  required double inheritedOpacity,
}) {
  final keys = source['_gradient'] as Map,
      gradient = NativeAuthoredGradient(keys);
  final angle = (source['_angleDeg'] as num) * math.pi / 180,
      dx = math.cos(angle),
      dy = math.sin(angle);
  var min = double.infinity, max = double.negativeInfinity;
  for (var i = 0; i < shape.positions.length; i += 3) {
    final d = shape.positions[i] * dx + shape.positions[i + 1] * dy;
    min = math.min(min, d);
    max = math.max(max, d);
  }
  final span = max - min;
  final stops = <double>{
    0,
    1,
    for (var i = 0; i < (keys['m_NumColorKeys'] as int); i++)
      (keys['ctime$i'] as num) / 65535,
    for (var i = 0; i < (keys['m_NumAlphaKeys'] as int); i++)
      (keys['atime$i'] as num) / 65535,
  }.toList()..sort();
  final vertices = <double>[], indices = <int>[];
  List<double> vertex(int id) => [
    shape.positions[id * 3],
    shape.positions[id * 3 + 1],
    shape.positions[id * 3 + 2],
    shape.uv[id * 2],
    shape.uv[id * 2 + 1],
  ];
  double time(List<double> p) =>
      span == 0 ? 0 : (p[0] * dx + p[1] * dy - min) / span;
  List<List<double>> cut(
    List<List<double>> polygon,
    double boundary,
    bool lower,
  ) {
    final result = <List<double>>[];
    if (polygon.isEmpty) return result;
    var previous = polygon.last,
        previousTime = time(previous),
        previousInside = lower
            ? previousTime >= boundary
            : previousTime <= boundary;
    for (final point in polygon) {
      final currentTime = time(point),
          inside = lower ? currentTime >= boundary : currentTime <= boundary;
      if (inside != previousInside) {
        final t = (boundary - previousTime) / (currentTime - previousTime);
        result.add([
          for (var k = 0; k < 5; k++)
            previous[k] + (point[k] - previous[k]) * t,
        ]);
      }
      if (inside) result.add(point);
      previous = point;
      previousTime = currentTime;
      previousInside = inside;
    }
    return result;
  }

  for (var triangle = 0; triangle < shape.indices.length; triangle += 3) {
    final original = [
      for (var i = 0; i < 3; i++) vertex(shape.indices[triangle + i]),
    ];
    for (var interval = 0; interval < stops.length - 1; interval++) {
      final polygon = cut(
        cut(original, stops[interval], true),
        stops[interval + 1],
        false,
      );
      if (polygon.length < 3) continue;
      final base = vertices.length ~/ 10;
      for (final p in polygon) {
        final rgba = gradient.sample(time(p));
        for (var row = 0; row < 4; row++)
          vertices.add(
            clip[row] * p[0] +
                clip[4 + row] * p[1] +
                clip[8 + row] * p[2] +
                clip[12 + row],
          );
        vertices.addAll([
          p[3],
          p[4],
          for (var c = 0; c < 4; c++)
            rgba[c] *
                (source['_blendMode'] == 1 ? imageColor[c] : 1) *
                (c == 3 ? inheritedOpacity : 1),
        ]);
      }
      for (var i = 1; i < polygon.length - 1; i++)
        indices.addAll([base, base + i, base + i + 1]);
    }
  }
  return GeometryBuffer(
    Float32List.fromList(vertices),
    Uint16List.fromList(indices),
  );
}
