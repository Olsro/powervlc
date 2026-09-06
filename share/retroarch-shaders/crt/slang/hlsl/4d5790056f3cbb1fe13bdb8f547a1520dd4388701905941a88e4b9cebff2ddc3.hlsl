// Generated from crt/shaders/crt-gdv-mini-ultra.slang. See slang/upstream for licence/source.
cbuffer UBO : register(b0)
{
    float4 global_OutputSize : packoffset(c5);
    float4 global_SourceSize : packoffset(c6);
    float4 global_OriginalSize : packoffset(c7);
};

cbuffer Push : register(b1)
{
    float params_brightboost : packoffset(c0);
    float params_sat : packoffset(c0.y);
    float params_glow : packoffset(c0.z);
    float params_scanline : packoffset(c1);
    float params_beam_min : packoffset(c1.y);
    float params_beam_max : packoffset(c1.z);
    float params_h_sharp : packoffset(c1.w);
    float params_shadowMask : packoffset(c2);
    float params_masksize : packoffset(c2.y);
    float params_mcut : packoffset(c2.z);
    float params_maskDark : packoffset(c2.w);
    float params_maskLight : packoffset(c3);
    float params_CGWG : packoffset(c3.y);
    float params_warpX : packoffset(c3.w);
    float params_warpY : packoffset(c4);
    float params_gamma_out_red : packoffset(c4.y);
    float params_gamma_out_green : packoffset(c4.z);
    float params_gamma_out_blue : packoffset(c4.w);
    float params_vignette : packoffset(c5);
    float params_gdv_mono : packoffset(c5.y);
    float params_gdv_R : packoffset(c5.z);
    float params_gdv_G : packoffset(c5.w);
    float params_gdv_B : packoffset(c6);
    float params_thres : packoffset(c6.y);
};

