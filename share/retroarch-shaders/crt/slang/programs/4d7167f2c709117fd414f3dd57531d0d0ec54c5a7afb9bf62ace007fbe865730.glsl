// Generated from crt/shaders/hyllian/support/glow/blur_horiz.slang. See slang/upstream for licence/source.
#version 120
#pragma parameter GLOW_RADIUS "        Radius" 4.0 2.0 4.0 0.1
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

uniform float GLOW_RADIUS;
uniform vec2 TextureSize;
struct UBO
{
    vec4 SourceSize;
};



struct Push
{
    float GLOW_RADIUS;
};



uniform sampler2D Texture;

varying vec2 RA_VARYING_0;

void main()
{
    vec2 _140 = vec2((GLOW_RADIUS) * (vec4(TextureSize, 1.0 / TextureSize)).z, 0.0);
    vec2 _164 = _140 * 4.0;
    vec2 _174 = _140 * 3.0;
    vec2 _184 = _140 * 2.0;
    gl_FragData[0] = vec4(((((((((texture2D(Texture, RA_VARYING_0 - _164).xyz * 0.001234402996487915515899658203125) + (texture2D(Texture, RA_VARYING_0 - _174).xyz * 0.01430468820035457611083984375)) + (texture2D(Texture, RA_VARYING_0 - _184).xyz * 0.0823177993297576904296875)) + (texture2D(Texture, RA_VARYING_0 - _140).xyz * 0.2352355420589447021484375)) + (texture2D(Texture, RA_VARYING_0).xyz * 0.3338151276111602783203125)) + (texture2D(Texture, RA_VARYING_0 + _140).xyz * 0.2352355420589447021484375)) + (texture2D(Texture, RA_VARYING_0 + _184).xyz * 0.0823177993297576904296875)) + (texture2D(Texture, RA_VARYING_0 + _174).xyz * 0.01430468820035457611083984375)) + (texture2D(Texture, RA_VARYING_0 + _164).xyz * 0.001234402996487915515899658203125), 1.0);
}


#endif
