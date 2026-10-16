/// Packed particle colour channels are quantized at birth and after tinting.
double quantizeAuthoredParticleChannel(double value) =>
    (value.clamp(0.0, 1.0) * 255).round() / 255;

/// Independent numeric gradient sampling. Colour and alpha have separate key
/// times; the source's colour-space tag remains available to material producers.
final class NativeAuthoredGradient {
  factory NativeAuthoredGradient(Map record) =>
      _gradients[record] ??= NativeAuthoredGradient._(record);
  NativeAuthoredGradient._(this.record) {
    final colorCount = record['m_NumColorKeys'] as int;
    final alphaCount = record['m_NumAlphaKeys'] as int;
    for (final count in [colorCount, alphaCount]) {
      if (count < 1 || count > 8) {
        throw FormatException('native_gradient_key_count:$count');
      }
    }
    _mode = record['m_Mode'];
    _colorSpace = record['m_ColorSpace'] as int?;
    _colors = List.unmodifiable([
      for (
        var i = 0;
        i < (colorCount > alphaCount ? colorCount : alphaCount);
        i++
      )
        List<double>.unmodifiable([
          for (final channel in const ['r', 'g', 'b', 'a'])
            ((record['key$i'] as Map)[channel] as num).toDouble(),
        ]),
    ]);
    _colorTimes = List.unmodifiable([
      for (var i = 0; i < colorCount; i++)
        (record['ctime$i'] as num).toDouble(),
    ]);
    _alphaTimes = List.unmodifiable([
      for (var i = 0; i < alphaCount; i++)
        (record['atime$i'] as num).toDouble(),
    ]);
  }
  final Map record;
  late final Object? _mode;
  late final int? _colorSpace;
  late final List<List<double>> _colors;
  late final List<double> _colorTimes, _alphaTimes;
  int get colorSpace => _colorSpace!;
  List<double> sample(double position) {
    final rgb = _keys(position, _colorTimes);
    final alpha = _keys(position, _alphaTimes);
    return [rgb[0], rgb[1], rgb[2], alpha[3]];
  }

  List<double> _keys(double position, List<double> times) {
    final time = position.clamp(0.0, 1.0) * 65535;
    if (time <= times.first) return _colors.first;
    for (var i = 1; i < times.length; i++) {
      final end = times[i];
      if (time > end) continue;
      final begin = times[i - 1];
      final a = _colors[i - 1], b = _colors[i];
      if (_mode == 1) return a;
      final amount = end <= begin ? 1.0 : (time - begin) / (end - begin);
      return [
        for (var channel = 0; channel < 4; channel++)
          a[channel] + (b[channel] - a[channel]) * amount,
      ];
    }
    return _colors[times.length - 1];
  }
}

final class NativeAuthoredMinMaxGradient {
  factory NativeAuthoredMinMaxGradient(Map record) =>
      _minMaxGradients[record] ??= NativeAuthoredMinMaxGradient._(record);
  NativeAuthoredMinMaxGradient._(this.record) : _mode = record['minMaxState'] {
    List<double> color(String name) {
      final value = record[name] as Map;
      return List.unmodifiable([
        for (final channel in const ['r', 'g', 'b', 'a'])
          (value[channel] as num).toDouble(),
      ]);
    }

    _minimumColor = _mode == 2 ? color('minColor') : null;
    _maximumColor = _mode == 0 || _mode == 2 ? color('maxColor') : null;
    _minimumGradient = _mode == 3
        ? NativeAuthoredGradient(record['minGradient'] as Map)
        : null;
    _maximumGradient = _mode == 1 || _mode == 3 || _mode == 4
        ? NativeAuthoredGradient(record['maxGradient'] as Map)
        : null;
  }
  final Map record;
  final Object? _mode;
  late final List<double>? _minimumColor, _maximumColor;
  late final NativeAuthoredGradient? _minimumGradient, _maximumGradient;
  List<double> sample(double normalizedAge, double actualRandom) {
    final random = actualRandom.clamp(0.0, 1.0);
    List<double> lerp(List<double> a, List<double> b) => [
      for (var i = 0; i < 4; i++) a[i] + (b[i] - a[i]) * random,
    ];
    return switch (_mode) {
      0 => List<double>.from(_maximumColor!),
      1 => _maximumGradient!.sample(normalizedAge),
      2 => lerp(_minimumColor!, _maximumColor!),
      3 => lerp(
        _minimumGradient!.sample(normalizedAge),
        _maximumGradient!.sample(normalizedAge),
      ),
      4 => _maximumGradient!.sample(random),
      _ => throw UnsupportedError('native_gradient_mode:$_mode'),
    };
  }
}

final _gradients = Expando<NativeAuthoredGradient>('native-authored-gradient');
final _minMaxGradients = Expando<NativeAuthoredMinMaxGradient>(
  'native-authored-min-max-gradient',
);
