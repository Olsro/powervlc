// Generated from crt/shaders/crt-yah/crt-yah-single-pass.slang. See slang/upstream for licence/source.
static const float _275[17] = { 0.111111111938953399658203125f, 0.125f, 0.14285714924335479736328125f, 0.16666667163372039794921875f, 0.20000000298023223876953125f, 0.25f, 0.3333333432674407958984375f, 0.5f, 1.0f, 2.0f, 3.0f, 4.0f, 5.0f, 6.0f, 7.0f, 8.0f, 9.0f };

cbuffer UBO : register(b0)
{
    row_major float4x4 global_MVP : packoffset(c0);
    float4 global_OriginalSize : packoffset(c4);
    float4 global_OutputSize : packoffset(c6);
    float4 global_FinalViewportSize : packoffset(c7);
    uint global_FrameCount : packoffset(c8);
    float global_GLOBAL_MASTER : packoffset(c8.w);
    float global_SCREEN_RESOLUTION_SCALE : packoffset(c9);
    float global_SCREEN_ORIENTATION : packoffset(c9.y);
    float global_SCREEN_SCALE : packoffset(c9.z);
    float global_SCREEN_FREQUENCY : packoffset(c9.w);
    float global_SCREEN_INTERLACED : packoffset(c10);
};

cbuffer Push : register(b1)
{
    float param_COLOR_BLACK_LIGHT : packoffset(c2);
    float param_SCANLINES_STRENGTH : packoffset(c2.y);
    float param_BEAM_WIDTH_MIN : packoffset(c2.w);
    float param_BEAM_WIDTH_MAX : packoffset(c3);
    float param_BEAM_SHAPE : packoffset(c3.y);
    float param_BEAM_FILTER : packoffset(c3.z);
    float param_ANTI_RINGING : packoffset(c3.w);
    float param_MASK_INTENSITY : packoffset(c4.y);
    float param_MASK_BLEND : packoffset(c4.z);
    float param_MASK_SCALE : packoffset(c4.w);
    float param_MASK_TYPE : packoffset(c5);
    float param_MASK_SUBPIXEL : packoffset(c5.y);
    float param_MASK_SUBPIXEL_ORDER : packoffset(c5.z);
    float param_MASK_SUBPIXEL_SHAPE : packoffset(c5.w);
    float param_MASK_COLOR_BLEED : packoffset(c6);
};


static float4 gl_Position;
static int ScreenOrientation;
static float3 ScreenMultipleProfile;
static float4 MaskProfile;
static float4 Position;
static float2 TexCoord;
static float2 Coord;
static float2 ScanTexCoord;
static float4 BeamProfile;
static float4x4 BeamFilter;
static float BrightnessCompensation;
static float AntiRining;
static float2 FloorProfile;
static uint2 FrameCounts;
static float2 TexSize;

struct SPIRV_Cross_Input
{
    float4 Position : TEXCOORD0;
    float2 Coord : TEXCOORD1;
};

struct SPIRV_Cross_Output
{
    float2 TexCoord : TEXCOORD0;
    float2 ScanTexCoord : TEXCOORD1;
    float2 TexSize : TEXCOORD2;
    nointerpolation int ScreenOrientation : TEXCOORD3;
    float3 ScreenMultipleProfile : TEXCOORD4;
    float BrightnessCompensation : TEXCOORD5;
    float4 MaskProfile : TEXCOORD6;
    float4 BeamProfile : TEXCOORD7;
    float AntiRining : TEXCOORD8;
    float2 FloorProfile : TEXCOORD9;
    nointerpolation uint2 FrameCounts : TEXCOORD10;
    float4x4 BeamFilter : TEXCOORD11;
    float4 gl_Position : SV_Position;
};

float mod(float x, float y)
{
    return x - y * floor(x / y);
}

float2 mod(float2 x, float2 y)
{
    return x - y * floor(x / y);
}

float3 mod(float3 x, float3 y)
{
    return x - y * floor(x / y);
}

float4 mod(float4 x, float4 y)
{
    return x - y * floor(x / y);
}

