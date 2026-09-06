// Generated from crt/shaders/crt-yah/crt-yah-single-pass.slang. See slang/upstream for licence/source.
#version 130
#pragma parameter GLOBAL_MASTER "· ¹Global > Master  (0-None .. 1-Full / 2-More)" 1.0 0.0 2.0 0.05
#pragma parameter SCREEN_ORIENTATION "·  Screen > Orientation  (0-Auto, 1-Horizontal, 2-Vertical)" 0.0 0.0 2.0 1.0
#pragma parameter SCREEN_RESOLUTION_SCALE "  ⁵Screen > Resolution  (1-Native, 2~240p/↑, 4~480p/↑)" 2.0 1.0 5.0 1.0
#pragma parameter SCREEN_FREQUENCY "  ⁴Screen > Frequency  (30Hz .. 60Hz)" 60.0 30.0 60.0 10.0
#pragma parameter SCREEN_INTERLACED "   Screen > Interlaced²⁴  (0-None .. 1-Full)" 0.0 0.0 1.0 0.05
#pragma parameter COLOR_PROFILE "·  Color > Profile¹  (-NTSC .. +Trinitron)" 0.0 -1.0 1.0 0.1
#pragma parameter COLOR_TEMPERATUE "   Color > Temperature¹  (-Colder .. +Warmer)" 0.0 -1.0 1.0 0.1
#pragma parameter COLOR_SATURATION "   Color > Saturation¹  (0-Low .. 2-High)" 1.1 0.0 2.0 0.05
#pragma parameter COLOR_CONTRAST "   Color > Contrast¹  (-Lower .. +Higher)" 0.1 -1.0 2.0 0.05
#pragma parameter COLOR_BRIGHTNESS "   Color > Brightness¹  (-Darken .. +Lighten)" 0.15 -1.0 4.0 0.05
#pragma parameter COLOR_OVERFLOW "·  Brightness > Glow¹  (0-None .. 1-Full / 2-More)" 1.0 0.0 2.0 0.25
#pragma parameter CRT_NOISE_AMOUNT "   Brightness > Noise¹³  (0-None .. 1-Full)" 0.25 0.0 1.0 0.05
#pragma parameter COLOR_BRIGHTNESS_FLICKER "   Brightness > Flicker⁴  (0-None .. 1-Full)" 0.25 0.0 1.0 0.05
#pragma parameter COLOR_BLACK_LIGHT "  ³Brightness > Black Lighten  (0-None .. 1-Full / 2-More)" 0.5 0.0 2.0 0.1
#pragma parameter COLOR_COMPENSATION "  ²Brightness > Compensation  (0-Off, 1-On)" 1.0 0.0 1.0 1.0
#pragma parameter SCANLINES_STRENGTH "·  Scanlines > Strength¹²³  (0-None .. 1-Full)" 0.5 0.0 1.0 0.05
#pragma parameter SCANLINES_COLOR_BURN "   Scanlines > Burn¹  (0-None .. 1-Full)" 1.0 0.0 1.0 0.25
#pragma parameter SCANLINES_OFFSET "   Scanlines > Offset⁴  (-Static / 0-None / +Jitter)" 0.25 -1.0 1.0 0.05
#pragma parameter SCREEN_SCALE "   Scanlines > Scale⁵  (-Down / 0-Auto / +Up)" 0.0 -4.0 2.0 0.05
#pragma parameter BEAM_WIDTH_MIN "·  Beam > Min. Width  (less-Shrink .. 1-Full)" 0.25 -1.0 1.0 0.05
#pragma parameter BEAM_WIDTH_MAX "   Beam > Max. Width  (1-Full .. more-Grow)" 1.25 1.0 2.0 0.05
#pragma parameter BEAM_SHAPE "   Beam > Shape²  (0-Sharp .. 1-Smooth)" 0.75 0.0 1.0 0.25
#pragma parameter BEAM_FILTER "   Beam > Filter  (-Blocky .. +Blurry)" -0.25 -1.0 1.0 0.05
#pragma parameter ANTI_RINGING "   Beam > Anti-Ringing  (0-None .. 1-Full)" 1.0 0.0 1.0 0.1
#pragma parameter MASK_INTENSITY "·  Mask > Intensity¹²³  (0-None .. 1-Full)" 0.5 0.0 1.0 0.05
#pragma parameter MASK_BLEND "   Mask > Blend²  (0-Multiplicative .. 1-Additive)" 0.25 0.0 1.0 0.05
#pragma parameter MASK_TYPE "   Mask > Type²  (1-Aperture, 2-Slot, 3-Shadow)" 1.0 1.0 3.0 1.0
#pragma parameter MASK_SCALE "   Mask > Scale⁵  (-1 Down / 0-Auto / +½ Up)" 0.0 -2.0 4.0 0.5
#pragma parameter MASK_SUBPIXEL "·  Sub-Pixel > Pattern²  (1-Mono, 2-MG/x, 4-RGB/x)" 4.0 1.0 5.0 1.0
#pragma parameter MASK_SUBPIXEL_ORDER "   Sub-Pixel > Colors  (1-RGB/←, 3-RBG/←, 5-BRG/←)" 1.0 1.0 6.0 1.0
#pragma parameter MASK_COLOR_BLEED "   Sub-Pixel > Bleed¹²  (0-None .. 1-Full)" 0.5 0.0 1.0 0.25
#pragma parameter MASK_SUBPIXEL_SHAPE "   Sub-Pixel > Shape²  (0-Sharp .. 1-Smooth)  [4K]" 1.0 0.0 1.0 0.25
#pragma parameter DECONVERGE_LINEAR "·  Deconverge > Linear Amount¹  (0-None .. -/+ 1-Full)" 0.25 -2.0 2.0 0.05
#pragma parameter DECONVERGE_RADIAL "   Deconverge > Radial Amount¹  (0-None .. -/+ 1-Full)" 0.0 -2.0 2.0 0.05
#pragma parameter PHOSPHOR_AMOUNT "·  Phosphor > Amount¹  (0-None .. 1-Full)" 0.25 0.0 1.0 0.05
#pragma parameter PHOSPHOR_DECAY "   Phosphor > Decay  (0-Slow .. 1-Fast)" 0.5 0.0 1.0 0.05
#pragma parameter HALATION_INTENSITY "·  Halation > Intensity¹  (0-None .. 1-Full / 2-More)" 0.25 0.0 2.0 0.05
#pragma parameter HALATION_DIFFUSION "   Halation > Diffusion  (0-Low .. 1-Medium .. 2-High)" 0.5 0.0 2.0 0.05
#pragma parameter HALATION_WEIGHT "   Halation > Weight  (0-None .. 1-Luma)" 0.75 0.0 1.0 0.05
#pragma parameter HALATION_INFLUENCE "   Halation > Influence  (-Mask / 0-Both / +Scanlines)" 0.5 -1.0 1.0 0.05
#pragma parameter NTSC_PROFILE "·  NTSC > Profile  (0-Off, 1-Separate Y/C, 2-Composite, 3-RF)" 0.0 0.0 3.0 0.1
#pragma parameter NTSC_PHASE "   NTSC > Chroma Phase  (0-Auto, 1-Two, 2-Three)" 1.0 0.0 2.0 1.0
#pragma parameter NTSC_SAMPLES "   NTSC > Chroma Samples  (¼-Min .. 1-Max)" 1.0 0.25 1.0 0.25
#pragma parameter NTSC_SHIFT "   NTSC > Chroma Shift  (-left .. +right)" 0.0 -1.0 1.0 0.1
#pragma parameter NTSC_JITTER "   NTSC > Offset⁴  (-Merge / 0-Static / +Jitter)" 1.0 -1.0 1.0 0.1
#pragma parameter NTSC_SCALE "   NTSC > Scale⁵  (-Down / 0-Auto / +Up)" 0.0 -0.5 0.5 0.05
#pragma parameter CRT_CURVATURE_AMOUNT "·  CRT > Curvature¹  (0-None .. 1-Full)" 0.0 0.0 1.0 0.05
#pragma parameter CRT_VIGNETTE_AMOUNT "   CRT > Vignette¹  (0-None .. 1-Full)" 0.0 0.0 1.0 0.05
#pragma parameter CRT_CORNER_RAIDUS "   CRT > Corner Roundness¹  (0-None .. 25%)" 0.0 0.0 0.25 0.01
#pragma parameter CRT_CORNER_SMOOTHNESS "   CRT > Edge Smoothness  (0-None .. 1-Full)" 0.0 0.0 1.0 0.05
#pragma parameter SHARP_AMOUNT "·  Sharpen > Amount¹  (0-None .. 1-Full)" 0.0 0.0 2.0 0.25
#pragma parameter INFO1 " ¹ Reduces marked effects" 0.0 0.0 0.0 0.0
#pragma parameter INFO2 " ² Compensates brightness changes of marked effects" 0.0 0.0 0.0 0.0
#pragma parameter INFO3 " ³ Increases black level of marked effects" 0.0 0.0 0.0 0.0
#pragma parameter INFO4 " ⁴ Affects frequency of marked effects" 0.0 0.0 0.0 0.0
#pragma parameter INFO5 " ⁵ Affects scaling of marked effects" 0.0 0.0 0.0 0.0
#ifdef VERTEX

