import 'dart:typed_data';

import 'authored_curve.dart';

/// Authored grid/whole-sheet animation in normalized particle lifetime.
/// Tile rows start at the top, matching the render contract's texture UVs.
final class NativeParticleTextureSheet {
  NativeParticleTextureSheet(Map module)
    : tilesX = module['tilesX'] as int,
      tilesY = module['tilesY'] as int,
      cycles = (module['cycles'] as num).toDouble(),
      channels = module['uvChannelMask'] as int,
      frame = NativeAuthoredMinMaxCurve(module['frameOverTime'] as Map),
      start = NativeAuthoredMinMaxCurve(module['startFrame'] as Map) {
    if (module['mode'] != 0 ||
        module['animationType'] != 0 ||
        module['timeMode'] != 0 ||
        module['flipU'] != 0 ||
        module['flipV'] != 0) {
      throw UnsupportedError('particle_texture_sheet_mode');
    }
    if (tilesX <= 0 || tilesY <= 0 || !cycles.isFinite || cycles < 0) {
      throw const FormatException('particle_texture_sheet_grid');
    }
  }

  final int tilesX, tilesY, channels;
  final double cycles;
  final NativeAuthoredMinMaxCurve frame, start;

  Float64List? tile(double normalizedAge, List<double> random) {
    if ((channels & 1) == 0) return null;
    final count = tilesX * tilesY;
    final phase = (normalizedAge * cycles) % 1;
    final value = frame.sample(phase, random[0]) + start.sample(0, random[1]);
    final index = (value * count).floor() % count;
    return Float64List.fromList([
      (index % tilesX) / tilesX,
      (index ~/ tilesX) / tilesY,
      1 / tilesX,
      1 / tilesY,
    ]);
  }
}