void vert_main()
{
    gl_Position = mul(Position, global_MVP);
    TexCoord = Coord;
    ScanTexCoord = Coord;
    int _1334 = int(global_SCREEN_ORIENTATION);
    int _3458;
    if (_1334 > 0)
    {
        _3458 = _1334 - 1;
    }
    else
    {
        _3458 = int(global_OutputSize.y > global_OutputSize.x);
    }
    ScreenOrientation = _3458;
    int _1447 = int(global_SCREEN_RESOLUTION_SCALE);
    bool _1448 = _1447 > 1;
    float _3506;
    if (_1448)
    {
        bool _1551 = ScreenOrientation > 0;
        float _3477;
        if (_1551)
        {
            _3477 = global_OriginalSize.x / global_OriginalSize.y;
        }
        else
        {
            _3477 = global_OriginalSize.y / global_OriginalSize.x;
        }
        float _1509 = float(global_OriginalSize.y > global_OriginalSize.x);
        float _1514 = (_1447 > 3) ? 480.0f : 240.0f;
        float _3479;
        if (_1551)
        {
            _3479 = lerp(_1514 * _3477, _1514, _1509);
        }
        else
        {
            _3479 = lerp(_1514, _1514 * _3477, _1509);
        }
        float _3481;
        if (_1551)
        {
            _3481 = global_OriginalSize.x / _3479;
        }
        else
        {
            _3481 = global_OriginalSize.y / _3479;
        }
        float _3485;
        if (_1551)
        {
            _3485 = global_FinalViewportSize.x / global_OriginalSize.x;
        }
        else
        {
            _3485 = global_FinalViewportSize.y / global_OriginalSize.y;
        }
        bool _1582 = _3481 < 1.0f;
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
            _3493 = round(2.0f / _3481) * 0.5f;
        }
        else
        {
            _3493 = round(_3481);
        }
        float _1621 = (((_1597 ? (-1.0f) : 1.0f) * (max(1.0f, _3493) - 1.0f)) + 8.0f) - global_SCREEN_SCALE;
        float _1658;
        float _3503;
        float _3498 = _1621;
        float _3504 = _3481;
        for (;;)
        {
            if (_3498 < 17.0f)
            {
                _1658 = lerp(_275[int(clamp(floor(_3498), 0.0f, 16.0f))], _275[int(clamp(ceil(_3498), 0.0f, 16.0f))], frac(_3498));
                if ((_3485 * _1658) >= 3.0f)
                {
                    _3503 = _1658;
                    break;
                }
                _3498 += 0.0500000007450580596923828125f;
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
        if (ScreenOrientation > 0)
        {
            _3459 = global_FinalViewportSize.x / global_OriginalSize.x;
        }
        else
        {
            _3459 = global_FinalViewportSize.y / global_OriginalSize.y;
        }
        float _1735 = (max(1.0f, round(1.0f)) + 7.0f) - global_SCREEN_SCALE;
        float _1772;
        float _3474;
        float _3469 = _1735;
        float _3475 = 1.0f;
        for (;;)
        {
            if (_3469 < 17.0f)
            {
                _1772 = lerp(_275[int(clamp(floor(_3469), 0.0f, 16.0f))], _275[int(clamp(ceil(_3469), 0.0f, 16.0f))], frac(_3469));
                if ((_3459 * _1772) >= 3.0f)
                {
                    _3474 = _1772;
                    break;
                }
                _3469 += 0.0500000007450580596923828125f;
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
    ScreenMultipleProfile.x = _3506;
    float _3554;
    if (_1448)
    {
        bool _1888 = ScreenOrientation > 0;
        float _3525;
        if (_1888)
        {
            _3525 = global_OriginalSize.x / global_OriginalSize.y;
        }
        else
        {
            _3525 = global_OriginalSize.y / global_OriginalSize.x;
        }
        float _1846 = float(global_OriginalSize.y > global_OriginalSize.x);
        float _1851 = (_1447 > 3) ? 480.0f : 240.0f;
        float _3527;
        if (_1888)
        {
            _3527 = lerp(_1851 * _3525, _1851, _1846);
        }
        else
        {
            _3527 = lerp(_1851, _1851 * _3525, _1846);
        }
        float _3529;
        if (_1888)
        {
            _3529 = global_OriginalSize.x / _3527;
        }
        else
        {
            _3529 = global_OriginalSize.y / _3527;
        }
        float _3533;
        if (_1888)
        {
            _3533 = global_FinalViewportSize.x / global_OriginalSize.x;
        }
        else
        {
            _3533 = global_FinalViewportSize.y / global_OriginalSize.y;
        }
        bool _1919 = _3529 < 1.0f;
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
            _3541 = round(2.0f / _3529) * 0.5f;
        }
        else
        {
            _3541 = round(_3529);
        }
        float _1955 = ((_1934 ? (-1.0f) : 1.0f) * (max(1.0f, _3541) - 1.0f)) + 8.0f;
        float _1995;
        float _3551;
        float _3546 = _1955;
        float _3552 = _3529;
        for (;;)
        {
            if (_3546 < 17.0f)
            {
                _1995 = lerp(_275[int(clamp(floor(_3546), 0.0f, 16.0f))], _275[int(clamp(ceil(_3546), 0.0f, 16.0f))], frac(_3546));
                if ((_3533 * _1995) >= 3.0f)
                {
                    _3551 = _1995;
                    break;
                }
                _3546 += 0.0500000007450580596923828125f;
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
        if (ScreenOrientation > 0)
        {
            _3507 = global_FinalViewportSize.x / global_OriginalSize.x;
        }
        else
        {
            _3507 = global_FinalViewportSize.y / global_OriginalSize.y;
        }
        float _2069 = max(1.0f, round(1.0f)) + 7.0f;
        float _2109;
        float _3522;
        float _3517 = _2069;
        float _3523 = 1.0f;
        for (;;)
        {
            if (_3517 < 17.0f)
            {
                _2109 = lerp(_275[int(clamp(floor(_3517), 0.0f, 16.0f))], _275[int(clamp(ceil(_3517), 0.0f, 16.0f))], frac(_3517));
                if ((_3507 * _2109) >= 3.0f)
                {
                    _3522 = _2109;
                    break;
                }
                _3517 += 0.0500000007450580596923828125f;
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
    ScreenMultipleProfile.y = _3554;
    bool _2200 = ScreenOrientation > 0;
    float _3555;
    if (_2200)
    {
        _3555 = global_OriginalSize.x / global_OriginalSize.y;
    }
    else
    {
        _3555 = global_OriginalSize.y / global_OriginalSize.x;
    }
    float _2158 = float(global_OriginalSize.y > global_OriginalSize.x);
    float _2163 = (_1447 > 3) ? 480.0f : 240.0f;
    float _3557;
    if (_2200)
    {
        _3557 = lerp(_2163 * _3555, _2163, _2158);
    }
    else
    {
        _3557 = lerp(_2163, _2163 * _3555, _2158);
    }
    float _3559;
    if (_2200)
    {
        _3559 = global_OriginalSize.x / _3557;
    }
    else
    {
        _3559 = global_OriginalSize.y / _3557;
    }
    float _3563;
    if (_2200)
    {
        _3563 = global_FinalViewportSize.x / global_OriginalSize.x;
    }
    else
    {
        _3563 = global_FinalViewportSize.y / global_OriginalSize.y;
    }
    bool _2231 = _3559 < 1.0f;
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
        _3571 = round(2.0f / _3559) * 0.5f;
    }
    else
    {
        _3571 = round(_3559);
    }
    float _2267 = ((_2246 ? (-1.0f) : 1.0f) * (max(1.0f, _3571) - 1.0f)) + 8.0f;
    float _2307;
    float _3581;
    float _3576 = _2267;
    float _3582 = _3559;
    for (;;)
    {
        if (_3576 < 17.0f)
        {
            _2307 = lerp(_275[int(clamp(floor(_3576), 0.0f, 16.0f))], _275[int(clamp(ceil(_3576), 0.0f, 16.0f))], frac(_3576));
            if ((_3563 * _2307) >= 3.0f)
            {
                _3581 = _2307;
                break;
            }
            _3576 += 0.0500000007450580596923828125f;
            _3582 = _2307;
            continue;
        }
        else
        {
            _3581 = _3582;
            break;
        }
    }
    ScreenMultipleProfile.z = _3581;
    float _3584;
    if (global_OriginalSize.x < global_OriginalSize.y)
    {
        _3584 = global_FinalViewportSize.x / global_OriginalSize.x;
    }
    else
    {
        _3584 = global_FinalViewportSize.y / global_OriginalSize.y;
    }
    float _2367 = max(1.0f, floor((_3584 / ((min(global_OriginalSize.x, global_OriginalSize.y) < 180.0f) ? 3.0f : 4.0f)) * ScreenMultipleProfile.z));
    float _3585;
    if (param_MASK_SCALE < 0.0f)
    {
        _3585 = ceil(_2367 / (floor(abs(param_MASK_SCALE)) + 1.0f));
    }
    else
    {
        _3585 = floor(_2367 * (param_MASK_SCALE + 1.0f));
    }
    float _2384 = max(1.0f, _3585);
    int _2387 = int(param_MASK_TYPE);
    bool _2388 = _2387 == 1;
    float _3588;
    if (_2388)
    {
        _3588 = clamp((_2384 - 2.0f) * 0.75f, 0.0f, 1.0f);
    }
    else
    {
        float _3587;
        if (_2387 == 2)
        {
            _3587 = clamp((_2384 - 2.0f) * 0.75f, 0.0f, 1.0f);
        }
        else
        {
            float _3586;
            if (_2387 == 3)
            {
                _3586 = clamp((_2384 - 2.0f) * 0.25f, 0.0f, 1.0f);
            }
            else
            {
                _3586 = 0.0f;
            }
            _3587 = _3586;
        }
        _3588 = _3587;
    }
    int _2427 = int(param_MASK_SUBPIXEL);
    MaskProfile = float4(float(_2427), _2384, _3588 * param_MASK_SUBPIXEL_SHAPE, float(int(param_MASK_SUBPIXEL_ORDER)));
    float _2569 = clamp(param_SCANLINES_STRENGTH * global_GLOBAL_MASTER, 0.0f, 1.0f);
    float _2482 = (1.0f - param_BEAM_SHAPE) * _2569;
    float _2500 = 1.0f - (_2482 * 0.5f);
    float _2522 = min(1.0f, _2569 * 2.0f);
    float _2678 = (0.5f * _2569) / (1.5f - abs(_2569));
    BeamProfile = float4(_2500 / (1.0f + (((min(1.0f, 1.0f - param_BEAM_WIDTH_MIN) - min(0.0f, param_BEAM_WIDTH_MIN * 2.0f)) * _2522) * 0.5f)), _2500 * (1.0f + ((max(0.0f, param_BEAM_WIDTH_MAX - 1.0f) * _2522) * 0.5f)), 2.0f + ((2.0f * _2482) * (_2482 + 1.0f)), (_2678 * 1.25f) + 0.25f);
    float _2818 = clamp(param_BEAM_FILTER * global_GLOBAL_MASTER, -1.0f, 1.0f);
    float _2692 = _2818 * 2.0f;
    float _2693 = _2692 + 1.0f;
    float _3592;
    float _3596;
    if (_2693 <= 0.0f)
    {
        _3596 = 0.0f;
        _3592 = _2693;
    }
    else
    {
        float _3593;
        float _3597;
        if (_2693 <= 1.0f)
        {
            _3597 = _2693 * 0.5f;
            _3593 = 0.0f;
        }
        else
        {
            float _3594;
            float _3598;
            if (_2693 <= 2.0f)
            {
                _3598 = 0.5f - (_2818 * 0.3333333432674407958984375f);
                _3594 = _2818 * 0.666666686534881591796875f;
            }
            else
            {
                float _3595;
                float _3599;
                if (_2693 <= 3.0f)
                {
                    float _2720 = _2692 + (-1.0f);
                    _3599 = 0.3333333432674407958984375f - (_2720 * 0.16666667163372039794921875f);
                    _3595 = 0.3333333432674407958984375f + (_2720 * 0.3333333432674407958984375f);
                }
                else
                {
                    _3599 = 0.0f;
                    _3595 = 0.0f;
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
    float _2734 = 6.0f * _3596;
    float _2738 = 3.0f * _3592;
    float _2740 = 12.0f * _3596;
    float _2750 = _3592 * 0.16666667163372039794921875f;
    float _2756 = (12.0f - (9.0f * _3592)) - _2734;
    BeamFilter = float4x4(float4(((-_3592) - _2734) * 0.16666667163372039794921875f, (_2738 + _2740) * 0.16666667163372039794921875f, (((-3.0f) * _3592) - _2734) * 0.16666667163372039794921875f, _2750), float4(_2756 * 0.16666667163372039794921875f, (((-18.0f) + (12.0f * _3592)) + _2734) * 0.16666667163372039794921875f, 0.0f, (6.0f - (2.0f * _3592)) * 0.16666667163372039794921875f), float4(_2756 * (-0.16666667163372039794921875f), ((18.0f - (15.0f * _3592)) - _2740) * 0.16666667163372039794921875f, (_2738 + _2734) * 0.16666667163372039794921875f, _2750), float4((_3592 + _2734) * 0.16666667163372039794921875f, -_3596, 0.0f, 0.0f));
    float _3175 = clamp(param_MASK_INTENSITY * global_GLOBAL_MASTER, 0.0f, 1.0f);
    float _2904 = _3175 * _3175;
    float _3209 = (0.5f * _2904) / (1.5f - abs(_2904));
    float _2908 = 1.0f - param_MASK_BLEND;
    float _2912 = _2908 * _2908;
    float _2913 = 1.0f - _2912;
    float _3604;
    if (_2427 == 1)
    {
        _3604 = lerp(-1.0f, -0.25f, _2913);
    }
    else
    {
        float _3603;
        if (_2427 == 2)
        {
            _3603 = lerp(-1.0f, -0.25f, _2913);
        }
        else
        {
            float _3602;
            if (_2427 == 3)
            {
                _3602 = lerp(-0.4000000059604644775390625f, -0.100000001490116119384765625f, _2913);
            }
            else
            {
                float _3601;
                if (_2427 == 4)
                {
                    _3601 = 0.0f;
                }
                else
                {
                    float _3600;
                    if (_2427 == 5)
                    {
                        _3600 = lerp(0.60000002384185791015625f, 0.1500000059604644775390625f, _2913);
                    }
                    else
                    {
                        _3600 = 0.0f;
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
        _3612 = lerp(0.20000000298023223876953125f, 0.0500000007450580596923828125f, _2913);
    }
    else
    {
        float _3611;
        if (_2387 == 2)
        {
            _3611 = lerp(0.800000011920928955078125f, 0.20000000298023223876953125f, _2913);
        }
        else
        {
            float _3610;
            if (_2387 == 3)
            {
                _3610 = lerp(0.20000000298023223876953125f, 0.0500000007450580596923828125f, _2913);
            }
            else
            {
                _3610 = 0.0f;
            }
            _3611 = _3610;
        }
        _3612 = _3611;
    }
    bool _3002 = int(MaskProfile.y) > 2;
    float _3626;
    if (_2388 && _3002)
    {
        _3626 = lerp(-0.4000000059604644775390625f, -0.100000001490116119384765625f, _2913);
    }
    else
    {
        float _3625;
        if ((_2387 == 2) && _3002)
        {
            _3625 = lerp(-0.4000000059604644775390625f, -0.100000001490116119384765625f, _2913);
        }
        else
        {
            float _3624;
            if ((_2387 == 3) && _3002)
            {
                _3624 = lerp(0.4000000059604644775390625f, 0.100000001490116119384765625f, _2913);
            }
            else
            {
                _3624 = 0.0f;
            }
            _3625 = _3624;
        }
        _3626 = _3625;
    }
    float _3643;
    if (_2388)
    {
        _3643 = lerp(1.60000002384185791015625f, 0.4000000059604644775390625f, _2913);
    }
    else
    {
        float _3642;
        if (_2387 == 2)
        {
            _3642 = lerp(1.60000002384185791015625f, 0.4000000059604644775390625f, _2913);
        }
        else
        {
            float _3641;
            if (_2387 == 3)
            {
                _3641 = lerp(2.400000095367431640625f, 0.60000002384185791015625f, _2913);
            }
            else
            {
                _3641 = 1.0f;
            }
            _3642 = _3641;
        }
        _3643 = _3642;
    }
    BrightnessCompensation = ((((((((((0.5f * global_SCREEN_INTERLACED) / (1.5f - abs(global_SCREEN_INTERLACED))) * 2.0f) + (_2678 * lerp(0.5f, 1.0f, param_BEAM_SHAPE))) - ((_2678 * 0.25f) * (1.0f - abs((param_BEAM_SHAPE * 2.0f) - 1.0f)))) + ((1.5f * _2912) * _3209)) + (_3604 * _3209)) + (_3612 * _3209)) + (_3626 * _3209)) + ((MaskProfile.z * _3643) * _3209)) + ((clamp(param_MASK_COLOR_BLEED * global_GLOBAL_MASTER, 0.0f, 1.0f) * lerp(-0.5f, -0.25f, _2913)) * _3209);
    AntiRining = (1.0f - smoothstep(1.5f, 2.0f, _2818 + 1.0f)) * param_ANTI_RINGING;
    float _3278 = 0.00390625f * max(_2569, _3175);
    FloorProfile = float2(_3278 * param_COLOR_BLACK_LIGHT, (0.015625f - _3278) * param_COLOR_BLACK_LIGHT);
    int _3330 = int(global_SCREEN_FREQUENCY);
    int _3696;
    if (_3330 == 50)
    {
        _3696 = 48;
    }
    else
    {
        _3696 = _3330;
    }
    float _3361 = (round(4.0f) * 0.25f) * float(global_FrameCount);
    FrameCounts = uint2(uint(mod(float(uint(round(_3361 * (float(_3696) * 0.01666666753590106964111328125f)))), 2.0f)), uint(mod(float(uint(round(_3361 * 0.20000000298023223876953125f))), 20.0f)));
    float2 _3702;
    if (ScreenOrientation == 0)
    {
        _3702 = float2(1.0f, ScreenMultipleProfile.x);
    }
    else
    {
        _3702 = float2(ScreenMultipleProfile.x, 1.0f);
    }
    TexSize = global_OriginalSize.xy / _3702;
    bool _1390 = ScreenMultipleProfile.y > 1.0f;
    bool _1397;
    if (!_1390)
    {
        _1397 = ScreenMultipleProfile.z > 1.0f;
    }
    else
    {
        _1397 = _1390;
    }
    if (_1397)
    {
        bool2 _3713 = (ScreenOrientation == 0).xx;
        ScanTexCoord += (float2(_3713.x ? float2(0.5f, 0.0f).x : float2(0.0f, 0.5f).x, _3713.y ? float2(0.5f, 0.0f).y : float2(0.0f, 0.5f).y) / global_OriginalSize.xy);
    }
}

SPIRV_Cross_Output main(SPIRV_Cross_Input stage_input)
{
    Position = stage_input.Position;
    Coord = stage_input.Coord;
    vert_main();
    SPIRV_Cross_Output stage_output;
    stage_output.gl_Position = gl_Position;
    stage_output.ScreenOrientation = ScreenOrientation;
    stage_output.ScreenMultipleProfile = ScreenMultipleProfile;
    stage_output.MaskProfile = MaskProfile;
    stage_output.TexCoord = TexCoord;
    stage_output.ScanTexCoord = ScanTexCoord;
    stage_output.BeamProfile = BeamProfile;
    stage_output.BeamFilter = BeamFilter;
    stage_output.BrightnessCompensation = BrightnessCompensation;
    stage_output.AntiRining = AntiRining;
    stage_output.FloorProfile = FloorProfile;
    stage_output.FrameCounts = FrameCounts;
    stage_output.TexSize = TexSize;
    return stage_output;
}
