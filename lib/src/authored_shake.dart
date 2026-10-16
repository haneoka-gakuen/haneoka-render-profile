import 'dart:math' as math;
import 'dart:typed_data';

import 'tween_ease.dart';

final class AuthoredWaypointPath {
  AuthoredWaypointPath(
    List<List<double>> points,
    List<double> cumulative,
    this.ease,
  ) : points = List.unmodifiable(
        points.map((point) => List<double>.unmodifiable(point)),
      ),
      cumulative = List.unmodifiable(cumulative);
  final List<List<double>> points;
  final List<double> cumulative;
  final int ease;
  Map<String, Object?> toData() => {
    'points': points,
    'cumulative': cumulative,
    'ease': ease,
  };
  factory AuthoredWaypointPath.fromData(Map data) => AuthoredWaypointPath(
    [
      for (final raw in data['points'] as List)
        [for (final value in raw as List) (value as num).toDouble()],
    ],
    [for (final value in data['cumulative'] as List) (value as num).toDouble()],
    data['ease'] as int,
  );

  List<double> sample(double progress) {
    final normalized = progress.clamp(0.0, 1.0);
    var index = cumulative.indexWhere((end) => normalized <= end);
    if (index < 0) index = points.length - 1;
    final previous = index == 0 ? 0.0 : cumulative[index - 1];
    final width = cumulative[index] - previous;
    final t = sampleTweenEase(
      ease,
      width <= 0 ? 1 : ((normalized - previous) / width).clamp(0.0, 1.0),
    );
    final from = index == 0 ? const [0.0, 0.0, 0.0] : points[index - 1];
    final to = points[index];
    return [
      for (var axis = 0; axis < 3; axis++)
        from[axis] + (to[axis] - from[axis]) * t,
    ];
  }
}

/// The source's uniform XY Vector3 shake and scalar anchored-position shake.
AuthoredWaypointPath createAuthoredShakePath({
  required double strength,
  required double duration,
  required int vibrato,
  required double randomness,
  required bool fadeOut,
  required bool vectorBased,
  required double Function() randomUnit,
}) {
  if (duration <= 0) {
    return AuthoredWaypointPath(
      const [
        [0.0, 0.0, 0.0],
      ],
      const [1.0],
      1,
    );
  }
  final product = vibrato * duration;
  final count = product.isFinite ? math.max(2, product.truncate()) : 2;
  final points = <List<double>>[], times = <double>[];
  var magnitude = vectorBased ? math.sqrt(2) * strength.abs() : strength;
  final decay = fadeOut ? magnitude / count : 0.0;
  var axisLimit = strength;
  var angle = randomUnit() * 360;
  for (var index = 0; index < count; index++) {
    if (index == count - 1) {
      points.add(const [0.0, 0.0, 0.0]);
    } else {
      if (index > 0) {
        angle += -180 + (randomUnit() * 2 - 1) * randomness;
      }
      final az = angle * math.pi / 180;
      var x = magnitude * math.cos(az), y = magnitude * math.sin(az);
      if (vectorBased) {
        final ay = (randomUnit() * 2 - 1) * randomness * math.pi / 180;
        var z = -x * math.sin(ay);
        x *= math.cos(ay);
        var length = math.sqrt(x * x + y * y + z * z);
        if (length > axisLimit.abs() && length > 0) {
          x *= axisLimit / length;
        }
        length = math.sqrt(x * x + y * y + z * z);
        if (length > axisLimit.abs() && length > 0) {
          y *= axisLimit / length;
        }
        z = 0;
        length = math.sqrt(x * x + y * y + z * z);
        points.add(
          length > 1e-5
              ? [x * magnitude / length, y * magnitude / length, 0.0]
              : const [0.0, 0.0, 0.0],
        );
        magnitude -= decay;
        final limitLength = math.sqrt(2) * axisLimit.abs();
        if (limitLength > magnitude.abs() && limitLength > 0) {
          axisLimit *= magnitude / limitLength;
        }
      } else {
        points.add([x, y, 0.0]);
        magnitude -= decay;
      }
    }
    times.add(
      fadeOut
          ? (index + 1) * (index + 2) / (count * (count + 1))
          : (index + 1) / count,
    );
  }
  return AuthoredWaypointPath(points, times, 1);
}

