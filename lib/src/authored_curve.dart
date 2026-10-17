import 'dart:typed_data';

/// Scalar cubic curves consume actual source keys, slopes and tangent weights.
/// This is independent native mathematics, without shader/program translation.
final class NativeAuthoredCurve {
  factory NativeAuthoredCurve(Map record) =>
      _curves[record] ??= NativeAuthoredCurve._(record);
  NativeAuthoredCurve._(Map record)
    : keys = List.unmodifiable((record['m_Curve'] as List).cast<Map>()),
      _points = List.unmodifiable([
        for (final value in record['m_Curve'] as List)
          _NativeCurveKey(value as Map),
      ]) {
    var previous = double.negativeInfinity;
    for (final key in _points) {
      final time = key.time;
      if (!time.isFinite || time < previous) {
        throw const FormatException('native_curve_key_order');
      }
      previous = time;
    }
  }
  final List<Map> keys;
  final List<_NativeCurveKey> _points;
  double sample(double time) {
    if (_points.isEmpty) return 0;
    if (time <= _points.first.time) {
      return _points.first.value;
    }
    if (time >= _points.last.time) {
      return _points.last.value;
    }
    var low = 0, high = _points.length - 1;
    while (low + 1 < high) {
      final middle = (low + high) ~/ 2;
      if (_points[middle].time <= time) {
        low = middle;
      } else {
        high = middle;
      }
    }
    final left = _points[low], right = _points[high];
    final from = left.value;
    final to = right.value;
    final span = right.time - left.time;
    if (span <= 0) return to;
    final outgoing = left.outSlope;
    final incoming = right.inSlope;
    if (!outgoing.isFinite || !incoming.isFinite) return from;
    final normalized = (time - left.time) / span;
    final outWeighted = (left.weightedMode & 2) != 0;
    final inWeighted = (right.weightedMode & 1) != 0;
    if (!outWeighted && !inWeighted) {
      final t2 = normalized * normalized, t3 = t2 * normalized;
      return (2 * t3 - 3 * t2 + 1) * from +
          (t3 - 2 * t2 + normalized) * outgoing * span +
          (-2 * t3 + 3 * t2) * to +
          (t3 - t2) * incoming * span;
    }
    final w0 = outWeighted ? left.outWeight : 1 / 3;
    final w1 = inWeighted ? right.inWeight : 1 / 3;
    if (w0 < 0 || w0 > 1 || w1 < 0 || w1 > 1) {
      throw const FormatException('native_curve_weight');
    }
    // Invert the monotone Bezier x coordinate before evaluating its y curve.
    var lo = 0.0, hi = 1.0;
    for (var iteration = 0; iteration < 32; iteration++) {
      final middle = (lo + hi) / 2;
      final x = _bezier(0, w0, 1 - w1, 1, middle);
      if (x < normalized) {
        lo = middle;
      } else {
        hi = middle;
      }
    }
    return _bezier(
      from,
      from + outgoing * span * w0,
      to - incoming * span * w1,
      to,
      (lo + hi) / 2,
    );
  }
}

final class _NativeCurveKey {
  _NativeCurveKey(Map value)
    : time = (value['time'] as num).toDouble(),
      value = (value['value'] as num).toDouble(),
      inSlope = (value['inSlope'] as num).toDouble(),
      outSlope = (value['outSlope'] as num).toDouble(),
      weightedMode = value['weightedMode'] as int? ?? 0,
      inWeight = ((value['weightedMode'] as int? ?? 0) & 1) != 0
          ? (value['inWeight'] as num).toDouble()
          : 1 / 3,
      outWeight = ((value['weightedMode'] as int? ?? 0) & 2) != 0
          ? (value['outWeight'] as num).toDouble()
          : 1 / 3;
  final double time, value, inSlope, outSlope, inWeight, outWeight;
  final int weightedMode;
}

double _bezier(double a, double b, double c, double d, double t) {
  final s = 1 - t;
  return s * s * s * a + 3 * s * s * t * b + 3 * s * t * t * c + t * t * t * d;
}

final class NativeAuthoredMinMaxCurve {
  factory NativeAuthoredMinMaxCurve(Map record) =>
      _minMaxCurves[record] ??= NativeAuthoredMinMaxCurve._(record);
  NativeAuthoredMinMaxCurve._(this.record)
    : minimum = NativeAuthoredCurve(record['minCurve'] as Map),
      maximum = NativeAuthoredCurve(record['maxCurve'] as Map),
      _mode = record['minMaxState'],
      _scalarValue = _constructionF32((record['scalar'] as num).toDouble()),
      _minimumScalar = _constructionF32(
        (record['minScalar'] as num).toDouble(),
      );
  final Map record;
  final NativeAuthoredCurve minimum, maximum;
  final Object? _mode;
  final double _scalarValue, _minimumScalar;
  final Float32List _scalar = Float32List(1);
  double _f(double value) {
    _scalar[0] = value;
    return _scalar[0];
  }

  double sample(
    double normalizedTime,
    double actualRandom, {
    double? scalarOverride,
  }) {
    final random = actualRandom.clamp(0.0, 1.0);
    final scalar = scalarOverride == null ? _scalarValue : _f(scalarOverride);
    final minScalar = _minimumScalar;
    if (_mode == 2) {
      final low = _f(minimum.sample(normalizedTime));
      final high = _f(maximum.sample(normalizedTime));
      return _f(scalar * _f(low + (high - low) * random));
    }
    return switch (_mode) {
      0 => scalar,
      1 => _f(scalar * _f(maximum.sample(normalizedTime))),
      3 => _f(minScalar + (scalar - minScalar) * random),
      _ => throw UnsupportedError('native_minmax_curve_mode:$_mode'),
    };
  }
}

final _constructionScalar = Float32List(1);
double _constructionF32(double value) {
  _constructionScalar[0] = value;
  return _constructionScalar[0];
}

final _curves = Expando<NativeAuthoredCurve>('native-authored-curve');
final _minMaxCurves = Expando<NativeAuthoredMinMaxCurve>(
  'native-authored-min-max-curve',
);
