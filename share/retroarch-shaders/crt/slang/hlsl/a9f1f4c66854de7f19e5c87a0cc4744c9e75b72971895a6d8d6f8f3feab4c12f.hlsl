// Generated from crt/shaders/crt-beans/scanlines_fast_vertical.slang. See slang/upstream for licence/source.
static const float3 _93[2] = { float3(1.0f, 0.0f, 1.0f), float3(0.0f, 1.0f, 0.0f) };
static const float3 _112[3] = { float3(0.0f, 0.0f, 1.0f), float3(0.0f, 1.0f, 0.0f), float3(1.0f, 0.0f, 0.0f) };
static const float3 _130[4] = { float3(1.0f, 0.0f, 0.0f), float3(1.0f, 1.0f, 0.0f), float3(0.0f, 1.0f, 1.0f), float3(0.0f, 0.0f, 1.0f) };
static const float3 _146[5] = { float3(1.0f, 0.0f, 0.0f), float3(1.0f, 0.0f, 1.0f), float3(0.0f, 0.0f, 1.0f), float3(0.0f, 1.0f, 0.0f), float3(0.0f, 1.0f, 0.0f) };
static const float3 _170[3] = { float3(1.0f, 0.0f, 0.0f), float3(0.0f, 1.0f, 0.0f), float3(0.0f, 0.0f, 1.0f) };
static const float3 _182[4] = { float3(0.0f, 0.0f, 1.0f), float3(0.0f, 1.0f, 1.0f), float3(1.0f, 1.0f, 0.0f), float3(1.0f, 0.0f, 0.0f) };
static const float3 _194[5] = { float3(0.0f, 0.0f, 1.0f), float3(1.0f, 0.0f, 1.0f), float3(1.0f, 0.0f, 0.0f), float3(0.0f, 1.0f, 0.0f), float3(0.0f, 1.0f, 0.0f) };

