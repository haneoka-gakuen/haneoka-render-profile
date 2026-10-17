#version 450
layout(location=0) in vec2 uv;
layout(location=1) in vec4 tint;
layout(location=0) out vec4 fragment;
layout(set=0,binding=0) uniform sampler2D image;
layout(set=0,binding=1) uniform sampler2D gradingLut;
layout(set=0,binding=2) uniform sampler2D bloomImage;
layout(set=0,binding=3) uniform StoryUberSettings {
  vec4 texel;       // inverse width/height, width/height
  vec4 color;       // exposure, chroma amount, vignette intensity/smoothness
  vec4 vignette;    // RGB, rounded aspect
  vec4 center;      // vignette xy, input gamma, output gamma
  vec4 bloom;       // intensity, normalized linear tint RGB
  vec4 lut;         // inverse strip width/height, size-1, reserved
  vec4 distortion;  // center xy, multiplier xy
  vec4 warp;        // theta, sigma, inverse scale, signed amount
} settings;

vec3 fastLinear(vec3 value) {
  return value * (value * (value * 0.305306017 + 0.682171106) + 0.0125228781);
}
vec3 srgb(vec3 value) {
  vec3 low = value * 12.9232101;
  vec3 high = pow(abs(value),vec3(0.416666657))*1.05499995-0.0549999997;
  return mix(high,low,lessThanEqual(value,vec3(0.00313080009)));
}
vec2 distort(vec2 coord) {
  if(abs(settings.warp.w)<0.0001)return coord;
  vec2 centered=(coord-0.5)*settings.warp.z;
  vec2 radial=settings.distortion.zw*(centered-settings.distortion.xy);
  float radius=length(radial);
  if(radius<0.00001)return centered+0.5;
  float factor=settings.warp.w>=0.0
    ?tan(radius*settings.warp.x)/(radius*settings.warp.y)
    :settings.warp.x*atan(radius*settings.warp.y)/radius;
  return centered+0.5+radial*(factor-1.0);
}
vec3 grade(vec3 color) {
  vec3 c=clamp(color,0.0,1.0);
  vec3 point=c.zxy*settings.lut.z;
  float slice=floor(point.x);
  vec2 coord=point.yz*settings.lut.xy+settings.lut.xy*0.5;
  coord.x+=slice*settings.lut.y;
  vec3 left=texture(gradingLut,coord).rgb;
  vec3 right=texture(gradingLut,coord+vec2(settings.lut.y,0.0)).rgb;
  return mix(left,right,fract(point.x));
}
void main() {
  vec2 coord=distort(uv);
  vec2 limit=vec2(1.0)-settings.texel.xy*0.5;
  vec4 original=texture(image,min(coord,limit));
  vec3 sampled=original.rgb;
  if(settings.color.y>0.0) {
    vec2 radial=(uv-0.5)*2.0;
    vec2 offset=radial*dot(radial,radial)*settings.color.y;
    sampled.g=texture(image,min(distort(uv-offset*(1.0/3.0)),limit)).g;
    sampled.b=texture(image,min(distort(uv-offset*(2.0/3.0)),limit)).b;
  }
  vec3 base=settings.center.z>0.5?fastLinear(sampled):sampled;
  vec3 result=base;
  if(settings.bloom.x>0.0) {
    vec3 b=texture(bloomImage,coord).rgb;
    result+=b*b*settings.bloom.x*settings.bloom.yzw;
  }
  if(settings.color.z>0.0) {
    vec2 delta=abs(uv-settings.center.xy)*settings.color.z;
    delta.x*=settings.vignette.w;
    float fade=pow(max(1.0-dot(delta,delta),0.0),settings.color.w);
    result*=mix(settings.vignette.rgb,vec3(1.0),fade);
  }
  result=grade(clamp(result*settings.color.x,0.0,1.0));
  if(settings.center.w>0.5) {
    result=clamp(pow(abs(result),vec3(0.416666657))*1.05499995-0.0549999997,0.0,1.0);
    base=srgb(base);
  }
  float alpha=clamp(original.a,0.0,1.0);
  fragment=vec4(mix(base,result,alpha),alpha);
}
