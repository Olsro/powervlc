// Generated from crt/shaders/crt-caligari.slang. See slang/upstream for licence/source.
#version 120
#pragma parameter SPOT_WIDTH "CRTCaligari Spot Width" 0.9 0.5 1.5 0.05
#pragma parameter SPOT_HEIGHT "CRTCaligari Spot Height" 0.65 0.5 1.5 0.05
#pragma parameter COLOR_BOOST "CRTCaligari Color Boost" 1.45 1.0 2.0 0.05
#pragma parameter InputGamma "CRTCaligari Input Gamma" 2.4 0.0 5.0 0.1
#pragma parameter OutputGamma "CRTCaligari Output Gamma" 2.2 0.0 5.0 0.1
#ifdef VERTEX

uniform mat4 MVPMatrix;
uniform vec2 TextureSize;
struct UBO
{
    mat4 MVP;
};



struct Push
{
    vec4 SourceSize;
};



attribute vec4 VertexCoord;
varying vec2 RA_VARYING_0;
attribute vec2 TexCoord;
varying vec2 RA_VARYING_1;
varying vec2 RA_VARYING_2;

void main()
{
    gl_Position = (MVPMatrix) * VertexCoord;
    RA_VARYING_0 = TexCoord;
    RA_VARYING_1 = vec2((vec4(TextureSize, 1.0 / TextureSize)).z, 0.0);
    RA_VARYING_2 = vec2(0.0, (vec4(TextureSize, 1.0 / TextureSize)).w);
}


#endif
#ifdef FRAGMENT

uniform float COLOR_BOOST;
uniform float InputGamma;
uniform float OutputGamma;
uniform float SPOT_HEIGHT;
uniform float SPOT_WIDTH;
uniform vec2 TextureSize;
struct Push
{
    vec4 SourceSize;
    float SPOT_WIDTH;
    float SPOT_HEIGHT;
    float COLOR_BOOST;
    float InputGamma;
    float OutputGamma;
};



uniform sampler2D Texture;

varying vec2 RA_VARYING_0;
varying vec2 RA_VARYING_1;
varying vec2 RA_VARYING_2;

void main()
{
    vec2 _24 = RA_VARYING_0 * (vec4(TextureSize, 1.0 / TextureSize)).xy;
    vec2 _30 = floor(_24) + vec2(0.5);
    vec2 _36 = _30 * (vec4(TextureSize, 1.0 / TextureSize)).zw;
    vec4 _45 = texture2D(Texture, _36);
    vec4 _50 = vec4((InputGamma));
    float _59 = _24.x - _30.x;
    float _65 = _59 / (SPOT_WIDTH);
    float _303 = (_65 > 1.0) ? 1.0 : _65;
    float _75 = 1.0 - (_303 * _303);
    float _78 = _75 * _75;
    vec2 _269;
    float _270;
    if (_59 > 0.0)
    {
        _270 = 1.0 - _59;
        _269 = RA_VARYING_1;
    }
    else
    {
        _270 = 1.0 + _59;
        _269 = -RA_VARYING_1;
    }
    vec2 _102 = _36 + _269;
    vec4 _103 = texture2D(Texture, _102);
    float _112 = _270 / (SPOT_WIDTH);
    float _304 = (_112 > 1.0) ? 1.0 : _112;
    float _120 = 1.0 - (_304 * _304);
    float _123 = _120 * _120;
    float _136 = _24.y - _30.y;
    float _142 = _136 / (SPOT_HEIGHT);
    float _305 = (_142 > 1.0) ? 1.0 : _142;
    float _150 = 1.0 - (_305 * _305);
    vec2 _281;
    float _282;
    if (_136 > 0.0)
    {
        _282 = 1.0 - _136;
        _281 = RA_VARYING_2;
    }
    else
    {
        _282 = 1.0 + _136;
        _281 = -RA_VARYING_2;
    }
    float _185 = _282 / (SPOT_HEIGHT);
    float _306 = (_185 > 1.0) ? 1.0 : _185;
    float _193 = 1.0 - (_306 * _306);
    float _196 = _193 * _193;
    gl_FragData[0] = clamp(pow((((((pow(_45, _50) * vec4(_78)) + (pow(_103, _50) * vec4(_123))) * vec4(_150 * _150)) + (pow(texture2D(Texture, _36 + _281), _50) * vec4(_196 * _78))) + (pow(texture2D(Texture, _102 + _281), _50) * vec4(_196 * _123))) * vec4((COLOR_BOOST)), vec4(1.0 / (OutputGamma))), vec4(0.0), vec4(1.0));
}


#endif
