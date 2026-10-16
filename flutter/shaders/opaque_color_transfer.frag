#version 450
layout(location = 0) in vec2 uv;
layout(location = 1) in vec4 tint;
layout(location = 0) out vec4 fragment;
layout(set = 0, binding = 0) uniform sampler2D image;
void main() {
  fragment = vec4(texture(image, uv).rgb, 1.0);
}
