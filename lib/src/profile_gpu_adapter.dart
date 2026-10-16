import 'dart:typed_data';

import 'render_ir.dart';

final haneokaShaderPrograms = <String, ShaderProgramSpec>{
  'story-lut-ldr': ShaderProgramSpec(
    vertexEntry: 'HaneokaTexturedVertex',
    fragmentEntry: 'HaneokaStoryLutLdrFragment',
    uniformFloatCounts: {'StoryLutSettings': 64},
    acceptedTextureEncodings: {ColorEncoding.linear},
    textureSlots: {
      'curveMaster',
      'curveRed',
      'curveGreen',
      'curveBlue',
      'curveHueVsHue',
      'curveHueVsSat',
      'curveSatVsSat',
      'curveLumVsSat',
    },
  ),
  'story-uber': ShaderProgramSpec(
    vertexEntry: 'HaneokaTexturedVertex',
    fragmentEntry: 'HaneokaStoryUberFragment',
    uniformFloatCounts: {'StoryUberSettings': 32},
    textureSlots: {'image', 'gradingLut', 'bloomImage'},
    acceptedTextureEncodings: {
      ColorEncoding.gammaSrgb,
      ColorEncoding.linear,
      ColorEncoding.sqrtLinear,
    },
  ),
  'story-curved': ShaderProgramSpec(
    vertexEntry: 'HaneokaTexturedVertex',
    fragmentEntry: 'HaneokaStoryCurvedFragment',
    uniformFloatCounts: {'StoryCurvedSettings': 16},
    textureSlots: {'image'},
    acceptedTextureEncodings: {ColorEncoding.gammaSrgb},
  ),
  'story-bokeh': ShaderProgramSpec(
    vertexEntry: 'HaneokaTexturedVertex',
    fragmentEntry: 'HaneokaStoryBokehFragment',
    uniformFloatCounts: {'StoryBokehSettings': 12},
    textureSlots: {'image'},
  ),
  'textured-straight': ShaderProgramSpec(
    vertexEntry: 'HaneokaTexturedVertex',
    fragmentEntry: 'HaneokaTexturedFragment',
    required: true,
    textureSlots: {'image'},
  ),
  'textured-premultiplied': ShaderProgramSpec(
    vertexEntry: 'HaneokaTexturedVertex',
    fragmentEntry: 'HaneokaPremultipliedFragment',
    required: true,
    textureSlots: {'image'},
  ),
  'solid': ShaderProgramSpec(
    vertexEntry: 'HaneokaTexturedVertex',
    fragmentEntry: 'HaneokaSolidFragment',
    required: true,
  ),
  'game-composite': ShaderProgramSpec(
    vertexEntry: 'HaneokaTexturedVertex',
    fragmentEntry: 'HaneokaGameComposeFragment',
    required: true,
    textureSlots: {'image'},
  ),
  'hold': ShaderProgramSpec(
    vertexEntry: 'HaneokaHoldVertex',
    fragmentEntry: 'HaneokaHoldFragment',
    required: true,
    vertexStrideFloats: 17,
    uniformFloatCounts: {'HoldSettings': 20},
    textureSlots: {'gradient', 'mainImage'},
  ),
  'cubism': ShaderProgramSpec(
    vertexEntry: 'HaneokaCubismVertex',
    fragmentEntry: 'HaneokaCubismFragment',
    uniformFloatCounts: {'CubismSettings': 36},
    textureSlots: {'image', 'maskImage'},
  ),
  'cubism-mask': ShaderProgramSpec(
    vertexEntry: 'HaneokaTexturedVertex',
    fragmentEntry: 'HaneokaCubismMaskFragment',
    textureSlots: {'image'},
  ),
  'post': ShaderProgramSpec(
    vertexEntry: 'HaneokaTexturedVertex',
    fragmentEntry: 'HaneokaPostFragment',
    uniformFloatCounts: {'PostSettings': 16},
    textureSlots: {'image', 'auxiliaryImage'},
    acceptedTextureEncodings: ColorEncoding.values.toSet(),
  ),
  'mobile-hdr': ShaderProgramSpec(
    vertexEntry: 'HaneokaTexturedVertex',
    fragmentEntry: 'HaneokaMobileHdrFragment',
    textureSlots: {'image'},
  ),
  'sdf': ShaderProgramSpec(
    vertexEntry: 'HaneokaTexturedVertex',
    fragmentEntry: 'HaneokaSdfFragment',
    uniformFloatCounts: {'SdfSettings': 24},
    textureSlots: {'image'},
  ),
  'opaque-transfer': ShaderProgramSpec(
    vertexEntry: 'HaneokaTexturedVertex',
    fragmentEntry: 'HaneokaOpaqueColorTransferFragment',
    textureSlots: {'image'},
  ),
  'ui-additive-straight': ShaderProgramSpec(
    vertexEntry: 'HaneokaTexturedVertex',
    fragmentEntry: 'HaneokaUiAdditiveStraightFragment',
    textureSlots: {'image'},
  ),
  'ui-additive-premultiplied': ShaderProgramSpec(
    vertexEntry: 'HaneokaTexturedVertex',
    fragmentEntry: 'HaneokaUiAdditivePremultipliedFragment',
    textureSlots: {'image'},
  ),
  'rule-transition': ShaderProgramSpec(
    vertexEntry: 'HaneokaTexturedVertex',
    fragmentEntry: 'HaneokaRuleTransitionFragment',
    uniformFloatCounts: {'RuleSettings': 4},
    textureSlots: {'image'},
  ),
  'coverage-mask': ShaderProgramSpec(
    vertexEntry: 'HaneokaTexturedVertex',
    fragmentEntry: 'HaneokaCoverageMaskFragment',
    uniformFloatCounts: {'CoverageSettings': 4},
    textureSlots: {'image'},
  ),
  'ui-masked-textured-straight': ShaderProgramSpec(
    vertexEntry: 'HaneokaUiMaskedVertex',
    fragmentEntry: 'HaneokaUiMaskedTexturedFragment',
    uniformFloatCounts: {'MaskSettings': 20},
    textureSlots: {'image', 'coverageImage'},
  ),
  'ui-masked-textured-premultiplied': ShaderProgramSpec(
    vertexEntry: 'HaneokaUiMaskedVertex',
    fragmentEntry: 'HaneokaUiMaskedPremultipliedFragment',
    uniformFloatCounts: {'MaskSettings': 20},
    textureSlots: {'image', 'coverageImage'},
  ),
  'ui-masked-solid': ShaderProgramSpec(
    vertexEntry: 'HaneokaUiMaskedVertex',
    fragmentEntry: 'HaneokaUiMaskedSolidFragment',
    uniformFloatCounts: {'MaskSettings': 20},
    textureSlots: {'coverageImage'},
  ),
  'ui-masked-sdf': ShaderProgramSpec(
    vertexEntry: 'HaneokaUiMaskedVertex',
    fragmentEntry: 'HaneokaUiMaskedSdfFragment',
    uniformFloatCounts: {'SdfSettings': 24, 'MaskSettings': 20},
    textureSlots: {'image', 'coverageImage'},
  ),
  'ui-masked-coverage-mask': ShaderProgramSpec(
    vertexEntry: 'HaneokaUiMaskedVertex',
    fragmentEntry: 'HaneokaUiMaskedCoverageMaskFragment',
    uniformFloatCounts: {'CoverageSettings': 4, 'MaskSettings': 20},
    textureSlots: {'image', 'coverageImage'},
  ),
};