uniform float ANTI_RINGING;
uniform float BEAM_FILTER;
uniform float BEAM_SHAPE;
uniform float BEAM_WIDTH_MAX;
uniform float BEAM_WIDTH_MIN;
uniform float COLOR_BLACK_LIGHT;
uniform int FrameCount;
uniform float GLOBAL_MASTER;
uniform float MASK_BLEND;
uniform float MASK_COLOR_BLEED;
uniform float MASK_INTENSITY;
uniform float MASK_SCALE;
uniform float MASK_SUBPIXEL;
uniform float MASK_SUBPIXEL_ORDER;
uniform float MASK_SUBPIXEL_SHAPE;
uniform float MASK_TYPE;
uniform mat4 MVPMatrix;
uniform vec2 OrigTextureSize;
uniform vec2 OutputSize;
uniform vec2 RAViewportSize;
uniform float SCANLINES_STRENGTH;
uniform float SCREEN_FREQUENCY;
uniform float SCREEN_INTERLACED;
uniform float SCREEN_ORIENTATION;
uniform float SCREEN_RESOLUTION_SCALE;
uniform float SCREEN_SCALE;
const float _275[17] = float[](0.111111111938953399658203125, 0.125, 0.14285714924335479736328125, 0.16666667163372039794921875, 0.20000000298023223876953125, 0.25, 0.3333333432674407958984375, 0.5, 1.0, 2.0, 3.0, 4.0, 5.0, 6.0, 7.0, 8.0, 9.0);

struct UBO
{
    mat4 MVP;
    vec4 OriginalSize;
    vec4 OutputSize;
    vec4 FinalViewportSize;
    uint FrameCount;
    float GLOBAL_MASTER;
    float SCREEN_RESOLUTION_SCALE;
    float SCREEN_ORIENTATION;
    float SCREEN_SCALE;
    float SCREEN_FREQUENCY;
    float SCREEN_INTERLACED;
};



struct Push
{
    float COLOR_BLACK_LIGHT;
    float SCANLINES_STRENGTH;
    float BEAM_WIDTH_MIN;
    float BEAM_WIDTH_MAX;
    float BEAM_SHAPE;
    float BEAM_FILTER;
    float ANTI_RINGING;
    float MASK_INTENSITY;
    float MASK_BLEND;
    float MASK_SCALE;
    float MASK_TYPE;
    float MASK_SUBPIXEL;
    float MASK_SUBPIXEL_ORDER;
    float MASK_SUBPIXEL_SHAPE;
    float MASK_COLOR_BLEED;
};



flat out int RA_VARYING_3;
out vec3 RA_VARYING_4;
out vec4 RA_VARYING_6;
in vec4 VertexCoord;
out vec2 RA_VARYING_0;
in vec2 TexCoord;
out vec2 RA_VARYING_1;
out vec4 RA_VARYING_7;
out mat4 RA_VARYING_11;
out float RA_VARYING_5;
out float RA_VARYING_8;
out vec2 RA_VARYING_9;
flat out uvec2 RA_VARYING_10;
out vec2 RA_VARYING_2;

