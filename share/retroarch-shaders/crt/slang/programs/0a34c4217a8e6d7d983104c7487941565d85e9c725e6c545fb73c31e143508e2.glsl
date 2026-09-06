// Generated from crt/shaders/zfast_crt/zfast_crt_coarsemask.slang. See slang/upstream for licence/source.
#version 120
#pragma parameter BLURSCALEX "Blur Amount X-Axis" 0.30 0.0 1.0 0.05
#pragma parameter LOWLUMSCAN "Scanline Darkness - Low" 6.0 0.0 10.0 0.5
#pragma parameter HILUMSCAN "Scanline Darkness - High" 8.0 0.0 50.0 1.0
#pragma parameter BRIGHTBOOST "Dark Pixel Brightness Boost" 1.25 0.5 1.5 0.05
#pragma parameter MASK_DARK "Mask Effect Amount" 0.25 0.0 1.0 0.05
#pragma parameter MASK_FADE "Mask/Scanline Fade" 0.8 0.0 1.0 0.05
#ifdef VERTEX

uniform float MASK_FADE;
uniform mat4 MVPMatrix;
uniform vec2 TextureSize;
struct UBO
{
    mat4 MVP;
};



struct Push
{
    vec4 SourceSize;
    float MASK_FADE;
};



attribute vec4 VertexCoord;
varying vec2 RA_VARYING_0;
attribute vec2 TexCoord;
varying float RA_VARYING_1;
varying vec2 RA_VARYING_2;

void main()
{
    gl_Position = (MVPMatrix) * VertexCoord;
    RA_VARYING_0 = TexCoord;
    RA_VARYING_1 = 0.33329999446868896484375 * (MASK_FADE);
    RA_VARYING_2 = vec2(1.0) / (vec4(TextureSize, 1.0 / TextureSize)).xy;
}


#endif
#ifdef FRAGMENT

uniform float BLURSCALEX;
uniform float BRIGHTBOOST;
uniform float HILUMSCAN;
uniform float LOWLUMSCAN;
uniform float MASK_DARK;
uniform vec2 OutputSize;
uniform vec2 TextureSize;
struct Push
{
    vec4 SourceSize;
    vec4 OutputSize;
    float BLURSCALEX;
    float LOWLUMSCAN;
    float HILUMSCAN;
    float BRIGHTBOOST;
    float MASK_DARK;
};



uniform sampler2D Texture;

varying vec2 RA_VARYING_0;
varying vec2 RA_VARYING_2;
varying float RA_VARYING_1;

void main()
{
    vec2 _24 = RA_VARYING_0 * (vec4(TextureSize, 1.0 / TextureSize)).xy;
    vec2 _30 = floor(_24) + vec2(0.5);
    vec2 _34 = _24 - _30;
    vec2 _46 = (_30 + (((_34 * 4.0) * _34) * _34)) * RA_VARYING_2;
    _46.x = mix(_46.x, RA_VARYING_0.x, (BLURSCALEX));
    float _63 = _34.y;
    float _66 = _63 * _63;
    float _70 = _66 * _66;
    vec3 _106 = texture2D(Texture, _46).xyz;
    vec3 _147 = _106 * mix(((BRIGHTBOOST) - ((LOWLUMSCAN) * (_66 - (2.0499999523162841796875 * _70)))) * (1.0 + (float(fract(floor(RA_VARYING_0.x * (vec4(OutputSize, 1.0 / OutputSize)).x) * (-0.33329999446868896484375)) <= 0.3333300054073333740234375) * (-(MASK_DARK)))), 1.0 - ((HILUMSCAN) * (_70 - ((2.7999999523162841796875 * _70) * _66))), dot(_106, vec3(RA_VARYING_1)));
    gl_FragData[0].x = _147.x;
    gl_FragData[0].y = _147.y;
    gl_FragData[0].z = _147.z;
}


#endif
