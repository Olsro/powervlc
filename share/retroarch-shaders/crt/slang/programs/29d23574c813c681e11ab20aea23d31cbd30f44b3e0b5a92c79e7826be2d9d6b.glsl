// Generated from crt/shaders/crt-simple.slang. See slang/upstream for licence/source.
#version 120
#pragma parameter DISTORTION "Distortion" 0.12 0.0 0.30 0.01
#pragma parameter SCANLINE "Scanline Weight" 0.3 0.2 0.6 0.05
#pragma parameter DOWNSCALE "Scanlines Downscale" 1.0 1.0 2.0 1.0
#pragma parameter INPUTGAMMA "Input Gamma" 2.4 0.0 4.0 0.05
#pragma parameter OUTPUTGAMMA "Output Gamma" 2.2 0.0 4.0 0.05
#pragma parameter MASK "Mask Brightness" 0.7 0.0 1.0 0.05
#pragma parameter SIZE "Mask Size" 1.0 1.0 2.0 1.0
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
    RA_VARYING_0 = TexCoord * 1.00010001659393310546875;
}


#endif
#ifdef FRAGMENT

uniform float DISTORTION;
uniform float DOWNSCALE;
uniform float INPUTGAMMA;
uniform float MASK;
uniform float OUTPUTGAMMA;
uniform vec2 OrigTextureSize;
uniform vec2 OutputSize;
uniform float SCANLINE;
uniform float SIZE;
uniform vec2 TextureSize;
struct Push
{
    vec4 SourceSize;
    vec4 OriginalSize;
    vec4 OutputSize;
    float DISTORTION;
    float SCANLINE;
    float INPUTGAMMA;
    float OUTPUTGAMMA;
    float MASK;
    float SIZE;
    float DOWNSCALE;
};



uniform sampler2D Texture;

varying vec2 RA_VARYING_0;

void main()
{
    vec2 _308 = vec2((DISTORTION), (DISTORTION) * 1.5);
    vec2 _319 = (vec4(TextureSize, 1.0 / TextureSize)).xy / (vec4(OrigTextureSize, 1.0 / OrigTextureSize)).xy;
    vec2 _323 = (RA_VARYING_0 * _319) - vec2(0.5);
    float _325 = _323.x;
    float _330 = _323.y;
    vec2 _344 = (_323 + (_323 * (_308 * ((_325 * _325) + (_330 * _330))))) * (vec2(1.0) - (_308 * 0.23000000417232513427734375));
    bool _348 = abs(_344.x) >= 0.5;
    bool _356;
    if (!_348)
    {
        _356 = abs(_344.y) >= 0.5;
    }
    else
    {
        _356 = _348;
    }
    vec2 _452;
    if (_356)
    {
        _452 = vec2(-1.0);
    }
    else
    {
        _452 = (_344 + vec2(0.5)) / _319;
    }
    vec2 _181 = (_452 * (vec4(TextureSize, 1.0 / TextureSize)).xy) - vec2(0.5);
    vec2 _189 = fract(_181 / vec2((DOWNSCALE)));
    vec2 _197 = (floor(_181) + vec2(0.5)) / (vec4(TextureSize, 1.0 / TextureSize)).xy;
    _197.x = _452.x;
    vec4 _212 = vec4((INPUTGAMMA));
    vec4 _213 = pow(texture2D(Texture, _197), _212);
    vec4 _228 = pow(texture2D(Texture, _197 + vec2(0.0, (vec4(TextureSize, 1.0 / TextureSize)).w)), _212);
    float _232 = _189.y;
    vec4 _380 = vec4(2.0) + (pow(_213, vec4(4.0)) * 2.0);
    vec4 _409 = vec4(2.0) + (pow(_228, vec4(4.0)) * 2.0);
    gl_FragData[0] = vec4(pow(((_213 * ((exp(-pow(vec4(_232 / (SCANLINE)) * inversesqrt(_380 * 0.5), _380)) * 1.39999997615814208984375) / (vec4(0.60000002384185791015625) + (_380 * 0.20000000298023223876953125)))) + (_228 * ((exp(-pow(vec4((1.0 - _232) / (SCANLINE)) * inversesqrt(_409 * 0.5), _409)) * 1.39999997615814208984375) / (vec4(0.60000002384185791015625) + (_409 * 0.20000000298023223876953125))))).xyz * mix(vec3((MASK)), vec3(1.0), vec3(fract(((RA_VARYING_0 * (vec4(OutputSize, 1.0 / OutputSize)).xy).x * 0.5) / (SIZE)))), vec3(1.0 / (OUTPUTGAMMA))), 1.0);
}


#endif
