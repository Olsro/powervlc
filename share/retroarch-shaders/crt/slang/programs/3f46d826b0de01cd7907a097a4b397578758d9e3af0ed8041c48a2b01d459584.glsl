// Generated from crt/shaders/crt-easymode-halation/linearize.slang. See slang/upstream for licence/source.
#version 120
#pragma parameter GAMMA_INPUT "Gamma Input" 2.4 0.1 5.0 0.01
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

uniform float GAMMA_INPUT;
struct Push
{
    float GAMMA_INPUT;
};



uniform sampler2D Texture;

varying vec2 RA_VARYING_0;

void main()
{
    gl_FragData[0] = pow(texture2D(Texture, RA_VARYING_0), vec4((GAMMA_INPUT)));
}


#endif
