// Generated from crt/shaders/crt-lottes-fast.slang. See slang/upstream for licence/source.
cbuffer Push : register(b1)
{
    float4 params_SourceSize : packoffset(c0);
    float4 params_OutputSize : packoffset(c2);
    float params_MASK : packoffset(c3.y);
    float params_MASK_INTENSITY : packoffset(c3.z);
    float params_SCANLINE_THINNESS : packoffset(c3.w);
    float params_SCAN_BLUR : packoffset(c4);
    float params_CURVATURE : packoffset(c4.y);
    float params_TRINITRON_CURVE : packoffset(c4.z);
    float params_CORNER : packoffset(c4.w);
    float params_CRT_GAMMA : packoffset(c5);
};

Texture2D<float4> Source : register(t2);
SamplerState _Source_sampler : register(s2);

static float4 FragColor;
static float2 vTexCoord;

struct SPIRV_Cross_Input
{
    float2 vTexCoord : TEXCOORD0;
};

struct SPIRV_Cross_Output
{
    float4 FragColor : SV_Target0;
};

void frag_main()
{
    float2 _721 = vTexCoord * params_OutputSize.xy;
    float2 _733 = params_SourceSize.xy * 0.5f.xx;
    float _741 = 0.5f * params_SCANLINE_THINNESS;
    float _742 = 0.5f + _741;
    float _747 = (-1.0f) * params_SCAN_BLUR;
    float _751 = 1.0f - params_MASK_INTENSITY;
    float _2374 = (params_MASK == 0.0f) ? 1.0f : _751;
    bool _827 = params_MASK == 1.0f;
    float _2084;
    if (_827)
    {
        _2084 = 0.5f + (_2374 * 0.5f);
    }
    else
    {
        _2084 = _2374;
    }
    float _838 = (1.0f - _741) * ((0.5f * _2084) + 0.5f);
    float _839 = 0.180000007152557373046875f / _838;
    float _857 = (-0.0324000008404254913330078125f) / _838;
    float2 _921 = (_721 * (params_OutputSize.zw * 2.0f)) - 1.0f.xx;
    float _923 = _921.y;
    float _932 = _921.x;
    float2 _942 = _921 * float2(1.0f + ((_923 * _923) * (params_CURVATURE * (1.0f - params_TRINITRON_CURVE))), 1.0f + ((_932 * _932) * (0.75f * params_CURVATURE)));
    float _944 = _942.x;
    float _951 = _942.y;
    float2 _975 = (_942 * _733) + _733;
    float _977 = _975.y;
    float _980 = floor(_977 - 0.5f) + 0.5f;
    float _982 = _975.x;
    float _985 = floor(_982 - 1.5f) + 0.5f;
    float _989 = _985 * params_SourceSize.z;
    float _993 = _980 * params_SourceSize.w;
    float2 _994 = float2(_989, _993);
    float2 _1222 = float2(params_SourceSize.x, params_SourceSize.y) / params_SourceSize.xy;
    float4 _1227 = Source.SampleBias(_Source_sampler, _994 * _1222, -16.0f);
    float _1236 = _1227.x;
    float _2089;
    if (_1236 <= 0.040449999272823333740234375f)
    {
        _2089 = _1236 * 0.077399380505084991455078125f;
    }
    else
    {
        _2089 = pow((abs(_1236) * 0.94786727428436279296875f) + 0.0521326996386051177978515625f, params_CRT_GAMMA);
    }
    float _1239 = _1227.y;
    float _2090;
    if (_1239 <= 0.040449999272823333740234375f)
    {
        _2090 = _1239 * 0.077399380505084991455078125f;
    }
    else
    {
        _2090 = pow((abs(_1239) * 0.94786727428436279296875f) + 0.0521326996386051177978515625f, params_CRT_GAMMA);
    }
    float _1242 = _1227.z;
    float _2091;
    if (_1242 <= 0.040449999272823333740234375f)
    {
        _2091 = _1242 * 0.077399380505084991455078125f;
    }
    else
    {
        _2091 = pow((abs(_1242) * 0.94786727428436279296875f) + 0.0521326996386051177978515625f, params_CRT_GAMMA);
    }
    float _1001 = _989 + params_SourceSize.z;
    _994.x = _1001;
    float4 _1315 = Source.SampleBias(_Source_sampler, _994 * _1222, -16.0f);
    float _1324 = _1315.x;
    float _2092;
    if (_1324 <= 0.040449999272823333740234375f)
    {
        _2092 = _1324 * 0.077399380505084991455078125f;
    }
    else
    {
        _2092 = pow((abs(_1324) * 0.94786727428436279296875f) + 0.0521326996386051177978515625f, params_CRT_GAMMA);
    }
    float _1327 = _1315.y;
    float _2093;
    if (_1327 <= 0.040449999272823333740234375f)
    {
        _2093 = _1327 * 0.077399380505084991455078125f;
    }
    else
    {
        _2093 = pow((abs(_1327) * 0.94786727428436279296875f) + 0.0521326996386051177978515625f, params_CRT_GAMMA);
    }
    float _1330 = _1315.z;
    float _2094;
    if (_1330 <= 0.040449999272823333740234375f)
    {
        _2094 = _1330 * 0.077399380505084991455078125f;
    }
    else
    {
        _2094 = pow((abs(_1330) * 0.94786727428436279296875f) + 0.0521326996386051177978515625f, params_CRT_GAMMA);
    }
    float _1009 = _1001 + params_SourceSize.z;
    _994.x = _1009;
    float4 _1403 = Source.SampleBias(_Source_sampler, _994 * _1222, -16.0f);
    float _1412 = _1403.x;
    float _2095;
    if (_1412 <= 0.040449999272823333740234375f)
    {
        _2095 = _1412 * 0.077399380505084991455078125f;
    }
    else
    {
        _2095 = pow((abs(_1412) * 0.94786727428436279296875f) + 0.0521326996386051177978515625f, params_CRT_GAMMA);
    }
    float _1415 = _1403.y;
    float _2096;
    if (_1415 <= 0.040449999272823333740234375f)
    {
        _2096 = _1415 * 0.077399380505084991455078125f;
    }
    else
    {
        _2096 = pow((abs(_1415) * 0.94786727428436279296875f) + 0.0521326996386051177978515625f, params_CRT_GAMMA);
    }
    float _1418 = _1403.z;
    float _2097;
    if (_1418 <= 0.040449999272823333740234375f)
    {
        _2097 = _1418 * 0.077399380505084991455078125f;
    }
    else
    {
        _2097 = pow((abs(_1418) * 0.94786727428436279296875f) + 0.0521326996386051177978515625f, params_CRT_GAMMA);
    }
    float _1017 = _1009 + params_SourceSize.z;
    _994.x = _1017;
    float4 _1491 = Source.SampleBias(_Source_sampler, _994 * _1222, -16.0f);
    float _1500 = _1491.x;
    float _2098;
    if (_1500 <= 0.040449999272823333740234375f)
    {
        _2098 = _1500 * 0.077399380505084991455078125f;
    }
    else
    {
        _2098 = pow((abs(_1500) * 0.94786727428436279296875f) + 0.0521326996386051177978515625f, params_CRT_GAMMA);
    }
    float _1503 = _1491.y;
    float _2099;
    if (_1503 <= 0.040449999272823333740234375f)
    {
        _2099 = _1503 * 0.077399380505084991455078125f;
    }
    else
    {
        _2099 = pow((abs(_1503) * 0.94786727428436279296875f) + 0.0521326996386051177978515625f, params_CRT_GAMMA);
    }
    float _1506 = _1491.z;
    float _2100;
    if (_1506 <= 0.040449999272823333740234375f)
    {
        _2100 = _1506 * 0.077399380505084991455078125f;
    }
    else
    {
        _2100 = pow((abs(_1506) * 0.94786727428436279296875f) + 0.0521326996386051177978515625f, params_CRT_GAMMA);
    }
    float2 _2542 = float2(_1017, _993 + params_SourceSize.w);
    float4 _1579 = Source.SampleBias(_Source_sampler, _2542 * _1222, -16.0f);
    float _1588 = _1579.x;
    float _2101;
    if (_1588 <= 0.040449999272823333740234375f)
    {
        _2101 = _1588 * 0.077399380505084991455078125f;
    }
    else
    {
        _2101 = pow((abs(_1588) * 0.94786727428436279296875f) + 0.0521326996386051177978515625f, params_CRT_GAMMA);
    }
    float _1591 = _1579.y;
    float _2102;
    if (_1591 <= 0.040449999272823333740234375f)
    {
        _2102 = _1591 * 0.077399380505084991455078125f;
    }
    else
    {
        _2102 = pow((abs(_1591) * 0.94786727428436279296875f) + 0.0521326996386051177978515625f, params_CRT_GAMMA);
    }
    float _1594 = _1579.z;
    float _2103;
    if (_1594 <= 0.040449999272823333740234375f)
    {
        _2103 = _1594 * 0.077399380505084991455078125f;
    }
    else
    {
        _2103 = pow((abs(_1594) * 0.94786727428436279296875f) + 0.0521326996386051177978515625f, params_CRT_GAMMA);
    }
    float _1033 = _1017 - params_SourceSize.z;
    _2542.x = _1033;
    float4 _1667 = Source.SampleBias(_Source_sampler, _2542 * _1222, -16.0f);
    float _1676 = _1667.x;
    float _2104;
    if (_1676 <= 0.040449999272823333740234375f)
    {
        _2104 = _1676 * 0.077399380505084991455078125f;
    }
    else
    {
        _2104 = pow((abs(_1676) * 0.94786727428436279296875f) + 0.0521326996386051177978515625f, params_CRT_GAMMA);
    }
    float _1679 = _1667.y;
    float _2105;
    if (_1679 <= 0.040449999272823333740234375f)
    {
        _2105 = _1679 * 0.077399380505084991455078125f;
    }
    else
    {
        _2105 = pow((abs(_1679) * 0.94786727428436279296875f) + 0.0521326996386051177978515625f, params_CRT_GAMMA);
    }
    float _1682 = _1667.z;
    float _2106;
    if (_1682 <= 0.040449999272823333740234375f)
    {
        _2106 = _1682 * 0.077399380505084991455078125f;
    }
    else
    {
        _2106 = pow((abs(_1682) * 0.94786727428436279296875f) + 0.0521326996386051177978515625f, params_CRT_GAMMA);
    }
    float _1041 = _1033 - params_SourceSize.z;
    _2542.x = _1041;
    float4 _1755 = Source.SampleBias(_Source_sampler, _2542 * _1222, -16.0f);
    float _1764 = _1755.x;
    float _2107;
    if (_1764 <= 0.040449999272823333740234375f)
    {
        _2107 = _1764 * 0.077399380505084991455078125f;
    }
    else
    {
        _2107 = pow((abs(_1764) * 0.94786727428436279296875f) + 0.0521326996386051177978515625f, params_CRT_GAMMA);
    }
    float _1767 = _1755.y;
    float _2108;
    if (_1767 <= 0.040449999272823333740234375f)
    {
        _2108 = _1767 * 0.077399380505084991455078125f;
    }
    else
    {
        _2108 = pow((abs(_1767) * 0.94786727428436279296875f) + 0.0521326996386051177978515625f, params_CRT_GAMMA);
    }
    float _1770 = _1755.z;
    float _2109;
    if (_1770 <= 0.040449999272823333740234375f)
    {
        _2109 = _1770 * 0.077399380505084991455078125f;
    }
    else
    {
        _2109 = pow((abs(_1770) * 0.94786727428436279296875f) + 0.0521326996386051177978515625f, params_CRT_GAMMA);
    }
    _2542.x = _1041 - params_SourceSize.z;
    float4 _1843 = Source.SampleBias(_Source_sampler, _2542 * _1222, -16.0f);
    float _1852 = _1843.x;
    float _2110;
    if (_1852 <= 0.040449999272823333740234375f)
    {
        _2110 = _1852 * 0.077399380505084991455078125f;
    }
    else
    {
        _2110 = pow((abs(_1852) * 0.94786727428436279296875f) + 0.0521326996386051177978515625f, params_CRT_GAMMA);
    }
    float _1855 = _1843.y;
    float _2111;
    if (_1855 <= 0.040449999272823333740234375f)
    {
        _2111 = _1855 * 0.077399380505084991455078125f;
    }
    else
    {
        _2111 = pow((abs(_1855) * 0.94786727428436279296875f) + 0.0521326996386051177978515625f, params_CRT_GAMMA);
    }
    float _1858 = _1843.z;
    float _2112;
    if (_1858 <= 0.040449999272823333740234375f)
    {
        _2112 = _1858 * 0.077399380505084991455078125f;
    }
    else
    {
        _2112 = pow((abs(_1858) * 0.94786727428436279296875f) + 0.0521326996386051177978515625f, params_CRT_GAMMA);
    }
    float _1056 = _977 - _980;
    float _1085 = _982 - _985;
    float _1087 = _1085 - 1.0f;
    float _1089 = _1085 - 2.0f;
    float _1091 = _1085 - 3.0f;
    float _1097 = exp2((_747 * _1085) * _1085);
    float _1103 = exp2((_747 * _1087) * _1087);
    float _1109 = exp2((_747 * _1089) * _1089);
    float _1115 = exp2((_747 * _1091) * _1091);
    float _1126 = (1.0f / (((_1097 + _1103) + _1109) + _1115)) * clamp(((-((1.0f - ((1.0f - clamp(_944 * _944, 0.0f, 1.0f)) * (1.0f - clamp(_951 * _951, 0.0f, 1.0f)))) * (0.99800002574920654296875f + (0.001000000047497451305389404296875f * params_CORNER)))) * params_SourceSize.y) + params_SourceSize.y, 0.0f, 1.0f);
    float3 _2365;
    do
    {
        if (params_MASK == 2.0f)
        {
            float3 _1931 = _751.xxx;
            float _1935 = frac(_721.x * 0.3333333432674407958984375f);
            float3 _2531;
            if (_1935 < 0.3333333432674407958984375f)
            {
                float3 _2483 = _1931;
                _2483.x = 1.0f;
                _2531 = _2483;
            }
            else
            {
                float3 _2532;
                if (_1935 < 0.666666686534881591796875f)
                {
                    float3 _2481 = _1931;
                    _2481.y = 1.0f;
                    _2532 = _2481;
                }
                else
                {
                    float3 _2479 = _1931;
                    _2479.z = 1.0f;
                    _2532 = _2479;
                }
                _2531 = _2532;
            }
            _2365 = _2531;
            break;
        }
        else
        {
            if (_827)
            {
                float _1958 = frac(_721.x * 0.3333333432674407958984375f);
                float3 _2529;
                if (_1958 < 0.3333333432674407958984375f)
                {
                    float3 _2476 = 1.0f.xxx;
                    _2476.x = _751;
                    _2529 = _2476;
                }
                else
                {
                    float3 _2530;
                    if (_1958 < 0.666666686534881591796875f)
                    {
                        float3 _2474 = 1.0f.xxx;
                        _2474.y = _751;
                        _2530 = _2474;
                    }
                    else
                    {
                        float3 _2472 = 1.0f.xxx;
                        _2472.z = _751;
                        _2530 = _2472;
                    }
                    _2529 = _2530;
                }
                _2365 = _2529;
                break;
            }
            else
            {
                if (params_MASK == 3.0f)
                {
                    float3 _1989 = _751.xxx;
                    float _1993 = frac((_721.x + (_721.y * 2.9999001026153564453125f)) * 0.16666667163372039794921875f);
                    float3 _2527;
                    if (_1993 < 0.3333333432674407958984375f)
                    {
                        float3 _2469 = _1989;
                        _2469.x = 1.0f;
                        _2527 = _2469;
                    }
                    else
                    {
                        float3 _2528;
                        if (_1993 < 0.666666686534881591796875f)
                        {
                            float3 _2467 = _1989;
                            _2467.y = 1.0f;
                            _2528 = _2467;
                        }
                        else
                        {
                            float3 _2465 = _1989;
                            _2465.z = 1.0f;
                            _2528 = _2465;
                        }
                        _2527 = _2528;
                    }
                    _2365 = _2527;
                    break;
                }
                else
                {
                    _2365 = 1.0f.xxx;
                    break;
                }
                break; // unreachable workaround
            }
            break; // unreachable workaround
        }
        break; // unreachable workaround
    } while(false);
    float3 _1172 = ((((((float3(_2089, _2090, _2091) * _1097) + (float3(_2092, _2093, _2094) * _1103)) + (float3(_2095, _2096, _2097) * _1109)) + (float3(_2098, _2099, _2100) * _1115)) * (((cos(min(0.5f, _1056 * _742) * 6.283185482025146484375f) * 0.5f) + 0.5f) * _1126)) + (((((float3(_2110, _2111, _2112) * _1097) + (float3(_2107, _2108, _2109) * _1103)) + (float3(_2104, _2105, _2106) * _1109)) + (float3(_2101, _2102, _2103) * _1115)) * (((cos(min(0.5f, ((-_1056) * _742) + _742) * 6.283185482025146484375f) * 0.5f) + 0.5f) * _1126))) * _2365;
    float _1180 = max(5.9604644775390625e-08f, max(_1172.x, max(_1172.y, _1172.z)));
    float _1188 = pow(_1180, 1.0f);
    float3 _1210 = pow(_1172 * (1.0f / _1180), 1.0f.xxx) * (_1188 * (1.0f / ((_1188 * (((-0.180000007152557373046875f) + _839) / (0.14760001003742218017578125f / _838))) + ((_857 + 0.180000007152557373046875f) / (_857 + _839)))));
    FragColor.x = _1210.x;
    FragColor.y = _1210.y;
    FragColor.z = _1210.z;
    float _2366;
    if (FragColor.x < 0.003130800090730190277099609375f)
    {
        _2366 = FragColor.x * 12.9200000762939453125f;
    }
    else
    {
        _2366 = (1.05499994754791259765625f * pow(FragColor.x, 0.416660010814666748046875f)) - 0.054999999701976776123046875f;
    }
    float _2367;
    if (FragColor.y < 0.003130800090730190277099609375f)
    {
        _2367 = FragColor.y * 12.9200000762939453125f;
    }
    else
    {
        _2367 = (1.05499994754791259765625f * pow(FragColor.y, 0.416660010814666748046875f)) - 0.054999999701976776123046875f;
    }
    float _2368;
    if (FragColor.z < 0.003130800090730190277099609375f)
    {
        _2368 = FragColor.z * 12.9200000762939453125f;
    }
    else
    {
        _2368 = (1.05499994754791259765625f * pow(FragColor.z, 0.416660010814666748046875f)) - 0.054999999701976776123046875f;
    }
    FragColor.x = _2366;
    FragColor.y = _2367;
    FragColor.z = _2368;
}

SPIRV_Cross_Output main(SPIRV_Cross_Input stage_input)
{
    vTexCoord = stage_input.vTexCoord;
    frag_main();
    SPIRV_Cross_Output stage_output;
    stage_output.FragColor = FragColor;
    return stage_output;
}