Texture2D<float4> Source : register(t1);
SamplerState _Source_sampler : register(s1);

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
    float2 _1678;
    float _1680;
    float3 _1685;
    float _1687;
    bool _1688;
    float2 _1617 = (vTexCoord * 2.0f) - 1.0f.xx;
    float _1619 = _1617.y;
    float _1628 = _1617.x;
    float2 _1312 = (((_1617 * float2(1.0f + ((_1619 * _1619) * params_warpX), 1.0f + ((_1628 * _1628) * params_warpY))) * 0.5f) + 0.5f.xx) * global_SourceSize.xy;
    float2 _1315 = frac(_1312);
    float2 _1331 = (floor(_1312) * global_SourceSize.zw) + (global_SourceSize.zw * 0.5f);
    float4 _1335 = Source.Sample(_Source_sampler, _1331);
    float4 _1342 = Source.Sample(_Source_sampler, _1331 + float2(global_SourceSize.z, 0.0f));
    float4 _1349 = Source.Sample(_Source_sampler, _1331 + float2(0.0f, global_SourceSize.w));
    float4 _1356 = Source.Sample(_Source_sampler, _1331 + global_SourceSize.zw);
    float _1360 = _1315.x;
    float _1365 = pow(_1360, params_h_sharp);
    float _1373 = pow(1.0f - _1360, params_h_sharp);
    float3 _1385 = (_1365 + _1373).xxx;
    float3 _1386 = ((_1342.xyz * _1365) + (_1335.xyz * _1373)) / _1385;
    float3 _1399 = ((_1356.xyz * _1365) + (_1349.xyz * _1373)) / _1385;
    float _1402 = _1315.y;
    float _1414 = ((_1386.x * 0.300000011920928955078125f) + (_1386.y * 0.60000002384185791015625f)) + (_1386.z * 0.100000001490116119384765625f);
    float _1426 = ((_1399.x * 0.300000011920928955078125f) + (_1399.y * 0.60000002384185791015625f)) + (_1399.z * 0.100000001490116119384765625f);
    float3 _1436 = (pow(_1386, 2.7999999523162841796875f.xxx) * 2.0f) - pow(_1386, 3.599999904632568359375f.xxx);
    float3 _1442 = (pow(_1399, 2.7999999523162841796875f.xxx) * 2.0f) - pow(_1399, 3.599999904632568359375f.xxx);
    float3 _3458;
    do
    {
        _1678 = floor((vTexCoord * global_OutputSize.xy) / params_masksize.xx);
        _1680 = params_maskDark;
        _1685 = _1680.xxx;
        _1687 = params_shadowMask;
        _1688 = _1687 == (-1.0f);
        float3 _4268;
        if (_1688)
        {
            _4268 = 1.0f.xxx;
        }
        else
        {
            float3 _4269;
            if (_1687 == 0.0f)
            {
                float _1702 = 1.0f - params_CGWG;
                float3 _4270;
                if (frac(_1678.x * 0.5f) < 0.5f)
                {
                    _4270 = float3(1.10000002384185791015625f, _1702, 1.10000002384185791015625f);
                }
                else
                {
                    _4270 = float3(_1702, 1.10000002384185791015625f, _1702);
                }
                _4269 = _4270;
            }
            else
            {
                float3 _4271;
                if (_1687 == 1.0f)
                {
                    float _3455;
                    if (frac((_1678.y + float(frac(_1678.x * 0.16666667163372039794921875f) < 0.5f)) * 0.5f) < 0.5f)
                    {
                        _3455 = _1680;
                    }
                    else
                    {
                        _3455 = params_maskLight;
                    }
                    float _1746 = frac(_1678.x * 0.3333333432674407958984375f);
                    float3 _4266;
                    if (_1746 < 0.333000004291534423828125f)
                    {
                        float3 _3891 = _1685;
                        _3891.z = params_maskLight;
                        _4266 = _3891;
                    }
                    else
                    {
                        float3 _4267;
                        if (_1746 < 0.66600000858306884765625f)
                        {
                            float3 _3894 = _1685;
                            _3894.y = params_maskLight;
                            _4267 = _3894;
                        }
                        else
                        {
                            float3 _3896 = _1685;
                            _3896.x = params_maskLight;
                            _4267 = _3896;
                        }
                        _4266 = _4267;
                    }
                    _4271 = _4266 * _3455;
                }
                else
                {
                    float3 _4272;
                    if (_1687 == 2.0f)
                    {
                        float _1780 = frac(_1678.x * 0.3333333432674407958984375f);
                        float3 _4273;
                        if (_1780 < 0.333000004291534423828125f)
                        {
                            float3 _3902 = _1685;
                            _3902.z = params_maskLight;
                            _4273 = _3902;
                        }
                        else
                        {
                            float3 _4274;
                            if (_1780 < 0.66600000858306884765625f)
                            {
                                float3 _3905 = _1685;
                                _3905.y = params_maskLight;
                                _4274 = _3905;
                            }
                            else
                            {
                                float3 _3907 = _1685;
                                _3907.x = params_maskLight;
                                _4274 = _3907;
                            }
                            _4273 = _4274;
                        }
                        _4272 = _4273;
                    }
                    else
                    {
                        float3 _4275;
                        if (_1687 == 3.0f)
                        {
                            float _1818 = frac((_1678.x + (_1678.y * 3.0f)) * 0.16666667163372039794921875f);
                            float3 _4276;
                            if (_1818 < 0.333000004291534423828125f)
                            {
                                float3 _3917 = _1685;
                                _3917.z = params_maskLight;
                                _4276 = _3917;
                            }
                            else
                            {
                                float3 _4277;
                                if (_1818 < 0.66600000858306884765625f)
                                {
                                    float3 _3920 = _1685;
                                    _3920.y = params_maskLight;
                                    _4277 = _3920;
                                }
                                else
                                {
                                    float3 _3922 = _1685;
                                    _3922.x = params_maskLight;
                                    _4277 = _3922;
                                }
                                _4276 = _4277;
                            }
                            _4275 = _4276;
                        }
                        else
                        {
                            float3 _4278;
                            if (_1687 == 4.0f)
                            {
                                float2 _1848 = floor(_1678 * float2(1.0f, 0.5f));
                                float _1859 = frac((_1848.x + (_1848.y * 3.0f)) * 0.16666667163372039794921875f);
                                float3 _4279;
                                if (_1859 < 0.333000004291534423828125f)
                                {
                                    float3 _3932 = _1685;
                                    _3932.z = params_maskLight;
                                    _4279 = _3932;
                                }
                                else
                                {
                                    float3 _4280;
                                    if (_1859 < 0.66600000858306884765625f)
                                    {
                                        float3 _3935 = _1685;
                                        _3935.y = params_maskLight;
                                        _4280 = _3935;
                                    }
                                    else
                                    {
                                        float3 _3937 = _1685;
                                        _3937.x = params_maskLight;
                                        _4280 = _3937;
                                    }
                                    _4279 = _4280;
                                }
                                _4278 = _4279;
                            }
                            else
                            {
                                float3 _4281;
                                if (_1687 == 5.0f)
                                {
                                    float _1894 = max(max(_1436.x, _1436.y), _1436.z);
                                    float3 _1915 = min((1.25f * max(_1894 - params_mcut, 0.0f)) / (1.0f - params_mcut), _1680 + ((0.20000000298023223876953125f * (1.0f - _1680)) * _1894)).xxx;
                                    float _1918 = 0.800000011920928955078125f * params_maskLight;
                                    float _1930 = (_1918 - ((0.5f * (_1918 - 1.0f)) * _1894)) + (0.75f * (1.0f - _1894));
                                    float3 _4282;
                                    if (frac(_1678.x * 0.5f) < 0.5f)
                                    {
                                        float3 _3946 = _1915;
                                        _3946.x = _1930;
                                        _3946.z = _1930;
                                        _4282 = _3946;
                                    }
                                    else
                                    {
                                        float3 _3950 = _1915;
                                        _3950.y = _1930;
                                        _4282 = _3950;
                                    }
                                    _4281 = _4282;
                                }
                                else
                                {
                                    float3 _4283;
                                    if (_1687 == 6.0f)
                                    {
                                        float _1961 = max(max(_1436.x, _1436.y), _1436.z);
                                        float3 _1982 = min((1.33000004291534423828125f * max(_1961 - params_mcut, 0.0f)) / (1.0f - params_mcut), _1680 + ((0.2249999940395355224609375f * (1.0f - _1680)) * _1961)).xxx;
                                        float _1985 = 0.800000011920928955078125f * params_maskLight;
                                        float _1997 = (_1985 - ((0.5f * (_1985 - 1.0f)) * _1961)) + (0.75f * (1.0f - _1961));
                                        float _2002 = frac(_1678.x * 0.3333333432674407958984375f);
                                        float3 _4284;
                                        if (_2002 < 0.333000004291534423828125f)
                                        {
                                            float3 _3959 = _1982;
                                            _3959.x = _1997;
                                            _4284 = _3959;
                                        }
                                        else
                                        {
                                            float3 _4285;
                                            if (_2002 < 0.66600000858306884765625f)
                                            {
                                                float3 _3962 = _1982;
                                                _3962.y = _1997;
                                                _4285 = _3962;
                                            }
                                            else
                                            {
                                                float3 _3964 = _1982;
                                                _3964.z = _1997;
                                                _4285 = _3964;
                                            }
                                            _4284 = _4285;
                                        }
                                        _4283 = _4284;
                                    }
                                    else
                                    {
                                        float3 _4286;
                                        if (_1687 == 7.0f)
                                        {
                                            float _2037 = max(max(_1436.x, _1436.y), _1436.z);
                                            float3 _4287;
                                            if (frac(_1678.x * 0.5f) < 0.5f)
                                            {
                                                _4287 = (1.0f + (0.60000002384185791015625f * (1.0f - _2037))).xxx;
                                            }
                                            else
                                            {
                                                _4287 = min((1.60000002384185791015625f * max(_2037 - params_mcut, 0.0f)) / (1.0f - params_mcut), 1.0f - params_CGWG).xxx;
                                            }
                                            _4286 = _4287;
                                        }
                                        else
                                        {
                                            float3 _4288;
                                            if (_1687 == 8.0f)
                                            {
                                                float _3451;
                                                if (frac((_1678.y + float(frac(_1678.x * 0.25f) < 0.5f)) * 0.5f) < 0.5f)
                                                {
                                                    _3451 = _1680;
                                                }
                                                else
                                                {
                                                    _3451 = params_maskLight;
                                                }
                                                float3 _4263;
                                                if (frac(_1678.x * 0.5f) < 0.5f)
                                                {
                                                    float3 _3979 = _1685;
                                                    _3979.x = params_maskLight;
                                                    _3979.z = params_maskLight;
                                                    _4263 = _3979;
                                                }
                                                else
                                                {
                                                    float3 _3983 = _1685;
                                                    _3983.y = params_maskLight;
                                                    _4263 = _3983;
                                                }
                                                _4288 = _4263 * _3451;
                                            }
                                            else
                                            {
                                                if (_1687 == 9.0f)
                                                {
                                                    bool _2129 = frac(_1678.x * 0.16666667163372039794921875f) < 0.5f;
                                                    float _2135 = frac(_1678.x * 0.3333333432674407958984375f);
                                                    float3 _4258;
                                                    if (_2135 < 0.33329999446868896484375f)
                                                    {
                                                        float3 _3987 = _1685;
                                                        _3987.z = 0.89999997615814208984375f;
                                                        _4258 = _3987;
                                                    }
                                                    else
                                                    {
                                                        float3 _4259;
                                                        if (_2135 < 0.6665999889373779296875f)
                                                        {
                                                            float3 _3989 = _1685;
                                                            _3989.y = 0.89999997615814208984375f;
                                                            _4259 = _3989;
                                                        }
                                                        else
                                                        {
                                                            float3 _3991 = _1685;
                                                            _3991.x = 0.89999997615814208984375f;
                                                            _4259 = _3991;
                                                        }
                                                        _4258 = _4259;
                                                    }
                                                    float _2151 = mod(_1678.y, 2.0f);
                                                    bool _2155 = (_2151 == 1.0f) && _2129;
                                                    bool _2166;
                                                    if (!_2155)
                                                    {
                                                        _2166 = (_2151 == 0.0f) && (!_2129);
                                                    }
                                                    else
                                                    {
                                                        _2166 = _2155;
                                                    }
                                                    float3 _4260;
                                                    if (_2166)
                                                    {
                                                        _4260 = _4258 * params_maskLight;
                                                    }
                                                    else
                                                    {
                                                        _4260 = _4258;
                                                    }
                                                    _3458 = _4260;
                                                    break;
                                                }
                                                else
                                                {
                                                    if (_1687 == 10.0f)
                                                    {
                                                        float _2202 = frac(_1678.x * 0.3333333432674407958984375f);
                                                        float3 _4252;
                                                        if (_2202 > 0.33329999446868896484375f)
                                                        {
                                                            float3 _3998 = _1685;
                                                            _3998.x = 1.0f;
                                                            _3998.z = 1.0f;
                                                            _4252 = _3998;
                                                        }
                                                        else
                                                        {
                                                            float3 _4253;
                                                            if (_2202 > 0.6665999889373779296875f)
                                                            {
                                                                float3 _4002 = _1685;
                                                                _4002.y = 1.0f;
                                                                _4253 = _4002;
                                                            }
                                                            else
                                                            {
                                                                _4253 = params_mcut.xxx;
                                                            }
                                                            _4252 = _4253;
                                                        }
                                                        float3 _4254;
                                                        if (_2202 > 0.333000004291534423828125f)
                                                        {
                                                            _4254 = _4252 * ((frac((_1678.y + float(frac(_1678.x * 0.16666667163372039794921875f) < 0.5f)) * 0.5f) < 0.5f) ? 1.0f : params_maskLight);
                                                        }
                                                        else
                                                        {
                                                            _4254 = _4252;
                                                        }
                                                        _3458 = _4254;
                                                        break;
                                                    }
                                                    else
                                                    {
                                                        if (_1687 == 11.0f)
                                                        {
                                                            bool3 _3833 = (frac(_1678.x * 0.3333333432674407958984375f) > 0.333000004291534423828125f).xxx;
                                                            _3458 = float3(_3833.x ? 1.0f.xxx.x : _1685.x, _3833.y ? 1.0f.xxx.y : _1685.y, _3833.z ? 1.0f.xxx.z : _1685.z);
                                                            break;
                                                        }
                                                    }
                                                }
                                                _4288 = _1685;
                                            }
                                            _4286 = _4288;
                                        }
                                        _4283 = _4286;
                                    }
                                    _4281 = _4283;
                                }
                                _4278 = _4281;
                            }
                            _4275 = _4278;
                        }
                        _4272 = _4275;
                    }
                    _4271 = _4272;
                }
                _4269 = _4271;
            }
            _4268 = _4269;
        }
        _3458 = _4268;
        break;
    } while(false);
    float3 _1460 = _1436 * lerp(_3458, 1.0f.xxx, (_1414 * params_thres).xxx);
    float3 _3523;
    do
    {
        float3 _4339;
        if (_1688)
        {
            _4339 = 1.0f.xxx;
        }
        else
        {
            float3 _4340;
            if (_1687 == 0.0f)
            {
                float _2325 = 1.0f - params_CGWG;
                float3 _4341;
                if (frac(_1678.x * 0.5f) < 0.5f)
                {
                    _4341 = float3(1.10000002384185791015625f, _2325, 1.10000002384185791015625f);
                }
                else
                {
                    _4341 = float3(_2325, 1.10000002384185791015625f, _2325);
                }
                _4340 = _4341;
            }
            else
            {
                float3 _4342;
                if (_1687 == 1.0f)
                {
                    float _3520;
                    if (frac((_1678.y + float(frac(_1678.x * 0.16666667163372039794921875f) < 0.5f)) * 0.5f) < 0.5f)
                    {
                        _3520 = _1680;
                    }
                    else
                    {
                        _3520 = params_maskLight;
                    }
                    float _2369 = frac(_1678.x * 0.3333333432674407958984375f);
                    float3 _4337;
                    if (_2369 < 0.333000004291534423828125f)
                    {
                        float3 _4030 = _1685;
                        _4030.z = params_maskLight;
                        _4337 = _4030;
                    }
                    else
                    {
                        float3 _4338;
                        if (_2369 < 0.66600000858306884765625f)
                        {
                            float3 _4033 = _1685;
                            _4033.y = params_maskLight;
                            _4338 = _4033;
                        }
                        else
                        {
                            float3 _4035 = _1685;
                            _4035.x = params_maskLight;
                            _4338 = _4035;
                        }
                        _4337 = _4338;
                    }
                    _4342 = _4337 * _3520;
                }
                else
                {
                    float3 _4343;
                    if (_1687 == 2.0f)
                    {
                        float _2403 = frac(_1678.x * 0.3333333432674407958984375f);
                        float3 _4344;
                        if (_2403 < 0.333000004291534423828125f)
                        {
                            float3 _4041 = _1685;
                            _4041.z = params_maskLight;
                            _4344 = _4041;
                        }
                        else
                        {
                            float3 _4345;
                            if (_2403 < 0.66600000858306884765625f)
                            {
                                float3 _4044 = _1685;
                                _4044.y = params_maskLight;
                                _4345 = _4044;
                            }
                            else
                            {
                                float3 _4046 = _1685;
                                _4046.x = params_maskLight;
                                _4345 = _4046;
                            }
                            _4344 = _4345;
                        }
                        _4343 = _4344;
                    }
                    else
                    {
                        float3 _4346;
                        if (_1687 == 3.0f)
                        {
                            float _2441 = frac((_1678.x + (_1678.y * 3.0f)) * 0.16666667163372039794921875f);
                            float3 _4347;
                            if (_2441 < 0.333000004291534423828125f)
                            {
                                float3 _4056 = _1685;
                                _4056.z = params_maskLight;
                                _4347 = _4056;
                            }
                            else
                            {
                                float3 _4348;
                                if (_2441 < 0.66600000858306884765625f)
                                {
                                    float3 _4059 = _1685;
                                    _4059.y = params_maskLight;
                                    _4348 = _4059;
                                }
                                else
                                {
                                    float3 _4061 = _1685;
                                    _4061.x = params_maskLight;
                                    _4348 = _4061;
                                }
                                _4347 = _4348;
                            }
                            _4346 = _4347;
                        }
                        else
                        {
                            float3 _4349;
                            if (_1687 == 4.0f)
                            {
                                float2 _2471 = floor(_1678 * float2(1.0f, 0.5f));
                                float _2482 = frac((_2471.x + (_2471.y * 3.0f)) * 0.16666667163372039794921875f);
                                float3 _4350;
                                if (_2482 < 0.333000004291534423828125f)
                                {
                                    float3 _4071 = _1685;
                                    _4071.z = params_maskLight;
                                    _4350 = _4071;
                                }
                                else
                                {
                                    float3 _4351;
                                    if (_2482 < 0.66600000858306884765625f)
                                    {
                                        float3 _4074 = _1685;
                                        _4074.y = params_maskLight;
                                        _4351 = _4074;
                                    }
                                    else
                                    {
                                        float3 _4076 = _1685;
                                        _4076.x = params_maskLight;
                                        _4351 = _4076;
                                    }
                                    _4350 = _4351;
                                }
                                _4349 = _4350;
                            }
                            else
                            {
                                float3 _4352;
                                if (_1687 == 5.0f)
                                {
                                    float _2517 = max(max(_1442.x, _1442.y), _1442.z);
                                    float3 _2538 = min((1.25f * max(_2517 - params_mcut, 0.0f)) / (1.0f - params_mcut), _1680 + ((0.20000000298023223876953125f * (1.0f - _1680)) * _2517)).xxx;
                                    float _2541 = 0.800000011920928955078125f * params_maskLight;
                                    float _2553 = (_2541 - ((0.5f * (_2541 - 1.0f)) * _2517)) + (0.75f * (1.0f - _2517));
                                    float3 _4353;
                                    if (frac(_1678.x * 0.5f) < 0.5f)
                                    {
                                        float3 _4085 = _2538;
                                        _4085.x = _2553;
                                        _4085.z = _2553;
                                        _4353 = _4085;
                                    }
                                    else
                                    {
                                        float3 _4089 = _2538;
                                        _4089.y = _2553;
                                        _4353 = _4089;
                                    }
                                    _4352 = _4353;
                                }
                                else
                                {
                                    float3 _4354;
                                    if (_1687 == 6.0f)
                                    {
                                        float _2584 = max(max(_1442.x, _1442.y), _1442.z);
                                        float3 _2605 = min((1.33000004291534423828125f * max(_2584 - params_mcut, 0.0f)) / (1.0f - params_mcut), _1680 + ((0.2249999940395355224609375f * (1.0f - _1680)) * _2584)).xxx;
                                        float _2608 = 0.800000011920928955078125f * params_maskLight;
                                        float _2620 = (_2608 - ((0.5f * (_2608 - 1.0f)) * _2584)) + (0.75f * (1.0f - _2584));
                                        float _2625 = frac(_1678.x * 0.3333333432674407958984375f);
                                        float3 _4355;
                                        if (_2625 < 0.333000004291534423828125f)
                                        {
                                            float3 _4098 = _2605;
                                            _4098.x = _2620;
                                            _4355 = _4098;
                                        }
                                        else
                                        {
                                            float3 _4356;
                                            if (_2625 < 0.66600000858306884765625f)
                                            {
                                                float3 _4101 = _2605;
                                                _4101.y = _2620;
                                                _4356 = _4101;
                                            }
                                            else
                                            {
                                                float3 _4103 = _2605;
                                                _4103.z = _2620;
                                                _4356 = _4103;
                                            }
                                            _4355 = _4356;
                                        }
                                        _4354 = _4355;
                                    }
                                    else
                                    {
                                        float3 _4357;
                                        if (_1687 == 7.0f)
                                        {
                                            float _2660 = max(max(_1442.x, _1442.y), _1442.z);
                                            float3 _4358;
                                            if (frac(_1678.x * 0.5f) < 0.5f)
                                            {
                                                _4358 = (1.0f + (0.60000002384185791015625f * (1.0f - _2660))).xxx;
                                            }
                                            else
                                            {
                                                _4358 = min((1.60000002384185791015625f * max(_2660 - params_mcut, 0.0f)) / (1.0f - params_mcut), 1.0f - params_CGWG).xxx;
                                            }
                                            _4357 = _4358;
                                        }
                                        else
                                        {
                                            float3 _4359;
                                            if (_1687 == 8.0f)
                                            {
                                                float _3516;
                                                if (frac((_1678.y + float(frac(_1678.x * 0.25f) < 0.5f)) * 0.5f) < 0.5f)
                                                {
                                                    _3516 = _1680;
                                                }
                                                else
                                                {
                                                    _3516 = params_maskLight;
                                                }
                                                float3 _4334;
                                                if (frac(_1678.x * 0.5f) < 0.5f)
                                                {
                                                    float3 _4118 = _1685;
                                                    _4118.x = params_maskLight;
                                                    _4118.z = params_maskLight;
                                                    _4334 = _4118;
                                                }
                                                else
                                                {
                                                    float3 _4122 = _1685;
                                                    _4122.y = params_maskLight;
                                                    _4334 = _4122;
                                                }
                                                _4359 = _4334 * _3516;
                                            }
                                            else
                                            {
                                                if (_1687 == 9.0f)
                                                {
                                                    bool _2752 = frac(_1678.x * 0.16666667163372039794921875f) < 0.5f;
                                                    float _2758 = frac(_1678.x * 0.3333333432674407958984375f);
                                                    float3 _4329;
                                                    if (_2758 < 0.33329999446868896484375f)
                                                    {
                                                        float3 _4126 = _1685;
                                                        _4126.z = 0.89999997615814208984375f;
                                                        _4329 = _4126;
                                                    }
                                                    else
                                                    {
                                                        float3 _4330;
                                                        if (_2758 < 0.6665999889373779296875f)
                                                        {
                                                            float3 _4128 = _1685;
                                                            _4128.y = 0.89999997615814208984375f;
                                                            _4330 = _4128;
                                                        }
                                                        else
                                                        {
                                                            float3 _4130 = _1685;
                                                            _4130.x = 0.89999997615814208984375f;
                                                            _4330 = _4130;
                                                        }
                                                        _4329 = _4330;
                                                    }
                                                    float _2774 = mod(_1678.y, 2.0f);
                                                    bool _2778 = (_2774 == 1.0f) && _2752;
                                                    bool _2789;
                                                    if (!_2778)
                                                    {
                                                        _2789 = (_2774 == 0.0f) && (!_2752);
                                                    }
                                                    else
                                                    {
                                                        _2789 = _2778;
                                                    }
                                                    float3 _4331;
                                                    if (_2789)
                                                    {
                                                        _4331 = _4329 * params_maskLight;
                                                    }
                                                    else
                                                    {
                                                        _4331 = _4329;
                                                    }
                                                    _3523 = _4331;
                                                    break;
                                                }
                                                else
                                                {
                                                    if (_1687 == 10.0f)
                                                    {
                                                        float _2825 = frac(_1678.x * 0.3333333432674407958984375f);
                                                        float3 _4323;
                                                        if (_2825 > 0.33329999446868896484375f)
                                                        {
                                                            float3 _4137 = _1685;
                                                            _4137.x = 1.0f;
                                                            _4137.z = 1.0f;
                                                            _4323 = _4137;
                                                        }
                                                        else
                                                        {
                                                            float3 _4324;
                                                            if (_2825 > 0.6665999889373779296875f)
                                                            {
                                                                float3 _4141 = _1685;
                                                                _4141.y = 1.0f;
                                                                _4324 = _4141;
                                                            }
                                                            else
                                                            {
                                                                _4324 = params_mcut.xxx;
                                                            }
                                                            _4323 = _4324;
                                                        }
                                                        float3 _4325;
                                                        if (_2825 > 0.333000004291534423828125f)
                                                        {
                                                            _4325 = _4323 * ((frac((_1678.y + float(frac(_1678.x * 0.16666667163372039794921875f) < 0.5f)) * 0.5f) < 0.5f) ? 1.0f : params_maskLight);
                                                        }
                                                        else
                                                        {
                                                            _4325 = _4323;
                                                        }
                                                        _3523 = _4325;
                                                        break;
                                                    }
                                                    else
                                                    {
                                                        if (_1687 == 11.0f)
                                                        {
                                                            bool3 _3840 = (frac(_1678.x * 0.3333333432674407958984375f) > 0.333000004291534423828125f).xxx;
                                                            _3523 = float3(_3840.x ? 1.0f.xxx.x : _1685.x, _3840.y ? 1.0f.xxx.y : _1685.y, _3840.z ? 1.0f.xxx.z : _1685.z);
                                                            break;
                                                        }
                                                    }
                                                }
                                                _4359 = _1685;
                                            }
                                            _4357 = _4359;
                                        }
                                        _4354 = _4357;
                                    }
                                    _4352 = _4354;
                                }
                                _4349 = _4352;
                            }
                            _4346 = _4349;
                        }
                        _4343 = _4346;
                    }
                    _4342 = _4343;
                }
                _4340 = _4342;
            }
            _4339 = _4340;
        }
        _3523 = _4339;
        break;
    } while(false);
    float3 _1477 = _1442 * lerp(_3523, 1.0f.xxx, (_1426 * params_thres).xxx);
    float _2904 = -params_scanline;
    float3 _4394;
    if (global_OriginalSize.y >= 400.0f)
    {
        _4394 = (_1460 + _1477) * 0.5f.xxx;
    }
    else
    {
        _4394 = (_1460 * exp2(_2904 * pow(_1402, lerp(params_beam_min, params_beam_max, _1414)))) + (_1477 * exp2(_2904 * pow(1.0f - _1402, lerp(params_beam_min, params_beam_max, _1426))));
    }
    float3 _1511 = min(_4394, 1.0f.xxx);
    float _2963 = _1331.x;
    float _2966 = 2.0f * global_SourceSize.z;
    float _2967 = _2963 - _2966;
    float _2969 = _1331.y;
    float _2981 = _2963 - global_SourceSize.z;
    float _3006 = _2963 + global_SourceSize.z;
    float _3021 = _2963 + _2966;
    float _3041 = _2969 - global_SourceSize.w;
    float _3058 = 2.0f * global_SourceSize.w;
    float _3059 = _2969 - _3058;
    float _3093 = _2969 + global_SourceSize.w;
    float _3111 = _2969 + _3058;
    float3 _3345 = (((Source.Sample(_Source_sampler, _1331).xyz * 3.0f) + ((((((((Source.Sample(_Source_sampler, float2(_2981, _2969)).xyz + Source.Sample(_Source_sampler, float2(_3006, _2969)).xyz) + Source.Sample(_Source_sampler, float2(_2981, _3041)).xyz) + Source.Sample(_Source_sampler, float2(_3006, _3093)).xyz) + Source.Sample(_Source_sampler, float2(_2981, _3093)).xyz) + Source.Sample(_Source_sampler, float2(_3006, _3041)).xyz) + Source.Sample(_Source_sampler, float2(_2963, _3041)).xyz) + Source.Sample(_Source_sampler, float2(_2963, _3093)).xyz) * 2.5f)) + ((((((((((((Source.Sample(_Source_sampler, float2(_2967, _2969)).xyz + Source.Sample(_Source_sampler, float2(_3021, _2969)).xyz) + Source.Sample(_Source_sampler, float2(_2967, _3041)).xyz) + Source.Sample(_Source_sampler, float2(_2981, _3059)).xyz) + Source.Sample(_Source_sampler, float2(_3006, _3111)).xyz) + Source.Sample(_Source_sampler, float2(_3021, _3093)).xyz) + Source.Sample(_Source_sampler, float2(_2967, _3093)).xyz) + Source.Sample(_Source_sampler, float2(_2981, _3111)).xyz) + Source.Sample(_Source_sampler, float2(_3006, _3059)).xyz) + Source.Sample(_Source_sampler, float2(_3021, _3041)).xyz) + Source.Sample(_Source_sampler, float2(_2963, _3059)).xyz) + Source.Sample(_Source_sampler, float2(_2963, _3111)).xyz) * 1.5f)) * 0.02222222276031970977783203125f.xxx;
    float3 _1558 = (pow(pow(pow(_1511, float3(1.0f / params_gamma_out_red, 1.0f, 1.0f)), float3(1.0f, 1.0f / params_gamma_out_green, 1.0f)), float3(1.0f, 1.0f, 1.0f / params_gamma_out_blue)) + (_3345 * params_glow)) * lerp(1.0f, params_brightboost, ((_1511.x * 0.300000011920928955078125f) + (_1511.y * 0.60000002384185791015625f)) + (_1511.z * 0.100000001490116119384765625f));
    bool3 _3842 = ((length(_1558) * 0.57749998569488525390625f) < 0.5f).xxx;
    float2 _3393 = vTexCoord * (1.0f.xx - vTexCoord);
    float _3844 = (params_vignette == 0.0f) ? 1.0f : min(pow((_3393.x * _3393.y) * 45.0f, 0.1500000059604644775390625f), 1.0f);
    float3 _1566 = mul(float3x3(float3(_3844, 0.0f, 0.0f), float3(0.0f, _3844, 0.0f), float3(0.0f, 0.0f, _3844)), lerp(dot(_1558, float3(_3842.x ? float3(0.180000007152557373046875f, 0.7200000286102294921875f, 0.02000000141561031341552734375f).x : float3(0.300000011920928955078125f, 0.60000002384185791015625f, 0.100000001490116119384765625f).x, _3842.y ? float3(0.180000007152557373046875f, 0.7200000286102294921875f, 0.02000000141561031341552734375f).y : float3(0.300000011920928955078125f, 0.60000002384185791015625f, 0.100000001490116119384765625f).y, _3842.z ? float3(0.180000007152557373046875f, 0.7200000286102294921875f, 0.02000000141561031341552734375f).z : float3(0.300000011920928955078125f, 0.60000002384185791015625f, 0.100000001490116119384765625f).z)).xxx, _1558, params_sat.xxx));
    float3 _4395;
    if (params_gdv_mono == 1.0f)
    {
        _4395 = (((_1566.x + _1566.y) + _1566.z) * 0.3333333432674407958984375f).xxx * float3(params_gdv_R, params_gdv_G, params_gdv_B);
    }
    else
    {
        _4395 = _1566;
    }
    FragColor = float4(_4395, 1.0f);
}

SPIRV_Cross_Output main(SPIRV_Cross_Input stage_input)
{
    vTexCoord = stage_input.vTexCoord;
    frag_main();
    SPIRV_Cross_Output stage_output;
    stage_output.FragColor = FragColor;
    return stage_output;
}
