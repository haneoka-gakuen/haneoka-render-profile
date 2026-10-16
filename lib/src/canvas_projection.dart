import 'dart:typed_data';

import 'authored_effect_graph.dart';
import 'projection.dart';
import 'render_ir.dart';

/// Actual RectTransform inputs after the source animation/controller update.
/// Canvas extent, pivot and camera projection are supplied by their source
/// owners; this layer has no reference resolution or camera defaults.
final class NativeCanvasNode {
  const NativeCanvasNode({
    required this.id,
    required this.parent,
    required this.active,
    required this.anchorMin,
    required this.anchorMax,
    required this.pivot,
    required this.size,
    required this.position,
    required this.localPositionOverride,
    required this.rotationQuaternion,
    required this.scale,
    required this.opacity,
    required this.ignoreParentGroups,
  });
  final String id;
  final String? parent;
  final bool active;
  final List<double> anchorMin, anchorMax, pivot, size;

  /// Position x/y are source anchoredPosition; z is source localPosition.z.
  final Float32List position, rotationQuaternion, scale;

  /// Transform-position animation supplies local XYZ directly, independently
  /// of anchoredPosition animation and actual parent rectangle dimensions.
  final Float32List? localPositionOverride;
  final double opacity;
  final bool ignoreParentGroups;
}

final class NativeCanvasPlacement {
  const NativeCanvasPlacement(
    this.width,
    this.height,
    this.opacity,
    this.matrix,
    this.active,
  );
  final double width, height, opacity;
  final Float32List matrix;
  final bool active;
}

/// The hierarchy's affine placement retains original Unity y-up coordinates
/// and homogeneous camera W. Ancestor opacity/active state is applied once.
Map<String, NativeCanvasPlacement> placeNativeCanvas({
  required Iterable<NativeCanvasNode> nodes,
  required double canvasWidth,
  required double canvasHeight,
  required List<double> canvasPivot,
  required Float32List canvasWorld,
}) {
  final byId = <String, NativeCanvasNode>{};
  for (final node in nodes) {
    if (node.ignoreParentGroups) {
      throw UnsupportedError('native_canvas_ignore_parent_groups:${node.id}');
    }
    if (byId.containsKey(node.id)) {
      throw FormatException('native_canvas_duplicate:${node.id}');
    }
    byId[node.id] = node;
  }
  final cache = <String, NativeCanvasPlacement>{}, visiting = <String>{};
  NativeCanvasPlacement place(String id) {
    if (cache[id] case final value?) return value;
    final node = byId[id];
    if (node == null) throw FormatException('native_canvas_parent:$id');
    if (!visiting.add(id)) throw FormatException('native_canvas_cycle:$id');
    final parent = node.parent == null
        ? NativeCanvasPlacement(canvasWidth, canvasHeight, 1, canvasWorld, true)
        : place(node.parent!);
    final parentPivot = node.parent == null
        ? canvasPivot
        : byId[node.parent]!.pivot;
    final width =
            parent.width * (node.anchorMax[0] - node.anchorMin[0]) +
            node.size[0],
        height =
            parent.height * (node.anchorMax[1] - node.anchorMin[1]) +
            node.size[1];
    final x =
            parent.width *
                (node.anchorMin[0] +
                    (node.anchorMax[0] - node.anchorMin[0]) * node.pivot[0] -
                    parentPivot[0]) +
            node.position[0],
        y =
            parent.height *
                (node.anchorMin[1] +
                    (node.anchorMax[1] - node.anchorMin[1]) * node.pivot[1] -
                    parentPivot[1]) +
            node.position[1];
    final local = NativeLocalTransform(
      position:
          node.localPositionOverride ??
          Float32List.fromList([x, y, node.position[2]]),
      quaternion: node.rotationQuaternion,
      scale: node.scale,
    ).matrix();
    final active = node.active && parent.active;
    final value = NativeCanvasPlacement(
      width,
      height,
      active ? parent.opacity * node.opacity.clamp(0.0, 1.0) : 0,
      NativeAuthoredEffectGraph.multiply(parent.matrix, local),
      active,
    );
    cache[id] = value;
    visiting.remove(id);
    return value;
  }

  for (final id in byId.keys) {
    place(id);
  }
  return Map.unmodifiable(cache);
}

/// Image geometry arrives in the normalized canvas coordinates produced by
/// the native image primitive. Convert it to original local units, preserve
/// UV/color and project through the actual node/canvas/camera matrices.
ProjectedMesh projectNativeCanvasImage({
  required ProjectedMesh image,
  required double canvasWidth,
  required double canvasHeight,
  required Float32List localClip,
  required double inheritedOpacity,
}) {
  if (image.layout != NativeMeshLayout.sprite10 ||
      canvasWidth <= 0 ||
      canvasHeight <= 0 ||
      localClip.length != 16 ||
      !inheritedOpacity.isFinite ||
      inheritedOpacity < 0 ||
      inheritedOpacity > 1) {
    throw const FormatException('native_canvas_image_projection');
  }
  final vertices = Float32List.fromList(image.vertices);
  for (var i = 0; i < vertices.length; i += 10) {
    final x = (vertices[i] + 1) * canvasWidth / 2,
        y = (vertices[i + 1] - 1) * canvasHeight / 2;
    for (var row = 0; row < 4; row++) {
      vertices[i + row] =
          localClip[row] * x + localClip[4 + row] * y + localClip[12 + row];
    }
    vertices[i + 9] *= inheritedOpacity;
  }
  return ProjectedMesh(vertices, image.indices);
}
