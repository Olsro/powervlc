// Generated from crt/shaders/crt-yah/crt-yah-single-pass.slang. See slang/upstream for licence/source.
static const float3 _1099[30] = { 1.0f.xxx, 1.0f.xxx, 1.0f.xxx, 1.0f.xxx, 1.0f.xxx, 1.0f.xxx, float3(0.0f, 1.0f, 0.0f), float3(1.0f, 0.0f, 1.0f), float3(0.0f, 0.0f, 1.0f), float3(1.0f, 1.0f, 0.0f), float3(0.0f, 1.0f, 1.0f), float3(1.0f, 0.0f, 0.0f), float3(0.0f, 1.0f, 0.0f), float3(1.0f, 0.0f, 1.0f), float3(0.0f, 0.0f, 1.0f), float3(1.0f, 1.0f, 0.0f), float3(0.0f, 1.0f, 1.0f), float3(1.0f, 0.0f, 0.0f), float3(1.0f, 0.0f, 0.0f), float3(0.0f, 0.0f, 1.0f), float3(1.0f, 0.0f, 0.0f), float3(0.0f, 1.0f, 0.0f), float3(0.0f, 0.0f, 1.0f), float3(0.0f, 1.0f, 0.0f), float3(1.0f, 0.0f, 0.0f), float3(0.0f, 0.0f, 1.0f), float3(1.0f, 0.0f, 0.0f), float3(0.0f, 1.0f, 0.0f), float3(0.0f, 0.0f, 1.0f), float3(0.0f, 1.0f, 0.0f) };
static const float3 _1102[30] = { 0.0f.xxx, 0.0f.xxx, 0.0f.xxx, 0.0f.xxx, 0.0f.xxx, 0.0f.xxx, float3(1.0f, 0.0f, 1.0f), float3(0.0f, 1.0f, 0.0f), float3(1.0f, 1.0f, 0.0f), float3(0.0f, 0.0f, 1.0f), float3(1.0f, 0.0f, 0.0f), float3(0.0f, 1.0f, 1.0f), float3(1.0f, 0.0f, 1.0f), float3(0.0f, 1.0f, 0.0f), float3(1.0f, 1.0f, 0.0f), float3(0.0f, 0.0f, 1.0f), float3(1.0f, 0.0f, 0.0f), float3(0.0f, 1.0f, 1.0f), float3(0.0f, 1.0f, 0.0f), float3(0.0f, 1.0f, 0.0f), float3(0.0f, 0.0f, 1.0f), float3(0.0f, 0.0f, 1.0f), float3(1.0f, 0.0f, 0.0f), float3(1.0f, 0.0f, 0.0f), float3(0.0f, 1.0f, 0.0f), float3(0.0f, 1.0f, 0.0f), float3(0.0f, 0.0f, 1.0f), float3(0.0f, 0.0f, 1.0f), float3(1.0f, 0.0f, 0.0f), float3(1.0f, 0.0f, 0.0f) };
static const float3 _1105[30] = { 0.5f.xxx, 0.5f.xxx, 0.5f.xxx, 0.5f.xxx, 0.5f.xxx, 0.5f.xxx, 0.5f.xxx, 0.5f.xxx, 0.5f.xxx, 0.5f.xxx, 0.5f.xxx, 0.5f.xxx, 0.0f.xxx, 0.0f.xxx, 0.0f.xxx, 0.0f.xxx, 0.0f.xxx, 0.0f.xxx, float3(0.0f, 0.0f, 1.0f), float3(1.0f, 0.0f, 0.0f), float3(0.0f, 1.0f, 0.0f), float3(1.0f, 0.0f, 0.0f), float3(0.0f, 1.0f, 0.0f), float3(0.0f, 0.0f, 1.0f), float3(0.0f, 0.0f, 1.0f), float3(1.0f, 0.0f, 0.0f), float3(0.0f, 1.0f, 0.0f), float3(1.0f, 0.0f, 0.0f), float3(0.0f, 1.0f, 0.0f), float3(0.0f, 0.0f, 1.0f) };
static const float3 _1107[30] = { 0.5f.xxx, 0.5f.xxx, 0.5f.xxx, 0.5f.xxx, 0.5f.xxx, 0.5f.xxx, 0.5f.xxx, 0.5f.xxx, 0.5f.xxx, 0.5f.xxx, 0.5f.xxx, 0.5f.xxx, 0.5f.xxx, 0.5f.xxx, 0.5f.xxx, 0.5f.xxx, 0.5f.xxx, 0.5f.xxx, 0.5f.xxx, 0.5f.xxx, 0.5f.xxx, 0.5f.xxx, 0.5f.xxx, 0.5f.xxx, 0.0f.xxx, 0.0f.xxx, 0.0f.xxx, 0.0f.xxx, 0.0f.xxx, 0.0f.xxx };
static const int _1111[5] = { 2, 2, 3, 3, 4 };

cbuffer UBO : register(b0)
{
    float4 global_OutputSize : packoffset(c6);
    float global_GLOBAL_MASTER : packoffset(c8.w);
    float global_SCREEN_INTERLACED : packoffset(c10);
};

