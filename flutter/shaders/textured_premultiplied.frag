#version 450
layout(location = 0) in vec2 uv;
layout(location = 1) in vec4 tint;
layout(location = 0) out vec4 fragment;
layout(set = 0, binding = 0) uniform sampler2D image;
void main() {
  vec4 sampled = texture(image, uv);
  fragment = vec4(sampled.rgb * tint.rgb * tint.a, sampled.a * tint.a);
}
