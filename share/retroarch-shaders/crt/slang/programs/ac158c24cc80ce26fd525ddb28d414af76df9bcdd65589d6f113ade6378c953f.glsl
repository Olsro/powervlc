// Generated from blurs/shaders/royale/blur9fast-vertical.slang. See slang/upstream for licence/source.
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

void main()
{
    gl_Position = (MVPMatrix) * VertexCoord;
    RA_VARYING_0 = TexCoord;
    RA_VARYING_1 = vec2(0.0, (((vec4(TextureSize, 1.0 / TextureSize)).xy / (vec4(OutputSize, 1.0 / OutputSize)).xy) / (vec4(TextureSize, 1.0 / TextureSize)).xy).y);
}


#endif
#ifdef FRAGMENT


uniform sampler2D Texture;

varying vec2 RA_VARYING_0;
varying vec2 RA_VARYING_1;

void main()
{
    vec2 _424 = RA_VARYING_1 * 3.2425899505615234375;
    vec2 _436 = RA_VARYING_1 * 1.38037836551666259765625;
    gl_FragData[0] = vec4((((((texture2D(Texture, RA_VARYING_0 - _424).xyz * 0.3054474890232086181640625) + (texture2D(Texture, RA_VARYING_0 - _436).xyz * 1.3716285228729248046875)) + (texture2D(Texture, RA_VARYING_0).xyz * 1.0)) + (texture2D(Texture, RA_VARYING_0 + _436).xyz * 1.3716285228729248046875)) + (texture2D(Texture, RA_VARYING_0 + _424).xyz * 0.3054474890232086181640625)) * 0.22966586053371429443359375, 1.0);
}


#endif
