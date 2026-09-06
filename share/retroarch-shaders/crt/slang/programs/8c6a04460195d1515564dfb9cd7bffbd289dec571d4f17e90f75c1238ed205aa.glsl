// Generated from crt/shaders/torridgristle/sunset-gaussian-vert.slang. See slang/upstream for licence/source.
#version 120

#ifdef VERTEX

uniform mat4 MVPMatrix;
uniform vec2 OutputSize;
struct UBO
{
    mat4 MVP;
};



struct Push
{
    vec4 OutputSize;
};



attribute vec4 VertexCoord;
varying vec2 RA_VARYING_0;
attribute vec2 TexCoord;
varying vec2 RA_VARYING_1[5];

void main()
{
    gl_Position = (MVPMatrix) * VertexCoord;
    RA_VARYING_0 = TexCoord;
    RA_VARYING_1[0] = RA_VARYING_0;
    vec2 _54 = (vec4(OutputSize, 1.0 / OutputSize)).zw * vec2(0.0, 1.40733301639556884765625);
    RA_VARYING_1[1] = RA_VARYING_0 + _54;
    RA_VARYING_1[2] = RA_VARYING_0 - _54;
    vec2 _71 = (vec4(OutputSize, 1.0 / OutputSize)).zw * vec2(0.0, 3.2942149639129638671875);
    RA_VARYING_1[3] = RA_VARYING_0 + _71;
    RA_VARYING_1[4] = RA_VARYING_0 - _71;
}


#endif
#ifdef FRAGMENT


uniform sampler2D Texture;

varying vec2 RA_VARYING_1[5];

void main()
{
    gl_FragData[0] = ((((texture2D(Texture, RA_VARYING_1[0]) * 0.2041639983654022216796875) + (texture2D(Texture, RA_VARYING_1[1]) * 0.3040049970149993896484375)) + (texture2D(Texture, RA_VARYING_1[2]) * 0.3040049970149993896484375)) + (texture2D(Texture, RA_VARYING_1[3]) * 0.093912996351718902587890625)) + (texture2D(Texture, RA_VARYING_1[4]) * 0.093912996351718902587890625);
}


#endif
