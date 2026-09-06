// Generated from crt/shaders/fake-crt-geom-potato.slang. See slang/upstream for licence/source.
#version 120
#pragma parameter size "Mask Size" 2.0 2.0 3.0 1.0
#pragma parameter warp "Curvature" 0.12 0.0 0.3 0.01
#pragma parameter border "Border Smoothness" 0.02 0.0 0.2 0.005
#pragma parameter hheld_mode "Handheld mode" 0.0 0.0 1.0 1.0
#ifdef VERTEX

uniform mat4 MVPMatrix;
uniform vec2 OrigTextureSize;
uniform vec2 OutputSize;
uniform vec2 TextureSize;
struct UBO
{
    mat4 MVP;
};



struct Push
{
    vec4 SourceSize;
    vec4 OriginalSize;
    vec4 OutputSize;
};



attribute vec4 VertexCoord;
varying vec2 RA_VARYING_0;
attribute vec2 TexCoord;
varying vec2 RA_VARYING_1;
varying float RA_VARYING_2;

void main()
{
    gl_Position = (MVPMatrix) * VertexCoord;
    RA_VARYING_0 = TexCoord * 1.00010001659393310546875;
    RA_VARYING_1 = (vec4(TextureSize, 1.0 / TextureSize)).xy / (vec4(OrigTextureSize, 1.0 / OrigTextureSize)).xy;
    RA_VARYING_2 = (RA_VARYING_0.x * (vec4(OutputSize, 1.0 / OutputSize)).x) * RA_VARYING_1.x;
}


#endif
#ifdef FRAGMENT

uniform vec2 TextureSize;
uniform float border;
uniform float hheld_mode;
uniform float size;
uniform float warp;
struct Push
{
    vec4 SourceSize;
    float size;
    float warp;
    float border;
    float hheld_mode;
};



uniform sampler2D Texture;

varying vec2 RA_VARYING_0;
varying vec2 RA_VARYING_1;
varying float RA_VARYING_2;

void main()
{
    vec2 _15 = RA_VARYING_0 * RA_VARYING_1;
    float _21 = _15.x;
    float _23 = _21 - 0.5;
    float _28 = _15.y - 0.5;
    float _46 = _21 + (((_28 * _28) * (warp)) * _23);
    float _58 = _15.y + (((_23 * _23) * (warp)) * _28);
    vec2 _64 = vec2(_46, _58) / RA_VARYING_1;
    vec2 _72 = _64 * (vec4(TextureSize, 1.0 / TextureSize)).xy;
    vec2 _77 = floor(_72) + vec2(0.5);
    vec2 _81 = _72 - _77;
    float _86 = _81.y;
    vec2 _243 = _64;
    _243.y = (_77.y + (((((16.0 * _86) * _86) * _86) * _86) * _86)) * (vec4(TextureSize, 1.0 / TextureSize)).w;
    vec4 _115 = texture2D(Texture, _243);
    vec3 _116 = _115.xyz;
    float _121 = dot(vec3(0.25), _116);
    vec3 _224;
    if (mod(floor(RA_VARYING_2), (size)) == 0.0)
    {
        _224 = _116 * 0.699999988079071044921875;
    }
    else
    {
        _224 = _116;
    }
    vec3 _226;
    if ((hheld_mode) == 0.0)
    {
        float _151 = mix(0.5, 0.20000000298023223876953125, _121);
        _226 = _224 * (((_151 * sin((_72.y - 0.25) * 6.28318500518798828125)) + 1.0) - _151);
    }
    else
    {
        _226 = _224;
    }
    vec3 _207 = sqrt(_226 * mix(1.4500000476837158203125, 1.25, _121)) * ((smoothstep(0.0, (border), _46) * smoothstep(0.0, (border), 1.0 - _46)) * (smoothstep(0.0, (border), _58) * smoothstep(0.0, (border), 1.0 - _58)));
    gl_FragData[0].x = _207.x;
    gl_FragData[0].y = _207.y;
    gl_FragData[0].z = _207.z;
}


#endif
