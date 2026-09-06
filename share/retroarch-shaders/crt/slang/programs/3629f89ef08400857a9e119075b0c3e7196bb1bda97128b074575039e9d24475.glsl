// Generated from crt/shaders/glow/threshold.slang. See slang/upstream for licence/source.
#version 120
#pragma parameter GLOW_WHITEPOINT "Glow Whitepoint" 1.0 0.5 1.1 0.02
#pragma parameter GLOW_ROLLOFF "Glow Rolloff" 3.0 1.2 6.0 0.1
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

uniform float GLOW_ROLLOFF;
uniform float GLOW_WHITEPOINT;
struct Push
{
    float GLOW_WHITEPOINT;
    float GLOW_ROLLOFF;
};



uniform sampler2D Texture;

varying vec2 RA_VARYING_0;

void main()
{
    gl_FragData[0] = vec4(pow(clamp((texture2D(Texture, RA_VARYING_0).xyz * 1.14999997615814208984375) / vec3((GLOW_WHITEPOINT)), vec3(0.0), vec3(1.0)), vec3((GLOW_ROLLOFF))), 1.0);
}


#endif