DrawMaterial toDrawMaterial(NativeMaterial value) {
  final textures = <String, String>{};
  final uniforms = <String, Float32List>{};
  var mainSlot = 'image';
  var id = switch (value.recipe) {
    NativeMaterialRecipe.textured =>
      value.textureAlpha == TextureAlpha.straight
          ? 'textured-straight'
          : 'textured-premultiplied',
    NativeMaterialRecipe.solidColor => 'solid',
    NativeMaterialRecipe.gameComposite => 'game-composite',
    NativeMaterialRecipe.holdRibbon => 'hold',
    NativeMaterialRecipe.cubism => 'cubism',
    NativeMaterialRecipe.cubismMask => 'cubism-mask',
    NativeMaterialRecipe.postProcess => 'post',
    NativeMaterialRecipe.mobileHdr => 'mobile-hdr',
    NativeMaterialRecipe.sdfText => 'sdf',
    NativeMaterialRecipe.ruleTransition => 'rule-transition',
    NativeMaterialRecipe.uiSourceAlphaAdditive =>
      value.textureAlpha == TextureAlpha.straight
          ? 'ui-additive-straight'
          : 'ui-additive-premultiplied',
    NativeMaterialRecipe.sourceAlphaTexture =>
      value.textureAlpha == TextureAlpha.straight
          ? 'ui-additive-straight'
          : 'ui-additive-premultiplied',
    NativeMaterialRecipe.opaqueColorTransfer => 'opaque-transfer',
    NativeMaterialRecipe.storyBokeh => 'story-bokeh',
    NativeMaterialRecipe.storyColorLut => 'story-lut-ldr',
    NativeMaterialRecipe.storyUber => 'story-uber',
    NativeMaterialRecipe.storyCurvedLens => 'story-curved',
    NativeMaterialRecipe.coverageMask => 'coverage-mask',
  };
  final mask = value.coverageMask;
  if (mask != null) {
    final maskedId = 'ui-masked-$id';
    if (!haneokaShaderPrograms.containsKey(maskedId)) {
      throw ArgumentError('haneoka_unsupported_coverage_mask:$id');
    }
    id = maskedId;
    textures['coverageImage'] = mask.texture;
    uniforms['MaskSettings'] = Float32List(20)
      ..setAll(0, mask.clipToMaskUv)
      ..[16] = mask.mode == CoverageMaskMode.soft ? 1 : 0
      ..[17] = mask.threshold;
  }
  if (value.recipe == NativeMaterialRecipe.uiSourceAlphaAdditive &&
      (value.blend != NativeBlend.sourceAlphaAdditive ||
          value.depthWrite ||
          value.cull != NativeCull.none ||
          value.textureAlpha == TextureAlpha.independent)) {
    throw StateError('haneoka_ui_additive_pass_state');
  }
  if (value.recipe == NativeMaterialRecipe.sourceAlphaTexture &&
      (value.blend != NativeBlend.sourceAlpha ||
          value.depthWrite ||
          value.cull != NativeCull.none ||
          value.textureAlpha == TextureAlpha.independent)) {
    throw StateError('source_alpha_texture_pass_state');
  }
  if (value.recipe == NativeMaterialRecipe.opaqueColorTransfer &&
      (value.blend != NativeBlend.opaque ||
          value.textureAlpha != TextureAlpha.independent ||
          value.depthTest ||
          value.depthWrite ||
          value.cull != NativeCull.none)) {
    throw StateError('haneoka_opaque_color_transfer_state');
  }
  if (value.recipe != NativeMaterialRecipe.solidColor &&
      value.recipe != NativeMaterialRecipe.storyColorLut) {
    textures[mainSlot] = value.texture;
  }
  switch (value.recipe) {
    case NativeMaterialRecipe.storyColorLut:
      for (final slot in const [
        'curveMaster',
        'curveRed',
        'curveGreen',
        'curveBlue',
        'curveHueVsHue',
        'curveHueVsSat',
        'curveSatVsSat',
        'curveLumVsSat',
      ]) {
        textures[slot] = value.additionalTextures[slot]!;
      }
      if (value.uniformFloats != null) {
        uniforms['StoryLutSettings'] = value.uniformFloats!;
      }
    case NativeMaterialRecipe.storyUber:
      textures['gradingLut'] = value.additionalTextures['gradingLut']!;
      textures['bloomImage'] =
          value.additionalTextures['bloomImage'] ?? value.texture;
      if (value.uniformFloats != null) {
        uniforms['StoryUberSettings'] = value.uniformFloats!;
      }
    case NativeMaterialRecipe.storyCurvedLens:
      if (value.uniformFloats != null) {
        uniforms['StoryCurvedSettings'] = value.uniformFloats!;
      }
    case NativeMaterialRecipe.storyBokeh:
      if (value.uniformFloats != null) {
        uniforms['StoryBokehSettings'] = value.uniformFloats!;
      }
    case NativeMaterialRecipe.holdRibbon:
      mainSlot = 'gradient';
      textures.remove('image');
      textures['gradient'] = value.texture;
      textures['mainImage'] =
          value.additionalTextures['mainImage'] ?? value.texture;
      if (value.uniformFloats != null) {
        uniforms['HoldSettings'] = value.uniformFloats!;
      }
    case NativeMaterialRecipe.ruleTransition:
      if (value.uniformFloats != null) {
        uniforms['RuleSettings'] = value.uniformFloats!;
      }
    case NativeMaterialRecipe.sdfText:
      if (value.uniformFloats != null) {
        uniforms['SdfSettings'] = value.uniformFloats!;
      }
    case NativeMaterialRecipe.coverageMask:
      if (value.uniformFloats != null) {
        uniforms['CoverageSettings'] = value.uniformFloats!;
      }
    case NativeMaterialRecipe.postProcess:
      textures['auxiliaryImage'] =
          value.additionalTextures['auxiliaryImage'] ?? value.texture;
      if (value.uniformFloats != null) {
        uniforms['PostSettings'] = value.uniformFloats!;
      }
    case NativeMaterialRecipe.cubism:
      textures['maskImage'] =
          value.additionalTextures['maskImage'] ?? value.texture;
      if (value.uniformFloats != null) {
        uniforms['CubismSettings'] = value.uniformFloats!;
      }
    default:
      break;
  }
  final sampler =
      value.recipe == NativeMaterialRecipe.holdRibbon ||
          value.recipe == NativeMaterialRecipe.ruleTransition ||
          value.recipe == NativeMaterialRecipe.sdfText ||
          value.recipe == NativeMaterialRecipe.postProcess ||
          value.recipe == NativeMaterialRecipe.cubism
      ? TextureSampler(minFilter: value.minFilter, magFilter: value.magFilter)
      : TextureSampler(
          widthAddressMode: value.widthAddressMode,
          heightAddressMode: value.heightAddressMode,
          minFilter: value.minFilter,
          magFilter: value.magFilter,
        );
  return DrawMaterial(
    programId: id,
    textures: textures,
    uniforms: uniforms,
    expectedTextureAlpha: {
      if (textures.isNotEmpty) mainSlot: value.textureAlpha,
      if (value.recipe == NativeMaterialRecipe.cubism &&
          value.additionalTextures.containsKey('maskImage'))
        'maskImage': TextureAlpha.independent,
    },
    samplers: {
      for (final slot in textures.keys)
        slot: slot == 'coverageImage' ? const TextureSampler() : sampler,
    },
    blend: value.blend,
    cull: value.cull,
    depthTest: value.depthTest,
    depthWrite: value.depthWrite,
  );
}

RenderScene toRenderScene(NativeSceneResources source) => RenderScene(
  epoch: source.epoch,
  resourceScopeKey:
      '${source.source.server}:${source.source.release}:${source.source.document}',
  meshes: source.meshes,
  materials: {
    for (final entry in source.materials.entries)
      entry.key: toDrawMaterial(entry.value),
  },
  targets: source.targets,
);