cbuffer Push : register(b1)
{
    float param_COLOR_BRIGHTNESS : packoffset(c0);
    float param_COLOR_COMPENSATION : packoffset(c0.z);
    float param_COLOR_SATURATION : packoffset(c0.w);
    float param_COLOR_OVERFLOW : packoffset(c1);
    float param_COLOR_CONTRAST : packoffset(c1.y);
    float param_COLOR_TEMPERATUE : packoffset(c1.w);
    float param_SCANLINES_STRENGTH : packoffset(c2.y);
    float param_SCANLINES_COLOR_BURN : packoffset(c4);
    float param_MASK_INTENSITY : packoffset(c4.y);
    float param_MASK_BLEND : packoffset(c4.z);
    float param_MASK_TYPE : packoffset(c5);
    float param_MASK_COLOR_BLEED : packoffset(c6);
    float param_CRT_CURVATURE_AMOUNT : packoffset(c6.y);
    float param_CRT_VIGNETTE_AMOUNT : packoffset(c6.z);
    float param_CRT_NOISE_AMOUNT : packoffset(c6.w);
    float param_CRT_CORNER_RAIDUS : packoffset(c7);
    float param_CRT_CORNER_SMOOTHNESS : packoffset(c7.y);
};

Texture2D<float4> Source : register(t2);
SamplerState _Source_sampler : register(s2);

static float BrightnessCompensation;
static float2 FloorProfile;
static int ScreenOrientation;
static float4 BeamProfile;
static float AntiRining;
static float3 ScreenMultipleProfile;
static uint2 FrameCounts;
static float4x4 BeamFilter;
static float4 MaskProfile;
static float2 TexSize;
static float2 TexCoord;
static float2 ScanTexCoord;
static float4 FragColor;

struct SPIRV_Cross_Input
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
};

