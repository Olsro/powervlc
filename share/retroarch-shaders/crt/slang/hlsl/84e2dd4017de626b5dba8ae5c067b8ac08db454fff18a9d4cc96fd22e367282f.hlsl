// Generated from crt/shaders/crt-beans/scanlines_cubic.slang. See slang/upstream for licence/source.
static const float3 _89[2] = { float3(1.0f, 0.0f, 1.0f), float3(0.0f, 1.0f, 0.0f) };
static const float3 _108[3] = { float3(0.0f, 0.0f, 1.0f), float3(0.0f, 1.0f, 0.0f), float3(1.0f, 0.0f, 0.0f) };
static const float3 _126[4] = { float3(1.0f, 0.0f, 0.0f), float3(1.0f, 1.0f, 0.0f), float3(0.0f, 1.0f, 1.0f), float3(0.0f, 0.0f, 1.0f) };
static const float3 _142[5] = { float3(1.0f, 0.0f, 0.0f), float3(1.0f, 0.0f, 1.0f), float3(0.0f, 0.0f, 1.0f), float3(0.0f, 1.0f, 0.0f), float3(0.0f, 1.0f, 0.0f) };
static const float3 _166[3] = { float3(1.0f, 0.0f, 0.0f), float3(0.0f, 1.0f, 0.0f), float3(0.0f, 0.0f, 1.0f) };
static const float3 _178[4] = { float3(0.0f, 0.0f, 1.0f), float3(0.0f, 1.0f, 1.0f), float3(1.0f, 1.0f, 0.0f), float3(1.0f, 0.0f, 0.0f) };
static const float3 _190[5] = { float3(0.0f, 0.0f, 1.0f), float3(1.0f, 0.0f, 1.0f), float3(1.0f, 0.0f, 0.0f), float3(0.0f, 1.0f, 0.0f), float3(0.0f, 1.0f, 0.0f) };

cbuffer Push : register(b1)
{
    float4 params_SourceSize : packoffset(c0);
    float4 params_OutputSize : packoffset(c1);
    uint params_FrameCount : packoffset(c2);
    float params_MaxSpotSize : packoffset(c2.y);
    float params_OddFieldFirst : packoffset(c2.w);
    float params_MaskType : packoffset(c3.z);
    float params_SubpixelMaskPattern : packoffset(c3.w);
    float params_SubpixelPattern : packoffset(c4);
    float params_DynamicMaskTriads : packoffset(c4.y);
};

Texture2D<float4> Filtered : register(t2);
SamplerState _Filtered_sampler : register(s2);
Texture2D<float4> Source : register(t1);
SamplerState _Source_sampler : register(s1);

static float delta;
static float2 vTexCoord;
static float2 viewportCoord;
static float4 FragColor;

