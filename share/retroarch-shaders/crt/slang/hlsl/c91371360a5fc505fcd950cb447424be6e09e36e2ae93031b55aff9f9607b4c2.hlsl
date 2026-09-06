// Generated from crt/shaders/crt-pocket.slang. See slang/upstream for licence/source.
static float3 _2446;

cbuffer UBO : register(b0)
{
    float global_DOTMASK_STRENGTH : packoffset(c4);
    float global_maskDark : packoffset(c4.y);
    float global_maskLight : packoffset(c4.z);
    float global_shadowMask : packoffset(c4.w);
    float global_bgr : packoffset(c5);
    float global_maskl : packoffset(c5.y);
    float global_maskh : packoffset(c5.z);
    float global_gl : packoffset(c5.w);
    float global_ntsc : packoffset(c6);
    float global_TEMP : packoffset(c6.y);
    float global_size : packoffset(c6.z);
};

cbuffer Push : register(b1)
{
    float4 params_SourceSize : packoffset(c0);
    float4 params_OriginalSize : packoffset(c1);
    float4 params_OutputSize : packoffset(c2);
    uint params_FrameCount : packoffset(c3);
    float params_gammaout : packoffset(c3.y);
    float params_warpX : packoffset(c3.z);
    float params_warpY : packoffset(c3.w);
    float params_vignette : packoffset(c4);
    float params_vign : packoffset(c4.y);
    float params_corners : packoffset(c4.z);
    float params_beam1 : packoffset(c4.w);
    float params_beam2 : packoffset(c5);
    float params_scanline1 : packoffset(c5.y);
    float params_scanline2 : packoffset(c5.z);
    float params_interlace : packoffset(c5.w);
    float params_progress : packoffset(c6);
    float params_boost1 : packoffset(c6.y);
    float params_boost2 : packoffset(c6.z);
    float params_sat : packoffset(c6.w);
    float params_flick : packoffset(c7);
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
    float2 _1220 = (vTexCoord * 2.0f) - 1.0f.xx;
    float _1222 = _1220.y;
    float _1231 = _1220.x;
    float2 _1243 = (_1220 * float2(1.0f + ((_1222 * _1222) * params_warpX), 1.0f + ((_1231 * _1231) * params_warpY))) * 0.5f;
    float2 _1245 = _1243 + 0.5f.xx;
    float _961 = _1245.y;
    float _964 = _961 * params_SourceSize.y;
    bool _977 = params_OriginalSize.y > 400.0f;
    bool _984;
    if (_977)
    {
        _984 = params_interlace == 1.0f;
    }
    else
    {
        _984 = _977;
    }
    float _2141;
    if (_984)
    {
        _2141 = (sin(float(params_FrameCount) * 2.0f) > 0.0f) ? frac(0.5f + (_964 * 0.5f)) : frac(((_961 - 0.5f) * params_SourceSize.y) * 0.5f);
    }
    else
    {
        _2141 = frac(0.5f + _964);
    }
    bool _1024;
    if (_977)
    {
        _1024 = params_interlace == 0.0f;
    }
    else
    {
        _1024 = _977;
    }
    bool _1031;
    if (_1024)
    {
        _1031 = params_progress == 1.0f;
    }
    else
    {
        _1031 = _1024;
    }
    float _2138;
    if (_1031)
    {
        _2138 = frac(0.5f + (_964 * 0.5f));
    }
    else
    {
        _2138 = _2141;
    }
    float2 _1268 = _1245 * params_SourceSize.xy;
    float2 _1271 = floor(_1268) + 0.5f.xx;
    float2 _1281 = frac(_1268) - 0.5f.xx;
    float _2118;
    float3 _2119;
    float3 _2120;
    float3 _2121;
    _2121 = (-10000000.0f).xxx;
    _2120 = 10000000.0f.xxx;
    _2119 = 0.0f.xxx;
    _2118 = 0.0f;
    float3 _2234;
    float3 _2235;
    float3 _2250;
    float _2255;
    for (float _2117 = -2.0f; _2117 < 3.0f; _2121 = _2235, _2120 = _2234, _2119 = _2250, _2118 = _2255, _2117 += 1.0f)
    {
        _2255 = _2118;
        _2250 = _2119;
        _2235 = _2121;
        _2234 = _2120;
        float3 _1304;
        float3 _1307;
        float3 _1325;
        float _1328;
        for (float _2228 = -1.0f; _2228 < 2.0f; _2255 = _1328, _2250 = _1325, _2235 = _1307, _2234 = _1304, _2228 += 1.0f)
        {
            float4 _1300 = Source.Sample(_Source_sampler, params_SourceSize.zw * (_1271 + float2(_2117, _2228)));
            float3 _1301 = _1300.xyz;
            _1304 = min(_2234, _1301);
            _1307 = max(_2235, _1301);
            float _1311 = _2117 - _1281.x;
            float _2237;
            if (_1311 == 0.0f)
            {
                _2237 = 1.0f;
            }
            else
            {
                float _2236;
                if (abs(_1311) < 2.0f)
                {
                    float _1376 = _1311 * 3.1415920257568359375f;
                    float _1384 = _1311 * 1.57079601287841796875f;
                    _2236 = (sin(_1376) / _1376) * (sin(_1384) / _1384);
                }
                else
                {
                    _2236 = 0.0f;
                }
                _2237 = _2236;
            }
            float _1316 = _2228 - _1281.y;
            float _2241;
            if (_1316 == 0.0f)
            {
                _2241 = 1.0f;
            }
            else
            {
                float _2240;
                if (abs(_1316) < 1.0f)
                {
                    float _1419 = _1316 * 3.1415920257568359375f;
                    float _1423 = sin(_1419) / _1419;
                    _2240 = _1423 * _1423;
                }
                else
                {
                    _2240 = 0.0f;
                }
                _2241 = _2240;
            }
            float _1320 = _2237 * _2241;
            _1325 = _2250 + (_1301 * _1320);
            _1328 = _2255 + _1320;
        }
    }
    float3 _1344 = clamp(_2119 / _2118.xxx, _2120, _2121);
    float _1054 = dot(float3(0.300000011920928955078125f, 0.60000002384185791015625f, 0.100000001490116119384765625f), _1344);
    float3 _1062 = lerp(_1054.xxx, _1344, params_sat.xxx);
    float3 _2436;
    if (global_ntsc == 1.0f)
    {
        _2436 = mul(_1062, float3x3(float3(1.01429998874664306640625f, -0.0164999999105930328369140625f, 0.03070000000298023223876953125f), float3(0.07230000197887420654296875f, 0.91250002384185791015625f, 0.01730000041425228118896484375f), float3(0.01750000007450580596923828125f, -0.041900001466274261474609375f, 1.1101000308990478515625f)));
    }
    else
    {
        _2436 = _1062;
    }
    float _2129;
    float _2130;
    float3 _2131;
    _2131 = 0.0f.xxx;
    _2130 = 0.0f;
    _2129 = -2.0f;
    float3 _2226;
    float _2227;
    for (; _2129 < 3.0f; _2131 = _2226, _2130 = _2227, _2129 += 1.0f)
    {
        _2227 = _2130;
        _2226 = _2131;
        for (float _2222 = -2.0f; _2222 < 3.0f; )
        {
            float _1469 = exp(((-0.1500000059604644775390625f) * _2129) * _2129) + exp(((-0.4000000059604644775390625f) * _2222) * _2222);
            _2227 += _1469;
            _2226 += (Source.Sample(_Source_sampler, _1245 + (float2(_2129, _2222) * params_SourceSize.zw)).xyz * _1469);
            _2222 += 1.0f;
            continue;
        }
    }
    float3 _1500 = _2131 / _2130.xxx;
    float _1517 = clamp(global_TEMP, 1000.0f, 40000.0f) * 0.00999999977648258209228515625f;
    float3 _2447;
    if (_1517 <= 66.0f)
    {
        float3 _2321;
        _2321.x = 1.0f;
        _2321.y = clamp((0.390081584453582763671875f * log(_1517)) - 0.6318414211273193359375f, 0.0f, 1.0f);
        _2447 = _2321;
    }
    else
    {
        float _1530 = _1517 - 60.0f;
        float3 _2325;
        _2325.x = clamp(1.29293620586395263671875f * pow(_1530, -0.133204758167266845703125f), 0.0f, 1.0f);
        _2325.y = clamp(1.129890918731689453125f * pow(_1530, -0.075514845550060272216796875f), 0.0f, 1.0f);
        _2447 = _2325;
    }
    float3 _2448;
    if (_1517 >= 66.0f)
    {
        float3 _2329 = _2447;
        _2329.z = 1.0f;
        _2448 = _2329;
    }
    else
    {
        float3 _2449;
        if (_1517 <= 19.0f)
        {
            float3 _2331 = _2447;
            _2331.z = 0.0f;
            _2449 = _2331;
        }
        else
        {
            float3 _2333 = _2447;
            _2333.z = clamp((0.54320681095123291015625f * log(_1517 - 10.0f)) - 1.19625413417816162109375f, 0.0f, 1.0f);
            _2449 = _2333;
        }
        _2448 = _2449;
    }
    float3 _1084 = (clamp(_2436, 0.0f.xxx, 1.0f.xxx) + ((_1500 * _1500) * global_gl)) * _2448;
    float _1093 = max(max(_1084.x, _1084.y), _1084.z);
    float _1594 = lerp(params_scanline1, params_scanline2, _1093);
    float _1597 = _2138 * _1594;
    float _1104 = abs(1.0f - _2138);
    float _1624 = _1104 * _1594;
    float2 _1129 = floor(((vTexCoord * params_OutputSize.xy) / global_size.xx) + 0.5f.xx);
    float3 _2157;
    do
    {
        float3 _1663 = global_maskDark.xxx;
        float3 _2462;
        if (global_shadowMask == 0.0f)
        {
            float _1670 = 1.0f - global_DOTMASK_STRENGTH;
            _2157 = lerp(float3(1.0f, _1670, 1.0f), float3(_1670, 1.0f, _1670), floor(mod((((vTexCoord.x * params_SourceSize.x) * params_OutputSize.x) / global_size) / params_SourceSize.x, 2.0f)).xxx);
            break;
        }
        else
        {
            if (global_shadowMask == 1.0f)
            {
                float _1703 = _1129.x;
                float _2153;
                if (frac((_1129.y + float(frac(_1703 * 0.16666667163372039794921875f) < 0.5f)) * 0.5f) < 0.5f)
                {
                    _2153 = global_maskDark;
                }
                else
                {
                    _2153 = global_maskLight;
                }
                float _1723 = frac(_1703 * 0.3333333432674407958984375f);
                float3 _2458;
                if (_1723 < 0.333000004291534423828125f)
                {
                    float3 _2459;
                    if (global_bgr == 1.0f)
                    {
                        float3 _2344 = _1663;
                        _2344.z = global_maskLight;
                        _2459 = _2344;
                    }
                    else
                    {
                        float3 _2346 = _1663;
                        _2346.x = global_maskLight;
                        _2459 = _2346;
                    }
                    _2458 = _2459;
                }
                else
                {
                    float3 _2460;
                    if (_1723 < 0.66600000858306884765625f)
                    {
                        float3 _2349 = _1663;
                        _2349.y = global_maskLight;
                        _2460 = _2349;
                    }
                    else
                    {
                        float3 _2461;
                        if (global_bgr == 1.0f)
                        {
                            float3 _2351 = _1663;
                            _2351.x = global_maskLight;
                            _2461 = _2351;
                        }
                        else
                        {
                            float3 _2353 = _1663;
                            _2353.z = global_maskLight;
                            _2461 = _2353;
                        }
                        _2460 = _2461;
                    }
                    _2458 = _2460;
                }
                _2462 = _2458 * _2153;
            }
            else
            {
                float3 _2463;
                if (global_shadowMask == 2.0f)
                {
                    float _1775 = frac(_1129.x * 0.3333333432674407958984375f);
                    float3 _2464;
                    if (_1775 < 0.333000004291534423828125f)
                    {
                        float3 _2465;
                        if (global_bgr == 1.0f)
                        {
                            float3 _2359 = _1663;
                            _2359.z = global_maskLight;
                            _2465 = _2359;
                        }
                        else
                        {
                            float3 _2361 = _1663;
                            _2361.x = global_maskLight;
                            _2465 = _2361;
                        }
                        _2464 = _2465;
                    }
                    else
                    {
                        float3 _2466;
                        if (_1775 < 0.66600000858306884765625f)
                        {
                            float3 _2364 = _1663;
                            _2364.y = global_maskLight;
                            _2466 = _2364;
                        }
                        else
                        {
                            float3 _2467;
                            if (global_bgr == 1.0f)
                            {
                                float3 _2366 = _1663;
                                _2366.x = global_maskLight;
                                _2467 = _2366;
                            }
                            else
                            {
                                float3 _2368 = _1663;
                                _2368.z = global_maskLight;
                                _2467 = _2368;
                            }
                            _2466 = _2467;
                        }
                        _2464 = _2466;
                    }
                    _2463 = _2464;
                }
                else
                {
                    float3 _2468;
                    if (global_shadowMask == 3.0f)
                    {
                        float _1831 = frac((_1129.x + (_1129.y * 3.0f)) * 0.16666667163372039794921875f);
                        float3 _2469;
                        if (_1831 < 0.333000004291534423828125f)
                        {
                            float3 _2470;
                            if (global_bgr == 1.0f)
                            {
                                float3 _2378 = _1663;
                                _2378.z = global_maskLight;
                                _2470 = _2378;
                            }
                            else
                            {
                                float3 _2380 = _1663;
                                _2380.x = global_maskLight;
                                _2470 = _2380;
                            }
                            _2469 = _2470;
                        }
                        else
                        {
                            float3 _2471;
                            if (_1831 < 0.66600000858306884765625f)
                            {
                                float3 _2383 = _1663;
                                _2383.y = global_maskLight;
                                _2471 = _2383;
                            }
                            else
                            {
                                float3 _2472;
                                if (global_bgr == 1.0f)
                                {
                                    float3 _2385 = _1663;
                                    _2385.x = global_maskLight;
                                    _2472 = _2385;
                                }
                                else
                                {
                                    float3 _2387 = _1663;
                                    _2387.z = global_maskLight;
                                    _2472 = _2387;
                                }
                                _2471 = _2472;
                            }
                            _2469 = _2471;
                        }
                        _2468 = _2469;
                    }
                    else
                    {
                        float3 _2473;
                        if (global_shadowMask == 4.0f)
                        {
                            float2 _1879 = floor(_1129 * float2(1.0f, 0.5f));
                            float _1890 = frac((_1879.x + (_1879.y * 3.0f)) * 0.16666667163372039794921875f);
                            float3 _2474;
                            if (_1890 < 0.333000004291534423828125f)
                            {
                                float3 _2475;
                                if (global_bgr == 1.0f)
                                {
                                    float3 _2397 = _1663;
                                    _2397.z = global_maskLight;
                                    _2475 = _2397;
                                }
                                else
                                {
                                    float3 _2399 = _1663;
                                    _2399.x = global_maskLight;
                                    _2475 = _2399;
                                }
                                _2474 = _2475;
                            }
                            else
                            {
                                float3 _2476;
                                if (_1890 < 0.66600000858306884765625f)
                                {
                                    float3 _2402 = _1663;
                                    _2402.y = global_maskLight;
                                    _2476 = _2402;
                                }
                                else
                                {
                                    float3 _2477;
                                    if (global_bgr == 1.0f)
                                    {
                                        float3 _2404 = _1663;
                                        _2404.x = global_maskLight;
                                        _2477 = _2404;
                                    }
                                    else
                                    {
                                        float3 _2406 = _1663;
                                        _2406.z = global_maskLight;
                                        _2477 = _2406;
                                    }
                                    _2476 = _2477;
                                }
                                _2474 = _2476;
                            }
                            _2473 = _2474;
                        }
                        else
                        {
                            float3 _2478;
                            if (global_shadowMask == 5.0f)
                            {
                                float _1941 = (params_OutputSize.x * vTexCoord.x) * 3.1415920257568359375f;
                                float _1950 = (vTexCoord.y * params_OutputSize.y) * 1.57079601287841796875f;
                                float _1954 = (sin(_1941 + _1950) * 0.5f) + 0.5f;
                                float _1973 = (sin((_1941 + 4.18877887725830078125f) + _1950) * 0.5f) + 0.5f;
                                float _1992 = (sin((_1941 + 2.09440517425537109375f) + _1950) * 0.5f) + 0.5f;
                                float3 _2149;
                                if (global_bgr == 1.0f)
                                {
                                    _2149 = float3(_1992, _1973, _1954);
                                }
                                else
                                {
                                    _2149 = float3(_1954, _1973, _1992);
                                }
                                _2157 = min(_2149 * 2.0f, 1.0f.xxx);
                                break;
                            }
                            else
                            {
                                if (global_shadowMask == 6.0f)
                                {
                                    float _2020 = _1129.x;
                                    float _2147;
                                    if (frac((_1129.y + float(frac(_2020 * 0.25f) < 0.5f)) * 0.5f) < 0.5f)
                                    {
                                        _2147 = global_maskDark;
                                    }
                                    else
                                    {
                                        _2147 = global_maskLight;
                                    }
                                    float3 _2455;
                                    if (frac(_2020 * 0.5f) < 0.5f)
                                    {
                                        float3 _2414 = _1663;
                                        _2414.x = global_maskLight;
                                        _2414.z = global_maskLight;
                                        _2455 = _2414;
                                    }
                                    else
                                    {
                                        float3 _2418 = _1663;
                                        _2418.y = global_maskLight;
                                        _2455 = _2418;
                                    }
                                    _2478 = _2455 * _2147;
                                }
                                else
                                {
                                    float3 _2479;
                                    if (global_shadowMask == (-1.0f))
                                    {
                                        _2479 = 1.0f.xxx;
                                    }
                                    else
                                    {
                                        _2479 = _1663;
                                    }
                                    _2478 = _2479;
                                }
                            }
                            _2473 = _2478;
                        }
                        _2468 = _2473;
                    }
                    _2463 = _2468;
                }
                _2462 = _2463;
            }
        }
        _2157 = _2462;
        break;
    } while(false);
    float2 _2087 = vTexCoord * (1.0f.xx - vTexCoord);
    float _2309 = (params_vignette == 0.0f) ? 1.0f : min(pow((_2087.x * _2087.y) * 50.0f, params_vign), 1.0f);
    float2 _1174 = min(_1245, 0.5f.xx - _1243);
    float _1178 = 9.9999997473787516355514526367188e-05f / _1174.x;
    bool _1182 = params_corners == 1.0f;
    bool _1190;
    if (_1182)
    {
        _1190 = _1174.y <= _1178;
    }
    else
    {
        _1190 = _1182;
    }
    bool _1197;
    if (!_1190)
    {
        _1197 = _1178 < 9.9999997473787516355514526367188e-05f;
    }
    else
    {
        _1197 = _1190;
    }
    float3 _2507;
    if (_1197)
    {
        _2507 = 0.0f.xxx;
    }
    else
    {
        _2507 = mul(float3x3(float3(_2309, 0.0f, 0.0f), float3(0.0f, _2309, 0.0f), float3(0.0f, 0.0f, _2309)), pow((((_1084 * exp2(((-lerp(params_beam1, params_beam2, _2138)) * _1597) * _1597)) + (_1084 * exp2(((-lerp(params_beam1, params_beam2, _1104)) * _1624) * _1624))) * lerp(1.0f.xxx, _2157, lerp(global_maskl, global_maskh, _1093).xxx)) * lerp(params_boost1, params_boost2, _1054), (1.0f / params_gammaout).xxx)) + ((sin(float(params_FrameCount) * 2.0f) * params_flick) * 0.001000000047497451305389404296875f).xxx;
    }
    FragColor = float4(_2507, 1.0f);
}

SPIRV_Cross_Output main(SPIRV_Cross_Input stage_input)
{
    vTexCoord = stage_input.vTexCoord;
    frag_main();
    SPIRV_Cross_Output stage_output;
    stage_output.FragColor = FragColor;
    return stage_output;
}
