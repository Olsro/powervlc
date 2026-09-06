// Generated from crt/shaders/yeetron.slang. See slang/upstream for licence/source.
#version 120
#pragma parameter viewSizeHD "Min Dimming Res" 720.0 0.0 2190.0 1.0
#pragma parameter intensityR "Red Dimming Intensity" 1.2 0.0 2.0 0.1
#pragma parameter intensityG "Green Dimming Intensity" 0.9 0.0 2.0 0.1
#pragma parameter intensityB "Blue Dimming Intensity" 0.9 0.0 2.0 0.1
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

uniform vec2 OrigTextureSize;
uniform vec2 RAViewportSize;
uniform vec2 TextureSize;
uniform float intensityB;
uniform float intensityG;
uniform float intensityR;
uniform float viewSizeHD;
struct UBO
{
    vec4 FinalViewportSize;
};



struct Push
{
    float viewSizeHD;
    float intensityR;
    float intensityG;
    float intensityB;
    vec4 SourceSize;
    vec4 OriginalSize;
};



uniform sampler2D Texture;

varying vec2 RA_VARYING_0;

void main()
{
    vec2 _59 = floor((((vec4(TextureSize, 1.0 / TextureSize)).xy / (vec4(OrigTextureSize, 1.0 / OrigTextureSize)).xy) * RA_VARYING_0) * (vec4(RAViewportSize, 1.0 / RAViewportSize)).xy) + vec2(0.5);
    float _72 = fract(((_59.y * 3.0) + _59.x) * 0.16666699945926666259765625);
    vec4 _344;
    if (_72 < 0.333000004291534423828125)
    {
        vec4 _285 = vec4(0.0);
        _285.x = (intensityR);
        _285.y = (intensityG);
        _285.z = (intensityB);
        _344 = _285;
    }
    else
    {
        vec4 _345;
        if (_72 < 0.66600000858306884765625)
        {
            vec4 _291 = vec4(0.0);
            _291.x = (intensityB);
            _291.y = (intensityR);
            _291.z = (intensityG);
            _345 = _291;
        }
        else
        {
            vec4 _297 = vec4(0.0);
            _297.x = (intensityG);
            _297.y = (intensityB);
            _297.z = (intensityR);
            _345 = _297;
        }
        _344 = _345;
    }
    vec2 _129 = RA_VARYING_0 * (vec4(TextureSize, 1.0 / TextureSize)).xy;
    vec2 _132 = floor(_129);
    float _142 = clamp(abs(sin(_129.y * 3.141590118408203125)) + 0.25, 0.5, 1.0);
    vec4 _304 = _344;
    _304.w = _142;
    vec2 _149 = fract(_129) + vec2(-0.5);
    vec2 _158 = ((-RA_VARYING_0) * (vec4(TextureSize, 1.0 / TextureSize)).xy) + (_132 + vec2(0.5));
    float _170 = clamp(1.5 - abs(_158.x * 0.5), 0.800000011920928955078125, 1.25);
    float _179 = clamp(1.25 - abs(_158.y * 2.0), 0.5, 1.0);
    float _202 = _142 * _170;
    _304.w = _202;
    vec4 _227 = texture2D(Texture, ((((_149 - clamp(_149, vec2(-0.25), vec2(0.25))) * 2.0) + _132) + vec2(0.5)) / (vec4(TextureSize, 1.0 / TextureSize)).xy);
    vec3 _355 = vec3(_202 * _227.x, vec2(_170 * _179, _170 * ((_142 + _179) * 0.5)) * _227.yz);
    vec3 _277;
    if ((vec4(RAViewportSize, 1.0 / RAViewportSize)).y >= (viewSizeHD))
    {
        _277 = _304.xyz * _355;
    }
    else
    {
        _277 = _355;
    }
    gl_FragData[0] = vec4(_277, _227.w);
}


#endif
