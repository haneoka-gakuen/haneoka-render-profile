#version 450
layout(location=0) in vec2 uv;
layout(location=1) in vec4 tint;
layout(location=0) out vec4 fragment;
layout(set=0,binding=0) uniform sampler2D image;
layout(set=0,binding=1) uniform RuleSettings { vec4 controls; } settings;
void main() {
  float value = settings.controls.x;
  float coverage;
  if (settings.controls.y > 0.5) {
    float rule = texture(image,uv).r;
    coverage = clamp((rule - (value * 0.600000024 + 0.400000006)) * 5.0,0.0,1.0);
  } else {
    coverage = clamp((1.0-value)*0.5,0.0,1.0);
  }
  float alpha = coverage*coverage*(3.0-2.0*coverage)*tint.a;
  fragment = vec4(tint.rgb*alpha,alpha);
}