void main()
{
    gl_Position = (MVPMatrix) * VertexCoord;
    RA_VARYING_0 = TexCoord;
    RA_VARYING_1 = TexCoord;
    int _1334 = int((SCREEN_ORIENTATION));
    int _3458;
    if (_1334 > 0)
    {
        _3458 = _1334 - 1;
    }
    else
    {
        _3458 = int((vec4(OutputSize, 1.0 / OutputSize)).y > (vec4(OutputSize, 1.0 / OutputSize)).x);
    }
    RA_VARYING_3 = _3458;
    int _1447 = int((SCREEN_RESOLUTION_SCALE));
    bool _1448 = _1447 > 1;
    float _3506;
    if (_1448)
    {
        bool _1551 = RA_VARYING_3 > 0;
        float _3477;
        if (_1551)
        {
            _3477 = (vec4(OrigTextureSize, 1.0 / OrigTextureSize)).x / (vec4(OrigTextureSize, 1.0 / OrigTextureSize)).y;
        }
        else
        {
            _3477 = (vec4(OrigTextureSize, 1.0 / OrigTextureSize)).y / (vec4(OrigTextureSize, 1.0 / OrigTextureSize)).x;
        }
        float _1509 = float((vec4(OrigTextureSize, 1.0 / OrigTextureSize)).y > (vec4(OrigTextureSize, 1.0 / OrigTextureSize)).x);
        float _1514 = (_1447 > 3) ? 480.0 : 240.0;
        float _3479;
        if (_1551)
        {
            _3479 = mix(_1514 * _3477, _1514, _1509);
        }
        else
        {
            _3479 = mix(_1514, _1514 * _3477, _1509);
        }
        float _3481;
        if (_1551)
        {
            _3481 = (vec4(OrigTextureSize, 1.0 / OrigTextureSize)).x / _3479;
        }
        else
        {
            _3481 = (vec4(OrigTextureSize, 1.0 / OrigTextureSize)).y / _3479;
        }
        float _3485;
        if (_1551)
        {
            _3485 = (vec4(RAViewportSize, 1.0 / RAViewportSize)).x / (vec4(OrigTextureSize, 1.0 / OrigTextureSize)).x;
        }
        else
        {
            _3485 = (vec4(RAViewportSize, 1.0 / RAViewportSize)).y / (vec4(OrigTextureSize, 1.0 / OrigTextureSize)).y;
        }
        bool _1582 = _3481 < 1.0;
        bool _1597;
        if (_1582)
        {
            bool _1587 = _1447 == 3;
            bool _1595;
            if (!_1587)
            {
                _1595 = _1447 == 5;
            }
            else
            {
                _1595 = _1587;
            }
            _1597 = _1595;
        }
        else
        {
            _1597 = _1582;
        }
        float _3493;
        if (_1597)
        {
            _3493 = round(2.0 / _3481) * 0.5;
        }
        else
        {
            _3493 = round(_3481);
        }
        float _1621 = (((_1597 ? (-1.0) : 1.0) * (max(1.0, _3493) - 1.0)) + 8.0) - (SCREEN_SCALE);
        float _1658;
        float _3503;
        float _3498 = _1621;
        float _3504 = _3481;
        for (;;)
        {
            if (_3498 < 17.0)
            {
                _1658 = mix(_275[int(clamp(floor(_3498), 0.0, 16.0))], _275[int(clamp(ceil(_3498), 0.0, 16.0))], fract(_3498));
                if ((_3485 * _1658) >= 3.0)
                {
                    _3503 = _1658;
                    break;
                }
                _3498 += 0.0500000007450580596923828125;
                _3504 = _1658;
                continue;
            }
            else
            {
                _3503 = _3504;
                break;
            }
        }
        _3506 = _3503;
    }
    else
    {
        float _3459;
        if (RA_VARYING_3 > 0)
        {
            _3459 = (vec4(RAViewportSize, 1.0 / RAViewportSize)).x / (vec4(OrigTextureSize, 1.0 / OrigTextureSize)).x;
        }
        else
        {
            _3459 = (vec4(RAViewportSize, 1.0 / RAViewportSize)).y / (vec4(OrigTextureSize, 1.0 / OrigTextureSize)).y;
        }
        float _1735 = (max(1.0, round(1.0)) + 7.0) - (SCREEN_SCALE);
        float _1772;
        float _3474;
        float _3469 = _1735;
        float _3475 = 1.0;
        for (;;)
        {
            if (_3469 < 17.0)
            {
                _1772 = mix(_275[int(clamp(floor(_3469), 0.0, 16.0))], _275[int(clamp(ceil(_3469), 0.0, 16.0))], fract(_3469));
                if ((_3459 * _1772) >= 3.0)
                {
                    _3474 = _1772;
                    break;
                }
                _3469 += 0.0500000007450580596923828125;
                _3475 = _1772;
                continue;
            }
            else
            {
                _3474 = _3475;
                break;
            }
        }
        _3506 = _3474;
    }
    RA_VARYING_4.x = _3506;
    float _3554;
    if (_1448)
    {
        bool _1888 = RA_VARYING_3 > 0;
        float _3525;
        if (_1888)
        {
            _3525 = (vec4(OrigTextureSize, 1.0 / OrigTextureSize)).x / (vec4(OrigTextureSize, 1.0 / OrigTextureSize)).y;
        }
        else
        {
            _3525 = (vec4(OrigTextureSize, 1.0 / OrigTextureSize)).y / (vec4(OrigTextureSize, 1.0 / OrigTextureSize)).x;
        }
        float _1846 = float((vec4(OrigTextureSize, 1.0 / OrigTextureSize)).y > (vec4(OrigTextureSize, 1.0 / OrigTextureSize)).x);
        float _1851 = (_1447 > 3) ? 480.0 : 240.0;
        float _3527;
        if (_1888)
        {
            _3527 = mix(_1851 * _3525, _1851, _1846);
        }
        else
        {
            _3527 = mix(_1851, _1851 * _3525, _1846);
        }
        float _3529;
        if (_1888)
        {
            _3529 = (vec4(OrigTextureSize, 1.0 / OrigTextureSize)).x / _3527;
        }
        else
        {
            _3529 = (vec4(OrigTextureSize, 1.0 / OrigTextureSize)).y / _3527;
        }
        float _3533;
        if (_1888)
        {
            _3533 = (vec4(RAViewportSize, 1.0 / RAViewportSize)).x / (vec4(OrigTextureSize, 1.0 / OrigTextureSize)).x;
        }
        else
        {
            _3533 = (vec4(RAViewportSize, 1.0 / RAViewportSize)).y / (vec4(OrigTextureSize, 1.0 / OrigTextureSize)).y;
        }
        bool _1919 = _3529 < 1.0;
        bool _1934;
        if (_1919)
        {
            bool _1924 = _1447 == 3;
            bool _1932;
            if (!_1924)
            {
                _1932 = _1447 == 5;
            }
            else
            {
                _1932 = _1924;
            }
            _1934 = _1932;
        }
        else
        {
            _1934 = _1919;
        }
        float _3541;
        if (_1934)
        {
            _3541 = round(2.0 / _3529) * 0.5;
        }
        else
        {
            _3541 = round(_3529);
        }
        float _1955 = ((_1934 ? (-1.0) : 1.0) * (max(1.0, _3541) - 1.0)) + 8.0;
        float _1995;
        float _3551;
        float _3546 = _1955;
        float _3552 = _3529;
        for (;;)
        {
            if (_3546 < 17.0)
            {
                _1995 = mix(_275[int(clamp(floor(_3546), 0.0, 16.0))], _275[int(clamp(ceil(_3546), 0.0, 16.0))], fract(_3546));
                if ((_3533 * _1995) >= 3.0)
                {
                    _3551 = _1995;
                    break;
                }
                _3546 += 0.0500000007450580596923828125;
                _3552 = _1995;
                continue;
            }
            else
            {
                _3551 = _3552;
                break;
            }
        }
        _3554 = _3551;
    }
    else
    {
        float _3507;
        if (RA_VARYING_3 > 0)
        {
            _3507 = (vec4(RAViewportSize, 1.0 / RAViewportSize)).x / (vec4(OrigTextureSize, 1.0 / OrigTextureSize)).x;
        }
        else
        {
            _3507 = (vec4(RAViewportSize, 1.0 / RAViewportSize)).y / (vec4(OrigTextureSize, 1.0 / OrigTextureSize)).y;
        }
        float _2069 = max(1.0, round(1.0)) + 7.0;
        float _2109;
        float _3522;
        float _3517 = _2069;
        float _3523 = 1.0;
        for (;;)
        {
            if (_3517 < 17.0)
            {
                _2109 = mix(_275[int(clamp(floor(_3517), 0.0, 16.0))], _275[int(clamp(ceil(_3517), 0.0, 16.0))], fract(_3517));
                if ((_3507 * _2109) >= 3.0)
                {
                    _3522 = _2109;
                    break;
                }
                _3517 += 0.0500000007450580596923828125;
                _3523 = _2109;
                continue;
            }
            else
            {
                _3522 = _3523;
                break;
            }
        }
        _3554 = _3522;
    }
    RA_VARYING_4.y = _3554;
    bool _2200 = RA_VARYING_3 > 0;
    float _3555;
    if (_2200)
    {
        _3555 = (vec4(OrigTextureSize, 1.0 / OrigTextureSize)).x / (vec4(OrigTextureSize, 1.0 / OrigTextureSize)).y;
    }
    else
    {
        _3555 = (vec4(OrigTextureSize, 1.0 / OrigTextureSize)).y / (vec4(OrigTextureSize, 1.0 / OrigTextureSize)).x;
    }
    float _2158 = float((vec4(OrigTextureSize, 1.0 / OrigTextureSize)).y > (vec4(OrigTextureSize, 1.0 / OrigTextureSize)).x);
    float _2163 = (_1447 > 3) ? 480.0 : 240.0;
    float _3557;
    if (_2200)
    {
        _3557 = mix(_2163 * _3555, _2163, _2158);
    }
    else
    {
        _3557 = mix(_2163, _2163 * _3555, _2158);
    }
    float _3559;
    if (_2200)
    {
        _3559 = (vec4(OrigTextureSize, 1.0 / OrigTextureSize)).x / _3557;
    }
    else
    {
        _3559 = (vec4(OrigTextureSize, 1.0 / OrigTextureSize)).y / _3557;
    }
    float _3563;
    if (_2200)
    {
        _3563 = (vec4(RAViewportSize, 1.0 / RAViewportSize)).x / (vec4(OrigTextureSize, 1.0 / OrigTextureSize)).x;
    }
    else
    {
        _3563 = (vec4(RAViewportSize, 1.0 / RAViewportSize)).y / (vec4(OrigTextureSize, 1.0 / OrigTextureSize)).y;
    }
    bool _2231 = _3559 < 1.0;
    bool _2246;
    if (_2231)
    {
        bool _2236 = _1447 == 3;
        bool _2244;
        if (!_2236)
        {
            _2244 = _1447 == 5;
        }
        else
        {
            _2244 = _2236;
        }
        _2246 = _2244;
    }
    else
    {
        _2246 = _2231;
    }
    float _3571;
    if (_2246)
    {
        _3571 = round(2.0 / _3559) * 0.5;
    }
    else
    {
        _3571 = round(_3559);
    }
    float _2267 = ((_2246 ? (-1.0) : 1.0) * (max(1.0, _3571) - 1.0)) + 8.0;
    float _2307;
    float _3581;
    float _3576 = _2267;
    float _3582 = _3559;
    for (;;)
    {
        if (_3576 < 17.0)
        {
            _2307 = mix(_275[int(clamp(floor(_3576), 0.0, 16.0))], _275[int(clamp(ceil(_3576), 0.0, 16.0))], fract(_3576));
            if ((_3563 * _2307) >= 3.0)
            {
                _3581 = _2307;
                break;
            }
            _3576 += 0.0500000007450580596923828125;
            _3582 = _2307;
            continue;
        }
        else
        {
            _3581 = _3582;
            break;
        }
    }
    RA_VARYING_4.z = _3581;
    float _3584;
    if ((vec4(OrigTextureSize, 1.0 / OrigTextureSize)).x < (vec4(OrigTextureSize, 1.0 / OrigTextureSize)).y)
    {
        _3584 = (vec4(RAViewportSize, 1.0 / RAViewportSize)).x / (vec4(OrigTextureSize, 1.0 / OrigTextureSize)).x;
    }
    else
    {
        _3584 = (vec4(RAViewportSize, 1.0 / RAViewportSize)).y / (vec4(OrigTextureSize, 1.0 / OrigTextureSize)).y;
    }
    float _2367 = max(1.0, floor((_3584 / ((min((vec4(OrigTextureSize, 1.0 / OrigTextureSize)).x, (vec4(OrigTextureSize, 1.0 / OrigTextureSize)).y) < 180.0) ? 3.0 : 4.0)) * RA_VARYING_4.z));
    float _3585;
    if ((MASK_SCALE) < 0.0)
    {
        _3585 = ceil(_2367 / (floor(abs((MASK_SCALE))) + 1.0));
    }
    else
    {
        _3585 = floor(_2367 * ((MASK_SCALE) + 1.0));
    }
    float _2384 = max(1.0, _3585);
    int _2387 = int((MASK_TYPE));
    bool _2388 = _2387 == 1;
    float _3588;
    if (_2388)
    {
        _3588 = clamp((_2384 - 2.0) * 0.75, 0.0, 1.0);
    }
    else
    {
        float _3587;
        if (_2387 == 2)
        {
            _3587 = clamp((_2384 - 2.0) * 0.75, 0.0, 1.0);
        }
        else
        {
            float _3586;
            if (_2387 == 3)
            {
                _3586 = clamp((_2384 - 2.0) * 0.25, 0.0, 1.0);
            }
            else
            {
                _3586 = 0.0;
            }
            _3587 = _3586;
        }
        _3588 = _3587;
    }
    int _2427 = int((MASK_SUBPIXEL));
    RA_VARYING_6 = vec4(float(_2427), _2384, _3588 * (MASK_SUBPIXEL_SHAPE), float(int((MASK_SUBPIXEL_ORDER))));
    float _2569 = clamp((SCANLINES_STRENGTH) * (GLOBAL_MASTER), 0.0, 1.0);
    float _2482 = (1.0 - (BEAM_SHAPE)) * _2569;
    float _2500 = 1.0 - (_2482 * 0.5);
    float _2522 = min(1.0, _2569 * 2.0);
    float _2678 = (0.5 * _2569) / (1.5 - abs(_2569));
    RA_VARYING_7 = vec4(_2500 / (1.0 + (((min(1.0, 1.0 - (BEAM_WIDTH_MIN)) - min(0.0, (BEAM_WIDTH_MIN) * 2.0)) * _2522) * 0.5)), _2500 * (1.0 + ((max(0.0, (BEAM_WIDTH_MAX) - 1.0) * _2522) * 0.5)), 2.0 + ((2.0 * _2482) * (_2482 + 1.0)), (_2678 * 1.25) + 0.25);
    float _2818 = clamp((BEAM_FILTER) * (GLOBAL_MASTER), -1.0, 1.0);
    float _2692 = _2818 * 2.0;
    float _2693 = _2692 + 1.0;
    float _3592;
    float _3596;
    if (_2693 <= 0.0)
    {
        _3596 = 0.0;
        _3592 = _2693;
    }
    else
    {
        float _3593;
        float _3597;
        if (_2693 <= 1.0)
        {
            _3597 = _2693 * 0.5;
            _3593 = 0.0;
        }
        else
        {
            float _3594;
            float _3598;
            if (_2693 <= 2.0)
            {
                _3598 = 0.5 - (_2818 * 0.3333333432674407958984375);
                _3594 = _2818 * 0.666666686534881591796875;
            }
            else
            {
                float _3595;
                float _3599;
                if (_2693 <= 3.0)
                {
                    float _2720 = _2692 + (-1.0);
                    _3599 = 0.3333333432674407958984375 - (_2720 * 0.16666667163372039794921875);
                    _3595 = 0.3333333432674407958984375 + (_2720 * 0.3333333432674407958984375);
                }
                else
                {
                    _3599 = 0.0;
                    _3595 = 0.0;
                }
                _3598 = _3599;
                _3594 = _3595;
            }
            _3597 = _3598;
            _3593 = _3594;
        }
        _3596 = _3597;
        _3592 = _3593;
    }
    float _2734 = 6.0 * _3596;
    float _2738 = 3.0 * _3592;
    float _2740 = 12.0 * _3596;
    float _2750 = _3592 * 0.16666667163372039794921875;
    float _2756 = (12.0 - (9.0 * _3592)) - _2734;
    RA_VARYING_11 = mat4(vec4(((-_3592) - _2734) * 0.16666667163372039794921875, (_2738 + _2740) * 0.16666667163372039794921875, (((-3.0) * _3592) - _2734) * 0.16666667163372039794921875, _2750), vec4(_2756 * 0.16666667163372039794921875, (((-18.0) + (12.0 * _3592)) + _2734) * 0.16666667163372039794921875, 0.0, (6.0 - (2.0 * _3592)) * 0.16666667163372039794921875), vec4(_2756 * (-0.16666667163372039794921875), ((18.0 - (15.0 * _3592)) - _2740) * 0.16666667163372039794921875, (_2738 + _2734) * 0.16666667163372039794921875, _2750), vec4((_3592 + _2734) * 0.16666667163372039794921875, -_3596, 0.0, 0.0));
    float _3175 = clamp((MASK_INTENSITY) * (GLOBAL_MASTER), 0.0, 1.0);
    float _2904 = _3175 * _3175;
    float _3209 = (0.5 * _2904) / (1.5 - abs(_2904));
    float _2908 = 1.0 - (MASK_BLEND);
    float _2912 = _2908 * _2908;
    float _2913 = 1.0 - _2912;
    float _3604;
    if (_2427 == 1)
    {
        _3604 = mix(-1.0, -0.25, _2913);
    }
    else
    {
        float _3603;
        if (_2427 == 2)
        {
            _3603 = mix(-1.0, -0.25, _2913);
        }
        else
        {
            float _3602;
            if (_2427 == 3)
            {
                _3602 = mix(-0.4000000059604644775390625, -0.100000001490116119384765625, _2913);
            }
            else
            {
                float _3601;
                if (_2427 == 4)
                {
                    _3601 = 0.0;
                }
                else
                {
                    float _3600;
                    if (_2427 == 5)
                    {
                        _3600 = mix(0.60000002384185791015625, 0.1500000059604644775390625, _2913);
                    }
                    else
                    {
                        _3600 = 0.0;
                    }
                    _3601 = _3600;
                }
                _3602 = _3601;
            }
            _3603 = _3602;
        }
        _3604 = _3603;
    }
    float _3612;
    if (_2388)
    {
        _3612 = mix(0.20000000298023223876953125, 0.0500000007450580596923828125, _2913);
    }
    else
    {
        float _3611;
        if (_2387 == 2)
        {
            _3611 = mix(0.800000011920928955078125, 0.20000000298023223876953125, _2913);
        }
        else
        {
            float _3610;
            if (_2387 == 3)
            {
                _3610 = mix(0.20000000298023223876953125, 0.0500000007450580596923828125, _2913);
            }
            else
            {
                _3610 = 0.0;
            }
            _3611 = _3610;
        }
        _3612 = _3611;
    }
    bool _3002 = int(RA_VARYING_6.y) > 2;
    float _3626;
    if (_2388 && _3002)
    {
        _3626 = mix(-0.4000000059604644775390625, -0.100000001490116119384765625, _2913);
    }
    else
    {
        float _3625;
        if ((_2387 == 2) && _3002)
        {
            _3625 = mix(-0.4000000059604644775390625, -0.100000001490116119384765625, _2913);
        }
        else
        {
            float _3624;
            if ((_2387 == 3) && _3002)
            {
                _3624 = mix(0.4000000059604644775390625, 0.100000001490116119384765625, _2913);
            }
            else
            {
                _3624 = 0.0;
            }
            _3625 = _3624;
        }
        _3626 = _3625;
    }
    float _3643;
    if (_2388)
    {
        _3643 = mix(1.60000002384185791015625, 0.4000000059604644775390625, _2913);
    }
    else
    {
        float _3642;
        if (_2387 == 2)
        {
            _3642 = mix(1.60000002384185791015625, 0.4000000059604644775390625, _2913);
        }
        else
        {
            float _3641;
            if (_2387 == 3)
            {
                _3641 = mix(2.400000095367431640625, 0.60000002384185791015625, _2913);
            }
            else
            {
                _3641 = 1.0;
            }
            _3642 = _3641;
        }
        _3643 = _3642;
    }
    RA_VARYING_5 = ((((((((((0.5 * (SCREEN_INTERLACED)) / (1.5 - abs((SCREEN_INTERLACED)))) * 2.0) + (_2678 * mix(0.5, 1.0, (BEAM_SHAPE)))) - ((_2678 * 0.25) * (1.0 - abs(((BEAM_SHAPE) * 2.0) - 1.0)))) + ((1.5 * _2912) * _3209)) + (_3604 * _3209)) + (_3612 * _3209)) + (_3626 * _3209)) + ((RA_VARYING_6.z * _3643) * _3209)) + ((clamp((MASK_COLOR_BLEED) * (GLOBAL_MASTER), 0.0, 1.0) * mix(-0.5, -0.25, _2913)) * _3209);
    RA_VARYING_8 = (1.0 - smoothstep(1.5, 2.0, _2818 + 1.0)) * (ANTI_RINGING);
    float _3278 = 0.00390625 * max(_2569, _3175);
    RA_VARYING_9 = vec2(_3278 * (COLOR_BLACK_LIGHT), (0.015625 - _3278) * (COLOR_BLACK_LIGHT));
    int _3330 = int((SCREEN_FREQUENCY));
    int _3696;
    if (_3330 == 50)
    {
        _3696 = 48;
    }
    else
    {
        _3696 = _3330;
    }
    float _3361 = (round(4.0) * 0.25) * float((uint(FrameCount)));
    RA_VARYING_10 = uvec2(uint(mod(float(uint(round(_3361 * (float(_3696) * 0.01666666753590106964111328125)))), 2.0)), uint(mod(float(uint(round(_3361 * 0.20000000298023223876953125))), 20.0)));
    vec2 _3702;
    if (RA_VARYING_3 == 0)
    {
        _3702 = vec2(1.0, RA_VARYING_4.x);
    }
    else
    {
        _3702 = vec2(RA_VARYING_4.x, 1.0);
    }
    RA_VARYING_2 = (vec4(OrigTextureSize, 1.0 / OrigTextureSize)).xy / _3702;
    bool _1390 = RA_VARYING_4.y > 1.0;
    bool _1397;
    if (!_1390)
    {
        _1397 = RA_VARYING_4.z > 1.0;
    }
    else
    {
        _1397 = _1390;
    }
    if (_1397)
    {
        bvec2 _3713 = bvec2(RA_VARYING_3 == 0);
        RA_VARYING_1 += (vec2(_3713.x ? vec2(0.5, 0.0).x : vec2(0.0, 0.5).x, _3713.y ? vec2(0.5, 0.0).y : vec2(0.0, 0.5).y) / (vec4(OrigTextureSize, 1.0 / OrigTextureSize)).xy);
    }
}


