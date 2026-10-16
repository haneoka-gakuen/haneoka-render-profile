import 'dart:math' as math;
import 'dart:typed_data';

import 'render_ir.dart';

/// Actual bloom/FXAA parameters, with native fullscreen passes authored here.
/// RGBA16F preserves HDR on the public SDK; it is an explicit storage difference
/// from the original final effect R11G11B10F format.
final class NativeEffectPostprocessing {
  NativeEffectPostprocessing({required this.bloom, required this.fxaa});
  final Map bloom, fxaa;
  static const effectScales = [1.0, .85, .71];
  static const backgroundCameraFps = [30, 25, 20];
  static const live2dFps = [30, 25, 20];
  static const effectRefreshRate = 60;

  List<NativePass> build({
    required String prefix,
    required String sourceTarget,
    required int width,
    required int height,
    required int quality,
    required Map<String, ProjectedMesh> meshes,
    required Map<String, NativeMaterial> materials,
    required Map<String, NativeTarget> targets,
  }) {
    if (quality < 0 || quality > 2 || width <= 0 || height <= 0) {
      throw ArgumentError('native_effect_quality_or_viewport');
    }
    final qualityName = ['high', 'middle', 'low'][quality];
    final maximumLevels =
        ((bloom['qualityMipCounts'] as Map)[qualityName] as num).toInt();
    final possibleLevels =
        (math.log(math.max(1, math.max(width ~/ 2, height ~/ 2))) / math.ln2)
            .floor() -
        1;
    final levels = math.max(1, math.min(maximumLevels, possibleLevels));
    final authored = bloom['prefilterParams'] as List;
    final scatter = (authored[0] as num).toDouble();
    final clamp = (authored[1] as num).toDouble();
    final threshold = (authored[2] as num).toDouble();
    final knee = (authored[3] as num).toDouble();
    final intensity = (bloom['intensity'] as num).toDouble();
    final quad = ProjectedMesh(
      Float32List.fromList([
        -1,
        -1,
        0,
        1,
        0,
        1,
        1,
        1,
        1,
        1,
        1,
        -1,
        0,
        1,
        1,
        1,
        1,
        1,
        1,
        1,
        -1,
        1,
        0,
        1,
        0,
        0,
        1,
        1,
        1,
        1,
        1,
        1,
        0,
        1,
        1,
        0,
        1,
        1,
        1,
        1,
      ]),
      Uint16List.fromList([0, 1, 2, 2, 1, 3]),
    );
    meshes['$prefix:post-quad'] = quad;
    final passes = <NativePass>[];
    void pass(
      String output,
      String input,
      int operation,
      int outputWidth,
      int outputHeight, {
      String? auxiliary,
    }) {
      targets[output] = NativeTarget(
        width: outputWidth,
        height: outputHeight,
        format: NativeTargetFormat.rgba16f,
        alpha: NativeTextureAlpha.independent,
        encoding: operation <= 3
            ? NativeColorEncoding.sqrtLinear
            : NativeColorEncoding.gammaSrgb,
      );
      final inputSpec = targets[input];
      if (inputSpec == null) {
        throw StateError('native_post_source_target:$input');
      }
      materials[output] = NativeMaterial(
        texture: input,
        recipe: NativeMaterialRecipe.postProcess,
        textureAlpha: inputSpec.alpha,
        blend: NativeBlend.opaque,
        additionalTextures: {'auxiliaryImage': ?auxiliary},
        uniformFloats: Float32List.fromList([
          1 / inputSpec.width,
          1 / inputSpec.height,
          operation.toDouble(),
          scatter,
          clamp,
          threshold,
          knee,
          intensity,
          1,
          0,
          0,
          0,
          (fxaa['subpixelBlend'] as num).toDouble(),
          (fxaa['relativeContrast'] as num).toDouble(),
          (fxaa['absoluteContrast'] as num).toDouble(),
          0,
        ]),
      );
      passes.add(
        NativePass(
          target: output,
          draws: [NativeDraw(mesh: '$prefix:post-quad', material: output)],
        ),
      );
    }

    final mipKeys = <String>[], sizes = <(int, int)>[];
    var w = width, h = height, previous = sourceTarget;
    for (var level = 0; level < levels; level++) {
      w = math.max(1, w ~/ 2);
      h = math.max(1, h ~/ 2);
      final filtered = '$prefix:bloom-$level-prefilter';
      final horizontal = '$prefix:bloom-$level-horizontal';
      final vertical = '$prefix:bloom-$level-vertical';
      if (level == 0) {
        pass(filtered, previous, 0, w, h);
        mipKeys.add(filtered);
        sizes.add((w, h));
        previous = filtered;
        continue;
      } else {
        pass(horizontal, previous, 1, w, h);
      }
      pass(vertical, horizontal, 2, w, h);
      mipKeys.add(vertical);
      sizes.add((w, h));
      previous = vertical;
    }
    for (var level = levels - 2; level >= 0; level--) {
      final output = '$prefix:bloom-$level-upsample';
      pass(
        output,
        mipKeys[level],
        3,
        sizes[level].$1,
        sizes[level].$2,
        auxiliary: previous,
      );
      previous = output;
    }
    pass(
      '$prefix:bloom-composite',
      sourceTarget,
      4,
      width,
      height,
      auxiliary: previous,
    );
    pass('$prefix:output', '$prefix:bloom-composite', 5, width, height);
    return passes;
  }
}
