double _number(Object? value, String field) {
  if (value is! num || !value.isFinite) {
    throw FormatException('source_font_$field');
  }
  return value.toDouble();
}

List<double> _tuple(Object? value, int count, String field) {
  if (value is! List || value.length != count) {
    throw FormatException('source_font_$field');
  }
  return List.unmodifiable(value.map((v) => _number(v, field)));
}

final class SourceFontGlyph {
  SourceFontGlyph({
    required this.index,
    required this.atlasPage,
    required this.rect,
    required this.metrics,
    required this.scale,
  });
  final int index, atlasPage;

  /// Original TMP atlas pixel rectangle, bottom-left origin.
  final List<double> rect;

  /// Width, height, bearingX, bearingY, horizontalAdvance.
  final List<double> metrics;
  final double scale;
}

final class SourceGlyphSelection {
  const SourceGlyphSelection(this.font, this.glyph, this.characterScale);
  final SourceFontData font;
  final SourceFontGlyph glyph;
  final double characterScale;
}

final class SourceFontData {
  SourceFontData._({
    required this.id,
    required this.sourceHash,
    required this.size,
    required this.ascent,
    required this.descent,
    required this.lineHeight,
    required this.padding,
    required this.scale,
    required this.atlasWidth,
    required this.atlasHeight,
    required this.boldSpacing,
    required this.normalWeight,
    required this.boldWeight,
    required this.atlasAssets,
    required this.characters,
    required this.glyphs,
  });
  final String id, sourceHash;
  final double size,
      ascent,
      descent,
      lineHeight,
      padding,
      scale,
      atlasWidth,
      atlasHeight,
      boldSpacing,
      normalWeight,
      boldWeight;
  final List<String> atlasAssets;
  final Map<int, (int, double)> characters;
  final Map<int, SourceFontGlyph> glyphs;

  factory SourceFontData.fromJson(
    Map<String, Object?> data, {
    required String sourceHash,
    required List<String> actualAtlasAssetKeys,
    List? glyphPairs,
  }) {
    if (!RegExp(r'^[a-f0-9]{64}$').hasMatch(sourceHash) ||
        data['id'] is! String ||
        data['characters'] is! Map ||
        data['glyphs'] is! Map ||
        actualAtlasAssetKeys.isEmpty) {
      throw const FormatException('source_font_source');
    }
    final characters = <int, (int, double)>{};
    for (final e in (data['characters'] as Map).entries) {
      final code = int.parse(e.key.toString());
      final values = _tuple(e.value, 2, 'character');
      characters[code] = (values[0].toInt(), values[1]);
    }
    final glyphs = <int, SourceFontGlyph>{};
    for (final e in (data['glyphs'] as Map).entries) {
      final value = Map<String, Object?>.from(e.value as Map);
      final index = int.parse(e.key.toString()),
          page = (value['atlas'] as num).toInt();
      if (page < 0 || page >= actualAtlasAssetKeys.length) {
        throw const FormatException('source_font_atlas');
      }
      glyphs[index] = SourceFontGlyph(
        index: index,
        atlasPage: page,
        rect: _tuple(value['rect'], 4, 'rect'),
        metrics: _tuple(value['metrics'], 5, 'metrics'),
        scale: _number(value['scale'], 'glyph_scale'),
      );
    }
    final font = SourceFontData._(
      id: data['id'] as String,
      sourceHash: sourceHash,
      size: _number(data['size'], 'size'),
      ascent: _number(data['ascent'], 'ascent'),
      descent: _number(data['descent'], 'descent'),
      lineHeight: _number(data['lineHeight'], 'lineHeight'),
      padding: _number(data['padding'], 'padding'),
      scale: _number(data['scale'], 'scale'),
      atlasWidth: _number(data['atlasWidth'], 'atlasWidth'),
      atlasHeight: _number(data['atlasHeight'], 'atlasHeight'),
      boldSpacing: _number(data['boldSpacing'], 'boldSpacing'),
      normalWeight: _number(data['normalWeight'], 'normalWeight'),
      boldWeight: _number(data['boldWeight'], 'boldWeight'),
      atlasAssets: List.unmodifiable(actualAtlasAssetKeys),
      characters: Map.unmodifiable(characters),
      glyphs: Map.unmodifiable(glyphs),
    );
    if (font.size <= 0 || font.atlasWidth <= 0 || font.atlasHeight <= 0) {
      throw const FormatException('source_font_dimensions');
    }
    for (final row
        in (glyphPairs ?? data['pairs'] as List? ?? const []).cast<List>()) {
      font.pairs['${row[0]}:${row[1]}'] = (
        (row[2] as List).map((v) => (v as num).toDouble()).toList(),
        (row[3] as List).map((v) => (v as num).toDouble()).toList(),
      );
    }
    return font;
  }

  final pairs = <String, (List<double>, List<double>)>{};

  SourceGlyphSelection? select(int unicode) {
    final character = characters[unicode];
    if (character == null) return null;
    final glyph = glyphs[character.$1];
    return glyph == null
        ? null
        : SourceGlyphSelection(this, glyph, character.$2);
  }
}

/// The source-specific caller supplies the actual ordered locale/font chain.
final class SourceSdfFontBank {
  SourceSdfFontBank(List<SourceFontData> fonts)
    : fonts = List.unmodifiable(fonts) {
    if (fonts.isEmpty) throw const FormatException('source_font_bank');
  }
  final List<SourceFontData> fonts;
  SourceGlyphSelection? select(int unicode) {
    for (final font in fonts) {
      final glyph = font.select(unicode);
      if (glyph != null) return glyph;
    }
    return null;
  }
}
