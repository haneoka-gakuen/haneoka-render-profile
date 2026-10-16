#version 450
layout(location = 0) in vec2 uv;
layout(location = 1) in vec4 tint;
layout(location = 0) out vec4 fragment;
layout(set = 0, binding = 0) uniform sampler2D image;
// The pass supplies SourceAlpha/One for both channels. RGB remains straight;
// coverage is applied by the declared blend factor exactly once.
void main() {
  vec4 sampleColor = texture(image, uv);
  fragment = vec4(sampleColor.rgb * tint.rgb, sampleColor.a * tint.a);
}
