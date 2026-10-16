#version 450
layout(location = 0) in vec2 uv;
layout(location = 1) in vec4 tint;
layout(location = 0) out vec4 fragment;
layout(set = 0, binding = 0) uniform sampler2D image;
// Official image decoding supplies premultiplied pixels. Recover straight
// sample RGB before the source pass applies its SourceAlpha factor.
void main() {
  vec4 sampleColor = texture(image, uv);
  vec3 straightColor = sampleColor.a > 0.0
      ? sampleColor.rgb / sampleColor.a : vec3(0.0);
  fragment = vec4(straightColor * tint.rgb, sampleColor.a * tint.a);
}
