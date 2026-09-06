// Generated from crt/shaders/crt-lottes-multipass/scanpass-glow.slang. See slang/upstream for licence/source.
cbuffer UBO : register(b0)
{
    float4 global_OutputSize : packoffset(c4);
    float4 global_SourceSize : packoffset(c6);
};

cbuffer Push : register(b1)
{
    float param_hardScan : packoffset(c0);
    float param_hardPix : packoffset(c0.y);
    float param_warpX : packoffset(c0.z);
    float param_warpY : packoffset(c0.w);
    float param_maskDark : packoffset(c1);
    float param_maskLight : packoffset(c1.y);
    float param_shadowMask : packoffset(c1.w);
    float param_brightBoost : packoffset(c2);
    float param_bloomAmount : packoffset(c2.w);
    float param_shape : packoffset(c3);
    float param_DIFFUSION : packoffset(c3.y);
};

Texture2D<float4> ORIG_LINEARIZED : register(t3);
SamplerState _ORIG_LINEARIZED_sampler : register(s3);
Texture2D<float4> GlowPass : register(t5);
SamplerState _GlowPass_sampler : register(s5);
Texture2D<float4> BloomPass : register(t4);
SamplerState _BloomPass_sampler : register(s4);

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

void frag_main()
{
    float2 _672 = (vTexCoord * 2.0f) - 1.0f.xx;
    float _674 = _672.y;
    float _683 = _672.x;
    float2 _697 = ((_672 * float2(1.0f + ((_674 * _674) * param_warpX), 1.0f + ((_683 * _683) * param_warpY))) * 0.5f) + 0.5f.xx;
    float2 _818 = _697 * global_SourceSize.xy;
    float2 _901 = floor(_818);
    float2 _904 = 0.5f.xx - (_818 - _901);
    float _778 = _904.x;
    float _914 = exp2(param_hardPix * pow(abs(_778 - 1.0f), param_shape));
    float _924 = exp2(param_hardPix * pow(abs(_778), param_shape));
    float _934 = exp2(param_hardPix * pow(abs(_778 + 1.0f), param_shape));
    float3 _809 = ((_914 + _924) + _934).xxx;
    float _1202 = exp2(param_hardPix * pow(abs(_778 - 2.0f), param_shape));
    float _1242 = exp2(param_hardPix * pow(abs(_778 + 2.0f), param_shape));
    float _1445 = _904.y;
    float3 _736 = ((((((ORIG_LINEARIZED.Sample(_ORIG_LINEARIZED_sampler, (floor(_818 + (-1.0f).xx) + 0.5f.xx) / global_SourceSize.xy).xyz * param_brightBoost) * _914) + ((ORIG_LINEARIZED.Sample(_ORIG_LINEARIZED_sampler, (floor(_818 + float2(0.0f, -1.0f)) + 0.5f.xx) / global_SourceSize.xy).xyz * param_brightBoost) * _924)) + ((ORIG_LINEARIZED.Sample(_ORIG_LINEARIZED_sampler, (floor(_818 + float2(1.0f, -1.0f)) + 0.5f.xx) / global_SourceSize.xy).xyz * param_brightBoost) * _934)) / _809) * exp2(param_hardScan * pow(abs(_1445 + (-1.0f)), param_shape))) + ((((((((ORIG_LINEARIZED.Sample(_ORIG_LINEARIZED_sampler, (floor(_818 + float2(-2.0f, 0.0f)) + 0.5f.xx) / global_SourceSize.xy).xyz * param_brightBoost) * _1202) + ((ORIG_LINEARIZED.Sample(_ORIG_LINEARIZED_sampler, (floor(_818 + float2(-1.0f, 0.0f)) + 0.5f.xx) / global_SourceSize.xy).xyz * param_brightBoost) * _914)) + ((ORIG_LINEARIZED.Sample(_ORIG_LINEARIZED_sampler, (_901 + 0.5f.xx) / global_SourceSize.xy).xyz * param_brightBoost) * _924)) + ((ORIG_LINEARIZED.Sample(_ORIG_LINEARIZED_sampler, (floor(_818 + float2(1.0f, 0.0f)) + 0.5f.xx) / global_SourceSize.xy).xyz * param_brightBoost) * _934)) + ((ORIG_LINEARIZED.Sample(_ORIG_LINEARIZED_sampler, (floor(_818 + float2(2.0f, 0.0f)) + 0.5f.xx) / global_SourceSize.xy).xyz * param_brightBoost) * _1242)) / ((((_1202 + _914) + _924) + _934) + _1242).xxx) * exp2(param_hardScan * pow(abs(_1445), param_shape)));
    float3 _740 = _736 + ((((((ORIG_LINEARIZED.Sample(_ORIG_LINEARIZED_sampler, (floor(_818 + float2(-1.0f, 1.0f)) + 0.5f.xx) / global_SourceSize.xy).xyz * param_brightBoost) * _914) + ((ORIG_LINEARIZED.Sample(_ORIG_LINEARIZED_sampler, (floor(_818 + float2(0.0f, 1.0f)) + 0.5f.xx) / global_SourceSize.xy).xyz * param_brightBoost) * _924)) + ((ORIG_LINEARIZED.Sample(_ORIG_LINEARIZED_sampler, (floor(_818 + 1.0f.xx) + 0.5f.xx) / global_SourceSize.xy).xyz * param_brightBoost) * _934)) / _809) * exp2(param_hardScan * pow(abs(_1445 + 1.0f), param_shape)));
    float4 _619 = GlowPass.Sample(_GlowPass_sampler, _697);
    float3 _1769;
    if (param_shadowMask > 0.0f)
    {
        float2 _632 = (vTexCoord / global_OutputSize.zw) * 1.00000095367431640625f;
        float3 _1562 = param_maskDark.xxx;
        float3 _1867;
        if (param_shadowMask == 1.0f)
        {
            float _1570 = _632.x;
            float _1737;
            if (frac((_632.y + float(frac(_1570 * 0.16666667163372039794921875f) < 0.5f)) * 0.5f) < 0.5f)
            {
                _1737 = param_maskDark;
            }
            else
            {
                _1737 = param_maskLight;
            }
            float _1590 = frac(_1570 * 0.3333333432674407958984375f);
            float3 _1865;
            if (_1590 < 0.333000004291534423828125f)
            {
                float3 _1808 = _1562;
                _1808.x = param_maskLight;
                _1865 = _1808;
            }
            else
            {
                float3 _1866;
                if (_1590 < 0.66600000858306884765625f)
                {
                    float3 _1811 = _1562;
                    _1811.y = param_maskLight;
                    _1866 = _1811;
                }
                else
                {
                    float3 _1813 = _1562;
                    _1813.z = param_maskLight;
                    _1866 = _1813;
                }
                _1865 = _1866;
            }
            _1867 = _1865 * _1737;
        }
        else
        {
            float3 _1868;
            if (param_shadowMask == 2.0f)
            {
                float _1624 = frac(_632.x * 0.3333333432674407958984375f);
                float3 _1869;
                if (_1624 < 0.333000004291534423828125f)
                {
                    float3 _1819 = _1562;
                    _1819.x = param_maskLight;
                    _1869 = _1819;
                }
                else
                {
                    float3 _1870;
                    if (_1624 < 0.66600000858306884765625f)
                    {
                        float3 _1822 = _1562;
                        _1822.y = param_maskLight;
                        _1870 = _1822;
                    }
                    else
                    {
                        float3 _1824 = _1562;
                        _1824.z = param_maskLight;
                        _1870 = _1824;
                    }
                    _1869 = _1870;
                }
                _1868 = _1869;
            }
            else
            {
                float3 _1871;
                if (param_shadowMask == 3.0f)
                {
                    float _1662 = frac((_632.x + (_632.y * 3.0f)) * 0.16666667163372039794921875f);
                    float3 _1872;
                    if (_1662 < 0.333000004291534423828125f)
                    {
                        float3 _1834 = _1562;
                        _1834.x = param_maskLight;
                        _1872 = _1834;
                    }
                    else
                    {
                        float3 _1873;
                        if (_1662 < 0.66600000858306884765625f)
                        {
                            float3 _1837 = _1562;
                            _1837.y = param_maskLight;
                            _1873 = _1837;
                        }
                        else
                        {
                            float3 _1839 = _1562;
                            _1839.z = param_maskLight;
                            _1873 = _1839;
                        }
                        _1872 = _1873;
                    }
                    _1871 = _1872;
                }
                else
                {
                    float3 _1874;
                    if (param_shadowMask == 4.0f)
                    {
                        float2 _1692 = floor(_632 * float2(1.0f, 0.5f));
                        float _1703 = frac((_1692.x + (_1692.y * 3.0f)) * 0.16666667163372039794921875f);
                        float3 _1875;
                        if (_1703 < 0.333000004291534423828125f)
                        {
                            float3 _1849 = _1562;
                            _1849.x = param_maskLight;
                            _1875 = _1849;
                        }
                        else
                        {
                            float3 _1876;
                            if (_1703 < 0.66600000858306884765625f)
                            {
                                float3 _1852 = _1562;
                                _1852.y = param_maskLight;
                                _1876 = _1852;
                            }
                            else
                            {
                                float3 _1854 = _1562;
                                _1854.z = param_maskLight;
                                _1876 = _1854;
                            }
                            _1875 = _1876;
                        }
                        _1874 = _1875;
                    }
                    else
                    {
                        _1874 = _1562;
                    }
                    _1871 = _1874;
                }
                _1868 = _1871;
            }
            _1867 = _1868;
        }
        _1769 = _740 * _1867;
    }
    else
    {
        _1769 = _740;
    }
    FragColor = float4(pow((_1769 + lerp(0.0f.xxx, BloomPass.Sample(_BloomPass_sampler, _697).xyz, param_bloomAmount.xxx)) + (_619.xyz * param_DIFFUSION), 0.4545454680919647216796875f.xxx), 1.0f);
}

SPIRV_Cross_Output main(SPIRV_Cross_Input stage_input)
{
    vTexCoord = stage_input.vTexCoord;
    frag_main();
    SPIRV_Cross_Output stage_output;
    stage_output.FragColor = FragColor;
    return stage_output;
}