struct SPIRV_Cross_Input
{
    float2 vTexCoord : TEXCOORD0;
    nointerpolation float delta : TEXCOORD1;
    float2 viewportCoord : TEXCOORD2;
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
    float3 _2752;
    if (params_SourceSize.y <= 300.0f)
    {
        float _931 = vTexCoord.y * params_SourceSize.y;
        float _932 = round(_931);
        float _933 = _932 + 0.5f;
        float _941 = _933 - _931;
        float _943 = _941 - 1.0f;
        float _947 = _933 * params_SourceSize.w;
        float _951 = (_932 + (-0.5f)) * params_SourceSize.w;
        float _981 = vTexCoord.x * params_SourceSize.x;
        float _985 = params_MaxSpotSize / delta;
        float _989 = params_SourceSize.z * (round(_981 - _985) + 0.5f);
        float _1002 = params_SourceSize.z * round(_981 + _985);
        float _1010 = (delta * params_SourceSize.x) * (_989 - vTexCoord.x);
        float3 _2748;
        _2748 = 0.0f.xxx;
        for (float _2746 = _989, _2787 = _1010; _2746 < _1002; )
        {
            float2 _1022 = float2(_2746, _947);
            float3 _1031 = Source.SampleLevel(_Source_sampler, _1022, 0.0f).xyz;
            float2 _1036 = float2(_2746, _951);
            float3 _1045 = Source.SampleLevel(_Source_sampler, _1036, 0.0f).xyz;
            float _1082 = abs(_2787);
            float3 _1087 = clamp(_1031 * _1082, 0.0f.xxx, 1.0f.xxx);
            float3 _1094 = clamp(_1031 * abs(_941), 0.0f.xxx, 1.0f.xxx);
            float3 _1132 = clamp(_1045 * _1082, 0.0f.xxx, 1.0f.xxx);
            float3 _1139 = clamp(_1045 * abs(_943), 0.0f.xxx, 1.0f.xxx);
            _2787 += delta;
            _2748 = (_2748 + ((((Filtered.SampleLevel(_Filtered_sampler, _1022, 0.0f).xyz * _1031) * _1031) * (((_1087 * _1087) * ((_1087 * 2.0f) - 3.0f.xxx)) + 1.0f.xxx)) * (((_1094 * _1094) * ((_1094 * 2.0f) - 3.0f.xxx)) + 1.0f.xxx))) + ((((Filtered.SampleLevel(_Filtered_sampler, _1036, 0.0f).xyz * _1045) * _1045) * (((_1132 * _1132) * ((_1132 * 2.0f) - 3.0f.xxx)) + 1.0f.xxx)) * (((_1139 * _1139) * ((_1139 * 2.0f) - 3.0f.xxx)) + 1.0f.xxx));
            _2746 += params_SourceSize.z;
            continue;
        }
        _2752 = _2748 * (delta * params_MaxSpotSize);
    }
    else
    {
        float3 _2753;
        if (params_OddFieldFirst == 2.0f)
        {
            float _1177 = (0.5f * vTexCoord.y) * params_SourceSize.y;
            float _1180 = ceil(_1177 - 0.25f) * 2.0f;
            float _1181 = _1180 + 0.5f;
            float _1188 = vTexCoord.y * params_SourceSize.y;
            float _1190 = 0.5f * (_1181 - _1188);
            float _1192 = _1190 - 1.0f;
            float _1196 = _1181 * params_SourceSize.w;
            float _1200 = (_1180 + (-1.5f)) * params_SourceSize.w;
            float _1230 = vTexCoord.x * params_SourceSize.x;
            float _1234 = params_MaxSpotSize / delta;
            float _1238 = params_SourceSize.z * (round(_1230 - _1234) + 0.5f);
            float _1251 = params_SourceSize.z * round(_1230 + _1234);
            float _1259 = (delta * params_SourceSize.x) * (_1238 - vTexCoord.x);
            float3 _2732;
            _2732 = 0.0f.xxx;
            for (float _2730 = _1238, _2743 = _1259; _2730 < _1251; )
            {
                float2 _1271 = float2(_2730, _1196);
                float3 _1280 = Source.SampleLevel(_Source_sampler, _1271, 0.0f).xyz;
                float2 _1285 = float2(_2730, _1200);
                float3 _1294 = Source.SampleLevel(_Source_sampler, _1285, 0.0f).xyz;
                float _1331 = abs(_2743);
                float3 _1336 = clamp(_1280 * _1331, 0.0f.xxx, 1.0f.xxx);
                float3 _1343 = clamp(_1280 * abs(_1190), 0.0f.xxx, 1.0f.xxx);
                float3 _1381 = clamp(_1294 * _1331, 0.0f.xxx, 1.0f.xxx);
                float3 _1388 = clamp(_1294 * abs(_1192), 0.0f.xxx, 1.0f.xxx);
                _2743 += delta;
                _2732 = (_2732 + ((((Filtered.SampleLevel(_Filtered_sampler, _1271, 0.0f).xyz * _1280) * _1280) * (((_1336 * _1336) * ((_1336 * 2.0f) - 3.0f.xxx)) + 1.0f.xxx)) * (((_1343 * _1343) * ((_1343 * 2.0f) - 3.0f.xxx)) + 1.0f.xxx))) + ((((Filtered.SampleLevel(_Filtered_sampler, _1285, 0.0f).xyz * _1294) * _1294) * (((_1381 * _1381) * ((_1381 * 2.0f) - 3.0f.xxx)) + 1.0f.xxx)) * (((_1388 * _1388) * ((_1388 * 2.0f) - 3.0f.xxx)) + 1.0f.xxx));
                _2730 += params_SourceSize.z;
                continue;
            }
            float _1323 = delta * params_MaxSpotSize;
            float _1429 = ceil(_1177 + 0.25f) * 2.0f;
            float _1430 = _1429 - 0.5f;
            float _1439 = 0.5f * (_1430 - _1188);
            float _1441 = _1439 - 1.0f;
            float _1445 = _1430 * params_SourceSize.w;
            float _1449 = (_1429 - 2.5f) * params_SourceSize.w;
            float3 _2735;
            _2735 = 0.0f.xxx;
            for (float _2733 = _1238, _2738 = _1259; _2733 < _1251; )
            {
                float2 _1520 = float2(_2733, _1445);
                float3 _1529 = Source.SampleLevel(_Source_sampler, _1520, 0.0f).xyz;
                float2 _1534 = float2(_2733, _1449);
                float3 _1543 = Source.SampleLevel(_Source_sampler, _1534, 0.0f).xyz;
                float _1580 = abs(_2738);
                float3 _1585 = clamp(_1529 * _1580, 0.0f.xxx, 1.0f.xxx);
                float3 _1592 = clamp(_1529 * abs(_1439), 0.0f.xxx, 1.0f.xxx);
                float3 _1630 = clamp(_1543 * _1580, 0.0f.xxx, 1.0f.xxx);
                float3 _1637 = clamp(_1543 * abs(_1441), 0.0f.xxx, 1.0f.xxx);
                _2738 += delta;
                _2735 = (_2735 + ((((Filtered.SampleLevel(_Filtered_sampler, _1520, 0.0f).xyz * _1529) * _1529) * (((_1585 * _1585) * ((_1585 * 2.0f) - 3.0f.xxx)) + 1.0f.xxx)) * (((_1592 * _1592) * ((_1592 * 2.0f) - 3.0f.xxx)) + 1.0f.xxx))) + ((((Filtered.SampleLevel(_Filtered_sampler, _1534, 0.0f).xyz * _1543) * _1543) * (((_1630 * _1630) * ((_1630 * 2.0f) - 3.0f.xxx)) + 1.0f.xxx)) * (((_1637 * _1637) * ((_1637 * 2.0f) - 3.0f.xxx)) + 1.0f.xxx));
                _2733 += params_SourceSize.z;
                continue;
            }
            _2753 = ((_2732 * _1323) + (_2735 * _1323)) * 0.5f;
        }
        else
        {
            float3 _2754;
            if (((params_FrameCount + uint(params_OddFieldFirst == 1.0f)) % 2u) == 0u)
            {
                float _1678 = ceil(((0.5f * vTexCoord.y) * params_SourceSize.y) + 0.25f) * 2.0f;
                float _1679 = _1678 - 0.5f;
                float _1688 = 0.5f * (_1679 - (vTexCoord.y * params_SourceSize.y));
                float _1690 = _1688 - 1.0f;
                float _1694 = _1679 * params_SourceSize.w;
                float _1698 = (_1678 - 2.5f) * params_SourceSize.w;
                float _1728 = vTexCoord.x * params_SourceSize.x;
                float _1732 = params_MaxSpotSize / delta;
                float _1736 = params_SourceSize.z * (round(_1728 - _1732) + 0.5f);
                float _1749 = params_SourceSize.z * round(_1728 + _1732);
                float _1757 = (delta * params_SourceSize.x) * (_1736 - vTexCoord.x);
                float3 _2724;
                _2724 = 0.0f.xxx;
                for (float _2722 = _1736, _2727 = _1757; _2722 < _1749; )
                {
                    float2 _1769 = float2(_2722, _1694);
                    float3 _1778 = Source.SampleLevel(_Source_sampler, _1769, 0.0f).xyz;
                    float2 _1783 = float2(_2722, _1698);
                    float3 _1792 = Source.SampleLevel(_Source_sampler, _1783, 0.0f).xyz;
                    float _1829 = abs(_2727);
                    float3 _1834 = clamp(_1778 * _1829, 0.0f.xxx, 1.0f.xxx);
                    float3 _1841 = clamp(_1778 * abs(_1688), 0.0f.xxx, 1.0f.xxx);
                    float3 _1879 = clamp(_1792 * _1829, 0.0f.xxx, 1.0f.xxx);
                    float3 _1886 = clamp(_1792 * abs(_1690), 0.0f.xxx, 1.0f.xxx);
                    _2727 += delta;
                    _2724 = (_2724 + ((((Filtered.SampleLevel(_Filtered_sampler, _1769, 0.0f).xyz * _1778) * _1778) * (((_1834 * _1834) * ((_1834 * 2.0f) - 3.0f.xxx)) + 1.0f.xxx)) * (((_1841 * _1841) * ((_1841 * 2.0f) - 3.0f.xxx)) + 1.0f.xxx))) + ((((Filtered.SampleLevel(_Filtered_sampler, _1783, 0.0f).xyz * _1792) * _1792) * (((_1879 * _1879) * ((_1879 * 2.0f) - 3.0f.xxx)) + 1.0f.xxx)) * (((_1886 * _1886) * ((_1886 * 2.0f) - 3.0f.xxx)) + 1.0f.xxx));
                    _2722 += params_SourceSize.z;
                    continue;
                }
                _2754 = _2724 * (delta * params_MaxSpotSize);
            }
            else
            {
                float _1927 = ceil(((0.5f * vTexCoord.y) * params_SourceSize.y) - 0.25f) * 2.0f;
                float _1928 = _1927 + 0.5f;
                float _1937 = 0.5f * (_1928 - (vTexCoord.y * params_SourceSize.y));
                float _1939 = _1937 - 1.0f;
                float _1943 = _1928 * params_SourceSize.w;
                float _1947 = (_1927 + (-1.5f)) * params_SourceSize.w;
                float _1977 = vTexCoord.x * params_SourceSize.x;
                float _1981 = params_MaxSpotSize / delta;
                float _1985 = params_SourceSize.z * (round(_1977 - _1981) + 0.5f);
                float _1998 = params_SourceSize.z * round(_1977 + _1981);
                float _2006 = (delta * params_SourceSize.x) * (_1985 - vTexCoord.x);
                float3 _2716;
                _2716 = 0.0f.xxx;
                for (float _2714 = _1985, _2719 = _2006; _2714 < _1998; )
                {
                    float2 _2018 = float2(_2714, _1943);
                    float3 _2027 = Source.SampleLevel(_Source_sampler, _2018, 0.0f).xyz;
                    float2 _2032 = float2(_2714, _1947);
                    float3 _2041 = Source.SampleLevel(_Source_sampler, _2032, 0.0f).xyz;
                    float _2078 = abs(_2719);
                    float3 _2083 = clamp(_2027 * _2078, 0.0f.xxx, 1.0f.xxx);
                    float3 _2090 = clamp(_2027 * abs(_1937), 0.0f.xxx, 1.0f.xxx);
                    float3 _2128 = clamp(_2041 * _2078, 0.0f.xxx, 1.0f.xxx);
                    float3 _2135 = clamp(_2041 * abs(_1939), 0.0f.xxx, 1.0f.xxx);
                    _2719 += delta;
                    _2716 = (_2716 + ((((Filtered.SampleLevel(_Filtered_sampler, _2018, 0.0f).xyz * _2027) * _2027) * (((_2083 * _2083) * ((_2083 * 2.0f) - 3.0f.xxx)) + 1.0f.xxx)) * (((_2090 * _2090) * ((_2090 * 2.0f) - 3.0f.xxx)) + 1.0f.xxx))) + ((((Filtered.SampleLevel(_Filtered_sampler, _2032, 0.0f).xyz * _2041) * _2041) * (((_2128 * _2128) * ((_2128 * 2.0f) - 3.0f.xxx)) + 1.0f.xxx)) * (((_2135 * _2135) * ((_2135 * 2.0f) - 3.0f.xxx)) + 1.0f.xxx));
                    _2714 += params_SourceSize.z;
                    continue;
                }
                _2754 = _2716 * (delta * params_MaxSpotSize);
            }
            _2753 = _2754;
        }
        _2752 = _2753;
    }
    float3 _2783;
    if (params_MaskType == 1.0f)
    {
        float _2180 = viewportCoord.x * params_OutputSize.x;
        float3 _2756;
        float _2765;
        if (params_SubpixelPattern == 0.0f)
        {
            float3 _2757;
            float _2766;
            if (params_SubpixelMaskPattern == 2.0f)
            {
                _2766 = 2.0f;
                _2757 = _89[int(mod(_2180, 2.0f))];
            }
            else
            {
                float3 _2758;
                float _2767;
                if (params_SubpixelMaskPattern == 3.0f)
                {
                    _2767 = 3.0f;
                    _2758 = _108[int(mod(_2180, 3.0f))];
                }
                else
                {
                    float3 _2759;
                    float _2768;
                    if (params_SubpixelMaskPattern == 4.0f)
                    {
                        _2768 = 2.0f;
                        _2759 = _126[int(mod(_2180, 4.0f))];
                    }
                    else
                    {
                        bool _2212 = params_SubpixelMaskPattern == 5.0f;
                        float3 _2760;
                        if (_2212)
                        {
                            _2760 = _142[int(mod(_2180, 5.0f))];
                        }
                        else
                        {
                            _2760 = 1.0f.xxx;
                        }
                        _2768 = _2212 ? 2.5f : 1.0f;
                        _2759 = _2760;
                    }
                    _2767 = _2768;
                    _2758 = _2759;
                }
                _2766 = _2767;
                _2757 = _2758;
            }
            _2765 = _2766;
            _2756 = _2757;
        }
        else
        {
            float3 _2761;
            float _2770;
            if (params_SubpixelMaskPattern == 2.0f)
            {
                _2770 = 2.0f;
                _2761 = _89[int(mod(_2180, 2.0f))];
            }
            else
            {
                float3 _2762;
                float _2771;
                if (params_SubpixelMaskPattern == 3.0f)
                {
                    _2771 = 3.0f;
                    _2762 = _166[int(mod(_2180, 3.0f))];
                }
                else
                {
                    float3 _2763;
                    float _2772;
                    if (params_SubpixelMaskPattern == 4.0f)
                    {
                        _2772 = 2.0f;
                        _2763 = _178[int(mod(_2180, 4.0f))];
                    }
                    else
                    {
                        bool _2252 = params_SubpixelMaskPattern == 5.0f;
                        float3 _2764;
                        if (_2252)
                        {
                            _2764 = _190[int(mod(_2180, 5.0f))];
                        }
                        else
                        {
                            _2764 = 1.0f.xxx;
                        }
                        _2772 = _2252 ? 2.5f : 1.0f;
                        _2763 = _2764;
                    }
                    _2771 = _2772;
                    _2762 = _2763;
                }
                _2770 = _2771;
                _2761 = _2762;
            }
            _2765 = _2770;
            _2756 = _2761;
        }
        float3 _2279 = (1.0f - _2765).xxx;
        _2783 = ((clamp((_2752 - 1.0f.xxx) / _2279, 0.0f.xxx, _2752) * _2765) * float4(_2756, _2765).xyz) + clamp((1.0f.xxx - (_2752 * _2765)) / _2279, 0.0f.xxx, _2752);
    }
    else
    {
        float3 _2784;
        if (params_MaskType == 2.0f)
        {
            float _2325 = 3.0f * params_DynamicMaskTriads;
            float _2328 = _2325 * params_OutputSize.z;
            float _2333 = _2325 * viewportCoord.x;
            float3 _2749;
            if (_2328 < 0.5f)
            {
                float _2339 = round(_2333);
                float _2343 = clamp((_2333 - _2339) / _2328, -1.0f, 1.0f);
                int _2349 = int(mod(_2339 - 1.0f, 3.0f) + 0.001000000047497451305389404296875f);
                _2749 = ((_166[_2349] + _166[_2349].zxy) + ((_166[_2349].zxy - _166[_2349]) * (_2343 + (sin(3.1415927410125732421875f * _2343) * 0.3183098733425140380859375f)))) * 0.5f;
            }
            else
            {
                float3 _2750;
                if (_2328 < 1.0f)
                {
                    float _2376 = floor(_2333);
                    float _2381 = clamp((_2333 - _2376) / _2328, -1.0f, 1.0f);
                    float _2389 = clamp((_2333 - (_2376 + 1.0f)) / _2328, -1.0f, 1.0f);
                    int _2395 = int(mod(_2376 - 1.0f, 3.0f) + 0.001000000047497451305389404296875f);
                    _2750 = (((_166[_2395] + _166[_2395].yzx) + ((_166[_2395].zxy - _166[_2395]) * (_2381 + (sin(3.1415927410125732421875f * _2381) * 0.3183098733425140380859375f)))) + ((_166[_2395].yzx - _166[_2395].zxy) * (_2389 + (sin(3.1415927410125732421875f * _2389) * 0.3183098733425140380859375f)))) * 0.5f;
                }
                else
                {
                    float _2432 = round(_2333);
                    float _2437 = clamp((_2333 - (_2432 - 1.0f)) / _2328, -1.0f, 1.0f);
                    float _2445 = clamp((_2333 - _2432) / _2328, -1.0f, 1.0f);
                    float _2453 = clamp((_2333 - (_2432 + 1.0f)) / _2328, -1.0f, 1.0f);
                    int _2459 = int(mod(_2432 - 2.0f, 3.0f) + 0.001000000047497451305389404296875f);
                    _2750 = ((((_166[_2459] + _166[_2459].xyz) + ((_166[_2459].zxy - _166[_2459]) * (_2437 + (sin(3.1415927410125732421875f * _2437) * 0.3183098733425140380859375f)))) + ((_166[_2459].yzx - _166[_2459].zxy) * (_2445 + (sin(3.1415927410125732421875f * _2445) * 0.3183098733425140380859375f)))) + ((_166[_2459].xyz - _166[_2459].yzx) * (_2453 + (sin(3.1415927410125732421875f * _2453) * 0.3183098733425140380859375f)))) * 0.5f;
                }
                _2749 = _2750;
            }
            _2784 = ((clamp((_2752 - 1.0f.xxx) * (-0.5f).xxx, 0.0f.xxx, _2752) * 3.0f) * float4(_2749, 3.0f).xyz) + clamp((1.0f.xxx - (_2752 * 3.0f)) * (-0.5f).xxx, 0.0f.xxx, _2752);
        }
        else
        {
            _2784 = _2752;
        }
        _2783 = _2784;
    }
    FragColor.x = _2783.x;
    FragColor.y = _2783.y;
    FragColor.z = _2783.z;
}

SPIRV_Cross_Output main(SPIRV_Cross_Input stage_input)
{
    delta = stage_input.delta;
    vTexCoord = stage_input.vTexCoord;
    viewportCoord = stage_input.viewportCoord;
    frag_main();
    SPIRV_Cross_Output stage_output;
    stage_output.FragColor = FragColor;
    return stage_output;
}
