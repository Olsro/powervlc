// Generated from crt/shaders/crt-gdv-mini.slang. See slang/upstream for licence/source.
cbuffer Push : register(b1)
{
    float4 params_SourceSize : packoffset(c0);
    float4 params_OriginalSize : packoffset(c1);
    float4 params_OutputSize : packoffset(c2);
    float params_brightboost : packoffset(c3);
    float params_sat : packoffset(c3.y);
    float params_scanline : packoffset(c3.z);
    float params_beam_min : packoffset(c3.w);
    float params_beam_max : packoffset(c4);
    float params_h_sharp : packoffset(c4.y);
    float params_shadowMask : packoffset(c4.z);
    float params_masksize : packoffset(c4.w);
    float params_mcut : packoffset(c5);
    float params_maskDark : packoffset(c5.y);
    float params_maskLight : packoffset(c5.z);
    float params_CGWG : packoffset(c5.w);
    float params_warpX : packoffset(c6.y);
    float params_warpY : packoffset(c6.z);
    float params_gamma_out : packoffset(c6.w);
    float params_vignette : packoffset(c7);
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
    float2 _978 = (vTexCoord * 2.0f) - 1.0f.xx;
    float _980 = _978.y;
    float _989 = _978.x;
    float2 _753 = (((_978 * float2(1.0f + ((_980 * _980) * params_warpX), 1.0f + ((_989 * _989) * params_warpY))) * 0.5f) + 0.5f.xx) * params_SourceSize.xy;
    float2 _756 = frac(_753);
    float2 _776 = (floor(_753) * params_SourceSize.zw) + (params_SourceSize.zw * 0.5f);
    float _1748 = (params_OriginalSize.y > 400.0f) ? 1.0f : _756.y;
    float4 _794 = Source.Sample(_Source_sampler, _776);
    float4 _801 = Source.Sample(_Source_sampler, _776 - float2(params_SourceSize.z, 0.0f));
    float4 _808 = Source.Sample(_Source_sampler, _776 + float2(0.0f, params_SourceSize.w));
    float4 _820 = Source.Sample(_Source_sampler, _776 + float2(-params_SourceSize.z, params_SourceSize.w));
    float _824 = _756.x;
    float _829 = pow(_824, params_h_sharp);
    float _837 = pow(1.0f - _824, params_h_sharp);
    float3 _849 = (_829 + _837).xxx;
    float3 _850 = ((_801.xyz * _837) + (_794.xyz * _829)) / _849;
    float3 _863 = ((_820.xyz * _837) + (_808.xyz * _829)) / _849;
    float3 _866 = _850 * _850;
    float3 _869 = _863 * _863;
    float _875 = dot(_866, float3(0.300000011920928955078125f, 0.60000002384185791015625f, 0.100000001490116119384765625f));
    float _1677;
    if (params_vignette > 0.0f)
    {
        float _889 = vTexCoord.x - 0.5f;
        _1677 = _889 * _889;
    }
    else
    {
        _1677 = 0.0f;
    }
    float _1011 = params_scanline - 2.0f;
    float _1019 = params_beam_min + _1677;
    float _1023 = params_beam_max + _1677;
    float _1028 = _1748 * lerp(_1019, _1023, _875);
    float _905 = 1.0f - _1748;
    float _1060 = _905 * lerp(_1019, _1023, dot(_869, float3(0.300000011920928955078125f, 0.60000002384185791015625f, 0.100000001490116119384765625f)));
    float3 _913 = (_866 * exp2(((-lerp(_1011, params_scanline, _1748)) * _1028) * _1028)) + (_869 * exp2(((-lerp(_1011, params_scanline, _905)) * _1060) * _1060));
    float3 _1703;
    do
    {
        float2 _1102 = floor((vTexCoord * params_OutputSize.xy) / params_masksize.xx);
        float3 _1109 = params_maskDark.xxx;
        float3 _1924;
        if (params_shadowMask == (-1.0f))
        {
            _1924 = 1.0f.xxx;
        }
        else
        {
            float3 _1925;
            if (params_shadowMask == 0.0f)
            {
                float _1126 = 1.0f - params_CGWG;
                float3 _1926;
                if (frac(_1102.x * 0.5f) < 0.5f)
                {
                    _1926 = float3(1.10000002384185791015625f, _1126, 1.10000002384185791015625f);
                }
                else
                {
                    _1926 = float3(_1126, 1.10000002384185791015625f, _1126);
                }
                _1925 = _1926;
            }
            else
            {
                float3 _1927;
                if (params_shadowMask == 1.0f)
                {
                    float _1150 = _1102.x;
                    float _1700;
                    if (frac((_1102.y + float(frac(_1150 * 0.16666667163372039794921875f) < 0.5f)) * 0.5f) < 0.5f)
                    {
                        _1700 = params_maskDark;
                    }
                    else
                    {
                        _1700 = params_maskLight;
                    }
                    float _1170 = frac(_1150 * 0.3333333432674407958984375f);
                    float3 _1922;
                    if (_1170 < 0.333000004291534423828125f)
                    {
                        float3 _1792 = _1109;
                        _1792.z = params_maskLight;
                        _1922 = _1792;
                    }
                    else
                    {
                        float3 _1923;
                        if (_1170 < 0.66600000858306884765625f)
                        {
                            float3 _1795 = _1109;
                            _1795.y = params_maskLight;
                            _1923 = _1795;
                        }
                        else
                        {
                            float3 _1797 = _1109;
                            _1797.x = params_maskLight;
                            _1923 = _1797;
                        }
                        _1922 = _1923;
                    }
                    _1927 = _1922 * _1700;
                }
                else
                {
                    float3 _1928;
                    if (params_shadowMask == 2.0f)
                    {
                        float _1204 = frac(_1102.x * 0.3333333432674407958984375f);
                        float3 _1929;
                        if (_1204 < 0.333000004291534423828125f)
                        {
                            float3 _1803 = _1109;
                            _1803.z = params_maskLight;
                            _1929 = _1803;
                        }
                        else
                        {
                            float3 _1930;
                            if (_1204 < 0.66600000858306884765625f)
                            {
                                float3 _1806 = _1109;
                                _1806.y = params_maskLight;
                                _1930 = _1806;
                            }
                            else
                            {
                                float3 _1808 = _1109;
                                _1808.x = params_maskLight;
                                _1930 = _1808;
                            }
                            _1929 = _1930;
                        }
                        _1928 = _1929;
                    }
                    else
                    {
                        float3 _1931;
                        if (params_shadowMask == 3.0f)
                        {
                            float _1242 = frac((_1102.x + (_1102.y * 3.0f)) * 0.16666667163372039794921875f);
                            float3 _1932;
                            if (_1242 < 0.333000004291534423828125f)
                            {
                                float3 _1818 = _1109;
                                _1818.z = params_maskLight;
                                _1932 = _1818;
                            }
                            else
                            {
                                float3 _1933;
                                if (_1242 < 0.66600000858306884765625f)
                                {
                                    float3 _1821 = _1109;
                                    _1821.y = params_maskLight;
                                    _1933 = _1821;
                                }
                                else
                                {
                                    float3 _1823 = _1109;
                                    _1823.x = params_maskLight;
                                    _1933 = _1823;
                                }
                                _1932 = _1933;
                            }
                            _1931 = _1932;
                        }
                        else
                        {
                            float3 _1934;
                            if (params_shadowMask == 4.0f)
                            {
                                float2 _1272 = floor(_1102 * float2(1.0f, 0.5f));
                                float _1283 = frac((_1272.x + (_1272.y * 3.0f)) * 0.16666667163372039794921875f);
                                float3 _1935;
                                if (_1283 < 0.333000004291534423828125f)
                                {
                                    float3 _1833 = _1109;
                                    _1833.z = params_maskLight;
                                    _1935 = _1833;
                                }
                                else
                                {
                                    float3 _1936;
                                    if (_1283 < 0.66600000858306884765625f)
                                    {
                                        float3 _1836 = _1109;
                                        _1836.y = params_maskLight;
                                        _1936 = _1836;
                                    }
                                    else
                                    {
                                        float3 _1838 = _1109;
                                        _1838.x = params_maskLight;
                                        _1936 = _1838;
                                    }
                                    _1935 = _1936;
                                }
                                _1934 = _1935;
                            }
                            else
                            {
                                float3 _1937;
                                if (params_shadowMask == 5.0f)
                                {
                                    float _1318 = max(max(_913.x, _913.y), _913.z);
                                    float3 _1339 = min((1.25f * max(_1318 - params_mcut, 0.0f)) / (1.0f - params_mcut), params_maskDark + ((0.20000000298023223876953125f * (1.0f - params_maskDark)) * _1318)).xxx;
                                    float _1342 = 0.800000011920928955078125f * params_maskLight;
                                    float _1354 = (_1342 - ((0.5f * (_1342 - 1.0f)) * _1318)) + (0.75f * (1.0f - _1318));
                                    float3 _1938;
                                    if (frac(_1102.x * 0.5f) < 0.5f)
                                    {
                                        float3 _1847 = _1339;
                                        _1847.x = _1354;
                                        _1847.z = _1354;
                                        _1938 = _1847;
                                    }
                                    else
                                    {
                                        float3 _1851 = _1339;
                                        _1851.y = _1354;
                                        _1938 = _1851;
                                    }
                                    _1937 = _1938;
                                }
                                else
                                {
                                    float3 _1939;
                                    if (params_shadowMask == 6.0f)
                                    {
                                        float _1385 = max(max(_913.x, _913.y), _913.z);
                                        float3 _1406 = min((1.33000004291534423828125f * max(_1385 - params_mcut, 0.0f)) / (1.0f - params_mcut), params_maskDark + ((0.2249999940395355224609375f * (1.0f - params_maskDark)) * _1385)).xxx;
                                        float _1409 = 0.800000011920928955078125f * params_maskLight;
                                        float _1421 = (_1409 - ((0.5f * (_1409 - 1.0f)) * _1385)) + (0.75f * (1.0f - _1385));
                                        float _1426 = frac(_1102.x * 0.3333333432674407958984375f);
                                        float3 _1940;
                                        if (_1426 < 0.333000004291534423828125f)
                                        {
                                            float3 _1860 = _1406;
                                            _1860.x = _1421;
                                            _1940 = _1860;
                                        }
                                        else
                                        {
                                            float3 _1941;
                                            if (_1426 < 0.66600000858306884765625f)
                                            {
                                                float3 _1863 = _1406;
                                                _1863.y = _1421;
                                                _1941 = _1863;
                                            }
                                            else
                                            {
                                                float3 _1865 = _1406;
                                                _1865.z = _1421;
                                                _1941 = _1865;
                                            }
                                            _1940 = _1941;
                                        }
                                        _1939 = _1940;
                                    }
                                    else
                                    {
                                        float3 _1942;
                                        if (params_shadowMask == 7.0f)
                                        {
                                            float _1461 = max(max(_913.x, _913.y), _913.z);
                                            float3 _1943;
                                            if (frac(_1102.x * 0.5f) < 0.5f)
                                            {
                                                _1943 = (1.0f + (0.60000002384185791015625f * (1.0f - _1461))).xxx;
                                            }
                                            else
                                            {
                                                _1943 = min((1.60000002384185791015625f * max(_1461 - params_mcut, 0.0f)) / (1.0f - params_mcut), 1.0f - params_CGWG).xxx;
                                            }
                                            _1942 = _1943;
                                        }
                                        else
                                        {
                                            float3 _1944;
                                            if (params_shadowMask == 8.0f)
                                            {
                                                float _1499 = _1102.x;
                                                float _1696;
                                                if (frac((_1102.y + float(frac(_1499 * 0.25f) < 0.5f)) * 0.5f) < 0.5f)
                                                {
                                                    _1696 = params_maskDark;
                                                }
                                                else
                                                {
                                                    _1696 = params_maskLight;
                                                }
                                                float3 _1919;
                                                if (frac(_1499 * 0.5f) < 0.5f)
                                                {
                                                    float3 _1880 = _1109;
                                                    _1880.x = params_maskLight;
                                                    _1880.z = params_maskLight;
                                                    _1919 = _1880;
                                                }
                                                else
                                                {
                                                    float3 _1884 = _1109;
                                                    _1884.y = params_maskLight;
                                                    _1919 = _1884;
                                                }
                                                _1944 = _1919 * _1696;
                                            }
                                            else
                                            {
                                                if (params_shadowMask == 9.0f)
                                                {
                                                    float _1550 = _1102.x;
                                                    bool _1553 = frac(_1550 * 0.16666667163372039794921875f) < 0.5f;
                                                    float _1559 = frac(_1550 * 0.3333333432674407958984375f);
                                                    float3 _1914;
                                                    if (_1559 < 0.33329999446868896484375f)
                                                    {
                                                        float3 _1888 = _1109;
                                                        _1888.z = 0.89999997615814208984375f;
                                                        _1914 = _1888;
                                                    }
                                                    else
                                                    {
                                                        float3 _1915;
                                                        if (_1559 < 0.6665999889373779296875f)
                                                        {
                                                            float3 _1890 = _1109;
                                                            _1890.y = 0.89999997615814208984375f;
                                                            _1915 = _1890;
                                                        }
                                                        else
                                                        {
                                                            float3 _1892 = _1109;
                                                            _1892.x = 0.89999997615814208984375f;
                                                            _1915 = _1892;
                                                        }
                                                        _1914 = _1915;
                                                    }
                                                    float _1575 = mod(_1102.y, 2.0f);
                                                    bool _1579 = (_1575 == 1.0f) && _1553;
                                                    bool _1590;
                                                    if (!_1579)
                                                    {
                                                        _1590 = (_1575 == 0.0f) && (!_1553);
                                                    }
                                                    else
                                                    {
                                                        _1590 = _1579;
                                                    }
                                                    float3 _1916;
                                                    if (_1590)
                                                    {
                                                        _1916 = _1914 * params_maskLight;
                                                    }
                                                    else
                                                    {
                                                        _1916 = _1914;
                                                    }
                                                    _1703 = _1916;
                                                    break;
                                                }
                                                else
                                                {
                                                    if (params_shadowMask == 10.0f)
                                                    {
                                                        float _1608 = _1102.x;
                                                        float _1626 = frac(_1608 * 0.3333333432674407958984375f);
                                                        float3 _1908;
                                                        if (_1626 > 0.33329999446868896484375f)
                                                        {
                                                            float3 _1899 = _1109;
                                                            _1899.x = 1.0f;
                                                            _1899.z = 1.0f;
                                                            _1908 = _1899;
                                                        }
                                                        else
                                                        {
                                                            float3 _1909;
                                                            if (_1626 > 0.6665999889373779296875f)
                                                            {
                                                                float3 _1903 = _1109;
                                                                _1903.y = 1.0f;
                                                                _1909 = _1903;
                                                            }
                                                            else
                                                            {
                                                                _1909 = params_mcut.xxx;
                                                            }
                                                            _1908 = _1909;
                                                        }
                                                        float3 _1910;
                                                        if (_1626 > 0.333000004291534423828125f)
                                                        {
                                                            _1910 = _1908 * ((frac((_1102.y + float(frac(_1608 * 0.16666667163372039794921875f) < 0.5f)) * 0.5f) < 0.5f) ? 1.0f : params_maskLight);
                                                        }
                                                        else
                                                        {
                                                            _1910 = _1908;
                                                        }
                                                        _1703 = _1910;
                                                        break;
                                                    }
                                                }
                                                _1944 = _1109;
                                            }
                                            _1942 = _1944;
                                        }
                                        _1939 = _1942;
                                    }
                                    _1937 = _1939;
                                }
                                _1934 = _1937;
                            }
                            _1931 = _1934;
                        }
                        _1928 = _1931;
                    }
                    _1927 = _1928;
                }
                _1925 = _1927;
            }
            _1924 = _1925;
        }
        _1703 = _1924;
        break;
    } while(false);
    float3 _931 = pow(_913 * _1703, params_gamma_out.xxx);
    float3 _949 = lerp(dot(float3(0.300000011920928955078125f, 0.60000002384185791015625f, 0.100000001490116119384765625f), _931).xxx, _931 * lerp(1.0f, params_brightboost, _875), params_sat.xxx);
    FragColor.x = _949.x;
    FragColor.y = _949.y;
    FragColor.z = _949.z;
}

SPIRV_Cross_Output main(SPIRV_Cross_Input stage_input)
{
    vTexCoord = stage_input.vTexCoord;
    frag_main();
    SPIRV_Cross_Output stage_output;
    stage_output.FragColor = FragColor;
    return stage_output;
}
