import 'package:render_contracts/render_contracts.dart';

import 'dart:typed_data';

export 'package:render_contracts/render_contracts.dart';

typedef NativeSpriteGeometry = GeometryShape;
typedef NativeLocalTransform = LocalTransform;
GeometryBuffer projectSprite(
  GeometryShape sprite,
  Float32List clipFromLocal,
  Float32List tintRgba,
) => projectGeometry(sprite, clipFromLocal, tintRgba);