cbuffer Push : register(b1)
{
    float4 params_SourceSize : packoffset(c0);
    float4 params_OutputSize : packoffset(c1);
    uint params_FrameCount : packoffset(c2);
    float params_MaxSpotSize : packoffset(c2.y);
    float params_MinSpotSize : packoffset(c2.z);
    float params_OddFieldFirst : packoffset(c2.w);
    float params_MaskType : packoffset(c3.z);
    float params_SubpixelMaskPattern : packoffset(c3.w);
    float params_SubpixelPattern : packoffset(c4);
    float params_DynamicMaskTriads : packoffset(c4.y);
    float params_OutputGamma : packoffset(c4.z);
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
    bool _792 = params_OddFieldFirst == 3.0f;
    bool _799;
    if (_792)
    {
        _799 = params_SourceSize.y < 350.0f;
    }
    else
    {
        _799 = _792;
    }
    float3 _2556;
    if (_799)
    {
        float _1026 = vTexCoord.y * params_SourceSize.y;
        float _1027 = 2.0f * _1026;
        float _1036 = (ceil(_1027 - 0.5f) + 0.5f) - _1027;
        float3 _1080 = Source.SampleLevel(_Source_sampler, float2(vTexCoord.x, (ceil(_1026 + 0.25f) - 0.5f) * params_SourceSize.w), 0.0f).xyz;
        float _1085 = params_MinSpotSize * params_MaxSpotSize;
        float _1095 = _1085 - params_MaxSpotSize;
        float3 _1097 = _1085.xxx;
        float3 _1100 = 1.0f.xxx / (_1097 - (sqrt(_1080) * _1095));
        float3 _1108 = clamp(_1100 * abs(_1036), 0.0f.xxx, 1.0f.xxx);
        float3 _1129 = Source.SampleLevel(_Source_sampler, float2(vTexCoord.x, (ceil(_1026 - 0.25f) - 0.5f) * params_SourceSize.w), 0.0f).xyz;
        float3 _1149 = 1.0f.xxx / (_1097 - (sqrt(_1129) * _1095));
        float3 _1157 = clamp(_1149 * abs(_1036 - 1.0f), 0.0f.xxx, 1.0f.xxx);
        _2556 = (((_1080 * _1100) * (((_1108 * _1108) * ((_1108 * 2.0f) - 3.0f.xxx)) + 1.0f.xxx)) + ((_1129 * _1149) * (((_1157 * _1157) * ((_1157 * 2.0f) - 3.0f.xxx)) + 1.0f.xxx))) * params_MaxSpotSize;
    }
    else
    {
        bool _823 = params_OddFieldFirst == 4.0f;
        bool _830;
        if (!_823)
        {
            _830 = _792;
        }
        else
        {
            _830 = _823;
        }
        bool _838;
        if (!_830)
        {
            _838 = params_SourceSize.y <= 300.0f;
        }
        else
        {
            _838 = _830;
        }
        float3 _2557;
        if (_838)
        {
            float _1187 = vTexCoord.y * params_SourceSize.y;
            float _1188 = round(_1187);
            float _1189 = _1188 + 0.5f;
            float _1197 = _1189 - _1187;
            float3 _1229 = Source.SampleLevel(_Source_sampler, float2(vTexCoord.x, _1189 * params_SourceSize.w), 0.0f).xyz;
            float _1234 = params_MinSpotSize * params_MaxSpotSize;
            float _1244 = _1234 - params_MaxSpotSize;
            float3 _1246 = _1234.xxx;
            float3 _1249 = 1.0f.xxx / (_1246 - (sqrt(_1229) * _1244));
            float3 _1257 = clamp(_1249 * abs(_1197), 0.0f.xxx, 1.0f.xxx);
            float3 _1278 = Source.SampleLevel(_Source_sampler, float2(vTexCoord.x, (_1188 + (-0.5f)) * params_SourceSize.w), 0.0f).xyz;
            float3 _1298 = 1.0f.xxx / (_1246 - (sqrt(_1278) * _1244));
            float3 _1306 = clamp(_1298 * abs(_1197 - 1.0f), 0.0f.xxx, 1.0f.xxx);
            _2557 = (((_1229 * _1249) * (((_1257 * _1257) * ((_1257 * 2.0f) - 3.0f.xxx)) + 1.0f.xxx)) + ((_1278 * _1298) * (((_1306 * _1306) * ((_1306 * 2.0f) - 3.0f.xxx)) + 1.0f.xxx))) * params_MaxSpotSize;
        }
        else
        {
            float3 _2558;
            if (params_OddFieldFirst == 2.0f)
            {
                float _1337 = (0.5f * vTexCoord.y) * params_SourceSize.y;
                float _1340 = ceil(_1337 - 0.25f) * 2.0f;
                float _1341 = _1340 + 0.5f;
                float _1348 = vTexCoord.y * params_SourceSize.y;
                float _1350 = 0.5f * (_1341 - _1348);
                float _1379 = ceil(_1337 + 0.25f) * 2.0f;
                float _1380 = _1379 - 0.5f;
                float _1389 = 0.5f * (_1380 - _1348);
                float3 _1421 = Source.SampleLevel(_Source_sampler, float2(vTexCoord.x, _1341 * params_SourceSize.w), 0.0f).xyz;
                float _1426 = params_MinSpotSize * params_MaxSpotSize;
                float _1436 = _1426 - params_MaxSpotSize;
                float3 _1438 = _1426.xxx;
                float3 _1441 = 1.0f.xxx / (_1438 - (sqrt(_1421) * _1436));
                float3 _1449 = clamp(_1441 * abs(_1350), 0.0f.xxx, 1.0f.xxx);
                float3 _1470 = Source.SampleLevel(_Source_sampler, float2(vTexCoord.x, (_1340 + (-1.5f)) * params_SourceSize.w), 0.0f).xyz;
                float3 _1490 = 1.0f.xxx / (_1438 - (sqrt(_1470) * _1436));
                float3 _1498 = clamp(_1490 * abs(_1350 - 1.0f), 0.0f.xxx, 1.0f.xxx);
                float3 _1535 = Source.SampleLevel(_Source_sampler, float2(vTexCoord.x, _1380 * params_SourceSize.w), 0.0f).xyz;
                float3 _1555 = 1.0f.xxx / (_1438 - (sqrt(_1535) * _1436));
                float3 _1563 = clamp(_1555 * abs(_1389), 0.0f.xxx, 1.0f.xxx);
                float3 _1584 = Source.SampleLevel(_Source_sampler, float2(vTexCoord.x, (_1379 - 2.5f) * params_SourceSize.w), 0.0f).xyz;
                float3 _1604 = 1.0f.xxx / (_1438 - (sqrt(_1584) * _1436));
                float3 _1612 = clamp(_1604 * abs(_1389 - 1.0f), 0.0f.xxx, 1.0f.xxx);
                _2558 = (((((_1421 * _1441) * (((_1449 * _1449) * ((_1449 * 2.0f) - 3.0f.xxx)) + 1.0f.xxx)) + ((_1470 * _1490) * (((_1498 * _1498) * ((_1498 * 2.0f) - 3.0f.xxx)) + 1.0f.xxx))) * params_MaxSpotSize) + ((((_1535 * _1555) * (((_1563 * _1563) * ((_1563 * 2.0f) - 3.0f.xxx)) + 1.0f.xxx)) + ((_1584 * _1604) * (((_1612 * _1612) * ((_1612 * 2.0f) - 3.0f.xxx)) + 1.0f.xxx))) * params_MaxSpotSize)) * 0.5f;
            }
            else
            {
                float3 _2559;
                if (((params_FrameCount + uint(params_OddFieldFirst == 1.0f)) % 2u) == 0u)
                {
                    float _1646 = ceil(((0.5f * vTexCoord.y) * params_SourceSize.y) + 0.25f) * 2.0f;
                    float _1647 = _1646 - 0.5f;
                    float _1656 = 0.5f * (_1647 - (vTexCoord.y * params_SourceSize.y));
                    float3 _1688 = Source.SampleLevel(_Source_sampler, float2(vTexCoord.x, _1647 * params_SourceSize.w), 0.0f).xyz;
                    float _1693 = params_MinSpotSize * params_MaxSpotSize;
                    float _1703 = _1693 - params_MaxSpotSize;
                    float3 _1705 = _1693.xxx;
                    float3 _1708 = 1.0f.xxx / (_1705 - (sqrt(_1688) * _1703));
                    float3 _1716 = clamp(_1708 * abs(_1656), 0.0f.xxx, 1.0f.xxx);
                    float3 _1737 = Source.SampleLevel(_Source_sampler, float2(vTexCoord.x, (_1646 - 2.5f) * params_SourceSize.w), 0.0f).xyz;
                    float3 _1757 = 1.0f.xxx / (_1705 - (sqrt(_1737) * _1703));
                    float3 _1765 = clamp(_1757 * abs(_1656 - 1.0f), 0.0f.xxx, 1.0f.xxx);
                    _2559 = (((_1688 * _1708) * (((_1716 * _1716) * ((_1716 * 2.0f) - 3.0f.xxx)) + 1.0f.xxx)) + ((_1737 * _1757) * (((_1765 * _1765) * ((_1765 * 2.0f) - 3.0f.xxx)) + 1.0f.xxx))) * params_MaxSpotSize;
                }
                else
                {
                    float _1799 = ceil(((0.5f * vTexCoord.y) * params_SourceSize.y) - 0.25f) * 2.0f;
                    float _1800 = _1799 + 0.5f;
                    float _1809 = 0.5f * (_1800 - (vTexCoord.y * params_SourceSize.y));
                    float3 _1841 = Source.SampleLevel(_Source_sampler, float2(vTexCoord.x, _1800 * params_SourceSize.w), 0.0f).xyz;
                    float _1846 = params_MinSpotSize * params_MaxSpotSize;
                    float _1856 = _1846 - params_MaxSpotSize;
                    float3 _1858 = _1846.xxx;
                    float3 _1861 = 1.0f.xxx / (_1858 - (sqrt(_1841) * _1856));
                    float3 _1869 = clamp(_1861 * abs(_1809), 0.0f.xxx, 1.0f.xxx);
                    float3 _1890 = Source.SampleLevel(_Source_sampler, float2(vTexCoord.x, (_1799 + (-1.5f)) * params_SourceSize.w), 0.0f).xyz;
                    float3 _1910 = 1.0f.xxx / (_1858 - (sqrt(_1890) * _1856));
                    float3 _1918 = clamp(_1910 * abs(_1809 - 1.0f), 0.0f.xxx, 1.0f.xxx);
                    _2559 = (((_1841 * _1861) * (((_1869 * _1869) * ((_1869 * 2.0f) - 3.0f.xxx)) + 1.0f.xxx)) + ((_1890 * _1910) * (((_1918 * _1918) * ((_1918 * 2.0f) - 3.0f.xxx)) + 1.0f.xxx))) * params_MaxSpotSize;
                }
                _2558 = _2559;
            }
            _2557 = _2558;
        }
        _2556 = _2557;
    }
    float3 _2588;
    if (params_MaskType == 1.0f)
    {
        float _1956 = vTexCoord.x * params_OutputSize.x;
        float3 _2561;
        float _2570;
        if (params_SubpixelPattern == 0.0f)
        {
            float3 _2562;
            float _2571;
            if (params_SubpixelMaskPattern == 2.0f)
            {
                _2571 = 2.0f;
                _2562 = _93[int(mod(_1956, 2.0f))];
            }
            else
            {
                float3 _2563;
                float _2572;
                if (params_SubpixelMaskPattern == 3.0f)
                {
                    _2572 = 3.0f;
                    _2563 = _112[int(mod(_1956, 3.0f))];
                }
                else
                {
                    float3 _2564;
                    float _2573;
                    if (params_SubpixelMaskPattern == 4.0f)
                    {
                        _2573 = 2.0f;
                        _2564 = _130[int(mod(_1956, 4.0f))];
                    }
                    else
                    {
                        bool _1988 = params_SubpixelMaskPattern == 5.0f;
                        float3 _2565;
                        if (_1988)
                        {
                            _2565 = _146[int(mod(_1956, 5.0f))];
                        }
                        else
                        {
                            _2565 = 1.0f.xxx;
                        }
                        _2573 = _1988 ? 2.5f : 1.0f;
                        _2564 = _2565;
                    }
                    _2572 = _2573;
                    _2563 = _2564;
                }
                _2571 = _2572;
                _2562 = _2563;
            }
            _2570 = _2571;
            _2561 = _2562;
        }
        else
        {
            float3 _2566;
            float _2575;
            if (params_SubpixelMaskPattern == 2.0f)
            {
                _2575 = 2.0f;
                _2566 = _93[int(mod(_1956, 2.0f))];
            }
            else
            {
                float3 _2567;
                float _2576;
                if (params_SubpixelMaskPattern == 3.0f)
                {
                    _2576 = 3.0f;
                    _2567 = _170[int(mod(_1956, 3.0f))];
                }
                else
                {
                    float3 _2568;
                    float _2577;
                    if (params_SubpixelMaskPattern == 4.0f)
                    {
                        _2577 = 2.0f;
                        _2568 = _182[int(mod(_1956, 4.0f))];
                    }
                    else
                    {
                        bool _2028 = params_SubpixelMaskPattern == 5.0f;
                        float3 _2569;
                        if (_2028)
                        {
                            _2569 = _194[int(mod(_1956, 5.0f))];
                        }
                        else
                        {
                            _2569 = 1.0f.xxx;
                        }
                        _2577 = _2028 ? 2.5f : 1.0f;
                        _2568 = _2569;
                    }
                    _2576 = _2577;
                    _2567 = _2568;
                }
                _2575 = _2576;
                _2566 = _2567;
            }
            _2570 = _2575;
            _2561 = _2566;
        }
        float3 _2055 = (1.0f - _2570).xxx;
        _2588 = ((clamp((_2556 - 1.0f.xxx) / _2055, 0.0f.xxx, _2556) * _2570) * float4(_2561, _2570).xyz) + clamp((1.0f.xxx - (_2556 * _2570)) / _2055, 0.0f.xxx, _2556);
    }
    else
    {
        float3 _2589;
        if (params_MaskType == 2.0f)
        {
            float _2101 = 3.0f * params_DynamicMaskTriads;
            float _2104 = _2101 * params_OutputSize.z;
            float _2109 = _2101 * vTexCoord.x;
            float3 _2553;
            if (_2104 < 0.5f)
            {
                float _2115 = round(_2109);
                float _2119 = clamp((_2109 - _2115) / _2104, -1.0f, 1.0f);
                int _2125 = int(mod(_2115 - 1.0f, 3.0f) + 0.001000000047497451305389404296875f);
                _2553 = ((_170[_2125] + _170[_2125].zxy) + ((_170[_2125].zxy - _170[_2125]) * (_2119 + (sin(3.1415927410125732421875f * _2119) * 0.3183098733425140380859375f)))) * 0.5f;
            }
            else
            {
                float3 _2554;
                if (_2104 < 1.0f)
                {
                    float _2152 = floor(_2109);
                    float _2157 = clamp((_2109 - _2152) / _2104, -1.0f, 1.0f);
                    float _2165 = clamp((_2109 - (_2152 + 1.0f)) / _2104, -1.0f, 1.0f);
                    int _2171 = int(mod(_2152 - 1.0f, 3.0f) + 0.001000000047497451305389404296875f);
                    _2554 = (((_170[_2171] + _170[_2171].yzx) + ((_170[_2171].zxy - _170[_2171]) * (_2157 + (sin(3.1415927410125732421875f * _2157) * 0.3183098733425140380859375f)))) + ((_170[_2171].yzx - _170[_2171].zxy) * (_2165 + (sin(3.1415927410125732421875f * _2165) * 0.3183098733425140380859375f)))) * 0.5f;
                }
                else
                {
                    float _2208 = round(_2109);
                    float _2213 = clamp((_2109 - (_2208 - 1.0f)) / _2104, -1.0f, 1.0f);
                    float _2221 = clamp((_2109 - _2208) / _2104, -1.0f, 1.0f);
                    float _2229 = clamp((_2109 - (_2208 + 1.0f)) / _2104, -1.0f, 1.0f);
                    int _2235 = int(mod(_2208 - 2.0f, 3.0f) + 0.001000000047497451305389404296875f);
                    _2554 = ((((_170[_2235] + _170[_2235].xyz) + ((_170[_2235].zxy - _170[_2235]) * (_2213 + (sin(3.1415927410125732421875f * _2213) * 0.3183098733425140380859375f)))) + ((_170[_2235].yzx - _170[_2235].zxy) * (_2221 + (sin(3.1415927410125732421875f * _2221) * 0.3183098733425140380859375f)))) + ((_170[_2235].xyz - _170[_2235].yzx) * (_2229 + (sin(3.1415927410125732421875f * _2229) * 0.3183098733425140380859375f)))) * 0.5f;
                }
                _2553 = _2554;
            }
            _2589 = ((clamp((_2556 - 1.0f.xxx) * (-0.5f).xxx, 0.0f.xxx, _2556) * 3.0f) * float4(_2553, 3.0f).xyz) + clamp((1.0f.xxx - (_2556 * 3.0f)) * (-0.5f).xxx, 0.0f.xxx, _2556);
        }
        else
        {
            _2589 = _2556;
        }
        _2588 = _2589;
    }
    float3 _2590;
    if (params_OutputGamma < 0.5f)
    {
        float3 _2328 = clamp(_2588, 0.0f.xxx, 1.0f.xxx);
        bool3 _2330 = bool3(_2328.x < 0.003130800090730190277099609375f.xxx.x, _2328.y < 0.003130800090730190277099609375f.xxx.y, _2328.z < 0.003130800090730190277099609375f.xxx.z);
        float3 _2334 = (1.05499994754791259765625f.xxx * pow(_2328, 0.4166666567325592041015625f.xxx)) - 0.054999999701976776123046875f.xxx;
        float3 _2336 = _2328 * 12.9200000762939453125f.xxx;
        _2590 = float3(_2330.x ? _2336.x : _2334.x, _2330.y ? _2336.y : _2334.y, _2330.z ? _2336.z : _2334.z);
    }
    else
    {
        _2590 = pow(clamp(_2588, 0.0f.xxx, 1.0f.xxx), 0.4545454680919647216796875f.xxx);
    }
    FragColor.x = _2590.x;
    FragColor.y = _2590.y;
    FragColor.z = _2590.z;
}

SPIRV_Cross_Output main(SPIRV_Cross_Input stage_input)
{
    vTexCoord = stage_input.vTexCoord;
    frag_main();
    SPIRV_Cross_Output stage_output;
    stage_output.FragColor = FragColor;
    return stage_output;
}
