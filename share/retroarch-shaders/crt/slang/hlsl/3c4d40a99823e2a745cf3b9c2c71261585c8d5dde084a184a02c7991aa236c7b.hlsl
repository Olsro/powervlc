// Generated from crt/shaders/crt-beans/scanlines_analytical.slang. See slang/upstream for licence/source.
static const float3 _95[2] = { float3(1.0f, 0.0f, 1.0f), float3(0.0f, 1.0f, 0.0f) };
static const float3 _114[3] = { float3(0.0f, 0.0f, 1.0f), float3(0.0f, 1.0f, 0.0f), float3(1.0f, 0.0f, 0.0f) };
static const float3 _132[4] = { float3(1.0f, 0.0f, 0.0f), float3(1.0f, 1.0f, 0.0f), float3(0.0f, 1.0f, 1.0f), float3(0.0f, 0.0f, 1.0f) };
static const float3 _148[5] = { float3(1.0f, 0.0f, 0.0f), float3(1.0f, 0.0f, 1.0f), float3(0.0f, 0.0f, 1.0f), float3(0.0f, 1.0f, 0.0f), float3(0.0f, 1.0f, 0.0f) };
static const float3 _172[3] = { float3(1.0f, 0.0f, 0.0f), float3(0.0f, 1.0f, 0.0f), float3(0.0f, 0.0f, 1.0f) };
static const float3 _184[4] = { float3(0.0f, 0.0f, 1.0f), float3(0.0f, 1.0f, 1.0f), float3(1.0f, 1.0f, 0.0f), float3(1.0f, 0.0f, 0.0f) };
static const float3 _196[5] = { float3(0.0f, 0.0f, 1.0f), float3(1.0f, 0.0f, 1.0f), float3(1.0f, 0.0f, 0.0f), float3(0.0f, 1.0f, 0.0f), float3(0.0f, 1.0f, 0.0f) };

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

