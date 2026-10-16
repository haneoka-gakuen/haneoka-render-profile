#version 450
// Formal v25 CurvedLens pass, after URP/Uber and before FinalPost FXAA.
layout(location=0) in vec2 uv;
layout(location=1) in vec4 tint;
layout(location=0) out vec4 fragment;
layout(set=0,binding=0) uniform sampler2D image;
layout(set=0,binding=1) uniform StoryCurvedSettings {
  vec4 texelSize;
  vec4 params1;
  vec4 params2;
  vec4 params3;
} settings;
#define _BlitTexture_TexelSize settings.texelSize
#define _AdvCurvedLensParams1 settings.params1
#define _AdvCurvedLensParams2 settings.params2
#define _AdvCurvedLensParams3 settings.params3
vec2 u_xlat0;
vec4 u_xlat16_0;
vec2 u_xlat1;
bool u_xlatb1;
float u_xlat2;
vec2 u_xlat3;
vec2 u_xlat4;
void main()
{
    u_xlat0.x = _BlitTexture_TexelSize.y * _BlitTexture_TexelSize.z;
    u_xlat0.y = 1.0;
    u_xlat4.xy = uv.xy + (-_AdvCurvedLensParams1.xy);
    u_xlat1.xy = max(_AdvCurvedLensParams2.xw, vec2(9.99999975e-05, 0.00100000005));
    u_xlat4.xy = u_xlat4.xy / u_xlat1.yy;
    u_xlat1.x = float(1.0) / u_xlat1.x;
    u_xlat3.xy = u_xlat4.xy * _AdvCurvedLensParams2.yz;
    u_xlat0.xy = u_xlat0.xy * u_xlat3.xy;
    u_xlat0.x = dot(u_xlat0.xy, u_xlat0.xy);
    u_xlat2 = sqrt(u_xlat0.x);
    u_xlat2 = u_xlat2 + (-_AdvCurvedLensParams1.w);
    u_xlat2 = u_xlat1.x * u_xlat2;
    u_xlat2 = clamp(u_xlat2, 0.0, 1.0);
    u_xlat1.x = u_xlat2 * -2.0 + 3.0;
    u_xlat2 = u_xlat2 * u_xlat2;
    u_xlat2 = u_xlat2 * u_xlat1.x;
    u_xlatb1 = 0.5<_AdvCurvedLensParams3.x;
    u_xlat1.x = (u_xlatb1) ? (-_AdvCurvedLensParams1.z) : _AdvCurvedLensParams1.z;
    u_xlat0.x = u_xlat0.x * u_xlat1.x;
    u_xlat0.x = u_xlat0.x * u_xlat2 + 1.0;
    u_xlat0.x = max(u_xlat0.x, 0.00100000005);
    u_xlat0.xy = u_xlat4.xy * u_xlat0.xx + _AdvCurvedLensParams1.xy;
    u_xlat16_0 = texture(image, u_xlat0.xy);
    fragment = u_xlat16_0;
    return;
}

