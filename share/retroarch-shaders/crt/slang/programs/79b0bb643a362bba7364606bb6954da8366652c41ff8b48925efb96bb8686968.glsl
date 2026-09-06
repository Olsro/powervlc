// Generated from linear/linearize.slang. See slang/upstream for licence/source.
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


uniform sampler2D Texture;

varying vec2 RA_VARYING_0;

void main()
{
    vec3 _32 = texture2D(Texture, RA_VARYING_0).xyz;
    gl_FragData[0] = vec4(_32 * _32, 1.0);
}


#endif
