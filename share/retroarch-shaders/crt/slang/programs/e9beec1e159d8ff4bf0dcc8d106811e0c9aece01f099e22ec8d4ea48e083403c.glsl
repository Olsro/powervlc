// Generated from crt/shaders/crt-beans/scanlines_fast_horizontal.slang. See slang/upstream for licence/source.
#version 130
#pragma parameter OutputGamma "Output gamma (0: sRGB, 1: 2.2 gamma)" 1.0 0.0 1.0 1.0
#pragma parameter OverscanHorizontal "Horizontal overscan (proportion to crop)" 0.0 0.0 0.1 0.01
#pragma parameter OverscanVertical "Vertical overscan (proportion to crop)" 0.0 0.0 0.1 0.01
#pragma parameter MaxSpotSize "Maximum spot size (proportion of scanline)" 0.90 0.6 1.0 0.05
#pragma parameter MinSpotSize "Minimum spot size (proportion of maximum)" 0.4 0.3 1.0 0.1
#pragma parameter MaskType "Mask type (0: disabled, 1: subpixel, 2: dynamic)" 2.0 0.0 2.0 1.0
#pragma parameter SubpixelPattern "Monitor subpixel pattern (0: RGB, 1: BGR)" 0.0 0.0 1.0 1.0
#pragma parameter SubpixelMaskPattern "Subpixel mask width (pixels per triad)" 4.0 2.0 5.0 1.0
#pragma parameter DynamicMaskTriads "Dynamic mask phosphor triads (per screen width)" 550.0 400.0 800.0 25.0
#pragma parameter OddFieldFirst "Interlacing (0/1: bob/phase, 2: weave, 3: VGA, 4: off)" 0.0 0.0 4.0 1.0
#ifdef VERTEX

uniform mat4 MVPMatrix;
uniform float OddFieldFirst;
uniform float OverscanHorizontal;
uniform float OverscanVertical;
uniform vec2 RAViewportSize;
uniform vec2 TextureSize;
struct UBO
{
    mat4 MVP;
};



struct Push
{
    vec4 SourceSize;
    vec4 FinalViewportSize;
    float OverscanHorizontal;
    float OverscanVertical;
    float OddFieldFirst;
};



in vec4 VertexCoord;
out vec2 RA_VARYING_0;
in vec2 TexCoord;
flat out float RA_VARYING_1;

void main()
{
    gl_Position = (MVPMatrix) * VertexCoord;
    RA_VARYING_0 = TexCoord;
    RA_VARYING_1 = (((((vec4(RAViewportSize, 1.0 / RAViewportSize)).x * (vec4(RAViewportSize, 1.0 / RAViewportSize)).w) * (vec4(TextureSize, 1.0 / TextureSize)).y) * (vec4(TextureSize, 1.0 / TextureSize)).z) * (1.0 - (OverscanVertical))) / (1.0 - (OverscanHorizontal));
    bool _72 = (OddFieldFirst) <= 2.0;
    bool _79;
    if (_72)
    {
        _79 = (vec4(TextureSize, 1.0 / TextureSize)).y > 300.0;
    }
    else
    {
        _79 = _72;
    }
    if (_79)
    {
        RA_VARYING_1 = 0.5 * RA_VARYING_1;
    }
    else
    {
        bool _89 = (OddFieldFirst) == 3.0;
        bool _96;
        if (_89)
        {
            _96 = (vec4(TextureSize, 1.0 / TextureSize)).y < 350.0;
        }
        else
        {
            _96 = _89;
        }
        if (_96)
        {
            RA_VARYING_1 = 2.0 * RA_VARYING_1;
        }
    }
}


#endif
#ifdef FRAGMENT

uniform float MaxSpotSize;
uniform float MinSpotSize;
uniform vec2 TextureSize;
struct Push
{
    vec4 SourceSize;
    float MaxSpotSize;
    float MinSpotSize;
};



uniform sampler2D Texture;

in vec2 RA_VARYING_0;
flat in float RA_VARYING_1;
out vec4 FragColor;

void main()
{
    float _102 = RA_VARYING_0.x * (vec4(TextureSize, 1.0 / TextureSize)).x;
    float _107 = (MaxSpotSize) / RA_VARYING_1;
    float _112 = (vec4(TextureSize, 1.0 / TextureSize)).z * (floor(_102 - _107) + 0.5);
    float _128 = (vec4(TextureSize, 1.0 / TextureSize)).z * (floor(_102 + _107) + 1.0);
    float _136 = _102 * RA_VARYING_1;
    vec3 _264;
    _264 = vec3(0.0);
    for (float _262 = _112; _262 < _128; )
    {
        vec3 _160 = textureLod(Texture, vec2(_262, RA_VARYING_0.y), 0.0).xyz;
        float _168 = RA_VARYING_1 * (((vec4(TextureSize, 1.0 / TextureSize)).x * _262) - 0.5);
        float _215 = (MinSpotSize) * (MaxSpotSize);
        vec3 _230 = vec3(1.0) / (vec3(_215) - (sqrt(_160) * (_215 - (MaxSpotSize))));
        vec3 _249 = clamp(_230 * (_136 - _168), vec3(-1.0), vec3(1.0)) * 3.1415927410125732421875;
        vec3 _255 = clamp(_230 * (_136 - (_168 + RA_VARYING_1)), vec3(-1.0), vec3(1.0)) * 3.1415927410125732421875;
        _264 += (_160 * (((_249 + sin(_249)) - _255) - sin(_255)));
        _262 += (vec4(TextureSize, 1.0 / TextureSize)).z;
        continue;
    }
    vec3 _191 = _264 * vec3(0.15915493667125701904296875);
    FragColor.x = _191.x;
    FragColor.y = _191.y;
    FragColor.z = _191.z;
}


#endif
