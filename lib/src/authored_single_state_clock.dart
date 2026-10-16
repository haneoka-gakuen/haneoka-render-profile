import 'dart:typed_data';

/// Numeric clock for an authored single-state controller. Rendering and device
/// time remain the host's responsibility; reentry preserves the overshoot.
final class NativeSingleStateClock {
  NativeSingleStateClock(Map controller, this.duration) {
    final machines =
        (controller['m_Controller'] as Map)['m_StateMachineArray'] as List;
    final machine = (machines.single as Map)['data'] as Map;
    final states = machine['m_StateConstantArray'] as List;
    final state = (states.single as Map)['data'] as Map;
    speed = (state['m_Speed'] as num).toDouble();
    loop = state['m_Loop'] == true;
    final transitions = state['m_TransitionConstantArray'] as List;
    if (transitions.isNotEmpty) {
      final transition = (transitions.single as Map)['data'] as Map;
      if (transition['m_DestinationState'] != 0 ||
          transition['m_HasExitTime'] != true ||
          (transition['m_ConditionConstantArray'] as List).isNotEmpty ||
          transition['m_TransitionDuration'] != 0) {
        throw UnsupportedError('single_state_transition');
      }
      exitTime = (transition['m_ExitTime'] as num).toDouble();
      offset = (transition['m_TransitionOffset'] as num).toDouble();
    }
  }
  final double duration;
  late final double speed;
  late final bool loop;
  double? exitTime;
  double offset = 0, seconds = 0;
  final _scalar = Float32List(1);
  double _f(double value) {
    _scalar[0] = value;
    return _scalar[0];
  }

  double advance(double delta) {
    final before = seconds;
    seconds = _f(seconds + _f(delta * speed));
    final exit = exitTime;
    if (exit != null && duration > 0) {
      final a = before / duration, b = seconds / duration;
      final cycle = loop && exit < 1;
      final crossed = cycle
          ? (b - exit).floor() > (a - exit).floor()
          : a < exit && b >= exit;
      if (crossed) {
        final boundary = cycle ? (b - exit).floor() + exit : exit;
        seconds = _f(_f(offset * duration) + _f((b - boundary) * duration));
      }
    }
    return seconds;
  }
}
