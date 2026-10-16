#version 450
layout(location=0) in vec2 uv;
layout(location=1) in vec4 color;
layout(location=2) in vec4 maskClip;
layout(location=0) out vec4 fragment;
layout(set=0,binding=0) uniform sampler2D image;
layout(set=0,binding=1) uniform sampler2D maskImage;
layout(set=0,binding=2) uniform CubismSettings {
  vec4 multiplyColor;
  vec4 screenColor;
  vec4 controls;
  vec4 maskUvX;
  vec4 maskUvY;
  vec4 maskUvW;
  vec4 maskChannel;
  vec4 maskTileBounds;
  vec4 lighting;
} settings;
void main() {
  vec4 texel=texture(image,uv);
  vec3 rgb=texel.rgb*settings.multiplyColor.rgb;
  rgb*=settings.lighting.rgb;
  float coverage=1.0;
  if(settings.controls.x>0.5) {
    float w=dot(settings.maskUvW,maskClip);
    vec2 maskUv=vec2(dot(settings.maskUvX,maskClip),
                     dot(settings.maskUvY,maskClip))/w;
    bool inside=all(greaterThanEqual(maskUv,settings.maskTileBounds.xy)) &&
                all(lessThanEqual(maskUv,settings.maskTileBounds.zw));
    coverage=inside?dot(texture(maskImage,maskUv),settings.maskChannel):0.0;
    if(settings.controls.y>0.5) coverage=1.0-coverage;
  }
  float alpha=texel.a*color.a*coverage;
  fragment=vec4(rgb*color.rgb*color.a*coverage,alpha);
}
