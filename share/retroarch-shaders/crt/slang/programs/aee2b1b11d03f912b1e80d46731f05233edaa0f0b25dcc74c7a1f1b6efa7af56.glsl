// Generated from crt/shaders/crt-nes-mini.slang. See slang/upstream for licence/source.
#version 120
#pragma parameter SCANTHICK "Scanline Thickness" 2.0 2.0 4.0 2.0
#pragma parameter INTENSITY "Scanline Intensity" 0.15 0.0 1.0 0.01
#pragma parameter BRIGHTBOOST "Luminance Boost" 0.15 0.0 1.0 0.01
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

uniform float BRIGHTBOOST;
uniform float INTENSITY;
uniform float SCANTHICK;
uniform vec2 TextureSize;
struct Push
{
    vec4 SourceSize;
    float BRIGHTBOOST;
    float INTENSITY;
    float SCANTHICK;
};



uniform sampler2D Texture;

varying vec2 RA_VARYING_0;

void main()
{
    vec3 _21 = texture2D(Texture, RA_VARYING_0).xyz;
    float _71 = step(1.0, mod((RA_VARYING_0.y * (SCANTHICK)) * (vec4(TextureSize, 1.0 / TextureSize)).y, 2.0));
    gl_FragData[0] = vec4((((vec3(1.0 - (INTENSITY)) + (_21 * 0.100000001490116119384765625)) * _21) * (1.0 - _71)) + (((vec3(1.0 + (BRIGHTBOOST)) - (_21 * 0.20000000298023223876953125)) * _21) * _71), 1.0);
}


#endif
