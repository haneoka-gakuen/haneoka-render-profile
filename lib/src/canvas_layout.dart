import 'dart:math' as math;
import 'dart:typed_data';

import 'canvas_projection.dart';

final class NativeCanvasLayoutMetrics {
  const NativeCanvasLayoutMetrics({
    required this.minimum,
    required this.preferred,
    required this.flexible,
  });
  final List<double> minimum, preferred, flexible;
}

final class NativeCanvasLayoutGroup {
  NativeCanvasLayoutGroup.fromRaw(Map raw) {
    final name = (raw['m_Script'] as Map)['reference']['name'];
    horizontal = name == 'HorizontalLayoutGroup';
    if (!horizontal && name != 'VerticalLayoutGroup')
      throw const FormatException('canvas_layout_group');
    final p = raw['m_Padding'] as Map;
    padding = [
      for (final key in ['m_Left', 'm_Right', 'm_Top', 'm_Bottom'])
        (p[key] as num).toDouble(),
    ];
    spacing = (raw['m_Spacing'] as num).toDouble();
    alignment = raw['m_ChildAlignment'] as int;
    bool flag(String name) => raw[name] == 1 || raw[name] == true;
    control = [flag('m_ChildControlWidth'), flag('m_ChildControlHeight')];
    expand = [
      flag('m_ChildForceExpandWidth'),
      flag('m_ChildForceExpandHeight'),
    ];
    scale = [flag('m_ChildScaleWidth'), flag('m_ChildScaleHeight')];
    reverse = flag('m_ReverseArrangement');
  }
  late final bool horizontal, reverse;
  late final List<double> padding;
  late final List<bool> control, expand, scale;
  late final double spacing;
  late final int alignment;
}

