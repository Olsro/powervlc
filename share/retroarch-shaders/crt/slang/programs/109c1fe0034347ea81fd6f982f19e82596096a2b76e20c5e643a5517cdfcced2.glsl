// Generated from crt/shaders/hyllian/support/glow/threshold.slang. See slang/upstream for licence/source.
#version 120
#pragma parameter glow_nonono        "GLOW SETTINGS:"      0.0 0.0 0.0 0.0
#pragma parameter GLOW_ENABLE        "    Enable Glow"     0.0 0.0 1.0 1.0
#pragma parameter GLOW_WHITEPOINT    "        Whitepoint" 0.9 0.5 1.1 0.02
#pragma parameter GLOW_ROLLOFF       "        Rolloff"    2.0 1.2 6.0 0.1
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
    gl_FragData[0] = vec4(pow(clamp(texture2D(Texture, RA_VARYING_0).xyz / vec3((GLOW_WHITEPOINT)), vec3(0.0), vec3(1.0)), vec3((GLOW_ROLLOFF))), 1.0);
}


#endif
