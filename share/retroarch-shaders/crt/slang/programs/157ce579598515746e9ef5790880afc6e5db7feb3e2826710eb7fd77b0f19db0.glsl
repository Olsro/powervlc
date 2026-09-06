// Generated from crt/shaders/zfast_crt/zfast_crt_geo_svideo.slang. See slang/upstream for licence/source.
#version 120
#pragma parameter SCANLINE_WEIGHT "Scanline Amount"     7.0 0.0 15.0 0.5
#pragma parameter MASK_DARK       "Mask Effect Amount"  0.5 0.0 1.0 0.05
#pragma parameter blurx           "Convergence X-Axis"  0.70 -2.0 2.0 0.05
#pragma parameter blury           "Convergence Y-Axis" -0.30 -2.0 2.0 0.05
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

void main()
{
    gl_Position = (MVPMatrix) * VertexCoord;
    RA_VARYING_0 = TexCoord * 1.00010001659393310546875;
    RA_VARYING_1 = vec2(1.0) / (vec4(TextureSize, 1.0 / TextureSize)).xy;
}


#endif
#ifdef FRAGMENT

uniform float MASK_DARK;
uniform vec2 OutputSize;
uniform float SCANLINE_WEIGHT;
uniform vec2 TextureSize;
uniform float blurx;
uniform float blury;
float _438;

struct Push
{
    vec4 SourceSize;
    vec4 OutputSize;
    float SCANLINE_WEIGHT;
    float MASK_DARK;
    float blurx;
    float blury;
};



uniform sampler2D Texture;

varying vec2 RA_VARYING_0;

void main()
{
    vec2 _365 = (RA_VARYING_0 * 2.0) - vec2(1.0);
    float _367 = _365.y;
    float _374 = _365.x;
    vec2 _384 = (_365 * vec2(1.0 + ((_367 * _367) * 0.02759999968111515045166015625), 1.0 + ((_374 * _374) * 0.04140000045299530029296875))) * 0.5;
    vec2 _386 = _384 + vec2(0.5);
    vec2 _87 = min(_386, vec2(0.5) - _384);
    float _91 = 9.9999997473787516355514526367188e-05 / _87.x;
    float _100 = _386.x;
    vec2 _119 = (vec4(TextureSize, 1.0 / TextureSize)).xy * 2.0;
    vec2 _120 = vec2((blurx), _438) / _119;
    float _121 = _120.x;
    float _124 = _386.y;
    vec2 _134 = vec2(_438, (blury)) / _119;
    float _135 = _134.y;
    vec4 _138 = texture2D(Texture, vec2(_100 + _121, _124 - _135));
    vec4 _143 = texture2D(Texture, _386);
    vec4 _176 = texture2D(Texture, vec2(_100 - _121, _124 + _135));
    vec3 _196 = vec3(_138.x * 0.5, 0.25 * (_138.y + _176.y), _176.z * 0.5) + (_143.xyz * 0.5);
    vec2 _201 = RA_VARYING_0 * (vec2(1.0) - RA_VARYING_0);
    float _219 = RA_VARYING_0.y * (vec4(TextureSize, 1.0 / TextureSize)).y;
    float _225 = _219 - (floor(_219) + 0.5);
    float _229 = _225 * _225;
    float _244 = ((vec4(OutputSize, 1.0 / OutputSize)).y > 1499.0) ? 0.33329999446868896484375 : 0.5;
    bool _301 = _87.y <= _91;
    bool _308;
    if (!_301)
    {
        _308 = _91 < 9.9999997473787516355514526367188e-05;
    }
    else
    {
        _308 = _301;
    }
    vec3 _443;
    if (_308)
    {
        _443 = vec3(0.0);
    }
    else
    {
        _443 = max((_196 * _196) * (mat3(vec3(0.92060387134552001953125, 0.069309853017330169677734375, -0.0516451187431812286376953125), vec3(0.087028317153453826904296875, 0.9494526386260986328125, -0.0078606642782688140869140625), vec3(0.013233962468802928924560546875, 0.118294127285480499267578125, 1.02324199676513671875)) * min(sqrt((_201.x * _201.y) * 46.0), 1.0)), vec3(0.0));
    }
    vec3 _332 = _443 * mix((1.5 - ((SCANLINE_WEIGHT) * (_229 - (_229 * _229)))) * (1.0 + (float(fract(floor(RA_VARYING_0.x * (vec4(OutputSize, 1.0 / OutputSize)).x) * (-_244)) < _244) * (-(MASK_DARK)))), 1.0, 0.2666699886322021484375 * ((_443.x + _443.y) + _443.z));
    vec3 _392 = _332 - vec3(1.0);
    gl_FragData[0] = vec4(mix(sqrt(_332), sqrt(vec3(1.0) - (_392 * _392)), vec3((1.0 / ((((-0.0324999988079071044921875) * (SCANLINE_WEIGHT)) + 1.0) * (((-0.31099998950958251953125) * (MASK_DARK)) + 1.0))) - 1.2000000476837158203125)), 1.0);
}


#endif
