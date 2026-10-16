#version 450
layout(location=0) in vec2 uv;
layout(location=1) in vec4 tint;
layout(location=0) out vec4 fragment;
layout(set=0,binding=0) uniform sampler2D image;
layout(set=0,binding=1) uniform sampler2D auxiliaryImage;
layout(set=0,binding=2) uniform PostSettings {
  vec4 texelMode; // source inverse dimensions, operation, mapped scatter
  vec4 bloom; // clamp, threshold, knee, intensity
  vec4 options; // RGB-only target alpha policy and reserved
  vec4 antialias; // subpixel, relative contrast, absolute contrast, unused
} settings;
vec3 sampleRgb(vec2 offset) { return texture(image,uv+offset).rgb; }
float luma(vec3 rgb) { return dot(rgb,vec3(0.299,0.587,0.114)); }
vec3 squaredTap(vec2 offset, vec2 limit) {
  vec3 v=texture(image,min(uv+offset,limit)).rgb;
  return v*v;
}
vec3 horizontalGaussian() {
  vec2 limit=vec2(1.0)-settings.texelMode.xy;
  vec3 sum=squaredTap(vec2(0.0),limit)*0.227027029;
  for(int i=1;i<=4;i++) {
    vec2 step=vec2(float(i)*2.0*settings.texelMode.x,0.0);
    float weight=i==1?0.194594592:(i==2?0.121621624:(i==3?0.0540540516:0.0162162203));
    sum+=(squaredTap(step,limit)+squaredTap(-step,limit))*weight;
  }
  return sqrt(max(sum,vec3(0.0)));
}
vec3 verticalGaussian() {
  vec2 limit=vec2(1.0)-settings.texelMode.xy*0.5;
  vec3 sum=squaredTap(vec2(0.0),limit)*0.227027029;
  for(int i=1;i<=2;i++) {
    float distance=i==1?1.38461542:3.23076916;
    float weight=i==1?0.31621623:0.0702702701;
    vec2 step=vec2(0.0,distance*settings.texelMode.y);
    sum+=(squaredTap(step,limit)+squaredTap(-step,limit))*weight;
  }
  return sqrt(max(sum,vec3(0.0)));
}
void main() {
  vec4 inputColor=texture(image,uv);
  vec3 result=inputColor.rgb;
  int mode=int(settings.texelMode.z+0.5);
  if(mode==0 || mode==6) {
    if(mode==6 && settings.options.y>.5) {
      result=result*(result*(result*0.305306017+0.682171106)+0.0125228781);
    }
    result=min(result,vec3(settings.bloom.x));
    float peak=max(result.r,max(result.g,result.b));
    float soft=clamp(peak-settings.bloom.y+settings.bloom.z,0.0,2.0*settings.bloom.z);
    soft=soft*soft/(4.0*settings.bloom.z+9.99999975e-05);
    result=sqrt(max(result*max(soft,peak-settings.bloom.y)/max(peak,9.99999975e-05),vec3(0.0)));
  } else if(mode==1) {
    result=horizontalGaussian();
  } else if(mode==2) {
    result=verticalGaussian();
  } else if(mode==3) {
    vec3 low=texture(auxiliaryImage,uv).rgb;
    result=sqrt(max(mix(inputColor.rgb*inputColor.rgb,low*low,settings.texelMode.w),vec3(0.0)));
  } else if(mode==4) {
    vec3 bloomRgb=texture(auxiliaryImage,uv).rgb;
    vec3 linear=inputColor.rgb*(inputColor.rgb*(inputColor.rgb*0.305306011+0.682171111)+0.012522878);
    linear=clamp(linear+bloomRgb*bloomRgb*settings.bloom.w,0.0,1.0);
    result=clamp(pow(abs(linear),vec3(0.416666657))*1.055-0.055,0.0,1.0);
  } else if(mode==5) {
    if(inputColor.a<=0.0) {
      fragment=vec4(inputColor.rgb,settings.options.x>.5?1.0:inputColor.a);
      return;
    }
    vec2 pixel=settings.texelMode.xy;
    float center=luma(inputColor.rgb);
    float north=luma(sampleRgb(vec2(0.0,-pixel.y)));
    float south=luma(sampleRgb(vec2(0.0,pixel.y)));
    float east=luma(sampleRgb(vec2(pixel.x,0.0)));
    float west=luma(sampleRgb(vec2(-pixel.x,0.0)));
    float low=min(center,min(min(north,south),min(east,west)));
    float high=max(center,max(max(north,south),max(east,west)));
    float contrast=high-low;
    if(contrast>=max(settings.antialias.z,high*settings.antialias.y)) {
      float nw=luma(sampleRgb(-pixel));
      float ne=luma(sampleRgb(vec2(pixel.x,-pixel.y)));
      float sw=luma(sampleRgb(vec2(-pixel.x,pixel.y)));
      float se=luma(sampleRgb(pixel));
      float horizontal=abs(nw+sw-2.0*west)+2.0*abs(north+south-2.0*center)+abs(ne+se-2.0*east);
      float vertical=abs(nw+ne-2.0*north)+2.0*abs(west+east-2.0*center)+abs(sw+se-2.0*south);
      bool alongX=horizontal>=vertical;
      vec2 normal=alongX?vec2(0.0,-pixel.y):vec2(pixel.x,0.0);
      float sideA=alongX?north:east;
      float sideB=alongX?south:west;
      float neighbor=sideA;
      if(abs(sideB-center)>abs(sideA-center)) { normal=-normal; neighbor=sideB; }
      float edgeLuma=(center+neighbor)*0.5;
      float gradient=abs(neighbor-center)*0.25;
      vec2 tangent=alongX?vec2(pixel.x,0.0):vec2(0.0,pixel.y);
      vec2 edgeUv=uv+normal*0.5;
      float leftDistance=1.0,rightDistance=1.0;
      bool leftDone=false,rightDone=false;
      float leftLuma=0.0,rightLuma=0.0;
      for(int index=0;index<4;index++) {
        if(!leftDone) { leftLuma=luma(texture(image,edgeUv-tangent*leftDistance).rgb)-edgeLuma; leftDone=abs(leftLuma)>=gradient; }
        if(!rightDone) { rightLuma=luma(texture(image,edgeUv+tangent*rightDistance).rgb)-edgeLuma; rightDone=abs(rightLuma)>=gradient; }
        if(leftDone&&rightDone)break;
        float searchStep=index==0?1.5:(index==1?2.0:(index==2?4.0:12.0));
        if(!leftDone)leftDistance+=searchStep;
        if(!rightDone)rightDistance+=searchStep;
      }
      float closest=min(leftDistance,rightDistance);
      float endLuma=leftDistance<rightDistance?leftLuma:rightLuma;
      float edgeOffset=(endLuma<0.0)==(center-edgeLuma<0.0)?0.0:
        0.5-closest/max(leftDistance+rightDistance,0.000001);
      float average=(north+south+east+west)*2.0+nw+ne+sw+se;
      float subpixel=clamp(abs(average/12.0-center)/max(contrast,1e-5),0.0,1.0);
      subpixel=subpixel*subpixel*(3.0-2.0*subpixel);
      subpixel=subpixel*subpixel*settings.antialias.x;
      result=texture(image,uv+normal*max(edgeOffset,subpixel)).rgb;
    }
  }
  // HDR colour and camera alpha remain separate numeric channels.
  float alpha=(mode<=3 || (mode==5 && settings.options.x>.5))?1.0:inputColor.a;
  fragment=vec4(result,alpha);
}