/// Horizontal/vertical source layout drives RectTransform channels before the
/// ordinary affine Canvas placement. Glyph/image measurements stay external.
Map<String, NativeCanvasPlacement> layoutNativeCanvas({
  required List<NativeCanvasNode> nodes,
  required Map<String, NativeCanvasLayoutGroup> groups,
  required Map<String, NativeCanvasLayoutMetrics> elements,
  required double canvasWidth,
  required double canvasHeight,
  required List<double> canvasPivot,
  required Float32List canvasWorld,
}) {
  final current = {for (final node in nodes) node.id: node};
  final children = <String?, List<String>>{};
  for (final node in nodes) (children[node.parent] ??= []).add(node.id);
  Map<String, NativeCanvasPlacement> placements() => placeNativeCanvas(
    nodes: current.values,
    canvasWidth: canvasWidth,
    canvasHeight: canvasHeight,
    canvasPivot: canvasPivot,
    canvasWorld: canvasWorld,
  );
  var placed = placements();
  final totals = <String, List<({double min, double pref, double flex})>>{};
  List<String> activeChildren(String id) => [
    for (final child in children[id] ?? const <String>[])
      if (placed[child]!.active) child,
  ];
  ({double min, double pref, double flex}) size(
    String id,
    NativeCanvasLayoutGroup group,
    int axis,
  ) {
    final node = current[id]!;
    final element = elements[id];
    final calculated = totals[id]?[axis];
    final min = group.control[axis]
        ? math.max(element?.minimum[axis] ?? 0, calculated?.min ?? 0)
        : node.size[axis];
    final pref = group.control[axis]
        ? math.max(
            min,
            math.max(element?.preferred[axis] ?? 0, calculated?.pref ?? 0),
          )
        : node.size[axis];
    final flex = math.max(
      group.expand[axis] ? 1.0 : 0.0,
      group.control[axis]
          ? math.max(element?.flexible[axis] ?? 0, calculated?.flex ?? 0)
          : 0.0,
    );
    return (min: min, pref: pref, flex: flex);
  }

  List<({double min, double pref, double flex})> measure(String id) {
    for (final child in activeChildren(id)) measure(child);
    final group = groups[id];
    if (group == null) return const [];
    final cs = activeChildren(id),
        result = <({double min, double pref, double flex})>[];
    for (var axis = 0; axis < 2; axis++) {
      final pad = axis == 0
              ? group.padding[0] + group.padding[1]
              : group.padding[2] + group.padding[3],
          main = (axis == 0) == group.horizontal;
      var min = pad, pref = pad, flex = 0.0;
      for (final child in cs) {
        final s = size(child, group, axis),
            scale = group.scale[axis] ? current[child]!.scale[axis] : 1.0;
        if (main) {
          min += s.min * scale;
          pref += s.pref * scale;
          flex += s.flex * scale;
        } else {
          min = math.max(min, pad + s.min * scale);
          pref = math.max(pref, pad + s.pref * scale);
          flex = math.max(flex, s.flex * scale);
        }
      }
      if (main && cs.isNotEmpty) {
        min += group.spacing * (cs.length - 1);
        pref += group.spacing * (cs.length - 1);
      }
      result.add((min: min, pref: math.max(min, pref), flex: flex));
    }
    return totals[id] = result;
  }

  void drive(String id, int axis, double position, double? size) {
    final node = current[id]!,
        group = groups[node.parent]!,
        effectiveScale = group.scale[axis] ? node.scale[axis] : 1.0;
    final dimensions = List<double>.of(node.size);
    if (size != null) dimensions[axis] = size;
    final p = Float32List.fromList(node.position);
    p[axis] = axis == 0
        ? position + dimensions[axis] * node.pivot[axis] * effectiveScale
        : -position -
              dimensions[axis] * (1 - node.pivot[axis]) * effectiveScale;
    current[id] = NativeCanvasNode(
      id: id,
      parent: node.parent,
      active: node.active,
      anchorMin: const [0, 1],
      anchorMax: const [0, 1],
      pivot: node.pivot,
      size: dimensions,
      position: p,
      localPositionOverride: null,
      rotationQuaternion: node.rotationQuaternion,
      scale: node.scale,
      opacity: node.opacity,
      ignoreParentGroups: node.ignoreParentGroups,
    );
  }

  void control(String id, int axis) {
    final group = groups[id];
    if (group != null && placed[id]!.active) {
      final main = (axis == 0) == group.horizontal,
          padStart = group.padding[axis == 0 ? 0 : 2],
          padEnd = group.padding[axis == 0 ? 1 : 3],
          extent = axis == 0 ? placed[id]!.width : placed[id]!.height;
      final inner = extent - padStart - padEnd,
          align = axis == 0
              ? (group.alignment % 3) / 2
              : (group.alignment ~/ 3) / 2;
      final cs = group.reverse
              ? activeChildren(id).reversed.toList()
              : activeChildren(id),
          sizes = [
            for (final c
                in group.reverse
                    ? activeChildren(id).reversed
                    : activeChildren(id))
              size(c, group, axis),
          ];
      final total = totals[id]![axis];
      final min = total.min - padStart - padEnd,
          pref = total.pref - padStart - padEnd,
          flex = total.flex;
      final ratio = (pref > min ? (inner - min) / (pref - min) : 0.0).clamp(
            0.0,
            1.0,
          ),
          extra = inner > pref && flex > 0 ? (inner - pref) / flex : 0.0;
      var cursor =
          padStart +
          (main && inner > pref && flex == 0 ? (inner - pref) * align : 0);
      for (var i = 0; i < cs.length; i++) {
        final child = cs[i],
            s = sizes[i],
            node = current[child]!,
            scale = group.scale[axis] ? node.scale[axis] : 1.0;
        final allocated = main
            ? s.min + (s.pref - s.min) * ratio + s.flex * extra
            : math.max(s.min, math.min(inner, s.flex > 0 ? extent : s.pref));
        final drawn = group.control[axis] ? allocated : node.size[axis];
        final position = main
            ? cursor + (group.control[axis] ? 0 : (allocated - drawn) * align)
            : padStart +
                  (inner - allocated * scale) * align +
                  (group.control[axis] ? 0 : (allocated - drawn) * align);
        drive(child, axis, position, group.control[axis] ? drawn : null);
        if (main) cursor += allocated * scale + group.spacing;
      }
      placed = placements();
    }
    for (final child in activeChildren(id)) control(child, axis);
  }

  for (final root in children[null] ?? const <String>[]) {
    measure(root);
    for (var axis = 0; axis < 2; axis++) control(root, axis);
  }
  return placed;
}