final class AuthoredShakeTrack {
  final offset = Float32List(3);
  AuthoredWaypointPath? _path;
  int _startUs = 0, _durationUs = 0;
  bool get active => _path != null;
  Map<String, Object?> snapshotData() => {
    'version': 1,
    'path': _path?.toData(),
    'startUs': _startUs,
    'durationUs': _durationUs,
    'offset': offset.toList(),
  };
  void restoreData(Map data) {
    if (data['version'] != 1) throw const FormatException('shake_data_version');
    _path = data['path'] == null
        ? null
        : AuthoredWaypointPath.fromData(data['path'] as Map);
    _startUs = data['startUs'] as int;
    _durationUs = data['durationUs'] as int;
    offset.setAll(
      0,
      (data['offset'] as List).map((value) => (value as num).toDouble()),
    );
  }

  AuthoredShakeSnapshot snapshot() => AuthoredShakeSnapshot._(
    _path,
    _startUs,
    _durationUs,
    Float32List.fromList(offset),
  );

  void restore(AuthoredShakeSnapshot snapshot) {
    _path = snapshot._path;
    _startUs = snapshot._startUs;
    _durationUs = snapshot._durationUs;
    offset.setAll(0, snapshot._offset);
  }

  void start({
    required int nowUs,
    required int durationUs,
    required double strength,
    required bool vectorBased,
    required double Function() randomUnit,
    int vibrato = 10,
    double randomness = 90,
  }) {
    stop();
    if (durationUs <= 0) return;
    _startUs = nowUs;
    _durationUs = durationUs;
    _path = createAuthoredShakePath(
      strength: strength,
      duration: durationUs / 1000000,
      vibrato: vibrato,
      randomness: randomness,
      fadeOut: true,
      vectorBased: vectorBased,
      randomUnit: randomUnit,
    );
  }

  void update(int nowUs) {
    final path = _path;
    if (path == null) return;
    final progress = (nowUs - _startUs) / _durationUs;
    if (progress >= 1) {
      stop();
      return;
    }
    offset.setAll(0, path.sample(progress));
  }

  void stop() {
    _path = null;
    offset.fillRange(0, 3, 0);
  }
}

enum AuthoredCameraShakeState { idle, playing, stopping }

final class AuthoredShakeSnapshot {
  AuthoredShakeSnapshot._(
    this._path,
    this._startUs,
    this._durationUs,
    this._offset,
  );
  final AuthoredWaypointPath? _path;
  final int _startUs, _durationUs;
  final Float32List _offset;
}

final class AuthoredCameraShakeSnapshot {
  AuthoredCameraShakeSnapshot._(this._owner, this._restore);
  final AuthoredCameraShakeTrack _owner;
  final void Function() _restore;
}

/// Persistent camera cycles retain their startup position and fade at Update.
final class AuthoredCameraShakeTrack {
  final offset = Float32List(3);
  final _cycleStart = Float32List(3);
  AuthoredCameraShakeState state = AuthoredCameraShakeState.idle;
  AuthoredWaypointPath? _path;
  int _fadeStartUs = 0, _fadeUs = 0, _cycleStartUs = 0, _cycleUs = 0;
  int? _lastUpdate;
  bool _nextCycle = false;
  double _strength = 0, _randomness = 0;
  int _vibrato = 0;
  double Function()? _randomUnit;
  bool get isPlaying => state == AuthoredCameraShakeState.playing;
  Map<String, Object?> snapshotData() => {
    'version': 1,
    'state': state.name,
    'path': _path?.toData(),
    'offset': offset.toList(),
    'cycleStart': _cycleStart.toList(),
    'clocks': [_fadeStartUs, _fadeUs, _cycleStartUs, _cycleUs, _lastUpdate],
    'nextCycle': _nextCycle,
    'strength': _strength,
    'randomness': _randomness,
    'vibrato': _vibrato,
  };
  void restoreData(Map data, {required double Function() randomUnit}) {
    if (data['version'] != 1)
      throw const FormatException('camera_shake_data_version');
    state = AuthoredCameraShakeState.values.byName(data['state'] as String);
    _path = data['path'] == null
        ? null
        : AuthoredWaypointPath.fromData(data['path'] as Map);
    offset.setAll(
      0,
      (data['offset'] as List).map((v) => (v as num).toDouble()),
    );
    _cycleStart.setAll(
      0,
      (data['cycleStart'] as List).map((v) => (v as num).toDouble()),
    );
    final clocks = data['clocks'] as List;
    _fadeStartUs = clocks[0] as int;
    _fadeUs = clocks[1] as int;
    _cycleStartUs = clocks[2] as int;
    _cycleUs = clocks[3] as int;
    _lastUpdate = clocks[4] as int?;
    _nextCycle = data['nextCycle'] as bool;
    _strength = (data['strength'] as num).toDouble();
    _randomness = (data['randomness'] as num).toDouble();
    _vibrato = data['vibrato'] as int;
    _randomUnit = randomUnit;
  }

