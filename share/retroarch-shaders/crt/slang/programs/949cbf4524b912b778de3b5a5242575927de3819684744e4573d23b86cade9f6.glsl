// Generated from crt/shaders/crt-slangtest/scanline.slang. See slang/upstream for licence/source.
#version 130
#pragma parameter OUT_GAMMA "Monitor Output Gamma" 2.2 1.8 2.4
#pragma parameter BOOST "Color Boost" 1.0 0.2 2.0 0.02
#pragma parameter GAMMA "CRT gamma" 2.5 2.0 3.0 0.02
#ifdef VERTEX

uniform mat4 MVPMatrix;
struct UBO1
{
    mat4 MVP;
};



in vec4 VertexCoord;
out vec2 RA_VARYING_0;
in vec2 TexCoord;

void main()
{
    gl_Position = (MVPMatrix) * VertexCoord;
    RA_VARYING_0 = TexCoord;
}


#endif
#ifdef FRAGMENT

uniform float BOOST;
uniform float OUT_GAMMA;
uniform vec2 TextureSize;
struct UBO
{
    vec4 SourceSize;
    float OUT_GAMMA;
    float BOOST;
};



uniform sampler2D Texture;

in vec2 RA_VARYING_0;
out vec4 FragColor;

void main()
{
    vec2 _56 = RA_VARYING_0 * (vec4(TextureSize, 1.0 / TextureSize)).xy;
    float _62 = _56.y;
    vec2 _185 = _56;
    _185.y = floor(_62) + 0.5;
    vec2 _75 = _185 * (vec4(TextureSize, 1.0 / TextureSize)).zw;
    vec3 _87 = textureLodOffset(Texture, _75, 0.0, ivec2(0, -1)).xyz;
    vec3 _93 = textureLodOffset(Texture, _75, 0.0, ivec2(0)).xyz;
    vec3 _99 = textureLodOffset(Texture, _75, 0.0, ivec2(0, 1)).xyz;
    vec3 _120 = (vec3(3.5) - (vec3(dot(_87, vec3(0.2899999916553497314453125, 0.60000002384185791015625, 0.10999999940395355224609375)), dot(_93, vec3(0.2899999916553497314453125, 0.60000002384185791015625, 0.10999999940395355224609375)), dot(_99, vec3(0.2899999916553497314453125, 0.60000002384185791015625, 0.10999999940395355224609375))) * 1.0)) * (vec3(fract(_62) - 0.5) + vec3(1.0, 0.0, -1.0));
    vec3 _125 = exp2((-_120) * _120);
    FragColor = vec4(pow(clamp((((_87 * _125.x) + (_93 * _125.y)) + (_99 * _125.z)) * (BOOST), vec3(0.0), vec3(1.0)), vec3(1.0 / (OUT_GAMMA))), 1.0);
}


#endif
