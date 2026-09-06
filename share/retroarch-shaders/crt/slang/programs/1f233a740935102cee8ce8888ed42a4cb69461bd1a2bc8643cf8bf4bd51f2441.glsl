// Generated from crt/shaders/crt-frutbunn.slang. See slang/upstream for licence/source.
#version 120
#pragma parameter CURVATURE "Curvature Toggle" 1.0 0.0 1.0 1.0
#pragma parameter SCANLINES "Scanlines Toggle" 1.0 0.0 1.0 1.0
#pragma parameter CURVED_SCANLINES "Scanline Curve Toggle" 1.0 0.0 1.0 1.0
#pragma parameter LIGHT "Vignetting Toggle" 1.0 0.0 1.0 1.0
#pragma parameter light "Vignetting Strength" 9.0 0.0 20.0 1.0'
#pragma parameter blur "Blur Strength" 1.0 0.0 8.0 0.05
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

uniform float CURVATURE;
uniform float CURVED_SCANLINES;
uniform float LIGHT;
uniform vec2 OutputSize;
uniform float SCANLINES;
uniform vec2 TextureSize;
uniform float blur;
uniform float light;
struct Push
{
    vec4 SourceSize;
    vec4 OutputSize;
    float CURVATURE;
    float SCANLINES;
    float CURVED_SCANLINES;
    float LIGHT;
    float light;
    float blur;
};



uniform sampler2D Texture;

varying vec2 RA_VARYING_0;

void main()
{
    vec2 _210 = RA_VARYING_0 - vec2(0.5);
    float _217 = length(((_210 * 0.5) * _210) * 0.5);
    bool _222 = (CURVATURE) > 0.5;
    vec2 _572;
    if (_222)
    {
        _572 = (_210 * _217) + (_210 * 0.935000002384185791015625);
    }
    else
    {
        _572 = _210;
    }
    vec2 _238 = _572 + vec2(0.5);
    vec2 _246 = (vec4(TextureSize, 1.0 / TextureSize)).xy * 2.0;
    float _362 = _246.x;
    float _364 = _246.y;
    float _366 = (blur) / (_362 / _364);
    float _369 = _238.x;
    float _373 = _366 / _362;
    float _374 = _369 - _373;
    float _376 = _238.y;
    float _380 = _366 / _364;
    float _381 = _376 - _380;
    vec4 _383 = texture2D(Texture, vec2(_374, _381));
    vec4 _397 = texture2D(Texture, vec2(_374, _376));
    float _416 = _376 + _380;
    vec4 _418 = texture2D(Texture, vec2(_374, _416));
    vec4 _434 = texture2D(Texture, vec2(_369, _381));
    vec4 _445 = texture2D(Texture, _238);
    vec4 _461 = texture2D(Texture, vec2(_369, _416));
    float _473 = _369 + _373;
    vec4 _482 = texture2D(Texture, vec2(_473, _381));
    vec4 _498 = texture2D(Texture, vec2(_473, _376));
    vec4 _519 = texture2D(Texture, vec2(_473, _416));
    vec3 _523 = ((((((((_383.xyz * 0.077846996486186981201171875) + (_397.xyz * 0.1233170032501220703125)) + (_418.xyz * 0.077846996486186981201171875)) + (_434.xyz * 0.1233170032501220703125)) + (_445.xyz * 0.19534599781036376953125)) + (_461.xyz * 0.1233170032501220703125)) + (_482.xyz * 0.077846996486186981201171875)) + (_498.xyz * 0.1233170032501220703125)) + (_519.xyz * 0.077846996486186981201171875);
    vec3 _528;
    if ((LIGHT) > 0.5)
    {
        _528 = _523 * (1.0 - min(1.0, _217 * (light)));
    }
    else
    {
        _528 = _523;
    }
    float _526;
    if ((CURVED_SCANLINES) > 0.5)
    {
        _526 = _572.y;
    }
    else
    {
        _526 = _210.y;
    }
    vec3 _529;
    if ((SCANLINES) > 0.5)
    {
        _529 = (_528 * abs(0.0)) + ((_528 - (_528 * (cos((_526 * (vec4(TextureSize, 1.0 / TextureSize)).y) * (2.5 + ((vec4(OutputSize, 1.0 / OutputSize)).y * (vec4(TextureSize, 1.0 / TextureSize)).w))) * 0.25))) * 1.0);
    }
    else
    {
        _529 = _528;
    }
    vec3 _530;
    if (_222)
    {
        _530 = _529 * min(max(0.0, 1.0 - (2.0 * max(abs(_572.x), abs(_572.y)))) * 200.0, 1.0);
    }
    else
    {
        _530 = _529;
    }
    gl_FragData[0] = vec4(_530, 1.0);
}


#endif
