// Generated from crt/shaders/crt-yo6/crt-yo6-native-resolution.slang. See slang/upstream for licence/source.
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
varying float RA_VARYING_0;
attribute vec2 TexCoord;
varying float RA_VARYING_1;

void main()
{
    gl_Position = (MVPMatrix) * VertexCoord;
    RA_VARYING_0 = TexCoord.x;
    RA_VARYING_1 = (TexCoord.y * (vec4(OutputSize, 1.0 / OutputSize)).y) - floor((((vec4(OutputSize, 1.0 / OutputSize)).y - (vec4(TextureSize, 1.0 / TextureSize)).y) * 0.5) + float(0.5));
}


#endif
#ifdef FRAGMENT

uniform vec2 TextureSize;
struct Push
{
    vec4 SourceSize;
};



uniform sampler2D Texture;

varying float RA_VARYING_1;
varying float RA_VARYING_0;

void main()
{
    gl_FragData[0] = vec4(texture2D(Texture, vec2(RA_VARYING_0, RA_VARYING_1 / (vec4(TextureSize, 1.0 / TextureSize)).y)).xyz * (0.25 * ((sign(RA_VARYING_1) + 1.0) * (sign((vec4(TextureSize, 1.0 / TextureSize)).y - RA_VARYING_1) + 1.0))), 1.0);
}


#endif
