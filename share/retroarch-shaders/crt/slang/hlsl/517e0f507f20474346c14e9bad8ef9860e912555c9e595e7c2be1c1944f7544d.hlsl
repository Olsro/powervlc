// Generated from crt/shaders/crt-consumer.slang. See slang/upstream for licence/source.
cbuffer UBO : register(b0)
{
    float global_blurx : packoffset(c4);
    float global_blury : packoffset(c4.y);
    float global_warpx : packoffset(c4.z);
    float global_warpy : packoffset(c4.w);
    float global_corner : packoffset(c5);
    float global_smoothness : packoffset(c5.y);
    float global_scanlow : packoffset(c5.z);
    float global_scanhigh : packoffset(c5.w);
    float global_beamlow : packoffset(c6);
    float global_beamhigh : packoffset(c6.y);
    float global_brightboost1 : packoffset(c6.z);
    float global_brightboost2 : packoffset(c6.w);
    float global_Shadowmask : packoffset(c7);
    float global_masksize : packoffset(c7.y);
    float global_MaskDark : packoffset(c7.z);
    float global_MaskLight : packoffset(c7.w);
    float global_slotmask : packoffset(c8);
    float global_slotwidth : packoffset(c8.y);
    float global_double_slot : packoffset(c8.z);
    float global_slotms : packoffset(c8.w);
    float global_GAMMA_OUT : packoffset(c9);
    float global_glow : packoffset(c9.y);
    float global_glow_str : packoffset(c9.z);
    float global_sat : packoffset(c9.w);
    float global_contrast : packoffset(c10);
    float global_nois : packoffset(c10.y);
    float global_WP : packoffset(c10.z);
    float global_inter : packoffset(c10.w);
    float global_vignette : packoffset(c11);
    float global_vpower : packoffset(c11.y);
    float global_vstr : packoffset(c11.z);
    float global_alloff : packoffset(c11.w);
    float global_postbr : packoffset(c12);
    float global_PRE_SCALE : packoffset(c12.y);
    float global_preserve : packoffset(c12.z);
};

cbuffer Push : register(b1)
{
    float4 params_SourceSize : packoffset(c0);
    float4 params_OutputSize : packoffset(c1);
    uint params_FrameCount : packoffset(c2);
    float params_rg : packoffset(c2.y);
    float params_rb : packoffset(c2.z);
    float params_gr : packoffset(c2.w);
    float params_gb : packoffset(c3);
    float params_br : packoffset(c3.y);
    float params_bg : packoffset(c3.z);
    float params_Downscale : packoffset(c3.w);
    float params_quality : packoffset(c4);
    float params_palette_fix : packoffset(c4.y);
};

Texture2D<float4> Source : register(t2);
SamplerState _Source_sampler : register(s2);

static float2 vTexCoord;
static float4 FragColor;

