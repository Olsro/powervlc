// Generated from crt/shaders/torridgristle/Scanline-Interpolation.slang. See slang/upstream for licence/source.
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



uniform sampler2D Texture;

varying vec2 RA_VARYING_0;

void main()
{
    gl_FragData[0] = vec4(texture2D(Texture, vec2(RA_VARYING_0.x, (floor(RA_VARYING_0.y * (vec4(TextureSize, 1.0 / TextureSize)).y) + 0.5) / (vec4(TextureSize, 1.0 / TextureSize)).y)).xyz, 1.0);
}


#endif
