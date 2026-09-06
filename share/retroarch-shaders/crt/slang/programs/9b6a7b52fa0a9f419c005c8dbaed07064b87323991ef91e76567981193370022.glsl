// Generated from crt/shaders/glow/linearize.slang. See slang/upstream for licence/source.
#version 120
#pragma parameter INPUT_GAMMA "Input Gamma" 2.4 2.0 2.6 0.02
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

uniform float INPUT_GAMMA;
struct Push
{
    float INPUT_GAMMA;
};



uniform sampler2D Texture;

varying vec2 RA_VARYING_0;

void main()
{
    gl_FragData[0] = vec4(pow(texture2D(Texture, RA_VARYING_0).xyz, vec3((INPUT_GAMMA))), 1.0);
}


#endif
