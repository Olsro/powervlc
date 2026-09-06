// Generated from crt/shaders/crt-consumer/linear.slang. See slang/upstream for licence/source.
#version 120
#pragma parameter u_gamma "Gamma" 1.0 0.5 3.0 0.05
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

uniform float u_gamma;
struct Push
{
    float u_gamma;
};



uniform sampler2D Texture;

varying vec2 RA_VARYING_0;

void main()
{
    vec3 _34 = pow(texture2D(Texture, RA_VARYING_0).xyz, vec3((u_gamma)));
    gl_FragData[0].x = _34.x;
    gl_FragData[0].y = _34.y;
    gl_FragData[0].z = _34.z;
}


#endif
