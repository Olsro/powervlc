// Generated from crt/shaders/hyllian/crt-hyllian-3d.slang. See slang/upstream for licence/source.
#version 120
#pragma parameter CRT_MULRES_X "CRT - Internal X Res Multiplier" 2.0 1.0 8.0 1.0
#pragma parameter CRT_MULRES_Y "CRT - Internal Y Res Multiplier" 2.0 1.0 8.0 1.0
#pragma parameter PHOSPHOR "CRT - Phosphor ON/OFF" 1.0 0.0 1.0 1.0
#pragma parameter InputGamma "CRT - Input gamma" 2.4 0.0 5.0 0.1
#pragma parameter OutputGamma "CRT - Output Gamma" 2.2 0.0 5.0 0.1
#pragma parameter SHARPNESS "CRT - Sharpness Hack" 1.0 1.0 5.0 1.0
#pragma parameter COLOR_BOOST "CRT - Color Boost" 1.5 1.0 2.0 0.05
#pragma parameter RED_BOOST "CRT - Red Boost" 1.0 1.0 2.0 0.01
#pragma parameter GREEN_BOOST "CRT - Green Boost" 1.0 1.0 2.0 0.01
#pragma parameter BLUE_BOOST "CRT - Blue Boost" 1.0 1.0 2.0 0.01
#pragma parameter SCANLINES_STRENGTH "CRT - Scanline Strength" 0.72 0.0 1.0 0.02
#pragma parameter BEAM_MIN_WIDTH "CRT - Min Beam Width" 0.86 0.0 1.0 0.02
#pragma parameter BEAM_MAX_WIDTH "CRT - Max Beam Width" 1.0 0.0 1.0 0.02
#pragma parameter CRT_ANTI_RINGING "CRT - Anti-Ringing" 0.8 0.0 1.0 0.1
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

uniform float BEAM_MAX_WIDTH;
uniform float BEAM_MIN_WIDTH;
uniform float BLUE_BOOST;
uniform float COLOR_BOOST;
uniform float CRT_ANTI_RINGING;
uniform float CRT_MULRES_X;
uniform float CRT_MULRES_Y;
uniform float GREEN_BOOST;
uniform float InputGamma;
uniform float OutputGamma;
uniform vec2 OutputSize;
uniform float PHOSPHOR;
uniform float RED_BOOST;
uniform float SCANLINES_STRENGTH;
uniform float SHARPNESS;
uniform vec2 TextureSize;
struct Push
{
    vec4 SourceSize;
    vec4 OutputSize;
    float CRT_MULRES_X;
    float CRT_MULRES_Y;
    float PHOSPHOR;
    float InputGamma;
    float OutputGamma;
    float SHARPNESS;
    float COLOR_BOOST;
    float RED_BOOST;
    float GREEN_BOOST;
    float BLUE_BOOST;
    float SCANLINES_STRENGTH;
    float BEAM_MIN_WIDTH;
    float BEAM_MAX_WIDTH;
    float CRT_ANTI_RINGING;
};



uniform sampler2D Texture;

varying vec2 RA_VARYING_0;

void main()
{
    vec2 _586 = vec2((SHARPNESS) * (vec4(TextureSize, 1.0 / TextureSize)).x, (vec4(TextureSize, 1.0 / TextureSize)).y) / vec2((CRT_MULRES_X), (CRT_MULRES_Y));
    vec2 _590 = vec2(1.0 / _586.x, 0.0);
    vec2 _594 = vec2(0.0, 1.0 / _586.y);
    vec2 _598 = (RA_VARYING_0 * _586) + vec2(-0.5, 0.5);
    vec2 _603 = (floor(_598) + vec2(0.5)) / _586;
    vec2 _605 = fract(_598);
    vec2 _609 = _603 - _590;
    vec4 _621 = vec4((InputGamma));
    vec4 _637 = pow(texture2D(Texture, _603 - _594), _621);
    vec2 _641 = _603 + _590;
    vec4 _654 = pow(texture2D(Texture, _641 - _594), _621);
    vec2 _659 = _603 + (_590 * 2.0);
    vec4 _700 = pow(texture2D(Texture, _603), _621);
    vec4 _715 = pow(texture2D(Texture, _641), _621);
    vec4 _738 = min(min(_637, _700), min(_654, _715));
    vec4 _745 = max(max(_637, _700), max(_654, _715));
    float _797 = _605.x;
    float _800 = _797 * _797;
    vec4 _813 = vec4(_800 * _797, _800, _797, 1.0) * mat4(vec4(-0.5, 1.0, -0.5, 0.0), vec4(1.5, -2.5, 0.0, 1.0), vec4(-1.5, 2.0, 0.5, 0.0), vec4(0.5, -0.5, 0.0, 0.0));
    vec4 _816 = mat4(pow(texture2D(Texture, _609 - _594), _621), _637, _654, pow(texture2D(Texture, _659 - _594), _621)) * _813;
    vec4 _819 = mat4(pow(texture2D(Texture, _609), _621), _700, _715, pow(texture2D(Texture, _659), _621)) * _813;
    vec4 _829 = vec4((CRT_ANTI_RINGING));
    float _843 = _605.y;
    vec3 _853 = vec3((BEAM_MIN_WIDTH));
    vec3 _860 = vec3((BEAM_MAX_WIDTH));
    vec3 _862 = mix(_816, clamp(_816, _738, _745), _829).xyz;
    vec3 _879 = mix(_819, clamp(_819, _738, _745), _829).xyz;
    vec3 _889 = clamp(vec3(_843) / (mix(_853, _860, _862) + vec3(1.0000000116860974230803549289703e-07)), vec3(0.0), vec3(1.0));
    vec3 _898 = clamp(vec3(1.0 - _843) / (mix(_853, _860, _879) + vec3(1.0000000116860974230803549289703e-07)), vec3(0.0), vec3(1.0));
    float _901 = (-10.0) * (SCANLINES_STRENGTH);
    gl_FragData[0] = vec4(pow((clamp((_862 * exp((_889 * _901) * _889)) + (_879 * exp((_898 * _901) * _898)), vec3(0.0), vec3(1.0)) * (vec3((RED_BOOST), (GREEN_BOOST), (BLUE_BOOST)) * (COLOR_BOOST))) * mix(vec3(1.0), mix(vec3(1.0, 0.699999988079071044921875, 1.0), vec3(0.699999988079071044921875, 1.0, 0.699999988079071044921875), vec3(floor(mod(RA_VARYING_0.x * (vec4(OutputSize, 1.0 / OutputSize)).x, 2.0)))), vec3((PHOSPHOR))), vec3(1.0 / (OutputGamma))), 1.0);
}


#endif
