// Generated from crt/shaders/crtsim/screen.slang. See slang/upstream for licence/source.
#version 120
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

uniform float CRTMask_Scale;
uniform vec2 TextureSize;
uniform float Tuning_Mask_Brightness;
uniform float Tuning_Mask_Opacity;
uniform float Tuning_Satur;
struct UBO
{
    vec4 SourceSize;
};



struct Push
{
    float CRTMask_Scale;
    float Tuning_Satur;
    float Tuning_Mask_Brightness;
    float Tuning_Mask_Opacity;
};



uniform sampler2D shadowMaskSampler;
uniform sampler2D Texture;

varying vec2 RA_VARYING_0;

void main()
{
    vec4 _155 = vec4(texture2D(Texture, RA_VARYING_0).xyz * mix(vec3(1.0), texture2D(shadowMaskSampler, fract((RA_VARYING_0 * (vec4(TextureSize, 1.0 / TextureSize)).xy) / vec2((CRTMask_Scale)))).xyz + vec3((Tuning_Mask_Brightness)), vec3((Tuning_Mask_Opacity))), 1.0);
    float _157 = dot(vec4(0.2989999949932098388671875, 0.58700001239776611328125, 0.114000000059604644775390625, 0.0), _155);
    gl_FragData[0] = mix(vec4(_157, _157, _157, 1.0), _155, vec4((Tuning_Satur)));
}


#endif
