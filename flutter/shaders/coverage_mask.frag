#version 450
layout(location = 0) in vec2 uv;
layout(location = 1) in vec4 tint;
layout(location = 0) out vec4 fragment;
layout(set = 0, binding = 0) uniform sampler2D image;
layout(set = 0, binding = 1) uniform CoverageSettings {
  vec4 values; // soft mode, hard alpha threshold, reserved, reserved
} coverageSettings;
void main() {
  float amount = clamp(texture(image, uv).a * tint.a, 0.0, 1.0);
  if (coverageSettings.values.x < 0.5) {
    if (amount < coverageSettings.values.y) discard;
    amount = 1.0;
  }
  fragment = vec4(amount);
}