#endif
#ifdef FRAGMENT

uniform float COLOR_BRIGHTNESS;
uniform float COLOR_COMPENSATION;
uniform float COLOR_CONTRAST;
uniform float COLOR_OVERFLOW;
uniform float COLOR_SATURATION;
uniform float COLOR_TEMPERATUE;
uniform float CRT_CORNER_RAIDUS;
uniform float CRT_CORNER_SMOOTHNESS;
uniform float CRT_CURVATURE_AMOUNT;
uniform float CRT_NOISE_AMOUNT;
uniform float CRT_VIGNETTE_AMOUNT;
uniform float GLOBAL_MASTER;
uniform float MASK_BLEND;
uniform float MASK_COLOR_BLEED;
uniform float MASK_INTENSITY;
uniform float MASK_TYPE;
uniform vec2 OutputSize;
uniform float SCANLINES_COLOR_BURN;
uniform float SCANLINES_STRENGTH;
uniform float SCREEN_INTERLACED;
const vec3 _1099[30] = vec3[](vec3(1.0), vec3(1.0), vec3(1.0), vec3(1.0), vec3(1.0), vec3(1.0), vec3(0.0, 1.0, 0.0), vec3(1.0, 0.0, 1.0), vec3(0.0, 0.0, 1.0), vec3(1.0, 1.0, 0.0), vec3(0.0, 1.0, 1.0), vec3(1.0, 0.0, 0.0), vec3(0.0, 1.0, 0.0), vec3(1.0, 0.0, 1.0), vec3(0.0, 0.0, 1.0), vec3(1.0, 1.0, 0.0), vec3(0.0, 1.0, 1.0), vec3(1.0, 0.0, 0.0), vec3(1.0, 0.0, 0.0), vec3(0.0, 0.0, 1.0), vec3(1.0, 0.0, 0.0), vec3(0.0, 1.0, 0.0), vec3(0.0, 0.0, 1.0), vec3(0.0, 1.0, 0.0), vec3(1.0, 0.0, 0.0), vec3(0.0, 0.0, 1.0), vec3(1.0, 0.0, 0.0), vec3(0.0, 1.0, 0.0), vec3(0.0, 0.0, 1.0), vec3(0.0, 1.0, 0.0));
const vec3 _1102[30] = vec3[](vec3(0.0), vec3(0.0), vec3(0.0), vec3(0.0), vec3(0.0), vec3(0.0), vec3(1.0, 0.0, 1.0), vec3(0.0, 1.0, 0.0), vec3(1.0, 1.0, 0.0), vec3(0.0, 0.0, 1.0), vec3(1.0, 0.0, 0.0), vec3(0.0, 1.0, 1.0), vec3(1.0, 0.0, 1.0), vec3(0.0, 1.0, 0.0), vec3(1.0, 1.0, 0.0), vec3(0.0, 0.0, 1.0), vec3(1.0, 0.0, 0.0), vec3(0.0, 1.0, 1.0), vec3(0.0, 1.0, 0.0), vec3(0.0, 1.0, 0.0), vec3(0.0, 0.0, 1.0), vec3(0.0, 0.0, 1.0), vec3(1.0, 0.0, 0.0), vec3(1.0, 0.0, 0.0), vec3(0.0, 1.0, 0.0), vec3(0.0, 1.0, 0.0), vec3(0.0, 0.0, 1.0), vec3(0.0, 0.0, 1.0), vec3(1.0, 0.0, 0.0), vec3(1.0, 0.0, 0.0));
const vec3 _1105[30] = vec3[](vec3(0.5), vec3(0.5), vec3(0.5), vec3(0.5), vec3(0.5), vec3(0.5), vec3(0.5), vec3(0.5), vec3(0.5), vec3(0.5), vec3(0.5), vec3(0.5), vec3(0.0), vec3(0.0), vec3(0.0), vec3(0.0), vec3(0.0), vec3(0.0), vec3(0.0, 0.0, 1.0), vec3(1.0, 0.0, 0.0), vec3(0.0, 1.0, 0.0), vec3(1.0, 0.0, 0.0), vec3(0.0, 1.0, 0.0), vec3(0.0, 0.0, 1.0), vec3(0.0, 0.0, 1.0), vec3(1.0, 0.0, 0.0), vec3(0.0, 1.0, 0.0), vec3(1.0, 0.0, 0.0), vec3(0.0, 1.0, 0.0), vec3(0.0, 0.0, 1.0));
const vec3 _1107[30] = vec3[](vec3(0.5), vec3(0.5), vec3(0.5), vec3(0.5), vec3(0.5), vec3(0.5), vec3(0.5), vec3(0.5), vec3(0.5), vec3(0.5), vec3(0.5), vec3(0.5), vec3(0.5), vec3(0.5), vec3(0.5), vec3(0.5), vec3(0.5), vec3(0.5), vec3(0.5), vec3(0.5), vec3(0.5), vec3(0.5), vec3(0.5), vec3(0.5), vec3(0.0), vec3(0.0), vec3(0.0), vec3(0.0), vec3(0.0), vec3(0.0));
const int _1111[5] = int[](2, 2, 3, 3, 4);

