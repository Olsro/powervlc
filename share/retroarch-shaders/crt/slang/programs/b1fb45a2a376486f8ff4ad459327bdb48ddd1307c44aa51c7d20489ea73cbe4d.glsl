// Generated from crt/shaders/crt-slangtest/linearize.slang. See slang/upstream for licence/source.
#version 120
#pragma parameter OUT_GAMMA "Monitor Output Gamma" 2.2 1.8 2.4
#pragma parameter BOOST "Color Boost" 1.0 0.2 2.0 0.02
#pragma parameter GAMMA "CRT gamma" 2.5 2.0 3.0 0.02
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

uniform float GAMMA;
struct UBO
{
    float GAMMA;
};



uniform sampler2D Texture;

varying vec2 RA_VARYING_0;

void main()
{
    gl_FragData[0] = vec4(pow(texture2D(Texture, RA_VARYING_0).xyz, vec3((GAMMA))), 1.0);
}


#endif
