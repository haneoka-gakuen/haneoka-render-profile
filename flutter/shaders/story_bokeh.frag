#version 450
layout(location=0) in vec2 uv;
layout(location=0) out vec4 fragment;
layout(set=0,binding=0) uniform sampler2D image;
layout(set=0,binding=1) uniform StoryBokehSettings {
  vec4 texelScreen;
  vec4 blur;
  vec4 highlights;
} settings;

float pixelHash(vec2 pixel) {
  vec2 p=fract(pixel*vec2(123.339996,456.209991));
  p+=dot(p,p+vec2(45.3199997));
  return fract(p.x*p.y);
}
float highlight(vec3 rgb) {
  return clamp((dot(rgb,vec3(.212599993,.715200007,.0722000003))-settings.highlights.y)*4.,0.,1.);
}
void addTap(vec2 delta,float radiusRate,float baseWeight,inout vec4 sum,inout float total) {
  // The source graph stores these inputs in RGBA16 UNORM. Flutter GPU exposes
  // RGBA16F; preserve the source's normalized colour/alpha range at sampling.
  vec4 color=clamp(texture(image,uv+delta),0.,1.);
  if(settings.highlights.w>9.99999975e-05) {
    float amount=settings.highlights.w*.25;
    color.r=clamp(texture(image,uv+delta+delta*amount).r,0.,1.);
    color.b=clamp(texture(image,uv+delta-delta*amount).b,0.,1.);
  }
  float weight=baseWeight*(1.+settings.highlights.x*radiusRate)*(1.+highlight(color.rgb)*settings.highlights.z);
  sum+=color*weight;
  total+=weight;
}
void main() {
  vec4 center=clamp(texture(image,uv),0.,1.);
  float blur=clamp(settings.blur.x,0.,10.);
  if(blur<=9.99999975e-05) { fragment=center; return; }
  vec2 radius=blur*settings.blur.y*settings.blur.z*settings.texelScreen.xy;
  float jitter=(pixelHash(floor(uv*settings.texelScreen.zw))-.5)*.0299999993+settings.blur.w;
  float weight=(1.+highlight(center.rgb)*settings.highlights.z*.400000006)*.5;
  vec4 sum=center*weight;
  float total=weight;
  for(int i=0;i<8;i++) {
    float angle=jitter+float(i)*.7853981633974483;
    vec2 direction=vec2(cos(angle),sin(angle));
    addTap(direction*radius*.400000006,.400000006,.0500000007,sum,total);
    addTap(direction*radius*.720000029,.720000029,.0599999987,sum,total);
    addTap(direction*radius,1.,.0700000003,sum,total);
  }
  fragment=sum/max(total,9.99999975e-06);
}
