// Generated from reshade/shaders/blendoverlay/blendoverlay.slang. See slang/upstream for licence/source.
#version 120
#pragma parameter OverlayMix "Overlay Mix" 1.0 0.0 1.0 0.05
#pragma parameter LUTWidth "LUT Width" 6.0 1.0 1920.0 1.0
#pragma parameter LUTHeight "LUT Height" 4.0 1.0 1920.0 1.0
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

uniform float LUTHeight;
uniform float LUTWidth;
uniform vec2 OutputSize;
uniform float OverlayMix;
struct Push
{
    vec4 OutputSize;
    float OverlayMix;
    float LUTWidth;
    float LUTHeight;
};



uniform sampler2D Texture;
uniform sampler2D overlay;

varying vec2 RA_VARYING_0;

void main()
{
    vec4 _50 = texture2D(Texture, RA_VARYING_0);
    vec4 _105 = texture2D(overlay, vec2(fract((RA_VARYING_0.x * (vec4(OutputSize, 1.0 / OutputSize)).x) / (LUTWidth)), fract((RA_VARYING_0.y * (vec4(OutputSize, 1.0 / OutputSize)).y) / (LUTHeight))));
    float _111 = _50.x;
    float _114 = _105.x;
    float _215;
    if (_111 < 0.5)
    {
        _215 = (2.0 * _111) * _114;
    }
    else
    {
        _215 = 1.0 - ((2.0 * (1.0 - _111)) * (1.0 - _114));
    }
    float _119 = _50.y;
    float _122 = _105.y;
    float _216;
    if (_119 < 0.5)
    {
        _216 = (2.0 * _119) * _122;
    }
    else
    {
        _216 = 1.0 - ((2.0 * (1.0 - _119)) * (1.0 - _122));
    }
    float _127 = _50.z;
    float _130 = _105.z;
    float _217;
    if (_127 < 0.5)
    {
        _217 = (2.0 * _127) * _130;
    }
    else
    {
        _217 = 1.0 - ((2.0 * (1.0 - _127)) * (1.0 - _130));
    }
    gl_FragData[0] = vec4(mix(_50.xyz, clamp(vec3(_215, _216, _217), vec3(0.0), vec3(1.0)), vec3((OverlayMix))), 1.0);
}


#endif