struct SPIRV_Cross_Input
{
    float2 vTexCoord : TEXCOORD0;
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
    float2 _1593 = (vTexCoord * 2.0f) - 1.0f.xx;
    float _1595 = _1593.y;
    float _1604 = _1593.x;
    float2 _1618 = ((_1593 * float2(1.0f + ((_1595 * _1595) * global_warpx), 1.0f + ((_1604 * _1604) * global_warpy))) * 0.5f) + 0.5f.xx;
    float2 _1040 = _1618 + (0.5f.xx / params_SourceSize.xy);
    float2 _1044 = _1618 * params_SourceSize.xy;
    float2 _1045 = frac(_1044);
    bool _1049 = global_inter < 0.5f;
    bool _1056;
    if (_1049)
    {
        _1056 = params_SourceSize.y > 400.0f;
    }
    else
    {
        _1056 = _1049;
    }
    float2 _2821;
    if (_1056)
    {
        float2 _2690 = _1045;
        _2690.y = frac((_1618.y * params_SourceSize.y) / params_Downscale);
        _2821 = _2690;
    }
    else
    {
        _2821 = _1045;
    }
    float4 _2892;
    if (global_alloff == 1.0f)
    {
        _2892 = Source.Sample(_Source_sampler, _1040);
    }
    else
    {
        float _1096 = 0.5f / global_PRE_SCALE;
        float2 _1101 = _2821 - 0.5f.xx;
        float2 _1125 = (floor(_1044) + (((_1101 - clamp(_1101, (_1096 - 0.5f).xx, (0.5f - _1096).xx)) * global_PRE_SCALE) + 0.5f.xx)) / params_SourceSize.xy;
        float _1129 = _1125.x;
        float _1135 = global_blurx * params_SourceSize.z;
        float _1138 = _1125.y;
        float _1144 = global_blury * params_SourceSize.w;
        float4 _1147 = Source.Sample(_Source_sampler, float2(_1129 + _1135, _1138 - _1144));
        float4 _1152 = Source.Sample(_Source_sampler, _1125);
        float4 _1173 = Source.Sample(_Source_sampler, float2(_1129 - _1135, _1138 + _1144));
        float3 _1201 = float3(0.5f * (_1147.x + _1152.x), ((_1147.y * 0.25f) + (_1152.y * 0.5f)) + (_1173.y * 0.25f), 0.5f * (_1152.z + _1173.z));
        float3 _2822;
        if (params_palette_fix != 0.0f)
        {
            float3 _2823;
            if (params_palette_fix == 1.0f)
            {
                _2823 = _1201 * 1.066699981689453125f;
            }
            else
            {
                float3 _2824;
                if (params_palette_fix == 2.0f)
                {
                    _2824 = _1201 * 2.0f;
                }
                else
                {
                    _2824 = _1201;
                }
                _2823 = _2824;
            }
            _2822 = _2823;
        }
        else
        {
            _2822 = _1201;
        }
        float3 _2825;
        if (global_WP != 0.0f)
        {
            float3 _1260 = mul(mul(_2822, float3x3(float3(0.4552772939205169677734375f, 0.23230250179767608642578125f, 0.01454569958150386810302734375f), float3(0.3675499856472015380859375f, 0.707795619964599609375f, 0.104915402829647064208984375f), float3(0.14139260351657867431640625f, 0.059901900589466094970703125f, 0.70574891567230224609375f))), float3x3(float3(3.062897205352783203125f, -0.969265997409820556640625f, 0.0678775012493133544921875f), float3(-1.39317905902862548828125f, 1.87601077556610107421875f, -0.2288548052310943603515625f), float3(-0.475751698017120361328125f, 0.04155600070953369140625f, 1.0693490505218505859375f)));
            float3 _1291 = mul(mul(_2822, float3x3(float3(0.4306190013885498046875f, 0.22203789651393890380859375f, 0.020185299217700958251953125f), float3(0.34154188632965087890625f, 0.706638395786285400390625f, 0.129550397396087646484375f), float3(0.17830909788608551025390625f, 0.0713236033916473388671875f, 0.93909442424774169921875f))), float3x3(float3(2.960394382476806640625f, -0.978768408298492431640625f, 0.084487400949001312255859375f), float3(-1.4678518772125244140625f, 1.916141510009765625f, -0.25459730625152587890625f), float3(-0.46851050853729248046875f, 0.033454000949859619140625f, 1.42161738872528076171875f)));
            bool3 _1305 = (global_WP < 0.0f).xxx;
            _2825 = lerp(_2822, clamp(float3(_1305.x ? _1291.x : _1260.x, _1305.y ? _1291.y : _1260.y, _1305.z ? _1291.z : _1260.z), 0.0f.xxx, 1.0f.xxx), (abs(global_WP) * 0.00999999977648258209228515625f).xxx);
        }
        else
        {
            _2825 = _2822;
        }
        float3 _1336 = mul(_2825, float3x3(float3(1.0f, params_rg, params_rb), float3(params_gr, 1.0f, params_gb), float3(params_br, params_bg, 1.0f)));
        float3 _1346 = (pow(_1336, 2.7999999523162841796875f.xxx) * 2.0f) - pow(_1336, 3.599999904632568359375f.xxx);
        float _1360 = ((_1346.x * 0.300000011920928955078125f) + (_1346.y * 0.60000002384185791015625f)) + (_1346.z * 0.100000001490116119384765625f);
        float _1365 = frac(_2821.y - 0.5f);
        bool _1368 = global_inter > 0.5f;
        bool _1374;
        if (_1368)
        {
            _1374 = params_SourceSize.y > 400.0f;
        }
        else
        {
            _1374 = _1368;
        }
        float3 _2831;
        if (_1374)
        {
            _2831 = _1346;
        }
        else
        {
            float _1635 = lerp(global_beamlow, global_beamhigh, _1360);
            float _1638 = _1365 * _1635;
            float _1388 = 1.0f - _1365;
            float _1665 = _1388 * _1635;
            _2831 = (_1346 * exp2(((-lerp(global_scanlow, global_scanhigh, _1365)) * _1638) * _1638)) + (_1346 * exp2(((-lerp(global_scanlow, global_scanhigh, _1388)) * _1665) * _1665));
        }
        float _1406 = ((_2831.x * 0.300000011920928955078125f) + (_2831.y * 0.60000002384185791015625f)) + (_2831.z * 0.100000001490116119384765625f);
        float2 _1411 = vTexCoord * params_OutputSize.xy;
        float3 _2522;
        do
        {
            float2 _1701 = floor(_1411 / global_masksize.xx);
            if (global_Shadowmask == 0.0f)
            {
                if (frac(_1701.x * 0.4999000132083892822265625f) < 0.4999000132083892822265625f)
                {
                    _2522 = float3(1.0f, global_MaskDark, 1.0f);
                    break;
                }
                else
                {
                    _2522 = float3(global_MaskDark, 1.0f, global_MaskDark);
                    break;
                }
                break; // unreachable workaround
            }
            else
            {
                if (global_Shadowmask == 1.0f)
                {
                    float3 _1734 = global_MaskDark.xxx;
                    float _1738 = _1701.x;
                    float _2519;
                    if (frac((_1701.y + float(frac(_1738 * 0.16666667163372039794921875f) < 0.5f)) * 0.5f) < 0.5f)
                    {
                        _2519 = global_MaskDark;
                    }
                    else
                    {
                        _2519 = global_MaskLight;
                    }
                    float _1758 = frac(_1738 * 0.3333333432674407958984375f);
                    float3 _2853;
                    if (_1758 < 0.333000004291534423828125f)
                    {
                        float3 _2719 = _1734;
                        _2719.z = global_MaskLight;
                        _2853 = _2719;
                    }
                    else
                    {
                        float3 _2854;
                        if (_1758 < 0.66600000858306884765625f)
                        {
                            float3 _2717 = _1734;
                            _2717.y = global_MaskLight;
                            _2854 = _2717;
                        }
                        else
                        {
                            float3 _2715 = _1734;
                            _2715.x = global_MaskLight;
                            _2854 = _2715;
                        }
                        _2853 = _2854;
                    }
                    _2522 = _2853 * _2519;
                    break;
                }
                else
                {
                    if (global_Shadowmask == 2.0f)
                    {
                        float _1790 = frac(_1701.x * 0.33329999446868896484375f);
                        if (_1790 < 0.33329999446868896484375f)
                        {
                            _2522 = float3(global_MaskDark, global_MaskDark, global_MaskLight);
                            break;
                        }
                        if (_1790 < 0.6665999889373779296875f)
                        {
                            _2522 = float3(global_MaskDark, global_MaskLight, global_MaskDark);
                            break;
                        }
                        else
                        {
                            _2522 = float3(global_MaskLight, global_MaskDark, global_MaskDark);
                            break;
                        }
                        break; // unreachable workaround
                    }
                }
            }
            if (global_Shadowmask == 3.0f)
            {
                if (frac(_1701.x * 0.5f) < 0.5f)
                {
                    _2522 = 1.0f.xxx;
                    break;
                }
                else
                {
                    _2522 = global_MaskDark.xxx;
                    break;
                }
                break; // unreachable workaround
            }
            else
            {
                if (global_Shadowmask == 4.0f)
                {
                    float _1853 = _1701.x;
                    float _2515;
                    if (frac((_1701.y + float(frac(_1853 * 0.25f) < 0.5f)) * 0.5f) < 0.5f)
                    {
                        _2515 = global_MaskDark;
                    }
                    else
                    {
                        _2515 = global_MaskLight;
                    }
                    float3 _2850;
                    if (frac(_1853 * 0.5f) < 0.5f)
                    {
                        float3 _2768 = _2831;
                        _2768.x = 1.0f;
                        _2768.z = 1.0f;
                        _2850 = _2768;
                    }
                    else
                    {
                        float3 _2766 = _2831;
                        _2766.y = 1.0f;
                        _2850 = _2766;
                    }
                    _2522 = _2850 * _2515;
                    break;
                }
                else
                {
                    if (global_Shadowmask == 5.0f)
                    {
                        float _1892 = _1701.x;
                        float _1894 = frac(_1892 * 0.25f);
                        float3 _2507;
                        if (_1894 < 0.5f)
                        {
                            float3 _2508;
                            if (frac(_1701.y * 0.3333333432674407958984375f) < 0.66600000858306884765625f)
                            {
                                float3 _2509;
                                if (frac(_1892 * 0.5f) < 0.5f)
                                {
                                    _2509 = float3(1.0f, global_MaskDark, 1.0f);
                                }
                                else
                                {
                                    _2509 = float3(global_MaskDark, 1.0f, global_MaskDark);
                                }
                                _2508 = _2509;
                            }
                            else
                            {
                                _2508 = 1.0f.xxx * _1406;
                            }
                            _2507 = _2508;
                        }
                        else
                        {
                            float3 _2510;
                            if (_1894 >= 0.5f)
                            {
                                float3 _2511;
                                if (frac(_1701.y * 0.3333333432674407958984375f) > 0.333000004291534423828125f)
                                {
                                    float3 _2512;
                                    if (frac(_1892 * 0.5f) < 0.5f)
                                    {
                                        _2512 = float3(1.0f, global_MaskDark, 1.0f);
                                    }
                                    else
                                    {
                                        _2512 = float3(global_MaskDark, 1.0f, global_MaskDark);
                                    }
                                    _2511 = _2512;
                                }
                                else
                                {
                                    _2511 = 1.0f.xxx * _1406;
                                }
                                _2510 = _2511;
                            }
                            else
                            {
                                _2510 = 1.0f.xxx;
                            }
                            _2507 = _2510;
                        }
                        _2522 = _2507;
                        break;
                    }
                    else
                    {
                        if (global_Shadowmask == 6.0f)
                        {
                            float3 _1972 = global_MaskDark.xxx;
                            float _1974 = _1701.x;
                            float _1976 = frac(_1974 * 0.16666667163372039794921875f);
                            float3 _2840;
                            if (_1976 < 0.5f)
                            {
                                float3 _2845;
                                if (frac(_1701.y * 0.25f) < 0.75f)
                                {
                                    float _1988 = frac(_1974 * 0.3333333432674407958984375f);
                                    float3 _2846;
                                    if (_1988 < 0.33329999446868896484375f)
                                    {
                                        float3 _2755 = _1972;
                                        _2755.x = global_MaskLight;
                                        _2846 = _2755;
                                    }
                                    else
                                    {
                                        float3 _2847;
                                        if (_1988 < 0.6665999889373779296875f)
                                        {
                                            float3 _2753 = _1972;
                                            _2753.y = global_MaskLight;
                                            _2847 = _2753;
                                        }
                                        else
                                        {
                                            float3 _2751 = _1972;
                                            _2751.z = global_MaskLight;
                                            _2847 = _2751;
                                        }
                                        _2846 = _2847;
                                    }
                                    _2845 = _2846;
                                }
                                else
                                {
                                    _2845 = _1972;
                                }
                                _2840 = _2845;
                            }
                            else
                            {
                                float3 _2841;
                                if (_1976 >= 0.5f)
                                {
                                    float _2026 = frac(_1701.y * 0.25f);
                                    bool _2027 = _2026 >= 0.5f;
                                    bool _2036;
                                    if (!_2027)
                                    {
                                        _2036 = _2026 < 0.25f;
                                    }
                                    else
                                    {
                                        _2036 = _2027;
                                    }
                                    float3 _2842;
                                    if (_2036)
                                    {
                                        float _2041 = frac(_1974 * 0.3333333432674407958984375f);
                                        float3 _2843;
                                        if (_2041 < 0.33329999446868896484375f)
                                        {
                                            float3 _2746 = _1972;
                                            _2746.x = global_MaskLight;
                                            _2843 = _2746;
                                        }
                                        else
                                        {
                                            float3 _2844;
                                            if (_2041 < 0.6665999889373779296875f)
                                            {
                                                float3 _2744 = _1972;
                                                _2744.y = global_MaskLight;
                                                _2844 = _2744;
                                            }
                                            else
                                            {
                                                float3 _2742 = _1972;
                                                _2742.z = global_MaskLight;
                                                _2844 = _2742;
                                            }
                                            _2843 = _2844;
                                        }
                                        _2842 = _2843;
                                    }
                                    else
                                    {
                                        _2842 = _1972;
                                    }
                                    _2841 = _2842;
                                }
                                else
                                {
                                    _2841 = _1972;
                                }
                                _2840 = _2841;
                            }
                            _2522 = _2840;
                            break;
                        }
                        else
                        {
                            if (global_Shadowmask == 7.0f)
                            {
                                float _2080 = frac(_1701.x * 0.33329999446868896484375f);
                                if (_2080 < 0.33329999446868896484375f)
                                {
                                    _2522 = float3(global_MaskDark, global_MaskLight, global_MaskLight * _2831.z);
                                    break;
                                }
                                if (_2080 < 0.6665999889373779296875f)
                                {
                                    _2522 = float3(global_MaskLight * _2831.x, global_MaskDark, global_MaskLight);
                                    break;
                                }
                                else
                                {
                                    _2522 = float3(global_MaskLight, global_MaskLight * _2831.y, global_MaskDark);
                                    break;
                                }
                                break; // unreachable workaround
                            }
                            else
                            {
                                if (global_Shadowmask == 8.0f)
                                {
                                    float3 _2131 = global_MaskDark.xxx;
                                    float _2135 = _1701.x;
                                    bool _2138 = frac(_2135 * 0.16666667163372039794921875f) < 0.5f;
                                    float _2144 = frac(_2135 * 0.3333333432674407958984375f);
                                    float3 _2835;
                                    if (_2144 < 0.333000004291534423828125f)
                                    {
                                        float3 _2728 = _2131;
                                        _2728.z = 0.89999997615814208984375f;
                                        _2835 = _2728;
                                    }
                                    else
                                    {
                                        float3 _2836;
                                        if (_2144 < 0.66600000858306884765625f)
                                        {
                                            float3 _2726 = _2131;
                                            _2726.y = 0.89999997615814208984375f;
                                            _2836 = _2726;
                                        }
                                        else
                                        {
                                            float3 _2724 = _2131;
                                            _2724.x = 0.89999997615814208984375f;
                                            _2836 = _2724;
                                        }
                                        _2835 = _2836;
                                    }
                                    float _2160 = mod(_1701.y, 2.0f);
                                    bool _2164 = (_2160 == 1.0f) && _2138;
                                    bool _2175;
                                    if (!_2164)
                                    {
                                        _2175 = (_2160 == 0.0f) && (!_2138);
                                    }
                                    else
                                    {
                                        _2175 = _2164;
                                    }
                                    float3 _2837;
                                    if (_2175)
                                    {
                                        _2837 = _2835 * global_MaskLight;
                                    }
                                    else
                                    {
                                        _2837 = _2835;
                                    }
                                    _2522 = _2837;
                                    break;
                                }
                                else
                                {
                                    _2522 = 1.0f.xxx;
                                    break;
                                }
                                break; // unreachable workaround
                            }
                            break; // unreachable workaround
                        }
                        break; // unreachable workaround
                    }
                    break; // unreachable workaround
                }
                break; // unreachable workaround
            }
            break; // unreachable workaround
        } while(false);
        float3 _1426 = _2831 * lerp(_2522, 1.0f.xxx, (_1406 * global_preserve).xxx);
        float3 _2882;
        if (global_slotmask != 0.0f)
        {
            float _2553;
            do
            {
                if (global_slotmask == 0.0f)
                {
                    _2553 = 1.0f;
                    break;
                }
                float2 _2212 = floor((_1411 * 1.00010001659393310546875f) / global_slotms.xx);
                float _2221 = pow(max(max(_1426.x, _1426.y), _1426.z), 1.33000004291534423828125f);
                float _2229 = frac(_2212.x / (global_slotwidth * 2.0f));
                float _2241 = floor((frac(_2212.y / (2.0f * global_double_slot)) * 2.0f) * global_double_slot);
                float _2250 = lerp(1.0f - global_slotmask, 1.0f - (0.800000011920928955078125f * global_slotmask), _2221);
                float _2551;
                if ((_2241 == 0.0f) && (_2229 < 0.5f))
                {
                    _2551 = _2250;
                }
                else
                {
                    _2551 = ((_2241 == global_double_slot) && (_2229 >= 0.5f)) ? _2250 : (1.0f + ((0.699999988079071044921875f * global_slotmask) * (1.0f - _2221)));
                }
                _2553 = _2551;
                break;
            } while(false);
            _2882 = _1426 * _2553;
        }
        else
        {
            _2882 = _1426;
        }
        float3 _1467 = pow(_2882 * lerp(global_brightboost1, global_brightboost2, max(max(_2882.x, _2882.y), _2882.z)), (1.0f / global_GAMMA_OUT).xxx);
        float3 _2884;
        if (global_glow_str != 0.0f)
        {
            float2 _2295 = params_SourceSize.zw / params_quality.xx;
            float _2298 = -global_glow;
            float _2554;
            float3 _2555;
            _2555 = 0.0f.xxx;
            _2554 = _2298;
            float3 _2653;
            for (; _2554 <= global_glow; _2555 = _2653, _2554 += 1.0f)
            {
                float _2308 = 1.0f / global_glow;
                _2653 = _2555;
                for (float _2646 = _2298; _2646 <= global_glow; )
                {
                    float3 _2331 = Source.Sample(_Source_sampler, _1125 + (float2(_2554, _2646) * _2295)).xyz * _2308;
                    _2653 += (_2331 * _2331);
                    _2646 += 1.0f;
                    continue;
                }
            }
            _2884 = _1467 + ((_2555 * global_glow_str) / (global_glow * global_glow).xxx);
        }
        else
        {
            _2884 = _1467;
        }
        float3 _2885;
        if (global_sat != 1.0f)
        {
            bool3 _2675 = ((length(_2884) * 0.57749998569488525390625f) < 0.5f).xxx;
            _2885 = lerp(dot(_2884, float3(_2675.x ? float3(0.3200000226497650146484375f, 0.5f, 0.02000000141561031341552734375f).x : float3(0.4000000059604644775390625f, 0.5f, 0.100000001490116119384765625f).x, _2675.y ? float3(0.3200000226497650146484375f, 0.5f, 0.02000000141561031341552734375f).y : float3(0.4000000059604644775390625f, 0.5f, 0.100000001490116119384765625f).y, _2675.z ? float3(0.3200000226497650146484375f, 0.5f, 0.02000000141561031341552734375f).z : float3(0.4000000059604644775390625f, 0.5f, 0.100000001490116119384765625f).z)).xxx, _2884, global_sat.xxx);
        }
        else
        {
            _2885 = _2884;
        }
        float3 _2886;
        if (global_corner != 0.0f)
        {
            float2 _2395 = (_1040 - 0.5f.xx) * 1.0f;
            float2 _2412 = global_corner.xx;
            float2 _2417 = _2412 - min(min(_2395 + 0.5f.xx, 0.5f.xx - _2395) * float2(1.0f, params_SourceSize.y / params_SourceSize.x), _2412);
            _2886 = _2885 * clamp((global_corner - sqrt(dot(_2417, _2417))) * global_smoothness, 0.0f, 1.0f);
        }
        else
        {
            _2886 = _2885;
        }
        float3 _2887;
        if (global_nois != 0.0f)
        {
            _2887 = _2886 * (1.0f + (frac(sin((float(params_FrameCount) * 0.01666666753590106964111328125f) * dot(_1125 * 2.0f, float2(12.98980045318603515625f, 78.233001708984375f))) * 43758.546875f) / global_nois));
        }
        else
        {
            _2887 = _2886;
        }
        float4 _1525 = float4(_2887 * lerp(1.0f, global_postbr, _1360), 1.0f);
        float4 _2890;
        if (global_contrast != 1.0f)
        {
            float _2449 = (1.0f - global_contrast) * 0.5f;
            _2890 = mul(_1525, float4x4(float4(global_contrast, 0.0f, 0.0f, 0.0f), float4(0.0f, global_contrast, 0.0f, 0.0f), float4(0.0f, 0.0f, global_contrast, 0.0f), float4(_2449, _2449, _2449, 1.0f)));
        }
        else
        {
            _2890 = _1525;
        }
        bool _1545;
        if (_1368)
        {
            _1545 = params_SourceSize.y > 400.0f;
        }
        else
        {
            _1545 = _1368;
        }
        bool _1554;
        if (_1545)
        {
            _1554 = frac(float(params_FrameCount) * 0.5f) < 0.5f;
        }
        else
        {
            _1554 = _1545;
        }
        float4 _2891;
        if (_1554)
        {
            _2891 = _2890 * 0.949999988079071044921875f;
        }
        else
        {
            _2891 = _2890;
        }
        float2 _2471 = vTexCoord * (1.0f.xx - vTexCoord);
        float _2677 = (global_vignette == 0.0f) ? 1.0f : min(pow((_2471.x * _2471.y) * global_vstr, global_vpower), 1.0f);
        float3 _1565 = mul(float3x3(float3(_2677, 0.0f, 0.0f), float3(0.0f, _2677, 0.0f), float3(0.0f, 0.0f, _2677)), _2891.xyz);
        float4 _2784 = _2891;
        _2784.x = _1565.x;
        _2784.y = _1565.y;
        _2784.z = _1565.z;
        _2892 = _2784;
    }
    FragColor = _2892;
}

SPIRV_Cross_Output main(SPIRV_Cross_Input stage_input)
{
    vTexCoord = stage_input.vTexCoord;
    frag_main();
    SPIRV_Cross_Output stage_output;
    stage_output.FragColor = FragColor;
    return stage_output;
}