  int? get nextBoundaryUs => state == AuthoredCameraShakeState.idle
      ? null
      : math.max(_cycleStartUs + _cycleUs, _fadeStartUs + _fadeUs);

  AuthoredCameraShakeSnapshot snapshot() {
    final savedState = state, path = _path;
    final value = Float32List.fromList(offset);
    final cycle = Float32List.fromList(_cycleStart);
    final clocks = (
      _fadeStartUs,
      _fadeUs,
      _cycleStartUs,
      _cycleUs,
      _lastUpdate,
    );
    final controls = (
      _nextCycle,
      _strength,
      _randomness,
      _vibrato,
      _randomUnit,
    );
    return AuthoredCameraShakeSnapshot._(this, () {
      state = savedState;
      _path = path;
      offset.setAll(0, value);
      _cycleStart.setAll(0, cycle);
      _fadeStartUs = clocks.$1;
      _fadeUs = clocks.$2;
      _cycleStartUs = clocks.$3;
      _cycleUs = clocks.$4;
      _lastUpdate = clocks.$5;
      _nextCycle = controls.$1;
      _strength = controls.$2;
      _randomness = controls.$3;
      _vibrato = controls.$4;
      _randomUnit = controls.$5;
    });
  }

  void restore(AuthoredCameraShakeSnapshot snapshot) {
    if (!identical(snapshot._owner, this)) {
      throw const FormatException('camera_shake_snapshot_owner');
    }
    snapshot._restore();
  }

  void enable({
    required int nowUs,
    required int fadeUs,
    required int cycleUs,
    required double strength,
    required int vibrato,
    required double randomness,
    required double Function() randomUnit,
  }) {
    state = AuthoredCameraShakeState.playing;
    _fadeStartUs = nowUs;
    _fadeUs = fadeUs;
    _cycleUs = cycleUs;
    _strength = strength;
    _vibrato = vibrato;
    _randomness = randomness;
    _randomUnit = randomUnit;
    _beginCycle(nowUs);
  }

  void disable({required int nowUs, required int fadeUs}) {
    if (state == AuthoredCameraShakeState.idle) return;
    state = AuthoredCameraShakeState.stopping;
    _fadeStartUs = nowUs;
    _fadeUs = fadeUs;
    _beginCycle(nowUs);
  }

  void _beginCycle(int nowUs) {
    _cycleStart.setAll(0, offset);
    _cycleStartUs = nowUs;
    _nextCycle = false;
    _path = createAuthoredShakePath(
      strength: _strength,
      duration: _cycleUs / 1000000,
      vibrato: _vibrato,
      randomness: _randomness,
      fadeOut: false,
      vectorBased: true,
      randomUnit: _randomUnit!,
    );
  }

  void update(int nowUs, int updateIndex) {
    if (_lastUpdate == updateIndex || state == AuthoredCameraShakeState.idle) {
      return;
    }
    _lastUpdate = updateIndex;
    if (_nextCycle) _beginCycle(nowUs);
    final progress = _cycleUs <= 0 ? 1.0 : (nowUs - _cycleStartUs) / _cycleUs;
    final fade = _fadeUs <= 0
        ? 1.0
        : ((nowUs - _fadeStartUs) / _fadeUs).clamp(0.0, 1.0);
    final weight = isPlaying ? fade : 1 - fade;
    final sampled = _path!.sample(progress);
    for (var axis = 0; axis < 3; axis++) {
      offset[axis] = (_cycleStart[axis] + sampled[axis]) * weight;
    }
    if (progress >= 1) {
      if (state == AuthoredCameraShakeState.stopping && fade >= 1) {
        reset();
      } else {
        _nextCycle = true;
      }
    }
  }

  void reset() {
    state = AuthoredCameraShakeState.idle;
    _path = null;
    _nextCycle = false;
    _lastUpdate = null;
    offset.fillRange(0, 3, 0);
  }
}
