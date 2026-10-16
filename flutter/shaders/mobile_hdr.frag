#version 450
layout(location=0) in vec2 uv;
layout(location=1) in vec4 tint;
layout(location=0) out vec4 fragment;
layout(set=0,binding=0) uniform sampler2D image;
// The producer supplies original 2*Tint^2*vertex color. Texture gamma numbers
// stay independent. Alpha uses the authored positive ties-to-even quantization.
void main() {
  vec4 pixel=texture(image,uv);
  float scaled=max(tint.a,0.0)*255.0;
  float lower=floor(scaled),part=scaled-lower;
  float increment=part>0.5?1.0:(part<0.5?0.0:mod(lower,2.0));
  float alpha=(lower+increment)/255.0;
  fragment=vec4(pixel.rgb*tint.rgb,pixel.a*alpha);
}
