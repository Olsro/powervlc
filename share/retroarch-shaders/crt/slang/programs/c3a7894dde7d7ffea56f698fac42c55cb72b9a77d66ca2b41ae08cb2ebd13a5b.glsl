// Generated from crt/shaders/torridgristle/Candy-Bloom.slang. See slang/upstream for licence/source.
#version 120
#pragma parameter GlowLevel "Glow Level" 1.0 0.0 1.0 0.1
#pragma parameter GlowTightness "Glow Tightness" 0.5 0.0 1.0 0.1
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

uniform float GlowLevel;
uniform float GlowTightness;
struct Push
{
    float GlowLevel;
    float GlowTightness;
};



uniform sampler2D Texture;
uniform sampler2D Pass4Texture;

varying vec2 RA_VARYING_0;

void main()
{
    vec4 _20 = texture2D(Texture, RA_VARYING_0);
    float _27 = _20.x;
    float _30 = _20.y;
    float _33 = _20.z;
    float _59 = ((0.2989999949932098388671875 * _27) + (0.58700001239776611328125 * _30)) + (0.114000000059604644775390625 * _33);
    gl_FragData[0] = vec4(mix(texture2D(Pass4Texture, RA_VARYING_0).xyz, clamp(_20.xyz / vec3(max(_27, max(_30, _33))), vec3(0.0), vec3(1.0)), vec3(mix(1.0 - pow(1.0 - _59, 2.0), _59 * _59, (GlowTightness)) * (GlowLevel))), 1.0);
}


#endif