struct UBO
{
    vec4 OutputSize;
    float GLOBAL_MASTER;
    float SCREEN_INTERLACED;
};



struct Push
{
    float COLOR_BRIGHTNESS;
    float COLOR_COMPENSATION;
    float COLOR_SATURATION;
    float COLOR_OVERFLOW;
    float COLOR_CONTRAST;
    float COLOR_TEMPERATUE;
    float SCANLINES_STRENGTH;
    float SCANLINES_COLOR_BURN;
    float MASK_INTENSITY;
    float MASK_BLEND;
    float MASK_TYPE;
    float MASK_COLOR_BLEED;
    float CRT_CURVATURE_AMOUNT;
    float CRT_VIGNETTE_AMOUNT;
    float CRT_NOISE_AMOUNT;
    float CRT_CORNER_RAIDUS;
    float CRT_CORNER_SMOOTHNESS;
};



uniform sampler2D Texture;

in float RA_VARYING_5;
in vec2 RA_VARYING_9;
flat in int RA_VARYING_3;
in vec4 RA_VARYING_7;
in float RA_VARYING_8;
in vec3 RA_VARYING_4;
flat in uvec2 RA_VARYING_10;
in mat4 RA_VARYING_11;
in vec4 RA_VARYING_6;
in vec2 RA_VARYING_2;
in vec2 RA_VARYING_0;
in vec2 RA_VARYING_1;
out vec4 FragColor;

