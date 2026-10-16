import 'dart:math' as math;
import 'dart:typed_data';

/// Decodes the source clip's numeric streamed/dense/constant curve storage.
/// Binding identities remain original; the scene producer chooses their typed
/// property/component mapping instead of executing method names from assets.
final class NativeAuthoredAnimationClip {
  NativeAuthoredAnimationClip(Map record) {
    final muscle = record['m_MuscleClip'] as Map;
    final clip = (muscle['m_Clip'] as Map)['data'] as Map;
    final streamed = clip['m_StreamedClip'] as Map;
    final dense = clip['m_DenseClip'] as Map;
    final constants = clip['m_ConstantClip'] as Map;
    startTime = (muscle['m_StartTime'] as num).toDouble();
    stopTime = (muscle['m_StopTime'] as num).toDouble();
    bindings = List.unmodifiable(
      ((record['m_ClipBindingConstant'] as Map)['genericBindings'] as List)
          .cast<Map>(),
    );
    _streamCount =
        (streamed['curveCount'] as int) +
        ((streamed['discreteCurveCount'] as int?) ?? 0);
    _denseCount = dense['m_CurveCount'] as int;
    _denseFrames = dense['m_FrameCount'] as int;
    _denseRate = (dense['m_SampleRate'] as num).toDouble();
    _denseBegin = (dense['m_BeginTime'] as num).toDouble();
    _dense = Float32List.fromList(
      (dense['m_SampleArray'] as List)
          .map((value) => (value as num).toDouble())
          .toList(),
    );
    _constant = Float32List.fromList(
      (constants['data'] as List)
          .map((value) => (value as num).toDouble())
          .toList(),
    );
    if (_streamCount < 0 ||
        _denseCount < 0 ||
        _denseFrames < 0 ||
        _dense.length != _denseCount * _denseFrames ||
        !startTime.isFinite ||
        !stopTime.isFinite ||
        stopTime < startTime) {
      throw const FormatException('native_animation_storage');
    }
    _keys = List.generate(_streamCount, (_) => <_PolynomialKey>[]);
    final words = Uint32List.fromList((streamed['data'] as List).cast<int>());
    final bytes = ByteData.sublistView(words);
    var offset = 0;
    double scalar(int index) => bytes.getFloat32(index * 4, Endian.host);
    while (offset < words.length) {
      if (offset + 2 > words.length) {
        throw const FormatException('native_animation_stream_header');
      }
      final time = scalar(offset++);
      final count = words[offset++];
      // The original numeric stream ends with +Infinity and zero keys.
      // It is a terminal marker, never an animation time or curve sample.
      if (time == double.infinity && count == 0 && offset == words.length) {
        break;
      }
      if (offset + count * 5 > words.length || !time.isFinite) {
        throw const FormatException('native_animation_stream_frame');
      }
      for (var index = 0; index < count; index++) {
        final curve = words[offset++];
        if (curve >= _streamCount) {
          throw const FormatException('native_animation_curve_index');
        }
        final coefficients = [
          for (var part = 0; part < 4; part++) scalar(offset++),
        ];
        if (coefficients.any((value) => !value.isFinite)) {
          throw const FormatException('native_animation_curve_nonfinite');
        }
        final keys = _keys[curve];
        if (keys.isNotEmpty && time < keys.last.time) {
          throw const FormatException('native_animation_curve_order');
        }
        keys.add(_PolynomialKey(time, coefficients));
      }
    }
  }
  late final double startTime, stopTime;
  late final List<Map> bindings;
  late final int _streamCount, _denseCount, _denseFrames;
  late final double _denseRate, _denseBegin;
  late final Float32List _dense, _constant;
  late final List<List<_PolynomialKey>> _keys;
  int get curveCount => _streamCount + _denseCount + _constant.length;
  double get duration => stopTime - startTime;
  List<double> get keyTimes {
    final times = {
      for (final curve in _keys)
        for (final key in curve)
          if (key.time >= startTime && key.time <= stopTime)
            key.time - startTime,
    }.toList()..sort();
    return List.unmodifiable(times);
  }

  List<({Map binding, Float32List values})> sampleBindingsAt(
    double elapsedSeconds, {
    bool loop = false,
  }) {
    final samples = sampleAt(elapsedSeconds, loop: loop);
    final output = <({Map binding, Float32List values})>[];
    var cursor = 0;
    for (final binding in bindings) {
      final count = binding['typeID'] == 4
          ? switch (binding['attribute']) {
              1 || 3 || 4 => 3,
              2 => 4,
              _ => 1,
            }
          : 1;
      if (cursor + count > samples.length) {
        throw const FormatException('native_animation_binding_storage');
      }
      output.add((
        binding: binding,
        values: Float32List.fromList(samples.sublist(cursor, cursor + count)),
      ));
      cursor += count;
    }
    if (cursor != samples.length) {
      throw const FormatException('native_animation_binding_component_count');
    }
    return List.unmodifiable(output);
  }

  Float32List sampleAt(double elapsedSeconds, {bool loop = false}) {
    final elapsed = loop && duration > 0
        ? elapsedSeconds % duration
        : elapsedSeconds.clamp(0.0, duration);
    final time = startTime + elapsed;
    final values = Float32List(curveCount);
    for (var index = 0; index < _streamCount; index++) {
      final keys = _keys[index];
      if (keys.isEmpty) {
        throw StateError('native_animation_missing_curve:$index');
      }
      var low = 0, high = keys.length;
      while (low + 1 < high) {
        final middle = (low + high) ~/ 2;
        if (keys[middle].time <= time) {
          low = middle;
        } else {
          high = middle;
        }
      }
      final key = keys[low], dt = math.max(0.0, time - key.time);
      final c = key.coefficients;
      values[index] = ((c[0] * dt + c[1]) * dt + c[2]) * dt + c[3];
    }
    if (_denseCount > 0) {
      if (_denseFrames < 1 || _denseRate <= 0) {
        throw const FormatException('native_animation_dense_timing');
      }
      final position = ((time - _denseBegin) * _denseRate).clamp(
        0.0,
        (_denseFrames - 1).toDouble(),
      );
      final left = position.floor(),
          right = math.min(left + 1, _denseFrames - 1);
      final amount = position - left;
      for (var curve = 0; curve < _denseCount; curve++) {
        final a = _dense[left * _denseCount + curve],
            b = _dense[right * _denseCount + curve];
        values[_streamCount + curve] = a + (b - a) * amount;
      }
    }
    values.setAll(_streamCount + _denseCount, _constant);
    return values;
  }
}

final class _PolynomialKey {
  const _PolynomialKey(this.time, this.coefficients);
  final double time;
  final List<double> coefficients;
}