Texture2D<float4> Linearized : register(t2);
SamplerState _Linearized_sampler : register(s2);
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
    bool _831 = params_OddFieldFirst == 3.0f;
    bool _838;
    if (_831)
    {
        _838 = params_SourceSize.y < 350.0f;
    }
    else
    {
        _838 = _831;
    }
    float3 _3397;
    if (_838)
    {
        float _1051 = vTexCoord.y * params_SourceSize.y;
        float _1052 = 2.0f * _1051;
        float _1061 = (ceil(_1052 - 0.5f) + 0.5f) - _1052;
        float _1063 = _1061 - 1.0f;
        float _1073 = (ceil(_1051 + 0.25f) - 0.5f) * params_SourceSize.w;
        float _1083 = (ceil(_1051 - 0.25f) - 0.5f) * params_SourceSize.w;
        float _1119 = vTexCoord.x * params_SourceSize.x;
        float _1123 = params_MaxSpotSize / delta;
        float _1127 = params_SourceSize.z * (floor(_1119 - _1123) + 0.5f);
        float _1141 = params_SourceSize.z * (floor(_1119 + _1123) + 1.0f);
        float _1147 = _1119 * delta;
        float3 _3393;
        _3393 = 0.0f.xxx;
        for (float _3391 = _1127; _3391 < _1141; )
        {
            float2 _1159 = float2(_3391, _1073);
            float3 _1168 = Source.SampleLevel(_Source_sampler, _1159, 0.0f).xyz;
            float2 _1173 = float2(_3391, _1083);
            float3 _1182 = Source.SampleLevel(_Source_sampler, _1173, 0.0f).xyz;
            float _1189 = delta * ((params_SourceSize.x * _3391) - 0.5f);
            float _1232 = _1147 - _1189;
            float _1240 = _1147 - (_1189 + delta);
            float3 _1251 = clamp(_1168 * abs(_1061), 0.0f.xxx, 1.0f.xxx);
            float3 _1267 = clamp(_1168 * _1232, (-1.0f).xxx, 1.0f.xxx) * 3.1415927410125732421875f;
            float3 _1273 = clamp(_1168 * _1240, (-1.0f).xxx, 1.0f.xxx) * 3.1415927410125732421875f;
            float3 _1307 = clamp(_1182 * abs(_1063), 0.0f.xxx, 1.0f.xxx);
            float3 _1323 = clamp(_1182 * _1232, (-1.0f).xxx, 1.0f.xxx) * 3.1415927410125732421875f;
            float3 _1329 = clamp(_1182 * _1240, (-1.0f).xxx, 1.0f.xxx) * 3.1415927410125732421875f;
            _3393 = (_3393 + (((Linearized.SampleLevel(_Linearized_sampler, _1159, 0.0f).xyz * _1168) * (((_1251 * _1251) * ((_1251 * 2.0f) - 3.0f.xxx)) + 1.0f.xxx)) * (((_1267 + sin(_1267)) - _1273) - sin(_1273)))) + (((Linearized.SampleLevel(_Linearized_sampler, _1173, 0.0f).xyz * _1182) * (((_1307 * _1307) * ((_1307 * 2.0f) - 3.0f.xxx)) + 1.0f.xxx)) * (((_1323 + sin(_1323)) - _1329) - sin(_1329)));
            _3391 += params_SourceSize.z;
            continue;
        }
        _3397 = _3393 * (params_MaxSpotSize * 0.15915493667125701904296875f);
    }
    else
    {
        bool _861 = params_OddFieldFirst == 4.0f;
        bool _868;
        if (!_861)
        {
            _868 = _831;
        }
        else
        {
            _868 = _861;
        }
        bool _876;
        if (!_868)
        {
            _876 = params_SourceSize.y <= 300.0f;
        }
        else
        {
            _876 = _868;
        }
        float3 _3398;
        if (_876)
        {
            float _1345 = vTexCoord.y * params_SourceSize.y;
            float _1346 = round(_1345);
            float _1347 = _1346 + 0.5f;
            float _1355 = _1347 - _1345;
            float _1357 = _1355 - 1.0f;
            float _1361 = _1347 * params_SourceSize.w;
            float _1365 = (_1346 + (-0.5f)) * params_SourceSize.w;
            float _1401 = vTexCoord.x * params_SourceSize.x;
            float _1405 = params_MaxSpotSize / delta;
            float _1409 = params_SourceSize.z * (floor(_1401 - _1405) + 0.5f);
            float _1423 = params_SourceSize.z * (floor(_1401 + _1405) + 1.0f);
            float _1429 = _1401 * delta;
            float3 _3385;
            _3385 = 0.0f.xxx;
            for (float _3383 = _1409; _3383 < _1423; )
            {
                float2 _1441 = float2(_3383, _1361);
                float3 _1450 = Source.SampleLevel(_Source_sampler, _1441, 0.0f).xyz;
                float2 _1455 = float2(_3383, _1365);
                float3 _1464 = Source.SampleLevel(_Source_sampler, _1455, 0.0f).xyz;
                float _1471 = delta * ((params_SourceSize.x * _3383) - 0.5f);
                float _1514 = _1429 - _1471;
                float _1522 = _1429 - (_1471 + delta);
                float3 _1533 = clamp(_1450 * abs(_1355), 0.0f.xxx, 1.0f.xxx);
                float3 _1549 = clamp(_1450 * _1514, (-1.0f).xxx, 1.0f.xxx) * 3.1415927410125732421875f;
                float3 _1555 = clamp(_1450 * _1522, (-1.0f).xxx, 1.0f.xxx) * 3.1415927410125732421875f;
                float3 _1589 = clamp(_1464 * abs(_1357), 0.0f.xxx, 1.0f.xxx);
                float3 _1605 = clamp(_1464 * _1514, (-1.0f).xxx, 1.0f.xxx) * 3.1415927410125732421875f;
                float3 _1611 = clamp(_1464 * _1522, (-1.0f).xxx, 1.0f.xxx) * 3.1415927410125732421875f;
                _3385 = (_3385 + (((Linearized.SampleLevel(_Linearized_sampler, _1441, 0.0f).xyz * _1450) * (((_1533 * _1533) * ((_1533 * 2.0f) - 3.0f.xxx)) + 1.0f.xxx)) * (((_1549 + sin(_1549)) - _1555) - sin(_1555)))) + (((Linearized.SampleLevel(_Linearized_sampler, _1455, 0.0f).xyz * _1464) * (((_1589 * _1589) * ((_1589 * 2.0f) - 3.0f.xxx)) + 1.0f.xxx)) * (((_1605 + sin(_1605)) - _1611) - sin(_1611)));
                _3383 += params_SourceSize.z;
                continue;
            }
            _3398 = _3385 * (params_MaxSpotSize * 0.15915493667125701904296875f);
        }
        else
        {
            float3 _3399;
            if (params_OddFieldFirst == 2.0f)
            {
                float _1628 = (0.5f * vTexCoord.y) * params_SourceSize.y;
                float _1631 = ceil(_1628 - 0.25f) * 2.0f;
                float _1632 = _1631 + 0.5f;
                float _1639 = vTexCoord.y * params_SourceSize.y;
                float _1641 = 0.5f * (_1632 - _1639);
                float _1643 = _1641 - 1.0f;
                float _1647 = _1632 * params_SourceSize.w;
                float _1651 = (_1631 + (-1.5f)) * params_SourceSize.w;
                float _1670 = ceil(_1628 + 0.25f) * 2.0f;
                float _1671 = _1670 - 0.5f;
                float _1680 = 0.5f * (_1671 - _1639);
                float _1682 = _1680 - 1.0f;
                float _1686 = _1671 * params_SourceSize.w;
                float _1690 = (_1670 - 2.5f) * params_SourceSize.w;
                float _1726 = vTexCoord.x * params_SourceSize.x;
                float _1730 = params_MaxSpotSize / delta;
                float _1734 = params_SourceSize.z * (floor(_1726 - _1730) + 0.5f);
                float _1748 = params_SourceSize.z * (floor(_1726 + _1730) + 1.0f);
                float _1754 = _1726 * delta;
                float3 _3365;
                _3365 = 0.0f.xxx;
                for (float _3363 = _1734; _3363 < _1748; )
                {
                    float2 _1766 = float2(_3363, _1647);
                    float3 _1775 = Source.SampleLevel(_Source_sampler, _1766, 0.0f).xyz;
                    float2 _1780 = float2(_3363, _1651);
                    float3 _1789 = Source.SampleLevel(_Source_sampler, _1780, 0.0f).xyz;
                    float _1796 = delta * ((params_SourceSize.x * _3363) - 0.5f);
                    float _1839 = _1754 - _1796;
                    float _1847 = _1754 - (_1796 + delta);
                    float3 _1858 = clamp(_1775 * abs(_1641), 0.0f.xxx, 1.0f.xxx);
                    float3 _1874 = clamp(_1775 * _1839, (-1.0f).xxx, 1.0f.xxx) * 3.1415927410125732421875f;
                    float3 _1880 = clamp(_1775 * _1847, (-1.0f).xxx, 1.0f.xxx) * 3.1415927410125732421875f;
                    float3 _1914 = clamp(_1789 * abs(_1643), 0.0f.xxx, 1.0f.xxx);
                    float3 _1930 = clamp(_1789 * _1839, (-1.0f).xxx, 1.0f.xxx) * 3.1415927410125732421875f;
                    float3 _1936 = clamp(_1789 * _1847, (-1.0f).xxx, 1.0f.xxx) * 3.1415927410125732421875f;
                    _3365 = (_3365 + (((Linearized.SampleLevel(_Linearized_sampler, _1766, 0.0f).xyz * _1775) * (((_1858 * _1858) * ((_1858 * 2.0f) - 3.0f.xxx)) + 1.0f.xxx)) * (((_1874 + sin(_1874)) - _1880) - sin(_1880)))) + (((Linearized.SampleLevel(_Linearized_sampler, _1780, 0.0f).xyz * _1789) * (((_1914 * _1914) * ((_1914 * 2.0f) - 3.0f.xxx)) + 1.0f.xxx)) * (((_1930 + sin(_1930)) - _1936) - sin(_1936)));
                    _3363 += params_SourceSize.z;
                    continue;
                }
                float _1828 = params_MaxSpotSize * 0.15915493667125701904296875f;
                float3 _3372;
                _3372 = 0.0f.xxx;
                for (float _3370 = _1734; _3370 < _1748; )
                {
                    float2 _2013 = float2(_3370, _1686);
                    float3 _2022 = Source.SampleLevel(_Source_sampler, _2013, 0.0f).xyz;
                    float2 _2027 = float2(_3370, _1690);
                    float3 _2036 = Source.SampleLevel(_Source_sampler, _2027, 0.0f).xyz;
                    float _2043 = delta * ((params_SourceSize.x * _3370) - 0.5f);
                    float _2086 = _1754 - _2043;
                    float _2094 = _1754 - (_2043 + delta);
                    float3 _2105 = clamp(_2022 * abs(_1680), 0.0f.xxx, 1.0f.xxx);
                    float3 _2121 = clamp(_2022 * _2086, (-1.0f).xxx, 1.0f.xxx) * 3.1415927410125732421875f;
                    float3 _2127 = clamp(_2022 * _2094, (-1.0f).xxx, 1.0f.xxx) * 3.1415927410125732421875f;
                    float3 _2161 = clamp(_2036 * abs(_1682), 0.0f.xxx, 1.0f.xxx);
                    float3 _2177 = clamp(_2036 * _2086, (-1.0f).xxx, 1.0f.xxx) * 3.1415927410125732421875f;
                    float3 _2183 = clamp(_2036 * _2094, (-1.0f).xxx, 1.0f.xxx) * 3.1415927410125732421875f;
                    _3372 = (_3372 + (((Linearized.SampleLevel(_Linearized_sampler, _2013, 0.0f).xyz * _2022) * (((_2105 * _2105) * ((_2105 * 2.0f) - 3.0f.xxx)) + 1.0f.xxx)) * (((_2121 + sin(_2121)) - _2127) - sin(_2127)))) + (((Linearized.SampleLevel(_Linearized_sampler, _2027, 0.0f).xyz * _2036) * (((_2161 * _2161) * ((_2161 * 2.0f) - 3.0f.xxx)) + 1.0f.xxx)) * (((_2177 + sin(_2177)) - _2183) - sin(_2183)));
                    _3370 += params_SourceSize.z;
                    continue;
                }
                _3399 = ((_3365 * _1828) + (_3372 * _1828)) * 0.5f;
            }
            else
            {
                float3 _3400;
                if (((params_FrameCount + uint(params_OddFieldFirst == 1.0f)) % 2u) == 0u)
                {
                    float _2203 = ceil(((0.5f * vTexCoord.y) * params_SourceSize.y) + 0.25f) * 2.0f;
                    float _2204 = _2203 - 0.5f;
                    float _2213 = 0.5f * (_2204 - (vTexCoord.y * params_SourceSize.y));
                    float _2215 = _2213 - 1.0f;
                    float _2219 = _2204 * params_SourceSize.w;
                    float _2223 = (_2203 - 2.5f) * params_SourceSize.w;
                    float _2259 = vTexCoord.x * params_SourceSize.x;
                    float _2263 = params_MaxSpotSize / delta;
                    float _2267 = params_SourceSize.z * (floor(_2259 - _2263) + 0.5f);
                    float _2281 = params_SourceSize.z * (floor(_2259 + _2263) + 1.0f);
                    float _2287 = _2259 * delta;
                    float3 _3357;
                    _3357 = 0.0f.xxx;
                    for (float _3355 = _2267; _3355 < _2281; )
                    {
                        float2 _2299 = float2(_3355, _2219);
                        float3 _2308 = Source.SampleLevel(_Source_sampler, _2299, 0.0f).xyz;
                        float2 _2313 = float2(_3355, _2223);
                        float3 _2322 = Source.SampleLevel(_Source_sampler, _2313, 0.0f).xyz;
                        float _2329 = delta * ((params_SourceSize.x * _3355) - 0.5f);
                        float _2372 = _2287 - _2329;
                        float _2380 = _2287 - (_2329 + delta);
                        float3 _2391 = clamp(_2308 * abs(_2213), 0.0f.xxx, 1.0f.xxx);
                        float3 _2407 = clamp(_2308 * _2372, (-1.0f).xxx, 1.0f.xxx) * 3.1415927410125732421875f;
                        float3 _2413 = clamp(_2308 * _2380, (-1.0f).xxx, 1.0f.xxx) * 3.1415927410125732421875f;
                        float3 _2447 = clamp(_2322 * abs(_2215), 0.0f.xxx, 1.0f.xxx);
                        float3 _2463 = clamp(_2322 * _2372, (-1.0f).xxx, 1.0f.xxx) * 3.1415927410125732421875f;
                        float3 _2469 = clamp(_2322 * _2380, (-1.0f).xxx, 1.0f.xxx) * 3.1415927410125732421875f;
                        _3357 = (_3357 + (((Linearized.SampleLevel(_Linearized_sampler, _2299, 0.0f).xyz * _2308) * (((_2391 * _2391) * ((_2391 * 2.0f) - 3.0f.xxx)) + 1.0f.xxx)) * (((_2407 + sin(_2407)) - _2413) - sin(_2413)))) + (((Linearized.SampleLevel(_Linearized_sampler, _2313, 0.0f).xyz * _2322) * (((_2447 * _2447) * ((_2447 * 2.0f) - 3.0f.xxx)) + 1.0f.xxx)) * (((_2463 + sin(_2463)) - _2469) - sin(_2469)));
                        _3355 += params_SourceSize.z;
                        continue;
                    }
                    _3400 = _3357 * (params_MaxSpotSize * 0.15915493667125701904296875f);
                }
                else
                {
                    float _2489 = ceil(((0.5f * vTexCoord.y) * params_SourceSize.y) - 0.25f) * 2.0f;
                    float _2490 = _2489 + 0.5f;
                    float _2499 = 0.5f * (_2490 - (vTexCoord.y * params_SourceSize.y));
                    float _2501 = _2499 - 1.0f;
                    float _2505 = _2490 * params_SourceSize.w;
                    float _2509 = (_2489 + (-1.5f)) * params_SourceSize.w;
                    float _2545 = vTexCoord.x * params_SourceSize.x;
                    float _2549 = params_MaxSpotSize / delta;
                    float _2553 = params_SourceSize.z * (floor(_2545 - _2549) + 0.5f);
                    float _2567 = params_SourceSize.z * (floor(_2545 + _2549) + 1.0f);
                    float _2573 = _2545 * delta;
                    float3 _3349;
                    _3349 = 0.0f.xxx;
                    for (float _3347 = _2553; _3347 < _2567; )
                    {
                        float2 _2585 = float2(_3347, _2505);
                        float3 _2594 = Source.SampleLevel(_Source_sampler, _2585, 0.0f).xyz;
                        float2 _2599 = float2(_3347, _2509);
                        float3 _2608 = Source.SampleLevel(_Source_sampler, _2599, 0.0f).xyz;
                        float _2615 = delta * ((params_SourceSize.x * _3347) - 0.5f);
                        float _2658 = _2573 - _2615;
                        float _2666 = _2573 - (_2615 + delta);
                        float3 _2677 = clamp(_2594 * abs(_2499), 0.0f.xxx, 1.0f.xxx);
                        float3 _2693 = clamp(_2594 * _2658, (-1.0f).xxx, 1.0f.xxx) * 3.1415927410125732421875f;
                        float3 _2699 = clamp(_2594 * _2666, (-1.0f).xxx, 1.0f.xxx) * 3.1415927410125732421875f;
                        float3 _2733 = clamp(_2608 * abs(_2501), 0.0f.xxx, 1.0f.xxx);
                        float3 _2749 = clamp(_2608 * _2658, (-1.0f).xxx, 1.0f.xxx) * 3.1415927410125732421875f;
                        float3 _2755 = clamp(_2608 * _2666, (-1.0f).xxx, 1.0f.xxx) * 3.1415927410125732421875f;
                        _3349 = (_3349 + (((Linearized.SampleLevel(_Linearized_sampler, _2585, 0.0f).xyz * _2594) * (((_2677 * _2677) * ((_2677 * 2.0f) - 3.0f.xxx)) + 1.0f.xxx)) * (((_2693 + sin(_2693)) - _2699) - sin(_2699)))) + (((Linearized.SampleLevel(_Linearized_sampler, _2599, 0.0f).xyz * _2608) * (((_2733 * _2733) * ((_2733 * 2.0f) - 3.0f.xxx)) + 1.0f.xxx)) * (((_2749 + sin(_2749)) - _2755) - sin(_2755)));
                        _3347 += params_SourceSize.z;
                        continue;
                    }
                    _3400 = _3349 * (params_MaxSpotSize * 0.15915493667125701904296875f);
                }
                _3399 = _3400;
            }
            _3398 = _3399;
        }
        _3397 = _3398;
    }
    float3 _3429;
    if (params_MaskType == 1.0f)
    {
        float _2779 = viewportCoord.x * params_OutputSize.x;
        float3 _3402;
        float _3411;
        if (params_SubpixelPattern == 0.0f)
        {
            float3 _3403;
            float _3412;
            if (params_SubpixelMaskPattern == 2.0f)
            {
                _3412 = 2.0f;
                _3403 = _95[int(mod(_2779, 2.0f))];
            }
            else
            {
                float3 _3404;
                float _3413;
                if (params_SubpixelMaskPattern == 3.0f)
                {
                    _3413 = 3.0f;
                    _3404 = _114[int(mod(_2779, 3.0f))];
                }
                else
                {
                    float3 _3405;
                    float _3414;
                    if (params_SubpixelMaskPattern == 4.0f)
                    {
                        _3414 = 2.0f;
                        _3405 = _132[int(mod(_2779, 4.0f))];
                    }
                    else
                    {
                        bool _2811 = params_SubpixelMaskPattern == 5.0f;
                        float3 _3406;
                        if (_2811)
                        {
                            _3406 = _148[int(mod(_2779, 5.0f))];
                        }
                        else
                        {
                            _3406 = 1.0f.xxx;
                        }
                        _3414 = _2811 ? 2.5f : 1.0f;
                        _3405 = _3406;
                    }
                    _3413 = _3414;
                    _3404 = _3405;
                }
                _3412 = _3413;
                _3403 = _3404;
            }
            _3411 = _3412;
            _3402 = _3403;
        }
        else
        {
            float3 _3407;
            float _3416;
            if (params_SubpixelMaskPattern == 2.0f)
            {
                _3416 = 2.0f;
                _3407 = _95[int(mod(_2779, 2.0f))];
            }
            else
            {
                float3 _3408;
                float _3417;
                if (params_SubpixelMaskPattern == 3.0f)
                {
                    _3417 = 3.0f;
                    _3408 = _172[int(mod(_2779, 3.0f))];
                }
                else
                {
                    float3 _3409;
                    float _3418;
                    if (params_SubpixelMaskPattern == 4.0f)
                    {
                        _3418 = 2.0f;
                        _3409 = _184[int(mod(_2779, 4.0f))];
                    }
                    else
                    {
                        bool _2851 = params_SubpixelMaskPattern == 5.0f;
                        float3 _3410;
                        if (_2851)
                        {
                            _3410 = _196[int(mod(_2779, 5.0f))];
                        }
                        else
                        {
                            _3410 = 1.0f.xxx;
                        }
                        _3418 = _2851 ? 2.5f : 1.0f;
                        _3409 = _3410;
                    }
                    _3417 = _3418;
                    _3408 = _3409;
                }
                _3416 = _3417;
                _3407 = _3408;
            }
            _3411 = _3416;
            _3402 = _3407;
        }
        float3 _2878 = (1.0f - _3411).xxx;
        _3429 = ((clamp((_3397 - 1.0f.xxx) / _2878, 0.0f.xxx, _3397) * _3411) * float4(_3402, _3411).xyz) + clamp((1.0f.xxx - (_3397 * _3411)) / _2878, 0.0f.xxx, _3397);
    }
    else
    {
        float3 _3430;
        if (params_MaskType == 2.0f)
        {
            float _2924 = 3.0f * params_DynamicMaskTriads;
            float _2927 = _2924 * params_OutputSize.z;
            float _2932 = _2924 * viewportCoord.x;
            float3 _3394;
            if (_2927 < 0.5f)
            {
                float _2938 = round(_2932);
                float _2942 = clamp((_2932 - _2938) / _2927, -1.0f, 1.0f);
                int _2948 = int(mod(_2938 - 1.0f, 3.0f) + 0.001000000047497451305389404296875f);
                _3394 = ((_172[_2948] + _172[_2948].zxy) + ((_172[_2948].zxy - _172[_2948]) * (_2942 + (sin(3.1415927410125732421875f * _2942) * 0.3183098733425140380859375f)))) * 0.5f;
            }
            else
            {
                float3 _3395;
                if (_2927 < 1.0f)
                {
                    float _2975 = floor(_2932);
                    float _2980 = clamp((_2932 - _2975) / _2927, -1.0f, 1.0f);
                    float _2988 = clamp((_2932 - (_2975 + 1.0f)) / _2927, -1.0f, 1.0f);
                    int _2994 = int(mod(_2975 - 1.0f, 3.0f) + 0.001000000047497451305389404296875f);
                    _3395 = (((_172[_2994] + _172[_2994].yzx) + ((_172[_2994].zxy - _172[_2994]) * (_2980 + (sin(3.1415927410125732421875f * _2980) * 0.3183098733425140380859375f)))) + ((_172[_2994].yzx - _172[_2994].zxy) * (_2988 + (sin(3.1415927410125732421875f * _2988) * 0.3183098733425140380859375f)))) * 0.5f;
                }
                else
                {
                    float _3031 = round(_2932);
                    float _3036 = clamp((_2932 - (_3031 - 1.0f)) / _2927, -1.0f, 1.0f);
                    float _3044 = clamp((_2932 - _3031) / _2927, -1.0f, 1.0f);
                    float _3052 = clamp((_2932 - (_3031 + 1.0f)) / _2927, -1.0f, 1.0f);
                    int _3058 = int(mod(_3031 - 2.0f, 3.0f) + 0.001000000047497451305389404296875f);
                    _3395 = ((((_172[_3058] + _172[_3058].xyz) + ((_172[_3058].zxy - _172[_3058]) * (_3036 + (sin(3.1415927410125732421875f * _3036) * 0.3183098733425140380859375f)))) + ((_172[_3058].yzx - _172[_3058].zxy) * (_3044 + (sin(3.1415927410125732421875f * _3044) * 0.3183098733425140380859375f)))) + ((_172[_3058].xyz - _172[_3058].yzx) * (_3052 + (sin(3.1415927410125732421875f * _3052) * 0.3183098733425140380859375f)))) * 0.5f;
                }
                _3394 = _3395;
            }
            _3430 = ((clamp((_3397 - 1.0f.xxx) * (-0.5f).xxx, 0.0f.xxx, _3397) * 3.0f) * float4(_3394, 3.0f).xyz) + clamp((1.0f.xxx - (_3397 * 3.0f)) * (-0.5f).xxx, 0.0f.xxx, _3397);
        }
        else
        {
            _3430 = _3397;
        }
        _3429 = _3430;
    }
    FragColor.x = _3429.x;
    FragColor.y = _3429.y;
    FragColor.z = _3429.z;
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
