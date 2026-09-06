// Generated from crt/shaders/zfast_crt/zfast_crt_geo.slang. See slang/upstream for licence/source.
#version 120
#pragma parameter SCANLINE_WEIGHT "Scanline Amount"     7.0 0.0 15.0 0.5
#pragma parameter MASK_DARK       "Mask Effect Amount"  0.5 0.0 1.0 0.05
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
struct Push
{
    vec4 SourceSize;
    vec4 OutputSize;
    float SCANLINE_WEIGHT;
    float MASK_DARK;
};



uniform sampler2D Texture;

varying vec2 RA_VARYING_0;
varying vec2 RA_VARYING_1;

void main()
{
    vec2 _291 = (RA_VARYING_0 * 2.0) - vec2(1.0);
    float _293 = _291.y;
    float _300 = _291.x;
    vec2 _310 = (_291 * vec2(1.0 + ((_293 * _293) * 0.02759999968111515045166015625), 1.0 + ((_300 * _300) * 0.04140000045299530029296875))) * 0.5;
    vec2 _312 = _310 + vec2(0.5);
    vec2 _87 = min(_312, vec2(0.5) - _310);
    float _91 = 9.9999997473787516355514526367188e-05 / _87.x;
    vec2 _97 = RA_VARYING_0 * (vec2(1.0) - RA_VARYING_0);
    float _121 = _312.y * (vec4(TextureSize, 1.0 / TextureSize)).y;
    float _125 = floor(_121 - 0.5);
    float _130 = (-1.0) + (_121 - _125);
    float _134 = _130 * _130;
    float _162 = ((vec4(OutputSize, 1.0 / OutputSize)).y > 1499.0) ? 0.33329999446868896484375 : 0.5;
    vec4 _191 = texture2D(Texture, vec2(_312.x, ((_125 + 0.5) + ((4.0 * _134) * _130)) * RA_VARYING_1.y));
    vec3 _192 = _191.xyz;
    bool _228 = _87.y <= _91;
    bool _235;
    if (!_228)
    {
        _235 = _91 < 9.9999997473787516355514526367188e-05;
    }
    else
    {
        _235 = _228;
    }
    vec3 _362;
    if (_235)
    {
        _362 = vec3(0.0);
    }
    else
    {
        _362 = max((_192 * _192) * (mat3(vec3(1.0, 0.0, -0.0617300011217594146728515625), vec3(0.071110002696514129638671875, 0.968869984149932861328125, -0.011359999887645244598388671875), vec3(0.0, 0.081969998776912689208984375, 1.07280004024505615234375)) * min(sqrt((_97.x * _97.y) * 46.0), 1.0)), vec3(0.0));
    }
    vec3 _259 = _362 * mix((1.5 - ((SCANLINE_WEIGHT) * (_134 - (_134 * _134)))) * (1.0 + (float(fract(floor(RA_VARYING_0.x * (vec4(OutputSize, 1.0 / OutputSize)).x) * (-_162)) < _162) * (-(MASK_DARK)))), 1.0, 0.2666699886322021484375 * ((_362.x + _362.y) + _362.z));
    vec3 _318 = _259 - vec3(1.0);
    vec3 _329 = mix(sqrt(_259), sqrt(vec3(1.0) - (_318 * _318)), vec3((1.0 / ((((-0.0324999988079071044921875) * (SCANLINE_WEIGHT)) + 1.0) * (((-0.31099998950958251953125) * (MASK_DARK)) + 1.0))) - 1.2000000476837158203125));
    gl_FragData[0] = vec4(_329, 1.0);
}


#endif
