#version 450
layout(location=0) in vec3 local;
layout(location=1) in vec4 color;
layout(location=2) in vec2 bounds;
layout(location=3) in vec4 coords;
layout(location=0) out vec4 fragment;
layout(set=0,binding=0) uniform sampler2D gradient;
layout(set=0,binding=1) uniform sampler2D mainImage;
layout(set=0,binding=2) uniform HoldSettings {
  vec4 controls; // alpha normalization, gradient state, guide, authored main map present
  vec4 glowColor;
  vec4 glow; // intensity, falloff, width, disabled scale
  vec4 scales; // enabled, pressed, zmin, zmax
  vec4 guideColor;
} settings;
float sat(float x) { return clamp(x,0.0,1.0); }
vec3 hsv(vec3 rgb) {
  float maximum=max(rgb.r,max(rgb.g,rgb.b));
  float minimum=min(rgb.r,min(rgb.g,rgb.b));
  float delta=maximum-minimum;
  float hue=0.0;
  if(delta>1e-10) {
    if(maximum==rgb.r) hue=(rgb.g-rgb.b)/delta;
    else if(maximum==rgb.g) hue=2.0+(rgb.b-rgb.r)/delta;
    else hue=4.0+(rgb.r-rgb.g)/delta;
    hue=fract(hue/6.0);
  }
  return vec3(hue,delta/(maximum+1e-10),maximum);
}
vec3 rgb(vec3 value) {
  vec3 wheel=clamp(abs(fract(value.xxx+vec3(0.0,2.0/3.0,1.0/3.0))*6.0-3.0)-1.0,0.0,1.0);
  return value.z*mix(vec3(1.0),wheel,value.y);
}
void main() {
  if(local.z<settings.scales.z || local.z>settings.scales.w) discard;
  float width=bounds.y-bounds.x;
  float across=width>1e-5 ? sat((local.x-bounds.x)/width) : 0.5;
  // Original material's unbound _MainTex is its white default.
  vec2 sampleUv=vec2(mix(coords.x,coords.y,across),1.0-coords.w);
  vec4 texel=vec4(1.0);
  vec3 mainRgb=vec3(1.0);
  if(settings.controls.w>0.5) {
    texel=texture(mainImage,sampleUv);
    mainRgb=mix(texel.rgb,texture(mainImage,sampleUv-vec2(0.0,0.166666001)).rgb,coords.z);
  }
  vec4 nativeGradient=texture(gradient,vec2(color.r,(settings.controls.y+0.5)/3.0));
  float baseAlpha=texel.a*settings.controls.x*color.a;
  float stateScale=settings.controls.y<0.5 ? settings.glow.w :
      settings.controls.y<1.5 ? settings.scales.x : settings.scales.y;
  if(settings.controls.z>0.5) {
    vec4 guideTexel=settings.controls.w>0.5 ? texture(mainImage,vec2(color.b,0.5)) : vec4(1.0);
    float centerGlow=exp(-settings.glow.y*abs(color.b-0.5)*2.0/max(0.0001,settings.glow.z*stateScale));
    vec4 outputColor=guideTexel*settings.guideColor;
    outputColor.rgb+=settings.glowColor.rgb*(settings.glow.x*centerGlow*guideTexel.a);
    outputColor.a*=color.a;
    if(outputColor.a<0.001) discard;
    fragment=vec4(outputColor.rgb*outputColor.a,outputColor.a);
    return;
  }
  vec3 base=mainRgb*nativeGradient.rgb;
  float edge=sat(color.g/max(settings.glow.z,0.001));
  float glow=edge>0.0 ? pow(edge,settings.glow.y)*settings.glow.x*stateScale : 0.0;
  vec3 baseHsv=hsv(base);
  vec3 adjusted=rgb(vec3(baseHsv.x,sat(baseHsv.y-glow),sat(baseHsv.z+glow)));
  vec3 outputRgb=mix(adjusted,settings.glowColor.rgb,glow);
  float distance=width*(1.0-color.g);
  float derivative=abs(dFdx(distance))+abs(dFdy(distance));
  float coverage=width>1e-5 ? sat(distance/max(derivative,1e-5)) : 1.0;
  float outputAlpha=mix(baseAlpha*nativeGradient.a,baseAlpha,glow)*coverage;
  fragment=vec4(outputRgb*outputAlpha,outputAlpha);
}
