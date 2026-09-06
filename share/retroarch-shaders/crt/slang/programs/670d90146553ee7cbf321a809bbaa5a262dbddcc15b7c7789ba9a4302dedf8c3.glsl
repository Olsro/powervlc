// Generated from crt/shaders/torridgristle/Brighten.slang. See slang/upstream for licence/source.
#version 120
#pragma parameter BrightenLevel "Brighten Level" 2.0 1.0 10.0 1.0
#pragma parameter BrightenAmount "Brighten Amount" 0.1 0.0 1.0 0.1
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

uniform float BrightenAmount;
uniform float BrightenLevel;
struct Push
{
    float BrightenLevel;
    float BrightenAmount;
};



uniform sampler2D Texture;

varying vec2 RA_VARYING_0;

void main()
{
    vec3 _27 = clamp(texture2D(Texture, RA_VARYING_0).xyz, vec3(0.0), vec3(1.0));
    gl_FragData[0] = vec4(mix(_27, vec3(1.0) - pow(vec3(1.0) - _27, vec3((BrightenLevel))), vec3((BrightenAmount))), 1.0);
}


#endif
