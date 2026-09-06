// Generated from crt/shaders/crt-super-xbr/crt-custom.slang. See slang/upstream for licence/source.
cbuffer UBO : register(b0)
{
    float4 global_OutputSize : packoffset(c4);
    float4 global_SourceSize : packoffset(c6);
};

cbuffer Push : register(b1)
{
    float param_BEAM_MIN_WIDTH : packoffset(c0);
    float param_BEAM_MAX_WIDTH : packoffset(c0.y);
    float param_SCANLINES_STRENGTH : packoffset(c0.z);
    float param_COLOR_BOOST : packoffset(c0.w);
    float param_SHARPNESS_HACK : packoffset(c1);
    float param_PHOSPHOR_LAYOUT : packoffset(c1.y);
    float param_MASK_INTENSITY : packoffset(c1.z);
    float param_VSCANLINES : packoffset(c2.y);
    float param_CRT_ANTI_RINGING : packoffset(c2.z);
    float param_CRT_CURVATURE : packoffset(c2.w);
    float param_CRT_warpX : packoffset(c3);
    float param_CRT_warpY : packoffset(c3.y);
    float param_CRT_cornersize : packoffset(c3.z);
    float param_CRT_cornersmooth : packoffset(c3.w);
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
    float2 _1286 = param_VSCANLINES.xx;
    float2 _1287 = lerp(float2(global_SourceSize.x * param_SHARPNESS_HACK, global_SourceSize.y), float2(global_SourceSize.x, global_SourceSize.y * param_SHARPNESS_HACK), _1286);
    float2 _1292 = float2(1.0f / _1287.x, 0.0f);
    float2 _1296 = float2(0.0f, 1.0f / _1287.y);
    float2 _1300 = lerp(_1292, _1296, _1286);
    float2 _1313 = lerp(_1296, _1292, _1286);
    bool _1320 = param_CRT_CURVATURE > 0.5f;
    float2 _2988;
    if (_1320)
    {
        float2 _1700 = (vTexCoord * 2.0f) - 1.0f.xx;
        float _1702 = _1700.x;
        float _1707 = _1700.y;
        float _1712 = sqrt((_1702 * _1702) + (_1707 * _1707));
        float2 _1727 = 1.0f.xx / (1.0f.xx + ((float2(param_CRT_warpX, param_CRT_warpY) * 15.0f) * 0.20000000298023223876953125f));
        _2988 = ((((_1700 / _1712.xx) * (1.0f.xx - pow((1.0f - (_1712 * 0.707106769084930419921875f)).xx, _1727))) / (1.0f.xx - pow(0.292893230915069580078125f.xx, _1727))) * 0.5f) + 0.5f.xx;
    }
    else
    {
        _2988 = vTexCoord;
    }
    float2 _1336 = (_2988 * _1287) + float2(-0.5f, 0.5f);
    float2 _1339 = floor(_1336);
    float2 _1353 = lerp((_1339 + 0.5f.xx) / _1287, (_1339 + float2(1.5f, -0.5f)) / _1287, _1286);
    float2 _1363 = lerp(frac(_1336), frac(_1336.yx), _1286);
    float2 _1372 = _1353 - _1300;
    float4 _1375 = Source.Sample(_Source_sampler, _1372 - _1313);
    float4 _1382 = Source.Sample(_Source_sampler, _1353 - _1313);
    float3 _1383 = _1382.xyz;
    float2 _1388 = _1353 + _1300;
    float4 _1391 = Source.Sample(_Source_sampler, _1388 - _1313);
    float3 _1392 = _1391.xyz;
    float2 _1398 = _1353 + (_1300 * 2.0f);
    float4 _1401 = Source.Sample(_Source_sampler, _1398 - _1313);
    float4 _1408 = Source.Sample(_Source_sampler, _1372);
    float4 _1413 = Source.Sample(_Source_sampler, _1353);
    float3 _1414 = _1413.xyz;
    float4 _1420 = Source.Sample(_Source_sampler, _1388);
    float3 _1421 = _1420.xyz;
    float4 _1428 = Source.Sample(_Source_sampler, _1398);
    float _1479 = _1363.x;
    float _2991;
    do
    {
        float _1771 = abs((-1.0f) - _1479);
        if (_1771 < 1.0f)
        {
            _2991 = ((((_1771 - 1.7999999523162841796875f) * _1771) - 0.20000000298023223876953125f) * _1771) + 1.0f;
            break;
        }
        else
        {
            if ((_1771 >= 1.0f) && (_1771 < 2.0f))
            {
                float _1791 = _1771 - 1.0f;
                _2991 = (((((-0.3333333432674407958984375f) * _1791) + 0.800000011920928955078125f) * _1791) - 0.4666666686534881591796875f) * _1791;
                break;
            }
            else
            {
                _2991 = 0.0f;
                break;
            }
            break; // unreachable workaround
        }
        break; // unreachable workaround
    } while(false);
    float _2993;
    do
    {
        float _1812 = abs(-_1479);
        if (_1812 < 1.0f)
        {
            _2993 = ((((_1812 - 1.7999999523162841796875f) * _1812) - 0.20000000298023223876953125f) * _1812) + 1.0f;
            break;
        }
        else
        {
            if ((_1812 >= 1.0f) && (_1812 < 2.0f))
            {
                float _1832 = _1812 - 1.0f;
                _2993 = (((((-0.3333333432674407958984375f) * _1832) + 0.800000011920928955078125f) * _1832) - 0.4666666686534881591796875f) * _1832;
                break;
            }
            else
            {
                _2993 = 0.0f;
                break;
            }
            break; // unreachable workaround
        }
        break; // unreachable workaround
    } while(false);
    float _2995;
    do
    {
        float _1853 = abs(1.0f - _1479);
        if (_1853 < 1.0f)
        {
            _2995 = ((((_1853 - 1.7999999523162841796875f) * _1853) - 0.20000000298023223876953125f) * _1853) + 1.0f;
            break;
        }
        else
        {
            if ((_1853 >= 1.0f) && (_1853 < 2.0f))
            {
                float _1873 = _1853 - 1.0f;
                _2995 = (((((-0.3333333432674407958984375f) * _1873) + 0.800000011920928955078125f) * _1873) - 0.4666666686534881591796875f) * _1873;
                break;
            }
            else
            {
                _2995 = 0.0f;
                break;
            }
            break; // unreachable workaround
        }
        break; // unreachable workaround
    } while(false);
    float _2997;
    do
    {
        float _1894 = abs(2.0f - _1479);
        if (_1894 < 1.0f)
        {
            _2997 = ((((_1894 - 1.7999999523162841796875f) * _1894) - 0.20000000298023223876953125f) * _1894) + 1.0f;
            break;
        }
        else
        {
            if ((_1894 >= 1.0f) && (_1894 < 2.0f))
            {
                float _1914 = _1894 - 1.0f;
                _2997 = (((((-0.3333333432674407958984375f) * _1914) + 0.800000011920928955078125f) * _1914) - 0.4666666686534881591796875f) * _1914;
                break;
            }
            else
            {
                _2997 = 0.0f;
                break;
            }
            break; // unreachable workaround
        }
        break; // unreachable workaround
    } while(false);
    float4 _1764 = float4(_2991, _2993, _2995, _2997);
    float3 _1490 = dot(_1764, 1.0f.xxxx).xxx;
    float3 _1491 = mul(_1764, float4x3(float3(_1375.xyz), float3(_1382.xyz), float3(_1391.xyz), float3(_1401.xyz))) / _1490;
    float3 _1499 = mul(_1764, float4x3(float3(_1408.xyz), float3(_1413.xyz), float3(_1420.xyz), float3(_1428.xyz))) / _1490;
    float3 _1536 = lerp(_1491, clamp(_1491, min(_1383, _1392), max(_1383, _1392)), step(0.0f.xxx, (_1375.xyz - _1383) * (_1392 - _1401.xyz)) * param_CRT_ANTI_RINGING);
    float3 _1556 = lerp(_1499, clamp(_1499, min(_1414, _1421), max(_1414, _1421)), step(0.0f.xxx, (_1408.xyz - _1414) * (_1421 - _1428.xyz)) * param_CRT_ANTI_RINGING);
    float _1559 = _1363.y;
    float3 _1567 = param_BEAM_MIN_WIDTH.xxx;
    float3 _1570 = param_BEAM_MAX_WIDTH.xxx;
    float3 _1572 = lerp(_1567, _1570, _1536);
    float3 _1581 = lerp(_1567, _1570, _1556);
    float _1585 = 2.0f * param_SCANLINES_STRENGTH;
    float3 _1598 = clamp((_1585 * _1559).xxx / ((_1572 * _1572) + 1.0000000116860974230803549289703e-07f.xxx), 0.0f.xxx, 1.0f.xxx);
    float3 _1614 = clamp((_1585 * (1.0f - _1559)).xxx / ((_1581 * _1581) + 1.0000000116860974230803549289703e-07f.xxx), 0.0f.xxx, 1.0f.xxx);
    float _1936 = _1598.x;
    float _3038;
    if (_1936 <= 0.001000000047497451305389404296875f)
    {
        _3038 = 4.93480205535888671875f;
    }
    else
    {
        _3038 = (sin(_1936 * 1.57079637050628662109375f) * sin(_1936 * 3.1415927410125732421875f)) / (_1936 * _1936);
    }
    float _1959 = _1598.y;
    float _3039;
    if (_1959 <= 0.001000000047497451305389404296875f)
    {
        _3039 = 4.93480205535888671875f;
    }
    else
    {
        _3039 = (sin(_1959 * 1.57079637050628662109375f) * sin(_1959 * 3.1415927410125732421875f)) / (_1959 * _1959);
    }
    float _1982 = _1598.z;
    float _3040;
    if (_1982 <= 0.001000000047497451305389404296875f)
    {
        _3040 = 4.93480205535888671875f;
    }
    else
    {
        _3040 = (sin(_1982 * 1.57079637050628662109375f) * sin(_1982 * 3.1415927410125732421875f)) / (_1982 * _1982);
    }
    float _2012 = _1614.x;
    float _3044;
    if (_2012 <= 0.001000000047497451305389404296875f)
    {
        _3044 = 4.93480205535888671875f;
    }
    else
    {
        _3044 = (sin(_2012 * 1.57079637050628662109375f) * sin(_2012 * 3.1415927410125732421875f)) / (_2012 * _2012);
    }
    float _2035 = _1614.y;
    float _3045;
    if (_2035 <= 0.001000000047497451305389404296875f)
    {
        _3045 = 4.93480205535888671875f;
    }
    else
    {
        _3045 = (sin(_2035 * 1.57079637050628662109375f) * sin(_2035 * 3.1415927410125732421875f)) / (_2035 * _2035);
    }
    float _2058 = _1614.z;
    float _3046;
    if (_2058 <= 0.001000000047497451305389404296875f)
    {
        _3046 = 4.93480205535888671875f;
    }
    else
    {
        _3046 = (sin(_2058 * 1.57079637050628662109375f) * sin(_2058 * 3.1415927410125732421875f)) / (_2058 * _2058);
    }
    float2 _1640 = vTexCoord * global_OutputSize.xy;
    float2 _1647 = lerp(_1640, _1640.yx, _1286);
    int _1650 = int(param_PHOSPHOR_LAYOUT);
    float3 _3062;
    do
    {
        float _2123 = 1.0f - param_MASK_INTENSITY;
        float3 _2126 = float3(1.0f, _2123, _2123);
        float3 _2130 = float3(_2123, 1.0f, _2123);
        float3 _2133 = float3(_2123, _2123, 1.0f);
        float3 _2137 = float3(1.0f, _2123, 1.0f);
        float3 _2140 = float3(1.0f, 1.0f, _2123);
        float3 _2143 = float3(_2123, 1.0f, 1.0f);
        float3 _2145 = _2123.xxx;
        float _2151 = _1647.x;
        float3 _2154 = floor(mod(_2151, 2.0f)).xxx;
        float3 _2155 = lerp(_2137, _2130, _2154);
        if (_1650 == 0)
        {
            _3062 = 1.0f.xxx;
            break;
        }
        else
        {
            if (_1650 == 1)
            {
                _3062 = _2155;
                break;
            }
            else
            {
                if (_1650 == 2)
                {
                    _3062 = lerp(_2155, lerp(_2130, _2137, _2154), floor(mod(_1647.y, 2.0f)).xxx);
                    break;
                }
                else
                {
                    if (_1650 == 3)
                    {
                        float3 _2194[4] = { _2137, _2130, _2145, _2145 };
                        float3 _2199[4] = { _2137, _2130, _2137, _2130 };
                        float3 _2203[4] = { _2145, _2145, _2137, _2130 };
                        float3 _2204[3][4] = { _2194, _2199, _2203 };
                        float3 _2097[3][4] = _2204;
                        _3062 = _2097[int(floor(mod(_1647.y, 3.0f)))][int(floor(mod(_2151, 4.0f)))];
                        break;
                    }
                    else
                    {
                        if (_1650 == 4)
                        {
                            _3062 = lerp(_2140, _2133, _2154);
                            break;
                        }
                        else
                        {
                            if (_1650 == 5)
                            {
                                _3062 = lerp(lerp(_2140, _2133, _2154), lerp(_2133, _2140, _2154), floor(mod(_1647.y, 2.0f)).xxx);
                                break;
                            }
                            else
                            {
                                if (_1650 == 6)
                                {
                                    float3 _2269[4] = { _2126, _2130, _2133, _2145 };
                                    float3 _2100[4] = _2269;
                                    _3062 = _2100[int(floor(mod(_2151, 4.0f)))];
                                    break;
                                }
                                else
                                {
                                    if (_1650 == 7)
                                    {
                                        float3 _2287[5] = { _2126, _2137, _2133, _2130, _2130 };
                                        float3 _2101[5] = _2287;
                                        _3062 = _2101[int(floor(mod(_2151, 5.0f)))];
                                        break;
                                    }
                                    else
                                    {
                                        if (_1650 == 8)
                                        {
                                            float3 _2306[7] = { _2126, _2126, _2140, _2130, _2143, _2133, _2133 };
                                            float3 _2102[7] = _2306;
                                            _3062 = _2102[int(floor(mod(_2151, 7.0f)))];
                                            break;
                                        }
                                        else
                                        {
                                            if (_1650 == 9)
                                            {
                                                float3 _2324[4] = { _2126, _2140, _2143, _2133 };
                                                float3 _2103[4] = _2324;
                                                _3062 = _2103[int(floor(mod(_2151, 4.0f)))];
                                                break;
                                            }
                                            else
                                            {
                                                if (_1650 == 10)
                                                {
                                                    float3 _2342[4] = { _2126, _2137, _2143, _2130 };
                                                    float3 _2104[4] = _2342;
                                                    _3062 = _2104[int(floor(mod(_2151, 4.0f)))];
                                                    break;
                                                }
                                                else
                                                {
                                                    if (_1650 == 11)
                                                    {
                                                        float3 _2360[4] = { _2126, _2130, _2133, _2145 };
                                                        float3 _2365[4] = { _2133, _2145, _2126, _2130 };
                                                        float3 _2366[2][4] = { _2360, _2365 };
                                                        float3 _2105[2][4] = _2366;
                                                        _3062 = _2105[int(floor(mod(_1647.y, 2.0f)))][int(floor(mod(_2151, 4.0f)))];
                                                        break;
                                                    }
                                                    else
                                                    {
                                                        if (_1650 == 12)
                                                        {
                                                            float3 _2390[4] = { _2126, _2140, _2143, _2133 };
                                                            float3 _2395[4] = { _2143, _2133, _2126, _2140 };
                                                            float3 _2396[2][4] = { _2390, _2395 };
                                                            float3 _2106[2][4] = _2396;
                                                            _3062 = _2106[int(floor(mod(_1647.y, 2.0f)))][int(floor(mod(_2151, 4.0f)))];
                                                            break;
                                                        }
                                                        else
                                                        {
                                                            if (_1650 == 13)
                                                            {
                                                                float3 _2420[4] = { _2126, _2140, _2143, _2133 };
                                                                float3 _2430[4] = { _2143, _2133, _2126, _2140 };
                                                                float3 _2436[4][4] = { _2420, _2420, _2430, _2430 };
                                                                float3 _2107[4][4] = _2436;
                                                                _3062 = _2107[int(floor(mod(_1647.y, 4.0f)))][int(floor(mod(_2151, 4.0f)))];
                                                                break;
                                                            }
                                                            else
                                                            {
                                                                if (_1650 == 14)
                                                                {
                                                                    float3 _2459[6] = { _2137, _2130, _2145, _2145, _2145, _2145 };
                                                                    float3 _2466[6] = { _2137, _2130, _2145, _2137, _2130, _2145 };
                                                                    float3 _2471[6] = { _2145, _2145, _2145, _2137, _2130, _2145 };
                                                                    float3 _2472[3][6] = { _2459, _2466, _2471 };
                                                                    float3 _2108[3][6] = _2472;
                                                                    _3062 = _2108[int(floor(mod(_1647.y, 3.0f)))][int(floor(mod(_2151, 6.0f)))];
                                                                    break;
                                                                }
                                                                else
                                                                {
                                                                    if (_1650 == 15)
                                                                    {
                                                                        float3 _2500[8] = { _2126, _2140, _2143, _2133, _2126, _2140, _2143, _2133 };
                                                                        float3 _2506[8] = { _2126, _2140, _2143, _2133, _2145, _2145, _2145, _2145 };
                                                                        float3 _2521[8] = { _2145, _2145, _2145, _2145, _2126, _2140, _2143, _2133 };
                                                                        float3 _2522[4][8] = { _2500, _2506, _2500, _2521 };
                                                                        float3 _2109[4][8] = _2522;
                                                                        _3062 = _2109[int(floor(mod(_1647.y, 4.0f)))][int(floor(mod(_2151, 8.0f)))];
                                                                        break;
                                                                    }
                                                                    else
                                                                    {
                                                                        if (_1650 == 16)
                                                                        {
                                                                            float3 _2545[4] = { _2140, _2133, _2145, _2145 };
                                                                            float3 _2550[4] = { _2140, _2133, _2140, _2133 };
                                                                            float3 _2554[4] = { _2145, _2145, _2140, _2133 };
                                                                            float3 _2555[3][4] = { _2545, _2550, _2554 };
                                                                            float3 _2110[3][4] = _2555;
                                                                            _3062 = _2110[int(floor(mod(_1647.y, 3.0f)))][int(floor(mod(_2151, 4.0f)))];
                                                                            break;
                                                                        }
                                                                        else
                                                                        {
                                                                            if (_1650 == 17)
                                                                            {
                                                                                float3 _2583[10] = { _2126, _2137, _2133, _2130, _2130, _2126, _2137, _2133, _2130, _2130 };
                                                                                float3 _2589[10] = { _2145, _2133, _2133, _2130, _2130, _2126, _2126, _2145, _2145, _2145 };
                                                                                float3 _2603[10] = { _2126, _2126, _2145, _2145, _2145, _2145, _2133, _2133, _2130, _2130 };
                                                                                float3 _2604[4][10] = { _2583, _2589, _2583, _2603 };
                                                                                float3 _2111[4][10] = _2604;
                                                                                _3062 = _2111[int(floor(mod(_1647.y, 4.0f)))][int(floor(mod(_2151, 10.0f)))];
                                                                                break;
                                                                            }
                                                                            else
                                                                            {
                                                                                if (_1650 == 18)
                                                                                {
                                                                                    float3 _2632[10] = { _2126, _2140, _2130, _2133, _2133, _2126, _2140, _2130, _2133, _2133 };
                                                                                    float3 _2638[10] = { _2145, _2130, _2130, _2133, _2133, _2126, _2126, _2145, _2145, _2145 };
                                                                                    float3 _2652[10] = { _2126, _2126, _2145, _2145, _2145, _2145, _2130, _2130, _2133, _2133 };
                                                                                    float3 _2653[4][10] = { _2632, _2638, _2632, _2652 };
                                                                                    float3 _2112[4][10] = _2653;
                                                                                    _3062 = _2112[int(floor(mod(_1647.y, 4.0f)))][int(floor(mod(_2151, 10.0f)))];
                                                                                    break;
                                                                                }
                                                                                else
                                                                                {
                                                                                    if (_1650 == 19)
                                                                                    {
                                                                                        float3 _2683[14] = { _2126, _2126, _2140, _2130, _2143, _2133, _2133, _2126, _2126, _2140, _2130, _2143, _2133, _2133 };
                                                                                        float3 _2701[14] = { _2126, _2126, _2140, _2130, _2143, _2133, _2133, _2145, _2145, _2145, _2145, _2145, _2145, _2145 };
                                                                                        float3 _2730[14] = { _2145, _2145, _2145, _2145, _2145, _2145, _2145, _2145, _2126, _2126, _2140, _2130, _2143, _2133 };
                                                                                        float3 _2731[6][14] = { _2683, _2683, _2701, _2683, _2683, _2730 };
                                                                                        float3 _2113[6][14] = _2731;
                                                                                        _3062 = _2113[int(floor(mod(_1647.y, 6.0f)))][int(floor(mod(_2151, 14.0f)))];
                                                                                        break;
                                                                                    }
                                                                                    else
                                                                                    {
                                                                                        if (_1650 == 20)
                                                                                        {
                                                                                            float3 _2755[4] = { _2130, _2137, _2130, _2137 };
                                                                                            float3 _2760[4] = { _2145, _2133, _2130, _2126 };
                                                                                            float3 _2770[4] = { _2130, _2126, _2145, _2133 };
                                                                                            float3 _2771[4][4] = { _2755, _2760, _2755, _2770 };
                                                                                            float3 _2114[4][4] = _2771;
                                                                                            _3062 = _2114[int(floor(mod(_1647.y, 4.0f)))][int(floor(mod(_2151, 4.0f)))];
                                                                                            break;
                                                                                        }
                                                                                        else
                                                                                        {
                                                                                            if (_1650 == 21)
                                                                                            {
                                                                                                float3 _2799[8] = { _2126, _2130, _2133, _2145, _2126, _2130, _2133, _2145 };
                                                                                                float3 _2804[8] = { _2126, _2130, _2133, _2145, _2145, _2145, _2145, _2145 };
                                                                                                float3 _2819[8] = { _2145, _2145, _2145, _2145, _2126, _2130, _2133, _2145 };
                                                                                                float3 _2820[4][8] = { _2799, _2804, _2799, _2819 };
                                                                                                float3 _2115[4][8] = _2820;
                                                                                                _3062 = _2115[int(floor(mod(_1647.y, 4.0f)))][int(floor(mod(_2151, 8.0f)))];
                                                                                                break;
                                                                                            }
                                                                                            else
                                                                                            {
                                                                                                if (_1650 == 22)
                                                                                                {
                                                                                                    float3 _2842[3] = { _2145, 1.0f.xxx, 1.0f.xxx };
                                                                                                    float3 _2116[3] = _2842;
                                                                                                    _3062 = _2116[int(floor(mod(_2151, 3.0f)))];
                                                                                                    break;
                                                                                                }
                                                                                                else
                                                                                                {
                                                                                                    if (_1650 == 23)
                                                                                                    {
                                                                                                        float3 _2858[4] = { _2145, _2145, 1.0f.xxx, 1.0f.xxx };
                                                                                                        float3 _2117[4] = _2858;
                                                                                                        _3062 = _2117[int(floor(mod(_2151, 4.0f)))];
                                                                                                        break;
                                                                                                    }
                                                                                                    else
                                                                                                    {
                                                                                                        if (_1650 == 24)
                                                                                                        {
                                                                                                            float3 _2878[10] = { _2130, _2143, _2133, _2133, _2133, _2126, _2126, _2126, _2140, _2130 };
                                                                                                            float3 _2898[10] = { _2126, _2126, _2126, _2140, _2130, _2130, _2143, _2133, _2133, _2133 };
                                                                                                            float3 _2911[6][10] = { _2878, _2878, _2878, _2898, _2898, _2898 };
                                                                                                            float3 _2118[6][10] = _2911;
                                                                                                            _3062 = _2118[int(floor(mod(_1647.y, 6.0f)))][int(floor(mod(_2151, 10.0f)))];
                                                                                                            break;
                                                                                                        }
                                                                                                        else
                                                                                                        {
                                                                                                            _3062 = 1.0f.xxx;
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
        }
        break; // unreachable workaround
    } while(false);
    FragColor = float4(((((_1536 * float3(_3038, _3039, _3040)) + (_1556 * float3(_3044, _3045, _3046))) * param_COLOR_BOOST) * 0.20264236629009246826171875f.xxx) * _3062, 1.0f);
    float _3075;
    if (_1320)
    {
        float2 _2970 = param_CRT_cornersize.xx;
        float2 _2975 = _2970 - min(min(_2988, 1.0f.xx - _2988) * float2(1.0f, 0.75f), _2970);
        _3075 = clamp((param_CRT_cornersize - sqrt(dot(_2975, _2975))) * param_CRT_cornersmooth, 0.0f, 1.0f);
    }
    else
    {
        _3075 = 1.0f;
    }
    FragColor *= _3075;
}

SPIRV_Cross_Output main(SPIRV_Cross_Input stage_input)
{
    vTexCoord = stage_input.vTexCoord;
    frag_main();
    SPIRV_Cross_Output stage_output;
    stage_output.FragColor = FragColor;
    return stage_output;
}
