// Generated from crt/shaders/crt-easymode-halation/threshold.slang. See slang/upstream for licence/source.
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
uniform sampler2D Pass1Texture;

varying vec2 RA_VARYING_0;

void main()
{
    gl_FragData[0] = vec4(clamp(texture2D(Texture, RA_VARYING_0).xyz - texture2D(Pass1Texture, RA_VARYING_0).xyz, vec3(0.0), vec3(1.0)), 1.0);
}


#endif
