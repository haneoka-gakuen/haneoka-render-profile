import 'dart:typed_data';

import 'package:render_contracts/render_contracts.dart';

export 'package:render_contracts/render_contracts.dart';

final class RenderSource {
  const RenderSource({
    required this.server,
    required this.release,
    required this.document,
  });
  final String server, release, document;
}

enum NativeMaterialRecipe {
  textured,
  solidColor,
  gameComposite,
  holdRibbon,
  cubism,
  cubismMask,
  postProcess,
  mobileHdr,
  sdfText,
  ruleTransition,
  uiSourceAlphaAdditive,
  opaqueColorTransfer,
  storyBokeh,
  storyColorLut,
  storyUber,
  storyCurvedLens,
  coverageMask,
  sourceAlphaTexture,
}

typedef NativeTextureOrigin = TextureOrigin;
typedef NativeColorEncoding = ColorEncoding;
typedef NativeTextureDescriptor = TextureDescriptor;
typedef NativeTextureData = TextureData;
typedef NativeTextureAlpha = TextureAlpha;
typedef NativeBlend = DrawBlend;
typedef NativeCull = DrawCull;
typedef NativeSamplerAddress = SamplerAddress;
typedef NativeTargetFormat = TargetFormat;
typedef ProjectedMesh = GeometryBuffer;
typedef NativeDraw = RenderDraw;
typedef NativePass = RenderPass;
typedef NativeTarget = RenderTarget;
typedef NativeFrame = RenderFrame;

abstract final class NativeMeshLayout {
  static const sprite10 = VertexLayout.sprite;
  static const hold17 = VertexLayout('haneoka-hold', 17);
}

final class NativeMaterial {
  const NativeMaterial({
    required this.texture,
    this.recipe = NativeMaterialRecipe.textured,
    this.blend = NativeBlend.premultipliedAlpha,
    this.depthTest = false,
    this.depthWrite = false,
    this.textureAlpha = NativeTextureAlpha.straight,
    this.uniformFloats,
    this.additionalTextures = const {},
    this.cull = NativeCull.none,
    this.widthAddressMode = NativeSamplerAddress.clampToEdge,
    this.heightAddressMode = NativeSamplerAddress.clampToEdge,
    this.minFilter = SamplerFilter.linear,
    this.magFilter = SamplerFilter.linear,
    this.coverageMask,
  });
  final String texture;
  final NativeMaterialRecipe recipe;
  final NativeBlend blend;
  final NativeTextureAlpha textureAlpha;
  final bool depthTest, depthWrite;
  final Float32List? uniformFloats;
  final Map<String, String> additionalTextures;
  final NativeCull cull;
  final NativeSamplerAddress widthAddressMode, heightAddressMode;
  final SamplerFilter minFilter, magFilter;
  final CoverageMask? coverageMask;
}

final class NativeSceneResources {
  NativeSceneResources({
    required this.epoch,
    required this.source,
    required Map<String, ProjectedMesh> meshes,
    required Map<String, NativeMaterial> materials,
    required Map<String, NativeTarget> targets,
  }) : meshes = Map.unmodifiable(meshes),
       materials = Map.unmodifiable(materials),
       targets = Map.unmodifiable(targets);
  final int epoch;
  final RenderSource source;
  final Map<String, ProjectedMesh> meshes;
  final Map<String, NativeMaterial> materials;
  final Map<String, NativeTarget> targets;
}
