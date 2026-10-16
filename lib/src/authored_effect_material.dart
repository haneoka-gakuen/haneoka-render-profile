import 'dart:typed_data';

import 'authored_effect_graph.dart';
import 'render_ir.dart';

/// Source material numbers and an explicit generic render recipe.
/// Mobile particle shaders sample vertex colour without an HDR tint property.
final class NativeParticleMaterial {
  NativeParticleMaterial.mobileHdr(NativeMobileHdrMaterial value)
    : hdr = value,
      textureTransform = value.textureTransform,
      recipe = NativeMaterialRecipe.mobileHdr,
      blend = NativeBlend.sourceAlphaAdditive;

  NativeParticleMaterial._(this.textureTransform, this.recipe, this.blend)
    : hdr = null;

  factory NativeParticleMaterial.fromSource(
    NativeEffectObject material, {
    required NativeAuthoredEffectGraph graph,
  }) {
    if (material.type != 'Material') {
      throw ArgumentError('particle_material_type');
    }
    final shader = graph.reference(material, material.data['m_Shader'] as Map);
    if (shader == null || shader.type != 'Shader') {
      throw FormatException('particle_material_shader:${material.key}');
    }
    final parsed = shader.data['m_ParsedForm'] as Map;
    final name = parsed['m_Name'];
    if (name == 'Custom/Mobile/MobileAddHdrColor') {
      return NativeParticleMaterial.mobileHdr(
        NativeMobileHdrMaterial(material),
      );
    }
    final NativeBlend blend;
    final NativeMaterialRecipe recipe;
    final int destination;
    switch (name) {
      case 'Mobile/Particles/Additive':
        blend = NativeBlend.sourceAlphaAdditive;
        recipe = NativeMaterialRecipe.uiSourceAlphaAdditive;
        destination = 1;
        break;
      case 'Mobile/Particles/Alpha Blended':
        blend = NativeBlend.sourceAlpha;
        recipe = NativeMaterialRecipe.sourceAlphaTexture;
        destination = 10;
        break;
      default:
        throw UnsupportedError('particle_material_shader:$name');
    }
    final passes =
        ((parsed['m_SubShaders'] as List).single as Map)['m_Passes'] as List;
    final state = (passes.single as Map)['m_State'] as Map;
    final factors = state['rtBlend0'] as Map;
    double value(Map record, String field) =>
        ((record[field] as Map)['val'] as num).toDouble();
    if (value(factors, 'srcBlend') != 5 ||
        value(factors, 'srcBlendAlpha') != 5 ||
        value(factors, 'destBlend') != destination ||
        value(factors, 'destBlendAlpha') != destination ||
        value(factors, 'blendOp') != 0 ||
        value(factors, 'blendOpAlpha') != 0 ||
        value(factors, 'colMask') != 15 ||
        value(state, 'culling') != 0 ||
        value(state, 'zWrite') != 0) {
      throw UnsupportedError('particle_material_pass:${shader.key}');
    }
    final saved = material.data['m_SavedProperties'] as Map;
    if ((saved['m_Colors'] as List).isNotEmpty ||
        (saved['m_Floats'] as List).isNotEmpty ||
        (saved['m_Ints'] as List).isNotEmpty) {
      throw UnsupportedError('particle_material_properties:${material.key}');
    }
    final textures = (saved['m_TexEnvs'] as List).cast<List>();
    if (textures.length != 1 || textures.single[0] != '_MainTex') {
      throw UnsupportedError('particle_material_textures:${material.key}');
    }
    final texture = textures.single[1] as Map;
    final scale = texture['m_Scale'] as Map,
        offset = texture['m_Offset'] as Map;
    return NativeParticleMaterial._(
      Float32List.fromList([
        for (final v in [scale['x'], scale['y'], offset['x'], offset['y']])
          (v as num).toDouble(),
      ]),
      recipe,
      blend,
    );
  }

  final NativeMobileHdrMaterial? hdr;
  final Float32List textureTransform;
  final NativeMaterialRecipe recipe;
  final NativeBlend blend;

  Float32List vertexColor(
    List<double> color, {
    List<double>? authoredTintOverride,
  }) {
    if (hdr case final material?) {
      return material.hdrVertexColor(
        color,
        authoredTintOverride: authoredTintOverride,
      );
    }
    return Float32List.fromList([
      for (var i = 0; i < 4; i++)
        authoredTintOverride == null
            ? color[i]
            : color[i] * authoredTintOverride[i],
    ]);
  }

  NativeMaterial materialFor(
    String texture, {
    NativeTextureAlpha textureAlpha = NativeTextureAlpha.straight,
  }) => NativeMaterial(
    texture: texture,
    recipe: recipe,
    blend: blend,
    textureAlpha: textureAlpha,
  );
}

/// Numeric material state only. No serialized shader program is interpreted.
final class NativeMobileHdrMaterial {
  NativeMobileHdrMaterial(NativeEffectObject material) {
    if (material.type != 'Material') {
      throw ArgumentError('native_hdr_material_type');
    }
    final shader = material.data['m_Shader'] as Map,
        reference = shader['reference'] as Map;
    if (reference['status'] != 'resolved' ||
        reference['pathId'] != shader['m_PathID'] ||
        reference['type'] != 'Shader' ||
        reference['name'] != 'Custom/Mobile/MobileAddHdrColor') {
      throw UnsupportedError(
        'native_hdr_material_shader_identity:${material.key}',
      );
    }
    final saved = material.data['m_SavedProperties'] as Map;
    Map property(String list, String name) {
      final matches = (saved[list] as List)
          .where((row) => (row as List)[0] == name)
          .toList();
      if (matches.length != 1) {
        throw StateError('native_hdr_material_property:$name');
      }
      return (matches.single as List)[1] as Map;
    }

    final color = property('m_Colors', '_TintColor'),
        texture = property('m_TexEnvs', '_MainTex');
    tint = Float32List.fromList([
      for (final channel in ['r', 'g', 'b', 'a'])
        (color[channel] as num).toDouble(),
    ]);
    texturePointer = Map<String, Object?>.unmodifiable(
      Map<String, Object?>.from(texture['m_Texture'] as Map),
    );
    final scale = texture['m_Scale'] as Map,
        offset = texture['m_Offset'] as Map;
    textureTransform = Float32List.fromList([
      for (final value in [scale['x'], scale['y'], offset['x'], offset['y']])
        (value as num).toDouble(),
    ]);
  }
  late final Float32List tint, textureTransform;
  late final Map<String, Object?> texturePointer;
  Float32List hdrVertexColor(
    List<double> sourceColor, {
    List<double>? authoredTintOverride,
  }) {
    if (sourceColor.length != 4 ||
        (authoredTintOverride != null && authoredTintOverride.length != 4)) {
      throw ArgumentError('native_hdr_color_components');
    }
    final effective = authoredTintOverride ?? tint;
    return Float32List.fromList([
      for (var channel = 0; channel < 4; channel++)
        2 * sourceColor[channel] * effective[channel] * effective[channel],
    ]);
  }
}
