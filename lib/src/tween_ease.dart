import 'dart:math' as math;

int parseTweenEase(String? value, {int fallback = 6}) {
  const names = [
    'Unset',
    'Linear',
    'InSine',
    'OutSine',
    'InOutSine',
    'InQuad',
    'OutQuad',
    'InOutQuad',
    'InCubic',
    'OutCubic',
    'InOutCubic',
    'InQuart',
    'OutQuart',
    'InOutQuart',
    'InQuint',
    'OutQuint',
    'InOutQuint',
    'InExpo',
    'OutExpo',
    'InOutExpo',
    'InCirc',
    'OutCirc',
    'InOutCirc',
    'InElastic',
    'OutElastic',
    'InOutElastic',
    'InBack',
    'OutBack',
    'InOutBack',
    'InBounce',
    'OutBounce',
    'InOutBounce',
    'Flash',
    'InFlash',
    'OutFlash',
    'InOutFlash',
    'INTERNAL_Zero',
    'INTERNAL_Custom',
  ];
  final text = value?.trim() ?? '';
  if (text.isEmpty) return fallback;
  final numeric = int.tryParse(text);
  if (numeric != null) {
    return numeric >= 0 && numeric < names.length ? numeric : fallback;
  }
  var result = 0;
  for (final part in text.split(',')) {
    final index = names.indexOf(part.trim());
    if (index < 0) return fallback;
    result |= index;
  }
  return result < names.length ? result : fallback;
}

/// Standard authored easing IDs. Callers own clocks and write numeric results
/// into their transforms; no renderer or scene state is kept here.
double sampleTweenEase(int type, double t) {
  double outBounce(double x) {
    const a = 7.5625, b = 2.75;
    if (x < 1 / b) return a * x * x;
    if (x < 2 / b) {
      x -= 1.5 / b;
      return a * x * x + .75;
    }
    if (x < 2.5 / b) {
      x -= 2.25 / b;
      return a * x * x + .9375;
    }
    x -= 2.625 / b;
    return a * x * x + .984375;
  }

  double elastic(double x, bool incoming) {
    if (x == 0 || x == 1) return x;
    const period = .3;
    if (incoming) {
      x -= 1;
      return -math.pow(2, 10 * x) *
          math.sin((x - period / 4) * 2 * math.pi / period);
    }
    return math.pow(2, -10 * x) *
            math.sin((x - period / 4) * 2 * math.pi / period) +
        1;
  }

  switch (type) {
    case 0:
    case 6:
      return 1 - (1 - t) * (1 - t);
    case 1:
      return t;
    case 2:
      return 1 - math.cos(t * math.pi / 2);
    case 3:
      return math.sin(t * math.pi / 2);
    case 4:
      return (1 - math.cos(math.pi * t)) / 2;
    case 5:
      return t * t;
    case 7:
      return t < .5 ? 2 * t * t : 1 - math.pow(-2 * t + 2, 2) / 2;
    case 8:
      return t * t * t;
    case 9:
      return 1 - math.pow(1 - t, 3).toDouble();
    case 10:
      return t < .5 ? 4 * t * t * t : 1 - math.pow(-2 * t + 2, 3) / 2;
    case 11:
      return math.pow(t, 4).toDouble();
    case 12:
      return 1 - math.pow(1 - t, 4).toDouble();
    case 13:
      return t < .5
          ? 8 * math.pow(t, 4).toDouble()
          : 1 - math.pow(-2 * t + 2, 4) / 2;
    case 14:
      return math.pow(t, 5).toDouble();
    case 15:
      return 1 - math.pow(1 - t, 5).toDouble();
    case 16:
      return t < .5
          ? 16 * math.pow(t, 5).toDouble()
          : 1 - math.pow(-2 * t + 2, 5) / 2;
    case 17:
      return t == 0 ? 0 : math.pow(2, 10 * t - 10).toDouble();
    case 18:
      return t == 1 ? 1 : 1 - math.pow(2, -10 * t).toDouble();
    case 19:
      if (t == 0 || t == 1) return t;
      return t < .5
          ? math.pow(2, 20 * t - 10) / 2
          : (2 - math.pow(2, -20 * t + 10)) / 2;
    case 20:
      return 1 - math.sqrt(1 - t * t);
    case 21:
      return math.sqrt(1 - (t - 1) * (t - 1));
    case 22:
      return t < .5
          ? (1 - math.sqrt(1 - 4 * t * t)) / 2
          : (math.sqrt(1 - math.pow(-2 * t + 2, 2)) + 1) / 2;
    case 23:
      return elastic(t, true);
    case 24:
      return elastic(t, false);
    case 25:
      if (t == 0 || t == 1) return t;
      const period = .45;
      final x = t * 2 - 1;
      final wave = math.sin((x - period / 4) * 2 * math.pi / period);
      return x < 0
          ? -.5 * math.pow(2, 10 * x) * wave
          : .5 * math.pow(2, -10 * x) * wave + 1;
    case 26:
      return 2.70158 * t * t * t - 1.70158 * t * t;
    case 27:
      return 1 + 2.70158 * math.pow(t - 1, 3) + 1.70158 * math.pow(t - 1, 2);
    case 28:
      const c = 1.70158 * 1.525;
      return t < .5
          ? math.pow(2 * t, 2) * ((c + 1) * 2 * t - c) / 2
          : (math.pow(2 * t - 2, 2) * ((c + 1) * (2 * t - 2) + c) + 2) / 2;
    case 29:
      return 1 - outBounce(1 - t);
    case 30:
      return outBounce(t);
    case 31:
      return t < .5
          ? (1 - outBounce(1 - 2 * t)) / 2
          : (1 + outBounce(2 * t - 1)) / 2;
    default:
      throw UnsupportedError('authored_ease:$type');
  }
}
