// Generated from crt/shaders/crt-potato/shader-files/crt-potato.slang. See slang/upstream for licence/source.
#version 120

#ifdef VERTEX

uniform mat4 MVPMatrix;
uniform vec2 OutputSize;
uniform vec2 TextureSize;
struct UBO
{
    mat4 MVP;
};



struct Push
{
    vec4 SourceSize;
    vec4 OutputSize;
};



attribute vec4 VertexCoord;
varying vec2 RA_VARYING_0;
attribute vec2 TexCoord;
varying vec2 RA_VARYING_1;
varying vec2 RA_VARYING_2;

void main()
{
    gl_Position = (MVPMatrix) * VertexCoord;
    RA_VARYING_0 = TexCoord;
    RA_VARYING_1 = (vec4(TextureSize, 1.0 / TextureSize)).zw;
    RA_VARYING_2 = vec2(1.0) / ((vec4(TextureSize, 1.0 / TextureSize)).xy * floor((vec4(OutputSize, 1.0 / OutputSize)).y * (vec4(TextureSize, 1.0 / TextureSize)).w));
}


#endif
#ifdef FRAGMENT

uniform vec2 OutputSize;
uniform vec2 TextureSize;
struct Push
{
    vec4 SourceSize;
    vec4 OutputSize;
};



uniform sampler2D MASK;
uniform sampler2D Texture;

varying vec2 RA_VARYING_0;

void main()
{
    gl_FragData[0] = texture2D(MASK, fract((RA_VARYING_0 * (vec4(OutputSize, 1.0 / OutputSize)).xy) / vec2(2.0, floor(((vec4(OutputSize, 1.0 / OutputSize)).y / (vec4(TextureSize, 1.0 / TextureSize)).y) + 9.9999999747524270787835121154785e-07)))) * texture2D(Texture, RA_VARYING_0);
}


#endif
