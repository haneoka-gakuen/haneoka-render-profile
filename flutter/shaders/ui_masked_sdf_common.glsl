layout(location=0) in vec2 uv;
layout(location=1) in vec4 tint;
layout(location=0) out vec4 fragment;
layout(set=0,binding=0) uniform sampler2D image;
layout(set=0,binding=1) uniform SdfSettings {
  vec4 face;
  vec4 outline;
  vec4 shadow;
  vec4 edges; // face boundary, stroke radius, softness, pixel footprint
  vec4 shadowSampling; // source UV displacement, boundary, softness
  vec4 features; // authored outline/underlay enable flags
} settings;

// The atlas coverage is a signed-distance ramp. Integrate a linear distance
// ramp across one output pixel rather than displaying the black atlas RGB.
float coverage(float distance,float boundary,float width) {
  return clamp((distance-boundary)/max(width,0.000001)+0.5,0.0,1.0);
}
vec4 premultiplied(vec4 value,float amount) {
  float alpha=value.a*amount;
  return vec4(value.rgb*alpha,alpha);
}

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
  float distance=texture(image,uv).COVERAGE_CHANNEL;
  float radius=settings.features.x>0.5?settings.edges.y:0.0;
  float width=settings.edges.w+settings.edges.z;
  float faceAmount=coverage(distance,settings.edges.x+radius,width);
  float outerAmount=coverage(distance,settings.edges.x-radius,width);
  vec4 face=premultiplied(settings.face*tint,faceAmount);
  vec4 outline=premultiplied(settings.outline*tint,max(outerAmount-faceAmount,0.0));
  vec4 foreground=face+outline;
  if(settings.features.y>0.5) {
    float shadowDistance=texture(image,uv+settings.shadowSampling.xy).COVERAGE_CHANNEL;
    float shadowAmount=coverage(shadowDistance,settings.shadowSampling.z,
      settings.edges.w+settings.shadowSampling.w);
    vec4 shadow=premultiplied(settings.shadow*tint,shadowAmount);
    foreground+=shadow*(1.0-foreground.a);
  }
  fragment=foreground;
  fragment *= maskCoverage();
}
