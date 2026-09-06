// Generated from crt/shaders/crt-beans/filter.slang. See slang/upstream for licence/source.
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
#pragma parameter GlowSigma "Glow width (proportion of screen height)" 0.05 0.01 0.10 0.01
#pragma parameter GlowAmount "Glow amount (mix ratio)" 0.04 0.0 0.10 0.005
#pragma parameter YIQ "Composite (0: RGB, 1: YIQ/composite)" 0.0 0.0 1.0 1.0
#pragma parameter Cutoff "RGB/Y bandwidth (MHz)" 4.0 0.6 6.0 0.2
#pragma parameter ICutoff "I bandwidth (MHz)" 0.6 0.6 6.0 0.2
#pragma parameter QCutoff "Q bandwidth (MHz)" 0.6 0.6 6.0 0.2
#pragma parameter OddFieldFirst "Interlacing (0/1: bob/phase, 2: weave)" 0.0 0.0 2.0 1.0
#ifdef VERTEX

uniform mat4 MVPMatrix;
struct UBO
{
    mat4 MVP;
};



in vec4 VertexCoord;
out vec2 RA_VARYING_0;
in vec2 TexCoord;

void main()
{
    gl_Position = (MVPMatrix) * VertexCoord;
    RA_VARYING_0 = TexCoord;
}


#endif
#ifdef FRAGMENT

uniform float Cutoff;
uniform float ICutoff;
uniform float QCutoff;
uniform vec2 TextureSize;
uniform float YIQ;
struct Push
{
    vec4 SourceSize;
    float Cutoff;
    float ICutoff;
    float QCutoff;
    float YIQ;
};



uniform sampler2D Texture;

in vec2 RA_VARYING_0;
out vec4 FragColor;

void main()
{
    bool _56 = (YIQ) > 0.5;
    vec3 _279;
    if (_56)
    {
        _279 = vec3(1.0) / ((vec3((Cutoff), (ICutoff), (QCutoff)) * 53.3300018310546875) * 2.0);
    }
    else
    {
        _279 = vec3(1.0) / ((vec3((Cutoff)) * 53.3300018310546875) * 2.0);
    }
    float _98 = max(_279.x, max(_279.y, _279.z));
    vec3 _102 = vec3(1.0) / _279;
    int _118 = int(floor(RA_VARYING_0.y * (vec4(TextureSize, 1.0 / TextureSize)).y));
    int _132 = max(int(floor((vec4(TextureSize, 1.0 / TextureSize)).x * (RA_VARYING_0.x - _98))), 0);
    int _147 = min(int(floor((vec4(TextureSize, 1.0 / TextureSize)).x * (RA_VARYING_0.x + _98))), (int((vec4(TextureSize, 1.0 / TextureSize)).x) - 1));
    vec3 _167 = clamp(_102 * (RA_VARYING_0.x - (float(_132) * (vec4(TextureSize, 1.0 / TextureSize)).z)), vec3(-1.0), vec3(1.0)) * 3.1415927410125732421875;
    vec3 _282;
    vec3 _287;
    _287 = _167 + sin(_167);
    _282 = vec3(0.0);
    for (int _280 = _132; _280 <= _147; )
    {
        int _197 = _280 + 1;
        vec3 _213 = clamp(_102 * (RA_VARYING_0.x - (float(_197) * (vec4(TextureSize, 1.0 / TextureSize)).z)), vec3(-1.0), vec3(1.0)) * 3.1415927410125732421875;
        vec3 _217 = _213 + sin(_213);
        vec3 _221 = _287 - _217;
        _287 = _217;
        _282 += (texelFetch(Texture, ivec2(_280, _118), 0).xyz * _221);
        _280 = _197;
        continue;
    }
    vec3 _231 = _282 * vec3(0.15915493667125701904296875);
    vec3 _283;
    if (_56)
    {
        _283 = pow(clamp(mat3(vec3(1.0), vec3(0.946882188320159912109375, -0.2747876346111297607421875, -1.1085450649261474609375), vec3(0.623556554317474365234375, -0.635691106319427490234375, 1.70900690555572509765625)) * _231, vec3(0.0), vec3(1.0)), vec3(2.400000095367431640625));
    }
    else
    {
        _283 = pow(clamp(_231, vec3(0.0), vec3(1.0)), vec3(2.400000095367431640625));
    }
    FragColor.x = _283.x;
    FragColor.y = _283.y;
    FragColor.z = _283.z;
}


#endif
