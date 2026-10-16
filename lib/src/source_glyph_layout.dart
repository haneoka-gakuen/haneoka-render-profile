import 'source_sdf_font.dart';

import 'dart:typed_data';

final class SourceGlyphPadding {
  const SourceGlyphPadding(this.materialPadding, this.stylePadding);
  final double materialPadding, stylePadding;
}

typedef SourceGlyphPaddingResolver = SourceGlyphPadding Function(
  SourceFontData font,
  bool bold,
);

final _glyphSingle = Float32List(1);
double sourceGlyphF32(double value) {
  _glyphSingle[0] = value;
  return _glyphSingle[0];
}

double sourceGlyphSourceScale({
  required double size,
  required SourceFontData font,
  required SourceGlyphSelection selection,
}) {
  final f = sourceGlyphF32;
  return f(
    f(f(f(size / font.size) * font.scale) * selection.characterScale) *
        selection.glyph.scale,
  );
}

/// Source padding separates horizontal style expansion from vertical padding.
({List<double> rect, List<double> uv}) sourceGlyphPaddedGeometry({
  required SourceFontData font,
  required SourceFontGlyph glyph,
  required SourceGlyphPadding padding,
  required double scale,
  required double penX,
  required double baseline,
}) {
  final f = sourceGlyphF32,
      p = padding.materialPadding,
      sp = padding.stylePadding,
      m = glyph.metrics,
      r = glyph.rect;
  if (!p.isFinite || !sp.isFinite || p < 0 || !scale.isFinite) {
    throw const FormatException('source_glyph_padding');
  }
  final left = f(f(penX) + f(f(f(m[2] - p) - sp) * scale));
  final top = f(f(baseline) - f(f(m[3] + p) * scale));
  final right = f(left + f(f(f(m[0] + p * 2) + sp * 2) * scale));
  final bottom = f(top + f(f(m[1] + p * 2) * scale));
  final pad = f(p + sp);
  final u0 = f(f(r[0] - pad) / font.atlasWidth);
  final v0 = f(f(r[1] - pad) / font.atlasHeight);
  final u1 = f(f(f(r[0] + r[2]) + pad) / font.atlasWidth);
  final v1 = f(f(f(r[1] + r[3]) + pad) / font.atlasHeight);
  return (
    rect: [left, top, f(right - left), f(bottom - top)],
    uv: [u0, f(1 - v1), f(u1 - u0), f(v1 - v0)],
  );
}

final class SourceGlyphQuad {
  const SourceGlyphQuad({
    required this.unicode,
    required this.glyphIndex,
    required this.fontId,
    required this.atlasAsset,
    required this.atlasPage,
    required this.renderedIndex,
    required this.rect,
    required this.uvTopLeft,
    required this.baseline,
    required this.color,
    required this.bold,
    this.rubyGroup,
    this.isRuby = false,
    this.glyphScale,
  });
  final int unicode, glyphIndex, atlasPage, renderedIndex;
  final String fontId, atlasAsset;

  /// Local text coordinates: x right, y down; rect is left/top/width/height.
  final List<double> rect, uvTopLeft, color;
  final double baseline;
  final bool bold, isRuby;

  /// Source metric-to-local scale, retained for the host's SDF sampling.
  final double? glyphScale;
  final int? rubyGroup;
}

final class SourceGlyphRun {
  const SourceGlyphRun({
    required this.text,
    required this.fontSize,
    required this.color,
    required this.bold,
    required this.typingIndices,
    this.baselineOffset = 0,
    this.rubyGroup,
    this.isRuby = false,
    this.originX,
  });
  final String text;
  final double fontSize, baselineOffset;
  final List<double> color;
  final bool bold, isRuby;

  /// Actual component-preprocessed character indices. Ruby annotations may
  /// have independent TMP indices or a base association; the caller pins it.
  final List<int> typingIndices;
  final int? rubyGroup;
  final double? originX;
}

