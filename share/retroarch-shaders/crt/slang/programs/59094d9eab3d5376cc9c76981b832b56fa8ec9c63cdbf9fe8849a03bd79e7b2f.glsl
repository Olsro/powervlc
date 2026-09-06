// Generated from crt/shaders/crt-1tap.slang. See slang/upstream for licence/source.
#version 120
#pragma parameter CRT1TAP_SETTINGS "=== CRT-1tap v1.2 settings ===" 0.0 0.0 1.0 1.0
#pragma parameter MIN_THICK "Scanline thickness of dark pixels" 0.3 0.0 1.4 0.05
#pragma parameter MAX_THICK "Scanline thickness of bright pixels" 0.9 0.0 1.4 0.05
#pragma parameter V_SHARP "Vertical sharpness of the scanline" 0.5 0.0 1.0 0.05
#pragma parameter H_SHARP "Horizontal sharpness of pixel transitions" 0.15 0.0 1.0 0.05
#pragma parameter SUBPX_POS "Scanline subpixel position" 0.3 -0.5 0.5 0.01
#pragma parameter THICK_FALLOFF "Reduction / increase of thinner scanlines" 0.65 0.2 2.0 0.05
#ifdef VERTEX

uniform mat4 MVPMatrix;
struct UBO
{
    mat4 MVP;
};



attribute vec4 VertexCoord;
varying vec2 RA_VARYING_0;
attribute vec2 TexCoord;

void main()
{
    gl_Position = (MVPMatrix) * VertexCoord;
    RA_VARYING_0 = TexCoord;
}


#endif
#ifdef FRAGMENT

uniform float H_SHARP;
uniform float MAX_THICK;
uniform float MIN_THICK;
uniform float SUBPX_POS;
uniform float THICK_FALLOFF;
uniform vec2 TextureSize;
uniform float V_SHARP;
struct ResType
{
    float _m0;
    float _m1;
};

struct Push
{
    vec4 SourceSize;
    float MIN_THICK;
    float MAX_THICK;
    float V_SHARP;
    float H_SHARP;
    float SUBPX_POS;
    float THICK_FALLOFF;
};



uniform sampler2D Texture;

varying vec2 RA_VARYING_0;

void main()
{
    float _28 = (RA_VARYING_0.x * (vec4(TextureSize, 1.0 / TextureSize)).x) - 0.5;
    ResType _31;
    _31._m1 = float(int(_28));
    _31._m0 = _28 - _31._m1;
    float _44 = (RA_VARYING_0.y * (vec4(TextureSize, 1.0 / TextureSize)).y) - (SUBPX_POS);
    ResType _46;
    _46._m1 = float(int(_44));
    _46._m0 = _44 - _46._m1;
    float _49 = _46._m0 - 0.5;
    float _53 = sign(_31._m0 - 0.5);
    float _58 = (1.0 + _53) * 0.5;
    vec3 _102 = texture2D(Texture, vec2((((_31._m1 + _58) - ((0.5 * _53) * pow(2.0 * (_58 - (_53 * _31._m0)), mix(1.0, 6.0, (H_SHARP))))) + 0.5) * (vec4(TextureSize, 1.0 / TextureSize)).z, (_46._m1 + 0.5) * (vec4(TextureSize, 1.0 / TextureSize)).w)).xyz;
    vec3 _130 = pow(mix(vec3((MIN_THICK)), vec3((MAX_THICK)), _102), vec3((THICK_FALLOFF))) * 0.5;
    vec3 _151 = _102 * clamp(vec3(0.25) - ((vec3(_49 * _49) - (_130 * _130)) * (3.0 + ((50.0 * (V_SHARP)) * (V_SHARP)))), vec3(0.0), vec3(1.0));
    gl_FragData[0].x = _151.x;
    gl_FragData[0].y = _151.y;
    gl_FragData[0].z = _151.z;
}


#endif
