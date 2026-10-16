#version 450
layout(location=0) in vec4 position;
layout(location=1) in vec3 localPosition;
layout(location=2) in vec4 sourceColor;
layout(location=3) in vec2 sourceBounds;
layout(location=4) in vec4 sourceTexCoords;
layout(location=0) out vec3 local;
layout(location=1) out vec4 color;
layout(location=2) out vec2 bounds;
layout(location=3) out vec4 coords;
void main() {
  gl_Position=position;
  local=localPosition;
  color=sourceColor;
  bounds=sourceBounds;
  coords=sourceTexCoords;
}
