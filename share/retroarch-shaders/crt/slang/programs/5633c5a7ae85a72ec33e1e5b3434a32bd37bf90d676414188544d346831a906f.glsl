// Generated from crt/shaders/glow/gauss_vert.slang. See slang/upstream for licence/source.
#version 120
#pragma parameter BOOST "Color Boost" 1.0 0.5 1.5 0.02
#ifdef VERTEX

uniform mat4 MVPMatrix;
uniform vec2 TextureSize;
struct UBO
{
    mat4 MVP;
    vec4 SourceSize;
};



attribute vec4 VertexCoord;
varying vec2 RA_VARYING_0;
attribute vec2 TexCoord;
varying vec2 RA_VARYING_1;
varying float RA_VARYING_2;

void main()
{
    gl_Position = (MVPMatrix) * VertexCoord;
    RA_VARYING_0 = TexCoord;
    RA_VARYING_1 = (RA_VARYING_0 * (vec4(TextureSize, 1.0 / TextureSize)).xy) - vec2(0.0, 0.5);
    RA_VARYING_2 = (vec4(TextureSize, 1.0 / TextureSize)).w;
}


#endif
#ifdef FRAGMENT

uniform float BOOST;
uniform vec2 TextureSize;
struct UBO
{
    vec4 SourceSize;
};



struct Push
{
    float BOOST;
};



uniform sampler2D Texture;

varying vec2 RA_VARYING_1;
varying float RA_VARYING_2;

void main()
{
    vec2 _58 = floor(RA_VARYING_1);
    float _67 = RA_VARYING_1.y - _58.y;
    vec2 _83 = (_58 + vec2(0.5)) * (vec4(TextureSize, 1.0 / TextureSize)).zw;
    vec3 _98 = texture2D(Texture, _83).xyz;
    vec3 _108 = texture2D(Texture, _83 + vec2(0.0, RA_VARYING_2)).xyz;
    vec3 _156 = vec3(2.0) + (pow(_98, vec3(4.0)) * 2.0);
    vec3 _186 = vec3(2.0) + (pow(_108, vec3(4.0)) * 2.0);
    gl_FragData[0] = vec4((((((_98 * 2.0) * exp(-pow(vec3(abs(_67) * 3.3333332538604736328125) * inversesqrt(_156 * 0.5), _156))) / (vec3(0.60000002384185791015625) + (_156 * 0.20000000298023223876953125))) + (((_108 * 2.0) * exp(-pow(vec3(abs(1.0 - _67) * 3.3333332538604736328125) * inversesqrt(_186 * 0.5), _186))) / (vec3(0.60000002384185791015625) + (_186 * 0.20000000298023223876953125)))) * (BOOST)) * 0.869565188884735107421875, 1.0);
}


#endif
