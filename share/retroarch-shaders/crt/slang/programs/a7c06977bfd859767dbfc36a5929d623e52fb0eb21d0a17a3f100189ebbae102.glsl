// Generated from crt/shaders/crt-beans/transform.slang. See slang/upstream for licence/source.
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

uniform vec2 TextureSize;
uniform float YIQ;
struct Push
{
    vec4 SourceSize;
    float YIQ;
};



uniform sampler2D Texture;

in vec2 RA_VARYING_0;
out vec4 FragColor;

void main()
{
    vec3 _72 = texelFetch(Texture, ivec2(int(floor(RA_VARYING_0.x * (vec4(TextureSize, 1.0 / TextureSize)).x)), int(floor(RA_VARYING_0.y * (vec4(TextureSize, 1.0 / TextureSize)).y))), 0).xyz;
    vec3 _103;
    if ((YIQ) > 0.5)
    {
        _103 = mat3(vec3(0.300000011920928955078125, 0.59899997711181640625, 0.212999999523162841796875), vec3(0.589999973773956298828125, -0.27730000019073486328125, -0.5250999927520751953125), vec3(0.10999999940395355224609375, -0.3217000067234039306640625, 0.312099993228912353515625)) * _72;
    }
    else
    {
        _103 = _72;
    }
    FragColor.x = _103.x;
    FragColor.y = _103.y;
    FragColor.z = _103.z;
}


#endif
