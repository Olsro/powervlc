// Generated from crt/shaders/crt-beans/blur_horizontal.slang. See slang/upstream for licence/source.
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

uniform float GlowSigma;
uniform vec2 TextureSize;
struct Push
{
    vec4 SourceSize;
    float GlowSigma;
};



uniform sampler2D Texture;

in vec2 RA_VARYING_0;
out vec4 FragColor;

void main()
{
    float _23 = (GlowSigma) * (vec4(TextureSize, 1.0 / TextureSize)).y;
    int _32 = 2 * int(ceil(_23 * 1.5));
    vec2 _43 = RA_VARYING_0 * (vec4(TextureSize, 1.0 / TextureSize)).xy;
    float _82 = exp((-1.0) / ((2.0 * _23) * _23));
    float _86 = _82 * _82;
    float _90 = _82 * _86;
    vec3 _186;
    float _187;
    _187 = 1.0;
    _186 = texelFetch(Texture, ivec2(int(floor(_43.x)), int(floor(_43.y))), 0).xyz;
    int _184 = 1;
    float _188 = _82;
    float _189 = _90;
    for (; _184 <= _32; )
    {
        float _105 = _188 * _189;
        float _108 = _189 * _86;
        float _120 = _188 + _105;
        float _135 = (float(_184) + (_105 / _120)) * (vec4(TextureSize, 1.0 / TextureSize)).z;
        _189 = _108 * _86;
        _188 = _105 * _108;
        _187 = (2.0 * _120) + _187;
        _186 = (_186 + (textureLod(Texture, vec2(RA_VARYING_0.x - _135, RA_VARYING_0.y), 0.0).xyz * _120)) + (textureLod(Texture, vec2(RA_VARYING_0.x + _135, RA_VARYING_0.y), 0.0).xyz * _120);
        _184 += 2;
        continue;
    }
    vec3 _172 = _186 / vec3(_187);
    FragColor.x = _172.x;
    FragColor.y = _172.y;
    FragColor.z = _172.z;
}


#endif
