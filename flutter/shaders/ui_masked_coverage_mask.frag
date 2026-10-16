#version 450
layout(location = 0) in vec2 uv;
layout(location = 1) in vec4 tint;
layout(location = 0) out vec4 fragment;
layout(set = 0, binding = 0) uniform sampler2D image;
layout(set = 0, binding = 1) uniform CoverageSettings {
  vec4 values; // soft mode, hard alpha threshold, reserved, reserved
} coverageSettings;
layout(location = 2) in vec4 maskClip;
layout(set = 0, binding = 2) uniform sampler2D coverageImage;
layout(set = 0, binding = 3) uniform MaskSettings {
  mat4 clipToMaskUv;
  vec4 values; // soft mode, hard alpha threshold, reserved, reserved
} maskSettings;
float maskCoverage() {
  vec4 mapped = maskSettings.clipToMaskUv * maskClip;
  if (mapped.w <= 0.0) discard;
  vec2 maskUv = mapped.xy / mapped.w;
  if (any(lessThan(maskUv, vec2(0.0))) || any(greaterThan(maskUv, vec2(1.0)))) discard;
  float amount = clamp(texture(coverageImage, maskUv).a, 0.0, 1.0);
  if (maskSettings.values.x < 0.5) {
    if (amount < maskSettings.values.y) discard;
    return 1.0;
  }
  return amount;
}

void main() {
  float amount = clamp(texture(image, uv).a * tint.a, 0.0, 1.0);
  if (coverageSettings.values.x < 0.5) {
    if (amount < coverageSettings.values.y) discard;
    amount = 1.0;
  }
  fragment = vec4(amount);
  fragment *= maskCoverage();
}