final class SourceGlyphLayout {
  const SourceGlyphLayout({
    required this.quads,
    required this.renderedGlyphCount,
    required this.letterTestText,
    required this.width,
    required this.height,
    required this.lineBaselines,
    required this.missingGlyphs,
    required this.unsupported,
    int? meshCharacterCount,
  }) : meshCharacterCount = meshCharacterCount ?? renderedGlyphCount;
  final List<SourceGlyphQuad> quads;
  final int renderedGlyphCount;

  /// Mesh preprocessing stream includes Ruby annotations. The typing helper
  /// can have a distinct count for quoted Ruby and explicit sprite tags.
  final int meshCharacterCount;
  final String letterTestText;
  final double width, height;
  final List<double> lineBaselines;
  final Set<int> missingGlyphs;
  final List<String> unsupported;
  bool get usable => missingGlyphs.isEmpty && unsupported.isEmpty;
  Iterable<SourceGlyphQuad> visibleQuads(int maxVisibleCharacters) =>
      quads.where((q) => q.renderedIndex < maxVisibleCharacters);
}

/// Geometry is built from actual glyph advances/bearings. The caller's
/// preprocessed runs retain ruby and emoji components and original styling.
/// Supplied break positions come from the source's line-breaking rules.
SourceGlyphLayout layoutSourceGlyphRuns({
  required SourceSdfFontBank fonts,
  required List<SourceGlyphRun> runs,
  required String letterTestText,
  required double characterSpacing,
  required double lineSpacing,
  required double maxWidth,
  required Set<int> actualBreakBeforeIndices,
  required int actualRenderedGlyphCount,
  SourceGlyphPaddingResolver? paddingResolver,
  bool kerning = false,
}) {
  if (!maxWidth.isFinite ||
      maxWidth < 0 ||
      runs.any((r) => !r.fontSize.isFinite || r.fontSize <= 0)) {
    throw const FormatException('source_glyph_layout_input');
  }
  final quads = <SourceGlyphQuad>[],
      missing = <int>{},
      unsupported = <String>[];
  final primary = fonts.fonts.first;
  final baseSize = runs.isEmpty ? primary.size : runs.first.fontSize;
  final baseScale = baseSize / primary.size * primary.scale;
  final lineAdvance =
      primary.lineHeight * baseScale + lineSpacing * baseSize / 100;
  var baseline = primary.ascent * baseScale, x = 0.0, width = 0.0, index = 0;
  final baselines = <double>[baseline];
  void nextLine() {
    baseline += lineAdvance;
    baselines.add(baseline);
    x = 0;
  }

  for (final run in runs) {
    final units = run.text.runes.toList(growable: false);
    if (units.length != run.typingIndices.length ||
        run.typingIndices.any((i) => i < 0 || i >= actualRenderedGlyphCount) ||
        (run.isRuby && run.originX == null)) {
      throw const FormatException('source_glyph_source_indices');
    }
    final previousCursor = x;
    if (run.originX != null) x = run.originX!;
    final pairAdjustments = kerning
        ? List.generate(units.length, (_) => [0.0, 0.0, 0.0])
        : const <List<double>>[];
    if (kerning) {
      final selected = [for (final code in units) fonts.select(code)];
      for (var i = 0; i < selected.length - 1; i++) {
        final first = selected[i], second = selected[i + 1];
        if (first == null ||
            second == null ||
            !identical(first.font, second.font))
          continue;
        final pair =
            first.font.pairs['${first.glyph.index}:${second.glyph.index}'];
        if (pair == null) continue;
        for (var c = 0; c < 3; c++) {
          pairAdjustments[i][c] += pair.$1[c];
          pairAdjustments[i + 1][c] += pair.$2[c];
        }
      }
    }
    var unitIndex = 0;
    for (final code in units) {
      index = run.typingIndices[unitIndex++];
      if (code == 10 || code == 13) {
        index++;
        nextLine();
        continue;
      }
      final selected = fonts.select(code);
      if (selected == null) {
        missing.add(code);
        index++;
        continue;
      }
      final font = selected.font, glyph = selected.glyph;
      final scale = paddingResolver != null
          ? sourceGlyphSourceScale(
              size: run.fontSize,
              font: font,
              selection: selected,
            )
          : run.fontSize /
                font.size *
                font.scale *
                glyph.scale *
                selected.characterScale;
      final spacing =
          (characterSpacing + (run.bold ? font.boldSpacing : 0)) *
          run.fontSize /
          100;
      final adjustment = kerning
          ? pairAdjustments[unitIndex - 1]
          : const [0.0, 0.0, 0.0];
      final advance = kerning
          ? (glyph.metrics[4] + adjustment[2]) * scale + spacing
          : glyph.metrics[4] * scale + spacing;
      if (maxWidth > 0 && x + advance > maxWidth) {
        if (actualBreakBeforeIndices.contains(index)) {
          nextLine();
        } else {
          if (!unsupported.contains('source_line_break_required')) {
            unsupported.add('source_line_break_required');
          }
        }
      }
      final yBaseline = kerning
          ? baseline + run.baselineOffset - adjustment[1] * scale
          : baseline + run.baselineOffset;
      final penX = kerning ? x + adjustment[0] * scale : x;
      if (glyph.metrics[0] > 0 &&
          glyph.metrics[1] > 0 &&
          code != 32 &&
          code != 9) {
        final p = font.padding, rect = glyph.rect;
        final geometry = paddingResolver == null
            ? null
            : sourceGlyphPaddedGeometry(
                font: font,
                glyph: glyph,
                padding: paddingResolver(font, run.bold),
                scale: scale,
                penX: penX,
                baseline: yBaseline,
              );
        quads.add(
          SourceGlyphQuad(
            unicode: code,
            glyphIndex: glyph.index,
            fontId: font.id,
            atlasAsset: font.atlasAssets[glyph.atlasPage],
            atlasPage: glyph.atlasPage,
            renderedIndex: index,
            baseline: yBaseline,
            rect: List.unmodifiable(
              geometry?.rect ??
                  [
                    penX + (glyph.metrics[2] - p) * scale,
                    yBaseline - (glyph.metrics[3] + p) * scale,
                    (glyph.metrics[0] + p * 2) * scale,
                    (glyph.metrics[1] + p * 2) * scale,
                  ],
            ),
            uvTopLeft: List.unmodifiable(
              geometry?.uv ??
                  [
                    (rect[0] - p) / font.atlasWidth,
                    1 - (rect[1] + rect[3] + p) / font.atlasHeight,
                    (rect[2] + p * 2) / font.atlasWidth,
                    (rect[3] + p * 2) / font.atlasHeight,
                  ],
            ),
            color: List.unmodifiable(run.color),
            bold: run.bold,
            glyphScale: scale,
            rubyGroup: run.rubyGroup,
            isRuby: run.isRuby,
          ),
        );
      }
      x += advance;
      if (x > width) width = x;
      index++;
    }
    if (run.isRuby) x = previousCursor;
  }
  return SourceGlyphLayout(
    quads: List.unmodifiable(quads),
    renderedGlyphCount: actualRenderedGlyphCount,
    letterTestText: letterTestText,
    width: width,
    height: baseline - primary.descent * baseScale,
    lineBaselines: List.unmodifiable(baselines),
    missingGlyphs: Set.unmodifiable(missing),
    unsupported: List.unmodifiable(unsupported),
  );
}

/// Shared measured auto-size search; the source binding supplies its own size
/// limits and wrapping policy through the compiler callback.
SourceGlyphLayout measureSourceGlyphAutoSize({
  required SourceGlyphLayout Function(double) compile,
  required double size,
  required bool autoSize,
  required double minimum,
  required double maximum,
  required double width,
  required double height,
}) {
  if (!autoSize) return compile(size);
  var lower = minimum, upper = maximum;
  var best = compile(lower);
  for (var iteration = 0; iteration < 20 && upper - lower > .05; iteration++) {
    final candidate = (upper + lower) / 2, result = compile(candidate);
    if ((width <= 0 || result.width <= width) &&
        (height <= 0 || result.height <= height)) {
      lower = candidate;
      best = result;
    } else {
      upper = candidate;
    }
  }
  final result = compile(upper);
  return (width <= 0 || result.width <= width) &&
          (height <= 0 || result.height <= height)
      ? result
      : best;
}
