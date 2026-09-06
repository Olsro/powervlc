// Generated from crt/shaders/crt-super-xbr/custom-resolve.slang. See slang/upstream for licence/source.
#version 120
#pragma parameter BLOOM_STRENGTH "Bloom Strength"  0.10 0.0 1.0 0.01
#pragma parameter SOURCE_BOOST "Bloom Color Boost" 1.15 1.0 2.0 0.05
#pragma parameter OUTPUT_GAMMA "OUTPUT GAMMA"       2.2 1.0 3.0  0.1
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

uniform float BLOOM_STRENGTH;
uniform float OUTPUT_GAMMA;
uniform float SOURCE_BOOST;
struct Push
{
    float BLOOM_STRENGTH;
    float SOURCE_BOOST;
    float OUTPUT_GAMMA;
};



uniform sampler2D Pass7Texture;
uniform sampler2D Texture;

varying vec2 RA_VARYING_0;

void main()
{
    gl_FragData[0] = vec4(pow(clamp((texture2D(Pass7Texture, RA_VARYING_0).xyz * (SOURCE_BOOST)) + (texture2D(Texture, RA_VARYING_0).xyz * (BLOOM_STRENGTH)), vec3(0.0), vec3(1.0)), vec3(1.0 / (OUTPUT_GAMMA))), 1.0);
}


#endif
