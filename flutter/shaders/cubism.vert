#version 450
layout(location=0) in vec4 position;
layout(location=1) in vec2 sourceUv;
layout(location=2) in vec4 sourceColor;
layout(location=0) out vec2 uv;
layout(location=1) out vec4 color;
layout(location=2) out vec4 maskClip;
void main() {
  gl_Position=position;
  uv=sourceUv;
  color=sourceColor;
  maskClip=position;
}
