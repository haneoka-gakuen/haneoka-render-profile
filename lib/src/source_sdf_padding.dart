import 'dart:math' as math;
import 'dart:typed_data';

final class SourceSdfUnderlayParameters {
  const SourceSdfUnderlayParameters({
    required this.scaleRatio,
    required this.offsetX,
    required this.offsetY,
    required this.dilate,
    required this.softness,
  });
  final double scaleRatio, offsetX, offsetY, dilate, softness;
}

/// Admitted numeric TMP-compatible padding values, independent of source lookup.
final class SourceSdfPaddingParameters {
  const SourceSdfPaddingParameters({
    required this.scaleRatioA,
    required this.faceDilate,
    required this.outlineWidth,
    required this.outlineSoftness,
    required this.gradientScale,
    required this.style,
    required this.extraPadding,
    required this.underlay,
  });
  final double scaleRatioA, faceDilate, outlineWidth, outlineSoftness;
  final double gradientScale, style;
  final bool extraPadding;
  final SourceSdfUnderlayParameters? underlay;
}

typedef SourceSdfPadding = ({double materialPadding, double stylePadding});

final _single = Float32List(1);
double _f(double value) {
  _single[0] = value;
  return _single[0];
}

SourceSdfPadding computeSourceSdfPadding(SourceSdfPaddingParameters input) {
  final a = input.scaleRatioA;
  final face = _f(input.faceDilate * a);
  final outline = _f(input.outlineWidth * a);
  final softness = _f(input.outlineSoftness * a);
  final uniform = math.max(_f(_f(outline + softness) + face), face);
  final directional = <double>[0, 0, 0, 0];
  final underlay = input.underlay;
  if (underlay != null) {
    final c = underlay.scaleRatio;
    final ox = _f(underlay.offsetX * c);
    final oy = _f(underlay.offsetY * c);
    final base = _f(
      _f(face + _f(underlay.dilate * c)) + _f(underlay.softness * c),
    );
    directional[0] = math.max(0, _f(base - ox));
    directional[1] = math.max(0, _f(base - oy));
    directional[2] = math.max(0, _f(base + ox));
    directional[3] = math.max(0, _f(base + oy));
  }
  final gradient = input.gradientScale;
  final maximum = directional
      .map(
        (p) =>
            math.min(math.max(p, uniform) + (input.extraPadding ? 4 : 0), 1) *
            gradient,
      )
      .reduce(math.max);
  final materialPadding = _f(maximum + 1.25);
  final style = _f(_f(_f(input.style / 4) * gradient) * a);
  final padding = _f(style + materialPadding) > gradient
      ? _f(gradient - style)
      : materialPadding;
  return (materialPadding: padding, stylePadding: style);
}
