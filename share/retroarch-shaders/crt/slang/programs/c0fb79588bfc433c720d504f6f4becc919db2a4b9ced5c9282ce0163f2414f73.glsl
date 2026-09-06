// Generated from crt/shaders/crt-yo6/crt-yo6-warp.slang. See slang/upstream for licence/source.
#version 120

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

uniform vec2 TextureSize;
struct Push
{
    vec4 SourceSize;
};



uniform sampler2D TEX_CRT;
uniform sampler2D Texture;

varying vec2 RA_VARYING_0;

void main()
{
    vec4 _20 = texture2D(TEX_CRT, RA_VARYING_0);
    gl_FragData[0] = vec4(texture2D(Texture, ((RA_VARYING_0 * (vec4(TextureSize, 1.0 / TextureSize)).xy) + (((_20.xy * 255.0) * vec2(0.0625)) - vec2(7.0))) / (vec4(TextureSize, 1.0 / TextureSize)).xy).xyz * _20.z, 1.0);
}


#endif
