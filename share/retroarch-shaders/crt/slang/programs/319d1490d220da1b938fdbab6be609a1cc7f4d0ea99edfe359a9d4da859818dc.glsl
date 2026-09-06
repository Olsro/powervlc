// Generated from crt/shaders/newpixie/accumulate.slang. See slang/upstream for licence/source.
#version 120
#pragma parameter acc_modulate "Accumulate Modulation" 0.65 0.0 1.0 0.01
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

uniform float acc_modulate;
struct Push
{
    float acc_modulate;
};



uniform sampler2D FeedbackTexture;
uniform sampler2D Texture;

varying vec2 RA_VARYING_0;

void main()
{
    gl_FragData[0] = max(texture2D(FeedbackTexture, RA_VARYING_0) * vec4((acc_modulate)), texture2D(Texture, RA_VARYING_0) * 0.959999978542327880859375);
}


#endif