struct SPIRV_Cross_Output
{
    float4 FragColor : SV_Target0;
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

void frag_main()
{
    bool _2400;
    float _2450;
    float _2456;
    float2 _6156;
    do
    {
        _2450 = global_GLOBAL_MASTER;
        _2456 = clamp(param_CRT_CURVATURE_AMOUNT * _2450, 0.0f, 1.0f);
        _2400 = _2456 == 0.0f;
        if (_2400)
        {
            _6156 = TexCoord;
            break;
        }
        float2 _2409 = TexCoord - 0.5f.xx;
        float _2411 = _2409.x;
        float _2416 = _2409.y;
        float _2420 = (_2411 * _2411) + (_2416 * _2416);
        _6156 = (_2409 * ((1.0f + (_2420 * (_2456 * sqrt(_2420)))) / (1.0f + (_2456 * 0.125f)))) + 0.5f.xx;
        break;
    } while(false);
    float2 _2493 = _6156 * TexSize;
    float2 _2497 = floor(global_OutputSize.xy / TexSize);
    float2 _2500 = 0.5f.xx / _2497;
    float2 _2506 = frac(_2493) - 0.5f.xx;
    float2 _2521 = floor(_2493) + (((_2506 - clamp(_2506, _2500 - 0.5f.xx, 0.5f.xx - _2500)) * _2497) + 0.5f.xx);
    float2 _6158;
    do
    {
        if (_2400)
        {
            _6158 = ScanTexCoord;
            break;
        }
        float2 _2553 = ScanTexCoord - 0.5f.xx;
        float _2555 = _2553.x;
        float _2560 = _2553.y;
        float _2564 = (_2555 * _2555) + (_2560 * _2560);
        _6158 = (_2553 * ((1.0f + (_2564 * (_2456 * sqrt(_2564)))) / (1.0f + (_2456 * 0.125f)))) + 0.5f.xx;
        break;
    } while(false);
    float4 _2683 = Source.Sample(_Source_sampler, _2521 / TexSize);
    float _2719 = _2683.x;
    float _6161;
    if (_2719 <= 0.0404481999576091766357421875f)
    {
        _6161 = _2719 * 0.077399380505084991455078125f;
    }
    else
    {
        _6161 = pow((_2719 + 0.054999999701976776123046875f) * 0.947867333889007568359375f, 2.400000095367431640625f);
    }
    float _2723 = _2683.y;
    float _6163;
    if (_2723 <= 0.0404481999576091766357421875f)
    {
        _6163 = _2723 * 0.077399380505084991455078125f;
    }
    else
    {
        _6163 = pow((_2723 + 0.054999999701976776123046875f) * 0.947867333889007568359375f, 2.400000095367431640625f);
    }
    float _2727 = _2683.z;
    float _6165;
    if (_2727 <= 0.0404481999576091766357421875f)
    {
        _6165 = _2727 * 0.077399380505084991455078125f;
    }
    else
    {
        _6165 = pow((_2727 + 0.054999999701976776123046875f) * 0.947867333889007568359375f, 2.400000095367431640625f);
    }
    bool _2787;
    float3 _2730 = float3(_6161, _6163, _6165);
    float3 _6169;
    do
    {
        _2787 = FloorProfile.x == 0.0f;
        if (_2787)
        {
            _6169 = _2730;
            break;
        }
        float _2796 = FloorProfile.x * (1.0f - dot(_2730, float3(0.2125999927520751953125f, 0.715200006961822509765625f, 0.072200000286102294921875f)));
        _6169 = (_2730 + _2796.xxx) / (1.0f + _2796).xxx;
        break;
    } while(false);
    float _2822;
    bool _2823;
    float3 _6178;
    do
    {
        _2822 = global_SCREEN_INTERLACED;
        _2823 = _2822 == 0.0f;
        if (_2823)
        {
            _6178 = _6169;
            break;
        }
        bool _2838 = (int(floor(lerp(_2521, _2521.yx, float(ScreenOrientation).xx).y)) % 2) != 0;
        _6178 = lerp(_6169, lerp(lerp(0.0f.xxx, _6169, float(_2838).xxx), lerp(0.0f.xxx, _6169, float(!_2838).xxx), float(FrameCounts.x).xxx), _2822.xxx);
        break;
    } while(false);
    float2 _2987 = ((_6158 + 9.9999997473787516355514526367188e-06f.xx) * TexSize) + 0.5f.xx;
    float2 _2996 = float2(1.0f, ScreenMultipleProfile.x);
    bool _2999 = ScreenMultipleProfile.x > 1.0f;
    float2 _6190;
    if (_2999)
    {
        _6190 = float2(-0.5f, 0.5f) / _2996;
    }
    else
    {
        _6190 = float2(-0.5f, 0.5f);
    }
    bool _3011 = ScreenMultipleProfile.y > 1.0f;
    bool _3018;
    if (!_3011)
    {
        _3018 = ScreenMultipleProfile.z > 1.0f;
    }
    else
    {
        _3018 = _3011;
    }
    float2 _6194;
    if (_3018)
    {
        _6194 = _6190 + float2(-0.5f, 0.0f);
    }
    else
    {
        _6194 = _6190;
    }
    float2 _6199;
    if (_2999)
    {
        _6199 = _6194 + ((float2(0.0f, 0.5f) / _2996) * (ScreenMultipleProfile.x - 1.0f));
    }
    else
    {
        _6199 = _6194;
    }
    float2 _3051 = float(ScreenOrientation).xx;
    float2 _3043 = (floor(_2987) + lerp(_6199, _6199.yx, _3051)) / TexSize;
    float2 _2924 = 1.0f.xx / TexSize;
    float2 _3058 = float2(_2924.x, 0.0f);
    float2 _3062 = float2(0.0f, _2924.y);
    float2 _3066 = lerp(_3058, _3062, _3051);
    float2 _3080 = lerp(_3062, _3058, _3051);
    float2 _3089 = lerp(_2987, _2987.yx, _3051);
    float2 _2931 = frac(_3089);
    float _2933 = _2931.x;
    float _2936 = _2933 * _2933;
    float4 _2949 = mul(BeamFilter, float4(_2936 * _2933, _2936, _2933, 1.0f));
    float2 _3106 = _3043 - _3066;
    float4 _3109 = Source.Sample(_Source_sampler, _3106 - _3080);
    float _3216 = _3109.x;
    float _6212;
    if (_3216 <= 0.0404481999576091766357421875f)
    {
        _6212 = _3216 * 0.077399380505084991455078125f;
    }
    else
    {
        _6212 = pow((_3216 + 0.054999999701976776123046875f) * 0.947867333889007568359375f, 2.400000095367431640625f);
    }
    float _3220 = _3109.y;
    float _6214;
    if (_3220 <= 0.0404481999576091766357421875f)
    {
        _6214 = _3220 * 0.077399380505084991455078125f;
    }
    else
    {
        _6214 = pow((_3220 + 0.054999999701976776123046875f) * 0.947867333889007568359375f, 2.400000095367431640625f);
    }
    float _3224 = _3109.z;
    float _6216;
    if (_3224 <= 0.0404481999576091766357421875f)
    {
        _6216 = _3224 * 0.077399380505084991455078125f;
    }
    else
    {
        _6216 = pow((_3224 + 0.054999999701976776123046875f) * 0.947867333889007568359375f, 2.400000095367431640625f);
    }
    float3 _3227 = float3(_6212, _6214, _6216);
    float3 _6220;
    do
    {
        if (_2787)
        {
            _6220 = _3227;
            break;
        }
        float _3293 = FloorProfile.x * (1.0f - dot(_3227, float3(0.2125999927520751953125f, 0.715200006961822509765625f, 0.072200000286102294921875f)));
        _6220 = (_3227 + _3293.xxx) / (1.0f + _3293).xxx;
        break;
    } while(false);
    float4 _3116 = Source.Sample(_Source_sampler, _3043 - _3080);
    float _3337 = _3116.x;
    float _6229;
    if (_3337 <= 0.0404481999576091766357421875f)
    {
        _6229 = _3337 * 0.077399380505084991455078125f;
    }
    else
    {
        _6229 = pow((_3337 + 0.054999999701976776123046875f) * 0.947867333889007568359375f, 2.400000095367431640625f);
    }
    float _3341 = _3116.y;
    float _6231;
    if (_3341 <= 0.0404481999576091766357421875f)
    {
        _6231 = _3341 * 0.077399380505084991455078125f;
    }
    else
    {
        _6231 = pow((_3341 + 0.054999999701976776123046875f) * 0.947867333889007568359375f, 2.400000095367431640625f);
    }
    float _3345 = _3116.z;
    float _6233;
    if (_3345 <= 0.0404481999576091766357421875f)
    {
        _6233 = _3345 * 0.077399380505084991455078125f;
    }
    else
    {
        _6233 = pow((_3345 + 0.054999999701976776123046875f) * 0.947867333889007568359375f, 2.400000095367431640625f);
    }
    float3 _3348 = float3(_6229, _6231, _6233);
    float3 _6237;
    do
    {
        if (_2787)
        {
            _6237 = _3348;
            break;
        }
        float _3414 = FloorProfile.x * (1.0f - dot(_3348, float3(0.2125999927520751953125f, 0.715200006961822509765625f, 0.072200000286102294921875f)));
        _6237 = (_3348 + _3414.xxx) / (1.0f + _3414).xxx;
        break;
    } while(false);
    float2 _3122 = _3043 + _3066;
    float4 _3125 = Source.Sample(_Source_sampler, _3122 - _3080);
    float _3458 = _3125.x;
    float _6254;
    if (_3458 <= 0.0404481999576091766357421875f)
    {
        _6254 = _3458 * 0.077399380505084991455078125f;
    }
    else
    {
        _6254 = pow((_3458 + 0.054999999701976776123046875f) * 0.947867333889007568359375f, 2.400000095367431640625f);
    }
    float _3462 = _3125.y;
    float _6256;
    if (_3462 <= 0.0404481999576091766357421875f)
    {
        _6256 = _3462 * 0.077399380505084991455078125f;
    }
    else
    {
        _6256 = pow((_3462 + 0.054999999701976776123046875f) * 0.947867333889007568359375f, 2.400000095367431640625f);
    }
    float _3466 = _3125.z;
    float _6258;
    if (_3466 <= 0.0404481999576091766357421875f)
    {
        _6258 = _3466 * 0.077399380505084991455078125f;
    }
    else
    {
        _6258 = pow((_3466 + 0.054999999701976776123046875f) * 0.947867333889007568359375f, 2.400000095367431640625f);
    }
    float3 _3469 = float3(_6254, _6256, _6258);
    float3 _6262;
    do
    {
        if (_2787)
        {
            _6262 = _3469;
            break;
        }
        float _3535 = FloorProfile.x * (1.0f - dot(_3469, float3(0.2125999927520751953125f, 0.715200006961822509765625f, 0.072200000286102294921875f)));
        _6262 = (_3469 + _3535.xxx) / (1.0f + _3535).xxx;
        break;
    } while(false);
    float2 _3132 = _3043 + (_3066 * 2.0f);
    float4 _3135 = Source.Sample(_Source_sampler, _3132 - _3080);
    float _3579 = _3135.x;
    float _6275;
    if (_3579 <= 0.0404481999576091766357421875f)
    {
        _6275 = _3579 * 0.077399380505084991455078125f;
    }
    else
    {
        _6275 = pow((_3579 + 0.054999999701976776123046875f) * 0.947867333889007568359375f, 2.400000095367431640625f);
    }
    float _3583 = _3135.y;
    float _6277;
    if (_3583 <= 0.0404481999576091766357421875f)
    {
        _6277 = _3583 * 0.077399380505084991455078125f;
    }
    else
    {
        _6277 = pow((_3583 + 0.054999999701976776123046875f) * 0.947867333889007568359375f, 2.400000095367431640625f);
    }
    float _3587 = _3135.z;
    float _6279;
    if (_3587 <= 0.0404481999576091766357421875f)
    {
        _6279 = _3587 * 0.077399380505084991455078125f;
    }
    else
    {
        _6279 = pow((_3587 + 0.054999999701976776123046875f) * 0.947867333889007568359375f, 2.400000095367431640625f);
    }
    float3 _3590 = float3(_6275, _6277, _6279);
    float3 _6283;
    do
    {
        if (_2787)
        {
            _6283 = _3590;
            break;
        }
        float _3656 = FloorProfile.x * (1.0f - dot(_3590, float3(0.2125999927520751953125f, 0.715200006961822509765625f, 0.072200000286102294921875f)));
        _6283 = (_3590 + _3656.xxx) / (1.0f + _3656).xxx;
        break;
    } while(false);
    float3 _3160 = mul(_2949, float4x3(_6220, _6237, _6262, _6283));
    float3 _3185 = lerp(_3160, clamp(_3160, min(_6237, _6262), max(_6237, _6262)), step(0.0f.xxx, abs(_6220 - _6237) * abs(_6262 - _6283)) * AntiRining);
    float4 _3690 = Source.Sample(_Source_sampler, _3106);
    float _3797 = _3690.x;
    float _6372;
    if (_3797 <= 0.0404481999576091766357421875f)
    {
        _6372 = _3797 * 0.077399380505084991455078125f;
    }
    else
    {
        _6372 = pow((_3797 + 0.054999999701976776123046875f) * 0.947867333889007568359375f, 2.400000095367431640625f);
    }
    float _3801 = _3690.y;
    float _6374;
    if (_3801 <= 0.0404481999576091766357421875f)
    {
        _6374 = _3801 * 0.077399380505084991455078125f;
    }
    else
    {
        _6374 = pow((_3801 + 0.054999999701976776123046875f) * 0.947867333889007568359375f, 2.400000095367431640625f);
    }
    float _3805 = _3690.z;
    float _6376;
    if (_3805 <= 0.0404481999576091766357421875f)
    {
        _6376 = _3805 * 0.077399380505084991455078125f;
    }
    else
    {
        _6376 = pow((_3805 + 0.054999999701976776123046875f) * 0.947867333889007568359375f, 2.400000095367431640625f);
    }
    float3 _3808 = float3(_6372, _6374, _6376);
    float3 _6380;
    do
    {
        if (_2787)
        {
            _6380 = _3808;
            break;
        }
        float _3874 = FloorProfile.x * (1.0f - dot(_3808, float3(0.2125999927520751953125f, 0.715200006961822509765625f, 0.072200000286102294921875f)));
        _6380 = (_3808 + _3874.xxx) / (1.0f + _3874).xxx;
        break;
    } while(false);
    float4 _3697 = Source.Sample(_Source_sampler, _3043);
    float _3918 = _3697.x;
    float _6389;
    if (_3918 <= 0.0404481999576091766357421875f)
    {
        _6389 = _3918 * 0.077399380505084991455078125f;
    }
    else
    {
        _6389 = pow((_3918 + 0.054999999701976776123046875f) * 0.947867333889007568359375f, 2.400000095367431640625f);
    }
    float _3922 = _3697.y;
    float _6391;
    if (_3922 <= 0.0404481999576091766357421875f)
    {
        _6391 = _3922 * 0.077399380505084991455078125f;
    }
    else
    {
        _6391 = pow((_3922 + 0.054999999701976776123046875f) * 0.947867333889007568359375f, 2.400000095367431640625f);
    }
    float _3926 = _3697.z;
    float _6393;
    if (_3926 <= 0.0404481999576091766357421875f)
    {
        _6393 = _3926 * 0.077399380505084991455078125f;
    }
    else
    {
        _6393 = pow((_3926 + 0.054999999701976776123046875f) * 0.947867333889007568359375f, 2.400000095367431640625f);
    }
    float3 _3929 = float3(_6389, _6391, _6393);
    float3 _6397;
    do
    {
        if (_2787)
        {
            _6397 = _3929;
            break;
        }
        float _3995 = FloorProfile.x * (1.0f - dot(_3929, float3(0.2125999927520751953125f, 0.715200006961822509765625f, 0.072200000286102294921875f)));
        _6397 = (_3929 + _3995.xxx) / (1.0f + _3995).xxx;
        break;
    } while(false);
    float4 _3706 = Source.Sample(_Source_sampler, _3122);
    float _4039 = _3706.x;
    float _6414;
    if (_4039 <= 0.0404481999576091766357421875f)
    {
        _6414 = _4039 * 0.077399380505084991455078125f;
    }
    else
    {
        _6414 = pow((_4039 + 0.054999999701976776123046875f) * 0.947867333889007568359375f, 2.400000095367431640625f);
    }
    float _4043 = _3706.y;
    float _6416;
    if (_4043 <= 0.0404481999576091766357421875f)
    {
        _6416 = _4043 * 0.077399380505084991455078125f;
    }
    else
    {
        _6416 = pow((_4043 + 0.054999999701976776123046875f) * 0.947867333889007568359375f, 2.400000095367431640625f);
    }
    float _4047 = _3706.z;
    float _6418;
    if (_4047 <= 0.0404481999576091766357421875f)
    {
        _6418 = _4047 * 0.077399380505084991455078125f;
    }
    else
    {
        _6418 = pow((_4047 + 0.054999999701976776123046875f) * 0.947867333889007568359375f, 2.400000095367431640625f);
    }
    float3 _4050 = float3(_6414, _6416, _6418);
    float3 _6422;
    do
    {
        if (_2787)
        {
            _6422 = _4050;
            break;
        }
        float _4116 = FloorProfile.x * (1.0f - dot(_4050, float3(0.2125999927520751953125f, 0.715200006961822509765625f, 0.072200000286102294921875f)));
        _6422 = (_4050 + _4116.xxx) / (1.0f + _4116).xxx;
        break;
    } while(false);
    float4 _3716 = Source.Sample(_Source_sampler, _3132);
    float _4160 = _3716.x;
    float _6435;
    if (_4160 <= 0.0404481999576091766357421875f)
    {
        _6435 = _4160 * 0.077399380505084991455078125f;
    }
    else
    {
        _6435 = pow((_4160 + 0.054999999701976776123046875f) * 0.947867333889007568359375f, 2.400000095367431640625f);
    }
    float _4164 = _3716.y;
    float _6437;
    if (_4164 <= 0.0404481999576091766357421875f)
    {
        _6437 = _4164 * 0.077399380505084991455078125f;
    }
    else
    {
        _6437 = pow((_4164 + 0.054999999701976776123046875f) * 0.947867333889007568359375f, 2.400000095367431640625f);
    }
    float _4168 = _3716.z;
    float _6439;
    if (_4168 <= 0.0404481999576091766357421875f)
    {
        _6439 = _4168 * 0.077399380505084991455078125f;
    }
    else
    {
        _6439 = pow((_4168 + 0.054999999701976776123046875f) * 0.947867333889007568359375f, 2.400000095367431640625f);
    }
    float3 _4171 = float3(_6435, _6437, _6439);
    float3 _6443;
    do
    {
        if (_2787)
        {
            _6443 = _4171;
            break;
        }
        float _4237 = FloorProfile.x * (1.0f - dot(_4171, float3(0.2125999927520751953125f, 0.715200006961822509765625f, 0.072200000286102294921875f)));
        _6443 = (_4171 + _4237.xxx) / (1.0f + _4237).xxx;
        break;
    } while(false);
    float3 _3741 = mul(_2949, float4x3(_6380, _6397, _6422, _6443));
    float3 _3766 = lerp(_3741, clamp(_3741, min(_6397, _6422), max(_6397, _6422)), step(0.0f.xxx, abs(_6380 - _6397) * abs(_6422 - _6443)) * AntiRining);
    float _2961 = _2931.y;
    float3 _4281 = clamp(param_SCANLINES_COLOR_BURN * _2450, 0.0f, 1.0f).xxx;
    float3 _4284 = BeamProfile.x.xxx;
    float3 _4286 = BeamProfile.y.xxx;
    float _4296 = (-10.0f) * BeamProfile.w;
    float3 _4299 = BeamProfile.z.xxx;
    float3 _2974 = _3185 * exp(pow(_2961.xxx / (lerp(_4284, _4286, lerp(max(max(_3185.x, _3185.y), _3185.z).xxx, _3185, _4281)) + 9.9999997473787516355514526367188e-06f.xxx), _4299) * _4296);
    float3 _2977 = _3766 * exp(pow((1.0f - _2961).xxx / (lerp(_4284, _4286, lerp(max(max(_3766.x, _3766.y), _3766.z).xxx, _3766, _4281)) + 9.9999997473787516355514526367188e-06f.xxx), _4299) * _4296);
    float3 _6538;
    do
    {
        if (_2823)
        {
            _6538 = _2974 + _2977;
            break;
        }
        bool _4497 = (int(floor(_3089.y)) % 2) != 0;
        _6538 = lerp(_2974 + _2977, lerp(lerp(_2974, _2977, float(_4497).xxx), lerp(_2974, _2977, float(!_4497).xxx), float(FrameCounts.x).xxx), _2822.xxx);
        break;
    } while(false);
    float3 _6578;
    do
    {
        float _4581 = clamp(param_SCANLINES_STRENGTH * _2450, 0.0f, 1.0f);
        if (_4581 == 0.0f)
        {
            _6578 = _6178;
            break;
        }
        _6578 = lerp(_6178, _6538, min(1.0f, _4581 * 8.0f).xxx);
        break;
    } while(false);
    float _4600 = dot(_6578, float3(0.2125999927520751953125f, 0.715200006961822509765625f, 0.072200000286102294921875f));
    float3 _6745;
    do
    {
        int _4633 = int(param_MASK_TYPE);
        bool _4634 = _4633 == 0;
        if (_4634)
        {
            _6745 = _6578;
            break;
        }
        float2 _4726 = TexCoord * global_OutputSize.xy;
        int _4736 = int(MaskProfile.y);
        float3 _6714;
        do
        {
            if (_4634)
            {
                _6714 = 1.0f.xxx;
                break;
            }
            int _4821 = int(MaskProfile.x) - 1;
            float _4825 = float(_4736);
            float2 _4828 = lerp(_4726, _4726.yx, _3051) / _4825.xx;
            bool _4830 = _4633 == 1;
            bool _4832 = _4633 == 2;
            float2 _7072;
            if (_4830 || _4832)
            {
                float _4841 = floor(0.5f * _4825) / _4825;
                float2 _7073;
                if (_4821 == 2)
                {
                    _7073 = _4828 + (float2(_4841 * floor(_4828.x / (3.0f - _4841)), 0.0f) * float(_4736 > 1));
                }
                else
                {
                    float2 _7074;
                    if (_4821 == 4)
                    {
                        _7074 = _4828 + (float2(_4841 * floor(_4828.x / (4.0f - _4841)), 0.0f) * float(_4736 > 1));
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
            float2 _6675;
            float2 _6681;
            float2 _7076;
            if (_4830)
            {
                _7076 = _7072;
                _6681 = 1.0f.xx;
                _6675 = float2(1.0f, 8640.0f);
            }
            else
            {
                float2 _6676;
                float2 _6682;
                float2 _7077;
                if (_4832)
                {
                    bool _4882 = _4736 == 1;
                    float _4883 = _4882 ? 4.0f : 3.0f;
                    float _6634;
                    if (_4882)
                    {
                        _6634 = 0.5f;
                    }
                    else
                    {
                        _6634 = (_4736 == 2) ? 0.25f : 0.16666667163372039794921875f;
                    }
                    bool _4894 = _4736 == 3;
                    float2 _7078;
                    if ((_4821 == 0) || (_4821 == 1))
                    {
                        float2 _4907 = _7072 + float2(0.0f, (_4894 ? 1.66666662693023681640625f : 1.5f) * floor(mod(_7072.x * 0.5f, 2.0f)));
                        float _4910 = _4907.y * 1.000010013580322265625f;
                        float2 _6996 = _4907;
                        _6996.y = _4910;
                        _6996.y = _4910 + _6634;
                        _7078 = _6996;
                    }
                    else
                    {
                        float2 _7079;
                        if ((_4821 == 2) || (_4821 == 3))
                        {
                            float2 _4929 = _7072 + float2(0.0f, (_4894 ? 1.66666662693023681640625f : 1.5f) * floor(mod(_7072.x * 0.3333333432674407958984375f, 2.0f)));
                            float _4932 = _4929.y * 1.000010013580322265625f;
                            float2 _7003 = _4929;
                            _7003.y = _4932;
                            _7003.y = _4932 + _6634;
                            _7079 = _7003;
                        }
                        else
                        {
                            float2 _7080;
                            if (_4821 == 4)
                            {
                                float2 _4948 = _7072 + float2(0.0f, (_4894 ? 1.66666662693023681640625f : 1.5f) * floor(mod(_7072.x * 0.25f, 2.0f)));
                                float _4951 = _4948.y * 1.000010013580322265625f;
                                float2 _7010 = _4948;
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
                    _6682 = float2(1.0f, (_4883 - (_6634 * 2.0f)) / _4883);
                    _6676 = float2(1.0f, _4883);
                }
                else
                {
                    float2 _7081;
                    if (_4633 == 3)
                    {
                        float2 _7082;
                        if ((_4821 == 0) || (_4821 == 1))
                        {
                            _7082 = _7072 + float2(floor(mod(_7072.y, 2.0f)), 0.0f);
                        }
                        else
                        {
                            float2 _7083;
                            if ((_4821 == 2) || (_4821 == 3))
                            {
                                float2 _4999 = _7072 + float2(((_4736 == 3) ? 1.66666662693023681640625f : 1.5f) * floor(mod(_7072.y, 2.0f)), 0.0f);
                                _4999.x = _4999.x * 1.000010013580322265625f;
                                _7083 = _4999;
                            }
                            else
                            {
                                float2 _7084;
                                if (_4821 == 4)
                                {
                                    _7084 = _7072 + float2(2.0f * floor(mod(_7072.y, 2.0f)), 0.0f);
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
                    _6682 = 1.0f.xx;
                    _6676 = 1.0f.xx;
                }
                _7076 = _7077;
                _6681 = _6682;
                _6675 = _6676;
            }
            int _5021 = (_4821 * 6) + (int(MaskProfile.w) - 1);
            float3 _5162[4] = { _1099[_5021], _1102[_5021], _1105[_5021], _1107[_5021] };
            float3 _5153[4] = _5162;
            int _5176 = int(floor(mod(_7076.x, float(_1111[_4821]))));
            float3 _6713;
            if (_4736 > 2)
            {
                float2 _5047 = _6675 * 1024.0f;
                float _5202 = max(min(_5047.x, _5047.y), 1.0f);
                float2 _5232 = (abs(((frac(_7076 / _6675) - 0.5f.xx) * (2.0f.xx / _6681)) * _5047) - _5047) + _5202.xx;
                float _5211 = _5202 * MaskProfile.z;
                _6713 = _5153[_5176] * smoothstep(1.0f, 0.0f, (((length(max(_5232, 0.0f.xx)) + min(max(_5232.x, _5232.y), 0.0f)) - _5202) * (1.0f / _5211)) + (1.0f - sqrt(0.5f / _5211)));
            }
            else
            {
                float2 _5254 = abs((frac(_7076 / _6675) - 0.5f.xx) * 2.0f) - _6681;
                _6713 = _5153[_5176] * step(max(_5254.x, _5254.y), 0.0f);
            }
            _6714 = _6713;
            break;
        } while(false);
        float _5279 = clamp(param_MASK_COLOR_BLEED * _2450, 0.0f, 1.0f);
        float3 _4656 = _6714 + ((max(0.0f.xxx, dot(_6714, float3(0.2125999927520751953125f, 0.715200006961822509765625f, 0.072200000286102294921875f)).xxx - _6714) * _5279) * _5279);
        float3 _4665 = param_MASK_BLEND.xxx;
        float3 _4666 = lerp(_4656, _4656 + (_4600 * 0.5f).xxx, _4665);
        float _5309 = clamp(param_MASK_INTENSITY * _2450, 0.0f, 1.0f);
        _6745 = lerp(_6578, _6578 * lerp(_4666, clamp(_4666 + ((1.0f - _5309) * 0.5f).xxx, 0.0f.xxx, 1.0f.xxx) + (_5309 * 0.5f).xxx, _4665), _5309.xxx);
        break;
    } while(false);
    float3 _6826;
    do
    {
        float _5437 = clamp(param_CRT_NOISE_AMOUNT * _2450, 0.0f, 1.0f);
        if (_5437 == 0.0f)
        {
            _6826 = _6745;
            break;
        }
        float2 _5381 = TexCoord * global_OutputSize.xy;
        float _5385 = float(int(MaskProfile.y));
        float _5455 = frac(cos(dot((floor(lerp(_5381, _5381.yx, _3051) / _5385.xx) * _5385) * (float(FrameCounts.y) + 1.0f), float2(23.1406917572021484375f, 2.6651442050933837890625f))) * 123456.0f);
        float _5401 = 1.0f - _4600;
        _6826 = lerp(_6745, (_6745 * (_5455 * 2.0f)) + ((_5455 * _5401) * FloorProfile.y).xxx, ((_5401 * _5437) * 0.25f).xxx);
        break;
    } while(false);
    float _5498 = clamp(param_COLOR_OVERFLOW * _2450, 0.0f, 2.0f);
    float3 _6827;
    do
    {
        if (_5498 == 0.0f)
        {
            _6827 = _6826;
            break;
        }
        float3 _5518 = (_6826 * _6826) * (_5498 * 0.5f);
        float _5530 = _5518.y;
        float _5538 = _5518.z;
        float _5546 = _5518.x;
        float _5566 = _6826.z + (0.02027775906026363372802734375f * _5546);
        float3 _7085 = float3((_6826.x + (0.21520321071147918701171875f * _5530)) + (0.02027775906026363372802734375f * _5538), (_6826.y + (0.21520321071147918701171875f * _5546)) + (0.15499968826770782470703125f * _5538), _5566);
        _7085.z = _5566 + (0.15499968826770782470703125f * _5530);
        _6827 = _7085;
        break;
    } while(false);
    float _6891;
    do
    {
        float _5641 = clamp(param_CRT_VIGNETTE_AMOUNT * _2450, 0.0f, 1.0f);
        if (_5641 == 0.0f)
        {
            _6891 = 1.0f;
            break;
        }
        float _5675 = (1.5f * _5641) / (0.5f - (abs(_5641) * (-1.0f)));
        float _5612 = _5675 * 0.25f;
        _6891 = smoothstep(1.0f - _5612, 0.625f - (_5612 + (_5675 * 0.125f)), length(_6156 - 0.5f.xx));
        break;
    } while(false);
    float _6894;
    do
    {
        float _5726 = clamp(param_CRT_CORNER_RAIDUS * _2450, 0.0f, 0.25f);
        if (_5726 == 0.0f)
        {
            _6894 = 1.0f;
            break;
        }
        float _5767 = max(_5726 * min(global_OutputSize.x, global_OutputSize.y), 1.0f);
        float2 _5797 = (abs(((_6156 - 0.5f.xx) * 2.0f.xx) * global_OutputSize.xy) - global_OutputSize.xy) + _5767.xx;
        float _5776 = _5767 * param_CRT_CORNER_SMOOTHNESS;
        _6894 = smoothstep(1.0f, 0.0f, (((length(max(_5797, 0.0f.xx)) + min(max(_5797.x, _5797.y), 0.0f)) - _5767) * (1.0f / _5776)) + (1.0f - sqrt(0.5f / _5776)));
        break;
    } while(false);
    float _6900;
    do
    {
        if (int(param_COLOR_COMPENSATION) == 0)
        {
            _6900 = 0.0f;
            break;
        }
        float _5885 = 1.0f - param_MASK_BLEND;
        _6900 = lerp(BrightnessCompensation, BrightnessCompensation * (1.0f - _4600), 1.0f - (_5885 * _5885));
        break;
    } while(false);
    float3 _5926 = (((_6827 * _6891) * _6894) * (1.0f + _6900)) * (1.0f + clamp(param_COLOR_BRIGHTNESS * _2450, -1.0f, 4.0f));
    float _5941 = clamp(param_COLOR_CONTRAST * _2450, -1.0f, 2.0f);
    float3 _6902;
    do
    {
        if (_5941 == 0.0f)
        {
            _6902 = _5926;
            break;
        }
        float _5959 = clamp(max(max(_5926.x, _5926.y), _5926.z), 0.0f, 1.0f);
        _6902 = _5926 * (lerp(_5959, (sin(((_5959 * 2.0f) - 1.0f) * 1.5707962512969970703125f) + 1.0f) * 0.5f, _5941) / (_5959 + 9.9999997473787516355514526367188e-06f));
        break;
    } while(false);
    float _6008 = clamp((param_COLOR_TEMPERATUE * (-1.0f)) * _2450, -1.0f, 1.0f);
    float3 _6906;
    do
    {
        if (_6008 == 0.0f)
        {
            _6906 = _6902;
            break;
        }
        float3x3 _6903;
        if (_6008 < 0.0f)
        {
            _6903 = float3x3(float3(1.04668915271759033203125f, 0.056597299873828887939453125f, -0.02677500061690807342529296875f), float3(-0.006178599782288074493408203125f, 0.9779288768768310546875f, 0.0521964989602565765380859375f), float3(-0.055953301489353179931640625f, -0.0360764004290103912353515625f, 0.841718494892120361328125f));
        }
        else
        {
            _6903 = float3x3(float3(0.969639599323272705078125f, -0.0362020991742610931396484375f, 0.0240234993398189544677734375f), float3(0.001201599952764809131622314453125f, 1.01146495342254638671875f, -0.044550500810146331787109375f), float3(0.044388599693775177001953125f, 0.02780899964272975921630859375f, 1.129950046539306640625f));
        }
        _6906 = lerp(_6902, mul(_6903, _6902), abs(_6008).xxx);
        break;
    } while(false);
    float _6051 = clamp(1.0f + ((param_COLOR_SATURATION - 1.0f) * _2450), 0.0f, 2.0f);
    float3 _6907;
    do
    {
        if (_6051 == 1.0f)
        {
            _6907 = _6906;
            break;
        }
        _6907 = lerp(dot(_6906, float3(0.2125999927520751953125f, 0.715200006961822509765625f, 0.072200000286102294921875f)).xxx, _6906, _6051.xxx);
        break;
    } while(false);
    float _6908;
    if (_6907.x <= 0.0031306999735534191131591796875f)
    {
        _6908 = _6907.x * 12.9200000762939453125f;
    }
    else
    {
        _6908 = (1.05499994754791259765625f * pow(_6907.x, 0.4166666567325592041015625f)) - 0.054999999701976776123046875f;
    }
    float _6910;
    if (_6907.y <= 0.0031306999735534191131591796875f)
    {
        _6910 = _6907.y * 12.9200000762939453125f;
    }
    else
    {
        _6910 = (1.05499994754791259765625f * pow(_6907.y, 0.4166666567325592041015625f)) - 0.054999999701976776123046875f;
    }
    float _6912;
    if (_6907.z <= 0.0031306999735534191131591796875f)
    {
        _6912 = _6907.z * 12.9200000762939453125f;
    }
    else
    {
        _6912 = (1.05499994754791259765625f * pow(_6907.z, 0.4166666567325592041015625f)) - 0.054999999701976776123046875f;
    }
    FragColor = float4(_6908, _6910, _6912, 1.0f);
}

SPIRV_Cross_Output main(SPIRV_Cross_Input stage_input)
{
    BrightnessCompensation = stage_input.BrightnessCompensation;
    FloorProfile = stage_input.FloorProfile;
    ScreenOrientation = stage_input.ScreenOrientation;
    BeamProfile = stage_input.BeamProfile;
    AntiRining = stage_input.AntiRining;
    ScreenMultipleProfile = stage_input.ScreenMultipleProfile;
    FrameCounts = stage_input.FrameCounts;
    BeamFilter = stage_input.BeamFilter;
    MaskProfile = stage_input.MaskProfile;
    TexSize = stage_input.TexSize;
    TexCoord = stage_input.TexCoord;
    ScanTexCoord = stage_input.ScanTexCoord;
    frag_main();
    SPIRV_Cross_Output stage_output;
    stage_output.FragColor = FragColor;
    return stage_output;
}