void main()
{
    bool _2400;
    float _2450;
    float _2456;
    vec2 _6156;
    do
    {
        _2450 = (GLOBAL_MASTER);
        _2456 = clamp((CRT_CURVATURE_AMOUNT) * _2450, 0.0, 1.0);
        _2400 = _2456 == 0.0;
        if (_2400)
        {
            _6156 = RA_VARYING_0;
            break;
        }
        vec2 _2409 = RA_VARYING_0 - vec2(0.5);
        float _2411 = _2409.x;
        float _2416 = _2409.y;
        float _2420 = (_2411 * _2411) + (_2416 * _2416);
        _6156 = (_2409 * ((1.0 + (_2420 * (_2456 * sqrt(_2420)))) / (1.0 + (_2456 * 0.125)))) + vec2(0.5);
        break;
    } while(false);
    vec2 _2493 = _6156 * RA_VARYING_2;
    vec2 _2497 = floor((vec4(OutputSize, 1.0 / OutputSize)).xy / RA_VARYING_2);
    vec2 _2500 = vec2(0.5) / _2497;
    vec2 _2506 = fract(_2493) - vec2(0.5);
    vec2 _2521 = floor(_2493) + (((_2506 - clamp(_2506, _2500 - vec2(0.5), vec2(0.5) - _2500)) * _2497) + vec2(0.5));
    vec2 _6158;
    do
    {
        if (_2400)
        {
            _6158 = RA_VARYING_1;
            break;
        }
        vec2 _2553 = RA_VARYING_1 - vec2(0.5);
        float _2555 = _2553.x;
        float _2560 = _2553.y;
        float _2564 = (_2555 * _2555) + (_2560 * _2560);
        _6158 = (_2553 * ((1.0 + (_2564 * (_2456 * sqrt(_2564)))) / (1.0 + (_2456 * 0.125)))) + vec2(0.5);
        break;
    } while(false);
    vec4 _2683 = texture(Texture, _2521 / RA_VARYING_2);
    float _2719 = _2683.x;
    float _6161;
    if (_2719 <= 0.0404481999576091766357421875)
    {
        _6161 = _2719 * 0.077399380505084991455078125;
    }
    else
    {
        _6161 = pow((_2719 + 0.054999999701976776123046875) * 0.947867333889007568359375, 2.400000095367431640625);
    }
    float _2723 = _2683.y;
    float _6163;
    if (_2723 <= 0.0404481999576091766357421875)
    {
        _6163 = _2723 * 0.077399380505084991455078125;
    }
    else
    {
        _6163 = pow((_2723 + 0.054999999701976776123046875) * 0.947867333889007568359375, 2.400000095367431640625);
    }
    float _2727 = _2683.z;
    float _6165;
    if (_2727 <= 0.0404481999576091766357421875)
    {
        _6165 = _2727 * 0.077399380505084991455078125;
    }
    else
    {
        _6165 = pow((_2727 + 0.054999999701976776123046875) * 0.947867333889007568359375, 2.400000095367431640625);
    }
    bool _2787;
    vec3 _2730 = vec3(_6161, _6163, _6165);
    vec3 _6169;
    do
    {
        _2787 = RA_VARYING_9.x == 0.0;
        if (_2787)
        {
            _6169 = _2730;
            break;
        }
        float _2796 = RA_VARYING_9.x * (1.0 - dot(_2730, vec3(0.2125999927520751953125, 0.715200006961822509765625, 0.072200000286102294921875)));
        _6169 = (_2730 + vec3(_2796)) / vec3(1.0 + _2796);
        break;
    } while(false);
    float _2822;
    bool _2823;
    vec3 _6178;
    do
    {
        _2822 = (SCREEN_INTERLACED);
        _2823 = _2822 == 0.0;
        if (_2823)
        {
            _6178 = _6169;
            break;
        }
        bool _2838 = (int(floor(mix(_2521, _2521.yx, vec2(float(RA_VARYING_3))).y)) % 2) != 0;
        _6178 = mix(_6169, mix(mix(vec3(0.0), _6169, vec3(float(_2838))), mix(vec3(0.0), _6169, vec3(float(!_2838))), vec3(float(RA_VARYING_10.x))), vec3(_2822));
        break;
    } while(false);
    vec2 _2987 = ((_6158 + vec2(9.9999997473787516355514526367188e-06)) * RA_VARYING_2) + vec2(0.5);
    vec2 _2996 = vec2(1.0, RA_VARYING_4.x);
    bool _2999 = RA_VARYING_4.x > 1.0;
    vec2 _6190;
    if (_2999)
    {
        _6190 = vec2(-0.5, 0.5) / _2996;
    }
    else
    {
        _6190 = vec2(-0.5, 0.5);
    }
    bool _3011 = RA_VARYING_4.y > 1.0;
    bool _3018;
    if (!_3011)
    {
        _3018 = RA_VARYING_4.z > 1.0;
    }
    else
    {
        _3018 = _3011;
    }
    vec2 _6194;
    if (_3018)
    {
        _6194 = _6190 + vec2(-0.5, 0.0);
    }
    else
    {
        _6194 = _6190;
    }
    vec2 _6199;
    if (_2999)
    {
        _6199 = _6194 + ((vec2(0.0, 0.5) / _2996) * (RA_VARYING_4.x - 1.0));
    }
    else
    {
        _6199 = _6194;
    }
    vec2 _3051 = vec2(float(RA_VARYING_3));
    vec2 _3043 = (floor(_2987) + mix(_6199, _6199.yx, _3051)) / RA_VARYING_2;
    vec2 _2924 = vec2(1.0) / RA_VARYING_2;
    vec2 _3058 = vec2(_2924.x, 0.0);
    vec2 _3062 = vec2(0.0, _2924.y);
    vec2 _3066 = mix(_3058, _3062, _3051);
    vec2 _3080 = mix(_3062, _3058, _3051);
    vec2 _3089 = mix(_2987, _2987.yx, _3051);
    vec2 _2931 = fract(_3089);
    float _2933 = _2931.x;
    float _2936 = _2933 * _2933;
    vec4 _2949 = vec4(_2936 * _2933, _2936, _2933, 1.0) * RA_VARYING_11;
    vec2 _3106 = _3043 - _3066;
    vec4 _3109 = texture(Texture, _3106 - _3080);
    float _3216 = _3109.x;
    float _6212;
    if (_3216 <= 0.0404481999576091766357421875)
    {
        _6212 = _3216 * 0.077399380505084991455078125;
    }
    else
    {
        _6212 = pow((_3216 + 0.054999999701976776123046875) * 0.947867333889007568359375, 2.400000095367431640625);
    }
    float _3220 = _3109.y;
    float _6214;
    if (_3220 <= 0.0404481999576091766357421875)
    {
        _6214 = _3220 * 0.077399380505084991455078125;
    }
    else
    {
        _6214 = pow((_3220 + 0.054999999701976776123046875) * 0.947867333889007568359375, 2.400000095367431640625);
    }
    float _3224 = _3109.z;
    float _6216;
    if (_3224 <= 0.0404481999576091766357421875)
    {
        _6216 = _3224 * 0.077399380505084991455078125;
    }
    else
    {
        _6216 = pow((_3224 + 0.054999999701976776123046875) * 0.947867333889007568359375, 2.400000095367431640625);
    }
    vec3 _3227 = vec3(_6212, _6214, _6216);
    vec3 _6220;
    do
    {
        if (_2787)
        {
            _6220 = _3227;
            break;
        }
        float _3293 = RA_VARYING_9.x * (1.0 - dot(_3227, vec3(0.2125999927520751953125, 0.715200006961822509765625, 0.072200000286102294921875)));
        _6220 = (_3227 + vec3(_3293)) / vec3(1.0 + _3293);
        break;
    } while(false);
    vec4 _3116 = texture(Texture, _3043 - _3080);
    float _3337 = _3116.x;
    float _6229;
    if (_3337 <= 0.0404481999576091766357421875)
    {
        _6229 = _3337 * 0.077399380505084991455078125;
    }
    else
    {
        _6229 = pow((_3337 + 0.054999999701976776123046875) * 0.947867333889007568359375, 2.400000095367431640625);
    }
    float _3341 = _3116.y;
    float _6231;
    if (_3341 <= 0.0404481999576091766357421875)
    {
        _6231 = _3341 * 0.077399380505084991455078125;
    }
    else
    {
        _6231 = pow((_3341 + 0.054999999701976776123046875) * 0.947867333889007568359375, 2.400000095367431640625);
    }
    float _3345 = _3116.z;
    float _6233;
    if (_3345 <= 0.0404481999576091766357421875)
    {
        _6233 = _3345 * 0.077399380505084991455078125;
    }
    else
    {
        _6233 = pow((_3345 + 0.054999999701976776123046875) * 0.947867333889007568359375, 2.400000095367431640625);
    }
    vec3 _3348 = vec3(_6229, _6231, _6233);
    vec3 _6237;
    do
    {
        if (_2787)
        {
            _6237 = _3348;
            break;
        }
        float _3414 = RA_VARYING_9.x * (1.0 - dot(_3348, vec3(0.2125999927520751953125, 0.715200006961822509765625, 0.072200000286102294921875)));
        _6237 = (_3348 + vec3(_3414)) / vec3(1.0 + _3414);
        break;
    } while(false);
    vec2 _3122 = _3043 + _3066;
    vec4 _3125 = texture(Texture, _3122 - _3080);
    float _3458 = _3125.x;
    float _6254;
    if (_3458 <= 0.0404481999576091766357421875)
    {
        _6254 = _3458 * 0.077399380505084991455078125;
    }
    else
    {
        _6254 = pow((_3458 + 0.054999999701976776123046875) * 0.947867333889007568359375, 2.400000095367431640625);
    }
    float _3462 = _3125.y;
    float _6256;
    if (_3462 <= 0.0404481999576091766357421875)
    {
        _6256 = _3462 * 0.077399380505084991455078125;
    }
    else
    {
        _6256 = pow((_3462 + 0.054999999701976776123046875) * 0.947867333889007568359375, 2.400000095367431640625);
    }
    float _3466 = _3125.z;
    float _6258;
    if (_3466 <= 0.0404481999576091766357421875)
    {
        _6258 = _3466 * 0.077399380505084991455078125;
    }
    else
    {
        _6258 = pow((_3466 + 0.054999999701976776123046875) * 0.947867333889007568359375, 2.400000095367431640625);
    }
    vec3 _3469 = vec3(_6254, _6256, _6258);
    vec3 _6262;
    do
    {
        if (_2787)
        {
            _6262 = _3469;
            break;
        }
        float _3535 = RA_VARYING_9.x * (1.0 - dot(_3469, vec3(0.2125999927520751953125, 0.715200006961822509765625, 0.072200000286102294921875)));
        _6262 = (_3469 + vec3(_3535)) / vec3(1.0 + _3535);
        break;
    } while(false);
    vec2 _3132 = _3043 + (_3066 * 2.0);
    vec4 _3135 = texture(Texture, _3132 - _3080);
    float _3579 = _3135.x;
    float _6275;
    if (_3579 <= 0.0404481999576091766357421875)
    {
        _6275 = _3579 * 0.077399380505084991455078125;
    }
    else
    {
        _6275 = pow((_3579 + 0.054999999701976776123046875) * 0.947867333889007568359375, 2.400000095367431640625);
    }
    float _3583 = _3135.y;
    float _6277;
    if (_3583 <= 0.0404481999576091766357421875)
    {
        _6277 = _3583 * 0.077399380505084991455078125;
    }
    else
    {
        _6277 = pow((_3583 + 0.054999999701976776123046875) * 0.947867333889007568359375, 2.400000095367431640625);
    }
    float _3587 = _3135.z;
    float _6279;
    if (_3587 <= 0.0404481999576091766357421875)
    {
        _6279 = _3587 * 0.077399380505084991455078125;
    }
    else
    {
        _6279 = pow((_3587 + 0.054999999701976776123046875) * 0.947867333889007568359375, 2.400000095367431640625);
    }
    vec3 _3590 = vec3(_6275, _6277, _6279);
    vec3 _6283;
    do
    {
        if (_2787)
        {
            _6283 = _3590;
            break;
        }
        float _3656 = RA_VARYING_9.x * (1.0 - dot(_3590, vec3(0.2125999927520751953125, 0.715200006961822509765625, 0.072200000286102294921875)));
        _6283 = (_3590 + vec3(_3656)) / vec3(1.0 + _3656);
        break;
    } while(false);
    vec3 _3160 = mat4x3(_6220, _6237, _6262, _6283) * _2949;
    vec3 _3185 = mix(_3160, clamp(_3160, min(_6237, _6262), max(_6237, _6262)), step(vec3(0.0), abs(_6220 - _6237) * abs(_6262 - _6283)) * RA_VARYING_8);
    vec4 _3690 = texture(Texture, _3106);
    float _3797 = _3690.x;
    float _6372;
    if (_3797 <= 0.0404481999576091766357421875)
    {
        _6372 = _3797 * 0.077399380505084991455078125;
    }
    else
    {
        _6372 = pow((_3797 + 0.054999999701976776123046875) * 0.947867333889007568359375, 2.400000095367431640625);
    }
    float _3801 = _3690.y;
    float _6374;
    if (_3801 <= 0.0404481999576091766357421875)
    {
        _6374 = _3801 * 0.077399380505084991455078125;
    }
    else
    {
        _6374 = pow((_3801 + 0.054999999701976776123046875) * 0.947867333889007568359375, 2.400000095367431640625);
    }
    float _3805 = _3690.z;
    float _6376;
    if (_3805 <= 0.0404481999576091766357421875)
    {
        _6376 = _3805 * 0.077399380505084991455078125;
    }
    else
    {
        _6376 = pow((_3805 + 0.054999999701976776123046875) * 0.947867333889007568359375, 2.400000095367431640625);
    }
    vec3 _3808 = vec3(_6372, _6374, _6376);
    vec3 _6380;
    do
    {
        if (_2787)
        {
            _6380 = _3808;
            break;
        }
        float _3874 = RA_VARYING_9.x * (1.0 - dot(_3808, vec3(0.2125999927520751953125, 0.715200006961822509765625, 0.072200000286102294921875)));
        _6380 = (_3808 + vec3(_3874)) / vec3(1.0 + _3874);
        break;
    } while(false);
    vec4 _3697 = texture(Texture, _3043);
    float _3918 = _3697.x;
    float _6389;
    if (_3918 <= 0.0404481999576091766357421875)
    {
        _6389 = _3918 * 0.077399380505084991455078125;
    }
    else
    {
        _6389 = pow((_3918 + 0.054999999701976776123046875) * 0.947867333889007568359375, 2.400000095367431640625);
    }
    float _3922 = _3697.y;
    float _6391;
    if (_3922 <= 0.0404481999576091766357421875)
    {
        _6391 = _3922 * 0.077399380505084991455078125;
    }
    else
    {
        _6391 = pow((_3922 + 0.054999999701976776123046875) * 0.947867333889007568359375, 2.400000095367431640625);
    }
    float _3926 = _3697.z;
    float _6393;
    if (_3926 <= 0.0404481999576091766357421875)
    {
        _6393 = _3926 * 0.077399380505084991455078125;
    }
    else
    {
        _6393 = pow((_3926 + 0.054999999701976776123046875) * 0.947867333889007568359375, 2.400000095367431640625);
    }
    vec3 _3929 = vec3(_6389, _6391, _6393);
    vec3 _6397;
    do
    {
        if (_2787)
        {
            _6397 = _3929;
            break;
        }
        float _3995 = RA_VARYING_9.x * (1.0 - dot(_3929, vec3(0.2125999927520751953125, 0.715200006961822509765625, 0.072200000286102294921875)));
        _6397 = (_3929 + vec3(_3995)) / vec3(1.0 + _3995);
        break;
    } while(false);
    vec4 _3706 = texture(Texture, _3122);
    float _4039 = _3706.x;
    float _6414;
    if (_4039 <= 0.0404481999576091766357421875)
    {
        _6414 = _4039 * 0.077399380505084991455078125;
    }
    else
    {
        _6414 = pow((_4039 + 0.054999999701976776123046875) * 0.947867333889007568359375, 2.400000095367431640625);
    }
    float _4043 = _3706.y;
    float _6416;
    if (_4043 <= 0.0404481999576091766357421875)
    {
        _6416 = _4043 * 0.077399380505084991455078125;
    }
    else
    {
        _6416 = pow((_4043 + 0.054999999701976776123046875) * 0.947867333889007568359375, 2.400000095367431640625);
    }
    float _4047 = _3706.z;
    float _6418;
    if (_4047 <= 0.0404481999576091766357421875)
    {
        _6418 = _4047 * 0.077399380505084991455078125;
    }
    else
    {
        _6418 = pow((_4047 + 0.054999999701976776123046875) * 0.947867333889007568359375, 2.400000095367431640625);
    }
    vec3 _4050 = vec3(_6414, _6416, _6418);
    vec3 _6422;
    do
    {
        if (_2787)
        {
            _6422 = _4050;
            break;
        }
        float _4116 = RA_VARYING_9.x * (1.0 - dot(_4050, vec3(0.2125999927520751953125, 0.715200006961822509765625, 0.072200000286102294921875)));
        _6422 = (_4050 + vec3(_4116)) / vec3(1.0 + _4116);
        break;
    } while(false);
    vec4 _3716 = texture(Texture, _3132);
    float _4160 = _3716.x;
    float _6435;
    if (_4160 <= 0.0404481999576091766357421875)
    {
        _6435 = _4160 * 0.077399380505084991455078125;
    }
    else
    {
        _6435 = pow((_4160 + 0.054999999701976776123046875) * 0.947867333889007568359375, 2.400000095367431640625);
    }
    float _4164 = _3716.y;
    float _6437;
    if (_4164 <= 0.0404481999576091766357421875)
    {
        _6437 = _4164 * 0.077399380505084991455078125;
    }
    else
    {
        _6437 = pow((_4164 + 0.054999999701976776123046875) * 0.947867333889007568359375, 2.400000095367431640625);
    }
    float _4168 = _3716.z;
    float _6439;
    if (_4168 <= 0.0404481999576091766357421875)
    {
        _6439 = _4168 * 0.077399380505084991455078125;
    }
    else
    {
        _6439 = pow((_4168 + 0.054999999701976776123046875) * 0.947867333889007568359375, 2.400000095367431640625);
    }
    vec3 _4171 = vec3(_6435, _6437, _6439);
    vec3 _6443;
    do
    {
        if (_2787)
        {
            _6443 = _4171;
            break;
        }
        float _4237 = RA_VARYING_9.x * (1.0 - dot(_4171, vec3(0.2125999927520751953125, 0.715200006961822509765625, 0.072200000286102294921875)));
        _6443 = (_4171 + vec3(_4237)) / vec3(1.0 + _4237);
        break;
    } while(false);
    vec3 _3741 = mat4x3(_6380, _6397, _6422, _6443) * _2949;
    vec3 _3766 = mix(_3741, clamp(_3741, min(_6397, _6422), max(_6397, _6422)), step(vec3(0.0), abs(_6380 - _6397) * abs(_6422 - _6443)) * RA_VARYING_8);
    float _2961 = _2931.y;
    vec3 _4281 = vec3(clamp((SCANLINES_COLOR_BURN) * _2450, 0.0, 1.0));
    vec3 _4284 = vec3(RA_VARYING_7.x);
    vec3 _4286 = vec3(RA_VARYING_7.y);
    float _4296 = (-10.0) * RA_VARYING_7.w;
    vec3 _4299 = vec3(RA_VARYING_7.z);
    vec3 _2974 = _3185 * exp(pow(vec3(_2961) / (mix(_4284, _4286, mix(vec3(max(max(_3185.x, _3185.y), _3185.z)), _3185, _4281)) + vec3(9.9999997473787516355514526367188e-06)), _4299) * _4296);
    vec3 _2977 = _3766 * exp(pow(vec3(1.0 - _2961) / (mix(_4284, _4286, mix(vec3(max(max(_3766.x, _3766.y), _3766.z)), _3766, _4281)) + vec3(9.9999997473787516355514526367188e-06)), _4299) * _4296);
    vec3 _6538;
    do
    {
        if (_2823)
        {
            _6538 = _2974 + _2977;
            break;
        }
        bool _4497 = (int(floor(_3089.y)) % 2) != 0;
        _6538 = mix(_2974 + _2977, mix(mix(_2974, _2977, vec3(float(_4497))), mix(_2974, _2977, vec3(float(!_4497))), vec3(float(RA_VARYING_10.x))), vec3(_2822));
        break;
    } while(false);
    vec3 _6578;
    do
    {
        float _4581 = clamp((SCANLINES_STRENGTH) * _2450, 0.0, 1.0);
        if (_4581 == 0.0)
        {
            _6578 = _6178;
            break;
        }
        _6578 = mix(_6178, _6538, vec3(min(1.0, _4581 * 8.0)));
        break;
    } while(false);
    float _4600 = dot(_6578, vec3(0.2125999927520751953125, 0.715200006961822509765625, 0.072200000286102294921875));
    vec3 _6745;
    do
    {
        int _4633 = int((MASK_TYPE));
        bool _4634 = _4633 == 0;
        if (_4634)
        {
            _6745 = _6578;
            break;
        }
        vec2 _4726 = RA_VARYING_0 * (vec4(OutputSize, 1.0 / OutputSize)).xy;
        int _4736 = int(RA_VARYING_6.y);
        vec3 _6714;
        do
        {
            if (_4634)
            {
                _6714 = vec3(1.0);
                break;
            }
            int _4821 = int(RA_VARYING_6.x) - 1;
            float _4825 = float(_4736);
            vec2 _4828 = mix(_4726, _4726.yx, _3051) / vec2(_4825);
            bool _4830 = _4633 == 1;
            bool _4832 = _4633 == 2;
            vec2 _7072;
            if (_4830 || _4832)
            {
                float _4841 = floor(0.5 * _4825) / _4825;
                vec2 _7073;
                if (_4821 == 2)
                {
                    _7073 = _4828 + (vec2(_4841 * floor(_4828.x / (3.0 - _4841)), 0.0) * float(_4736 > 1));
                }
                else
                {
                    vec2 _7074;
                    if (_4821 == 4)
                    {
                        _7074 = _4828 + (vec2(_4841 * floor(_4828.x / (4.0 - _4841)), 0.0) * float(_4736 > 1));
                    }
                    else
                    {
                        _7074 = _4828;
                    }
                    _7073 = _7074;
                }
                _7072 = _7073;
            }
            else
            {
                _7072 = _4828;
            }
            vec2 _6675;
            vec2 _6681;
            vec2 _7076;
            if (_4830)
            {
                _7076 = _7072;
                _6681 = vec2(1.0);
                _6675 = vec2(1.0, 8640.0);
            }
            else
            {
                vec2 _6676;
                vec2 _6682;
                vec2 _7077;
                if (_4832)
                {
                    bool _4882 = _4736 == 1;
                    float _4883 = _4882 ? 4.0 : 3.0;
                    float _6634;
                    if (_4882)
                    {
                        _6634 = 0.5;
                    }
                    else
                    {
                        _6634 = (_4736 == 2) ? 0.25 : 0.16666667163372039794921875;
                    }
                    bool _4894 = _4736 == 3;
                    vec2 _7078;
                    if ((_4821 == 0) || (_4821 == 1))
                    {
                        vec2 _4907 = _7072 + vec2(0.0, (_4894 ? 1.66666662693023681640625 : 1.5) * floor(mod(_7072.x * 0.5, 2.0)));
                        float _4910 = _4907.y * 1.000010013580322265625;
                        vec2 _6996 = _4907;
                        _6996.y = _4910;
                        _6996.y = _4910 + _6634;
                        _7078 = _6996;
                    }
                    else
                    {
                        vec2 _7079;
                        if ((_4821 == 2) || (_4821 == 3))
                        {
                            vec2 _4929 = _7072 + vec2(0.0, (_4894 ? 1.66666662693023681640625 : 1.5) * floor(mod(_7072.x * 0.3333333432674407958984375, 2.0)));
                            float _4932 = _4929.y * 1.000010013580322265625;
                            vec2 _7003 = _4929;
                            _7003.y = _4932;
                            _7003.y = _4932 + _6634;
                            _7079 = _7003;
                        }
                        else
                        {
                            vec2 _7080;
                            if (_4821 == 4)
                            {
                                vec2 _4948 = _7072 + vec2(0.0, (_4894 ? 1.66666662693023681640625 : 1.5) * floor(mod(_7072.x * 0.25, 2.0)));
                                float _4951 = _4948.y * 1.000010013580322265625;
                                vec2 _7010 = _4948;
                                _7010.y = _4951;
                                _7010.y = _4951 + _6634;
                                _7080 = _7010;
                            }
                            else
                            {
                                _7080 = _7072;
                            }
                            _7079 = _7080;
                        }
                        _7078 = _7079;
                    }
                    _7077 = _7078;
                    _6682 = vec2(1.0, (_4883 - (_6634 * 2.0)) / _4883);
                    _6676 = vec2(1.0, _4883);
                }
                else
                {
                    vec2 _7081;
                    if (_4633 == 3)
                    {
                        vec2 _7082;
                        if ((_4821 == 0) || (_4821 == 1))
                        {
                            _7082 = _7072 + vec2(floor(mod(_7072.y, 2.0)), 0.0);
                        }
                        else
                        {
                            vec2 _7083;
                            if ((_4821 == 2) || (_4821 == 3))
                            {
                                vec2 _4999 = _7072 + vec2(((_4736 == 3) ? 1.66666662693023681640625 : 1.5) * floor(mod(_7072.y, 2.0)), 0.0);
                                _4999.x = _4999.x * 1.000010013580322265625;
                                _7083 = _4999;
                            }
                            else
                            {
                                vec2 _7084;
                                if (_4821 == 4)
                                {
                                    _7084 = _7072 + vec2(2.0 * floor(mod(_7072.y, 2.0)), 0.0);
                                }
                                else
                                {
                                    _7084 = _7072;
                                }
                                _7083 = _7084;
                            }
                            _7082 = _7083;
                        }
                        _7081 = _7082;
                    }
                    else
                    {
                        _7081 = _7072;
                    }
                    _7077 = _7081;
                    _6682 = vec2(1.0);
                    _6676 = vec2(1.0);
                }
                _7076 = _7077;
                _6681 = _6682;
                _6675 = _6676;
            }
            int _5021 = (_4821 * 6) + (int(RA_VARYING_6.w) - 1);
            vec3 _5153[4] = vec3[](_1099[_5021], _1102[_5021], _1105[_5021], _1107[_5021]);
            int _5176 = int(floor(mod(_7076.x, float(_1111[_4821]))));
            vec3 _6713;
            if (_4736 > 2)
            {
                vec2 _5047 = _6675 * 1024.0;
                float _5202 = max(min(_5047.x, _5047.y), 1.0);
                vec2 _5232 = (abs(((fract(_7076 / _6675) - vec2(0.5)) * (vec2(2.0) / _6681)) * _5047) - _5047) + vec2(_5202);
                float _5211 = _5202 * RA_VARYING_6.z;
                _6713 = _5153[_5176] * smoothstep(1.0, 0.0, (((length(max(_5232, vec2(0.0))) + min(max(_5232.x, _5232.y), 0.0)) - _5202) * (1.0 / _5211)) + (1.0 - sqrt(0.5 / _5211)));
            }
            else
            {
                vec2 _5254 = abs((fract(_7076 / _6675) - vec2(0.5)) * 2.0) - _6681;
                _6713 = _5153[_5176] * step(max(_5254.x, _5254.y), 0.0);
            }
            _6714 = _6713;
            break;
        } while(false);
        float _5279 = clamp((MASK_COLOR_BLEED) * _2450, 0.0, 1.0);
        vec3 _4656 = _6714 + ((max(vec3(0.0), vec3(dot(_6714, vec3(0.2125999927520751953125, 0.715200006961822509765625, 0.072200000286102294921875))) - _6714) * _5279) * _5279);
        vec3 _4665 = vec3((MASK_BLEND));
        vec3 _4666 = mix(_4656, _4656 + vec3(_4600 * 0.5), _4665);
        float _5309 = clamp((MASK_INTENSITY) * _2450, 0.0, 1.0);
        _6745 = mix(_6578, _6578 * mix(_4666, clamp(_4666 + vec3((1.0 - _5309) * 0.5), vec3(0.0), vec3(1.0)) + vec3(_5309 * 0.5), _4665), vec3(_5309));
        break;
    } while(false);
    vec3 _6826;
    do
    {
        float _5437 = clamp((CRT_NOISE_AMOUNT) * _2450, 0.0, 1.0);
        if (_5437 == 0.0)
        {
            _6826 = _6745;
            break;
        }
        vec2 _5381 = RA_VARYING_0 * (vec4(OutputSize, 1.0 / OutputSize)).xy;
        float _5385 = float(int(RA_VARYING_6.y));
        float _5455 = fract(cos(dot((floor(mix(_5381, _5381.yx, _3051) / vec2(_5385)) * _5385) * (float(RA_VARYING_10.y) + 1.0), vec2(23.1406917572021484375, 2.6651442050933837890625))) * 123456.0);
        float _5401 = 1.0 - _4600;
        _6826 = mix(_6745, (_6745 * (_5455 * 2.0)) + vec3((_5455 * _5401) * RA_VARYING_9.y), vec3((_5401 * _5437) * 0.25));
        break;
    } while(false);
    float _5498 = clamp((COLOR_OVERFLOW) * _2450, 0.0, 2.0);
    vec3 _6827;
    do
    {
        if (_5498 == 0.0)
        {
            _6827 = _6826;
            break;
        }
        vec3 _5518 = (_6826 * _6826) * (_5498 * 0.5);
        float _5530 = _5518.y;
        float _5538 = _5518.z;
        float _5546 = _5518.x;
        float _5566 = _6826.z + (0.02027775906026363372802734375 * _5546);
        vec3 _7085 = vec3((_6826.x + (0.21520321071147918701171875 * _5530)) + (0.02027775906026363372802734375 * _5538), (_6826.y + (0.21520321071147918701171875 * _5546)) + (0.15499968826770782470703125 * _5538), _5566);
        _7085.z = _5566 + (0.15499968826770782470703125 * _5530);
        _6827 = _7085;
        break;
    } while(false);
    float _6891;
    do
    {
        float _5641 = clamp((CRT_VIGNETTE_AMOUNT) * _2450, 0.0, 1.0);
        if (_5641 == 0.0)
        {
            _6891 = 1.0;
            break;
        }
        float _5675 = (1.5 * _5641) / (0.5 - (abs(_5641) * (-1.0)));
        float _5612 = _5675 * 0.25;
        _6891 = smoothstep(1.0 - _5612, 0.625 - (_5612 + (_5675 * 0.125)), length(_6156 - vec2(0.5)));
        break;
    } while(false);
    float _6894;
    do
    {
        float _5726 = clamp((CRT_CORNER_RAIDUS) * _2450, 0.0, 0.25);
        if (_5726 == 0.0)
        {
            _6894 = 1.0;
            break;
        }
        float _5767 = max(_5726 * min((vec4(OutputSize, 1.0 / OutputSize)).x, (vec4(OutputSize, 1.0 / OutputSize)).y), 1.0);
        vec2 _5797 = (abs(((_6156 - vec2(0.5)) * vec2(2.0)) * (vec4(OutputSize, 1.0 / OutputSize)).xy) - (vec4(OutputSize, 1.0 / OutputSize)).xy) + vec2(_5767);
        float _5776 = _5767 * (CRT_CORNER_SMOOTHNESS);
        _6894 = smoothstep(1.0, 0.0, (((length(max(_5797, vec2(0.0))) + min(max(_5797.x, _5797.y), 0.0)) - _5767) * (1.0 / _5776)) + (1.0 - sqrt(0.5 / _5776)));
        break;
    } while(false);
    float _6900;
    do
    {
        if (int((COLOR_COMPENSATION)) == 0)
        {
            _6900 = 0.0;
            break;
        }
        float _5885 = 1.0 - (MASK_BLEND);
        _6900 = mix(RA_VARYING_5, RA_VARYING_5 * (1.0 - _4600), 1.0 - (_5885 * _5885));
        break;
    } while(false);
    vec3 _5926 = (((_6827 * _6891) * _6894) * (1.0 + _6900)) * (1.0 + clamp((COLOR_BRIGHTNESS) * _2450, -1.0, 4.0));
    float _5941 = clamp((COLOR_CONTRAST) * _2450, -1.0, 2.0);
    vec3 _6902;
    do
    {
        if (_5941 == 0.0)
        {
            _6902 = _5926;
            break;
        }
        float _5959 = clamp(max(max(_5926.x, _5926.y), _5926.z), 0.0, 1.0);
        _6902 = _5926 * (mix(_5959, (sin(((_5959 * 2.0) - 1.0) * 1.5707962512969970703125) + 1.0) * 0.5, _5941) / (_5959 + 9.9999997473787516355514526367188e-06));
        break;
    } while(false);
    float _6008 = clamp(((COLOR_TEMPERATUE) * (-1.0)) * _2450, -1.0, 1.0);
    vec3 _6906;
    do
    {
        if (_6008 == 0.0)
        {
            _6906 = _6902;
            break;
        }
        mat3 _6903;
        if (_6008 < 0.0)
        {
            _6903 = mat3(vec3(1.04668915271759033203125, 0.056597299873828887939453125, -0.02677500061690807342529296875), vec3(-0.006178599782288074493408203125, 0.9779288768768310546875, 0.0521964989602565765380859375), vec3(-0.055953301489353179931640625, -0.0360764004290103912353515625, 0.841718494892120361328125));
        }
        else
        {
            _6903 = mat3(vec3(0.969639599323272705078125, -0.0362020991742610931396484375, 0.0240234993398189544677734375), vec3(0.001201599952764809131622314453125, 1.01146495342254638671875, -0.044550500810146331787109375), vec3(0.044388599693775177001953125, 0.02780899964272975921630859375, 1.129950046539306640625));
        }
        _6906 = mix(_6902, _6902 * _6903, vec3(abs(_6008)));
        break;
    } while(false);
    float _6051 = clamp(1.0 + (((COLOR_SATURATION) - 1.0) * _2450), 0.0, 2.0);
    vec3 _6907;
    do
    {
        if (_6051 == 1.0)
        {
            _6907 = _6906;
            break;
        }
        _6907 = mix(vec3(dot(_6906, vec3(0.2125999927520751953125, 0.715200006961822509765625, 0.072200000286102294921875))), _6906, vec3(_6051));
        break;
    } while(false);
    float _6908;
    if (_6907.x <= 0.0031306999735534191131591796875)
    {
        _6908 = _6907.x * 12.9200000762939453125;
    }
    else
    {
        _6908 = (1.05499994754791259765625 * pow(_6907.x, 0.4166666567325592041015625)) - 0.054999999701976776123046875;
    }
    float _6910;
    if (_6907.y <= 0.0031306999735534191131591796875)
    {
        _6910 = _6907.y * 12.9200000762939453125;
    }
    else
    {
        _6910 = (1.05499994754791259765625 * pow(_6907.y, 0.4166666567325592041015625)) - 0.054999999701976776123046875;
    }
    float _6912;
    if (_6907.z <= 0.0031306999735534191131591796875)
    {
        _6912 = _6907.z * 12.9200000762939453125;
    }
    else
    {
        _6912 = (1.05499994754791259765625 * pow(_6907.z, 0.4166666567325592041015625)) - 0.054999999701976776123046875;
    }
    FragColor = vec4(_6908, _6910, _6912, 1.0);
}


#endif
