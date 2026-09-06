// Generated from crt/shaders/crtsim/present.slang. See slang/upstream for licence/source.
#version 120
#pragma parameter BloomPower "Bloom Power" 1.0 0.0 10.0 0.1
#pragma parameter BloomScalar "Bloom Scalar" 0.1 0.0 1.0 0.05
#pragma parameter Tuning_Overscan "Overscan" 0.95 0.0 1.0 0.05
#pragma parameter Tuning_Barrel "Barrel Distortion" 0.25 0.0 1.0 0.05
#pragma parameter mask_toggle "Mask Toggle" 1.0 0.0 1.0 1.0
#pragma parameter CRTMask_Scale "CRT Mask Scale" 1.0 0.0 10.0 0.5
#pragma parameter Tuning_Satur "Saturation" 1.0 0.0 1.0 0.05
#pragma parameter Tuning_Mask_Brightness "Mask Brightness" 0.5 0.0 1.0 0.05
#pragma parameter Tuning_Mask_Opacity "Mask Opacity" 0.3 0.0 1.0 0.05
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

uniform float BloomPower;
uniform float BloomScalar;
uniform float CRTMask_Scale;
uniform vec2 TextureSize;
uniform float Tuning_Barrel;
uniform float Tuning_Mask_Brightness;
uniform float Tuning_Mask_Opacity;
uniform float Tuning_Overscan;
uniform float Tuning_Satur;
uniform float mask_toggle;
struct UBO
{
    vec4 SourceSize;
    float BloomPower;
    float BloomScalar;
    float Tuning_Overscan;
    float Tuning_Barrel;
    float mask_toggle;
};



struct Push
{
    float CRTMask_Scale;
    float Tuning_Satur;
    float Tuning_Mask_Brightness;
    float Tuning_Mask_Opacity;
};



uniform sampler2D shadowMaskSampler;
uniform sampler2D Pass2Texture;
uniform sampler2D Texture;

varying vec2 RA_VARYING_0;

void main()
{
    vec2 _145 = ((RA_VARYING_0 * (Tuning_Overscan)) - vec2(((Tuning_Overscan) - 1.0) * 0.5)) - vec2(0.5);
    float _149 = _145.x;
    float _155 = _145.y;
    vec2 _169 = (_145 + (_145 * ((Tuning_Barrel) * ((_149 * _149) + (_155 * _155))))) + vec2(0.5);
    bool _176 = (mask_toggle) > 0.5;
    bvec2 _180 = bvec2(_176);
    vec2 _181 = vec2(_180.x ? RA_VARYING_0.x : _169.x, _180.y ? RA_VARYING_0.y : _169.y);
    vec4 _295;
    if (_176)
    {
        vec4 _263 = vec4(texture2D(Pass2Texture, _181).xyz * mix(vec3(1.0), texture2D(shadowMaskSampler, fract((_181 * (vec4(TextureSize, 1.0 / TextureSize)).xy) / vec2((CRTMask_Scale)))).xyz + vec3((Tuning_Mask_Brightness)), vec3((Tuning_Mask_Opacity))), 1.0);
        float _265 = dot(vec4(0.2989999949932098388671875, 0.58700001239776611328125, 0.114000000059604644775390625, 0.0), _263);
        _295 = mix(vec4(_265, _265, _265, 1.0), _263, vec4((Tuning_Satur)));
    }
    else
    {
        _295 = texture2D(Pass2Texture, _181);
    }
    vec4 _202 = texture2D(Texture, _181);
    float _283 = dot(_202, vec4(0.2989999949932098388671875, 0.58700001239776611328125, 0.114000000059604644775390625, 0.0));
    gl_FragData[0] = _295 + (((_202 / vec4(_283)) * pow(_283, (BloomPower))) * (BloomScalar));
}


#endif
