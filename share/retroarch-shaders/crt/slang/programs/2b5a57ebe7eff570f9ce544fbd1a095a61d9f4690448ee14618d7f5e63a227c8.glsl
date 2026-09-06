// Generated from crt/shaders/crtsim/post-upsample.slang. See slang/upstream for licence/source.
#version 120
#pragma parameter bloom_scale_up "Upsample Bloom Scale" 0.02 0.0 0.03 0.001
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

uniform float bloom_scale_up;
struct Push
{
    float bloom_scale_up;
};



uniform sampler2D Texture;

varying vec2 RA_VARYING_0;

void main()
{
    vec2 _24 = vec2((bloom_scale_up));
    gl_FragData[0] = ((((((texture2D(Texture, RA_VARYING_0) + texture2D(Texture, RA_VARYING_0 + (vec2(1.0, 0.0) * _24))) + texture2D(Texture, RA_VARYING_0 + (vec2(-1.0, 0.0) * _24))) + texture2D(Texture, RA_VARYING_0 + (vec2(0.5, -0.86602497100830078125) * _24))) + texture2D(Texture, RA_VARYING_0 + (vec2(-0.5, -0.86602497100830078125) * _24))) + texture2D(Texture, RA_VARYING_0 + (vec2(0.5, 0.86602497100830078125) * _24))) + texture2D(Texture, RA_VARYING_0 + (vec2(-0.5, 0.86602497100830078125) * _24))) * 0.14285714924335479736328125;
}


#endif
