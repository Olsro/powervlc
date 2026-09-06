// Generated from crt/shaders/zfast_crt/zfast_crt_curvature.slang. See slang/upstream for licence/source.
#version 120
#pragma parameter BLURSCALEX "Blur Amount X-Axis" 0.30 0.0 1.0 0.05
#pragma parameter LOWLUMSCAN "Scanline Darkness - Low" 6.0 0.0 10.0 0.5
#pragma parameter HILUMSCAN "Scanline Darkness - High" 8.0 0.0 50.0 1.0
#pragma parameter BRIGHTBOOST "Dark Pixel Brightness Boost" 1.25 0.5 1.5 0.05
#pragma parameter MASK_DARK "Mask Effect Amount" 0.25 0.0 1.0 0.05
#pragma parameter MASK_FADE "Mask/Scanline Fade" 0.8 0.0 1.0 0.05
#pragma parameter CURVE "Curvature" 0.03 0.0 0.3 0.002
#pragma parameter CORNER "Corner" 0.3 0.0 20.0 0.1
#ifdef VERTEX

uniform float CORNER;
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
    float CORNER;
};



attribute vec4 VertexCoord;
varying vec2 RA_VARYING_0;
attribute vec2 TexCoord;
varying float RA_VARYING_1;
varying vec2 RA_VARYING_2;
varying float RA_VARYING_3;

void main()
{
    gl_Position = (MVPMatrix) * VertexCoord;
    RA_VARYING_0 = TexCoord;
    RA_VARYING_1 = 0.33329999446868896484375 * (MASK_FADE);
    RA_VARYING_2 = vec2(1.0) / (vec4(TextureSize, 1.0 / TextureSize)).xy;
    RA_VARYING_3 = (CORNER) * 9.9999997473787516355514526367188e-05;
}


#endif
#ifdef FRAGMENT

uniform float BLURSCALEX;
uniform float BRIGHTBOOST;
uniform float CURVE;
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
    float CURVE;
};



uniform sampler2D Texture;

varying vec2 RA_VARYING_0;
varying vec2 RA_VARYING_2;
varying float RA_VARYING_3;
varying float RA_VARYING_1;

void main()
{
    vec2 _230 = vec2(-1.0) + (RA_VARYING_0 * 2.0);
    vec2 _233 = _230 * _230;
    vec2 _256 = clamp(((_230 * vec2(1.0 + ((1.33329999446868896484375 * (CURVE)) * _233.y), 1.0 + ((CURVE) * _233.x))) * 0.5) + vec2(0.5), vec2(0.0), vec2(1.0));
    vec2 _76 = _256 * (vec4(TextureSize, 1.0 / TextureSize)).xy;
    vec2 _81 = floor(_76) + vec2(0.5);
    vec2 _85 = _76 - _81;
    vec2 _97 = (_81 + (((_85 * 4.0) * _85) * _85)) * RA_VARYING_2;
    _97.x = mix(_97.x, _256.x, (BLURSCALEX));
    float _109 = _85.y;
    float _112 = _109 * _109;
    float _116 = _112 * _112;
    vec3 _150 = texture2D(Texture, _97).xyz;
    vec2 _183 = min(_256, vec2(1.0) - _256);
    bvec3 _265 = bvec3(_183.y <= (RA_VARYING_3 / _183.x));
    vec3 _266 = vec3(_265.x ? vec3(0.0).x : _150.x, _265.y ? vec3(0.0).y : _150.y, _265.z ? vec3(0.0).z : _150.z);
    vec3 _211 = _266 * mix(((BRIGHTBOOST) - ((LOWLUMSCAN) * (_112 - (2.0499999523162841796875 * _116)))) * (1.0 + (float(fract(floor((RA_VARYING_0.x * (vec4(OutputSize, 1.0 / OutputSize)).x) * (-0.4999000132083892822265625))) < 0.5) * (-(MASK_DARK)))), 1.0 - ((HILUMSCAN) * (_116 - ((2.7999999523162841796875 * _116) * _112))), dot(_266, vec3(RA_VARYING_1)));
    gl_FragData[0].x = _211.x;
    gl_FragData[0].y = _211.y;
    gl_FragData[0].z = _211.z;
}


#endif
