// Generated from crt/shaders/crt-cgwg-fast.slang. See slang/upstream for licence/source.
#version 120
#pragma parameter CRTCGWG_GAMMA "CRTcgwg Gamma" 2.7 0.0 10.0 0.01
#ifdef VERTEX

uniform mat4 MVPMatrix;
uniform vec2 OutputSize;
uniform vec2 TextureSize;
struct UBO
{
    mat4 MVP;
    vec4 OutputSize;
    vec4 SourceSize;
};



attribute vec4 VertexCoord;
varying vec2 RA_VARYING_0;
attribute vec2 TexCoord;
varying vec2 RA_VARYING_1;
varying vec2 RA_VARYING_2;
varying vec2 RA_VARYING_3;
varying vec2 RA_VARYING_4;
varying vec2 RA_VARYING_5;
varying vec2 RA_VARYING_6;
varying vec2 RA_VARYING_7;
varying vec2 RA_VARYING_8;
varying float RA_VARYING_9;
varying vec2 RA_VARYING_10;

void main()
{
    gl_Position = (MVPMatrix) * VertexCoord;
    RA_VARYING_0 = TexCoord;
    float _53 = -(vec4(TextureSize, 1.0 / TextureSize)).z;
    RA_VARYING_1 = RA_VARYING_0 + vec2(_53, 0.0);
    RA_VARYING_2 = RA_VARYING_0;
    RA_VARYING_3 = RA_VARYING_0 + vec2((vec4(TextureSize, 1.0 / TextureSize)).z, 0.0);
    float _70 = 2.0 * (vec4(TextureSize, 1.0 / TextureSize)).z;
    RA_VARYING_4 = RA_VARYING_0 + vec2(_70, 0.0);
    RA_VARYING_5 = RA_VARYING_0 + vec2(_53, (vec4(TextureSize, 1.0 / TextureSize)).w);
    RA_VARYING_6 = RA_VARYING_0 + vec2(0.0, (vec4(TextureSize, 1.0 / TextureSize)).w);
    RA_VARYING_7 = RA_VARYING_0 + vec2((vec4(TextureSize, 1.0 / TextureSize)).zw);
    RA_VARYING_8 = RA_VARYING_0 + vec2(_70, (vec4(TextureSize, 1.0 / TextureSize)).w);
    RA_VARYING_9 = RA_VARYING_0.x * (vec4(OutputSize, 1.0 / OutputSize)).x;
    RA_VARYING_10 = RA_VARYING_0 * (vec4(TextureSize, 1.0 / TextureSize)).xy;
}


#endif
#ifdef FRAGMENT

uniform float CRTCGWG_GAMMA;
struct Push
{
    float CRTCGWG_GAMMA;
};



uniform sampler2D Texture;

varying vec2 RA_VARYING_10;
varying vec2 RA_VARYING_1;
varying vec2 RA_VARYING_2;
varying vec2 RA_VARYING_3;
varying vec2 RA_VARYING_4;
varying vec2 RA_VARYING_5;
varying vec2 RA_VARYING_6;
varying vec2 RA_VARYING_7;
varying vec2 RA_VARYING_8;
varying float RA_VARYING_9;

void main()
{
    vec2 _13 = fract(RA_VARYING_10);
    float _106 = _13.x;
    vec4 _120 = vec4(1.0 + _106, _106, 1.0 - _106, 2.0 - _106) + vec4(0.004999999888241291046142578125);
    vec4 _133 = (sin(_120 * 3.1415927410125732421875) * sin(_120 * 1.57079637050628662109375)) / (_120 * _120);
    vec4 _139 = _133 / vec4(dot(_133, vec4(1.0)));
    float _145 = _13.y;
    vec3 _175 = clamp(mat4x3(vec3(texture2D(Texture, RA_VARYING_1).xyz), vec3(texture2D(Texture, RA_VARYING_2).xyz), vec3(texture2D(Texture, RA_VARYING_3).xyz), vec3(texture2D(Texture, RA_VARYING_4).xyz)) * _139, vec3(0.0), vec3(1.0));
    vec3 _182 = clamp(mat4x3(vec3(texture2D(Texture, RA_VARYING_5).xyz), vec3(texture2D(Texture, RA_VARYING_6).xyz), vec3(texture2D(Texture, RA_VARYING_7).xyz), vec3(texture2D(Texture, RA_VARYING_8).xyz)) * _139, vec3(0.0), vec3(1.0));
    vec3 _190 = (pow(_175, vec3(4.0)) * 2.0) + vec3(2.0);
    vec3 _196 = (pow(_182, vec3(4.0)) * 2.0) + vec3(2.0);
    vec3 _206 = vec3((CRTCGWG_GAMMA));
    gl_FragData[0] = vec4(pow(mix(vec3(1.0, 0.699999988079071044921875, 1.0), vec3(0.699999988079071044921875, 1.0, 0.699999988079071044921875), vec3(floor(mod(RA_VARYING_9, 2.0)))) * ((pow(_175, _206) * (exp(-pow(vec3(3.3299999237060546875 * _145) * inversesqrt(_190 * 0.5), _190)) / ((_190 * 0.1319999992847442626953125) + vec3(0.3919999897480010986328125)))) + (pow(_182, _206) * (exp(-pow(vec3(((-3.3299999237060546875) * _145) + 3.3299999237060546875) * inversesqrt(_196 * 0.5), _196)) / ((_196 * 0.1319999992847442626953125) + vec3(0.3919999897480010986328125))))), vec3(0.4545449912548065185546875)), 1.0);
}


#endif
