// Generated from crt/shaders/GritsScanlines/GritsScanlines.slang. See slang/upstream for licence/source.
#version 120
#pragma parameter ScanlinesOpacity "Scanline Opacity" 0.9 0.0 1.0 0.05
#pragma parameter GammaCorrection "Gamma Correction" 1.2 0.5 2.0 0.1
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

uniform float ScanlinesOpacity;
uniform vec2 TextureSize;
struct Push
{
    vec4 SourceSize;
    float ScanlinesOpacity;
};



uniform sampler2D luminance_LUT;
uniform sampler2D Texture;
uniform sampler2D scanlines_LUT;

varying vec2 RA_VARYING_0;

void main()
{
    vec4 _96 = texture2D(Texture, RA_VARYING_0);
    float _160 = ((_96.x * 15.0) + 0.4999000132083892822265625) * 0.00390625;
    float _165 = ((_96.y * 15.0) + 0.4999000132083892822265625) * 0.0625;
    float _167 = _96.z;
    float _168 = _167 * 15.0;
    float _172 = (floor(_168) * 0.0625) + _160;
    float _179 = (ceil(_168) * 0.0625) + _160;
    gl_FragData[0] = ((texture2D(scanlines_LUT, vec2(clamp(mix(texture2D(luminance_LUT, vec2(_172, _165)).x, texture2D(luminance_LUT, vec2(_179, _165)).x, clamp(max((_167 - _172) / (_179 - _172), 0.0), 0.0, 32.0)), 0.0, 1.0), fract(RA_VARYING_0.y * (vec4(TextureSize, 1.0 / TextureSize)).y))) * (ScanlinesOpacity)) + vec4(1.0 - (ScanlinesOpacity))) * _96;
}


#endif
