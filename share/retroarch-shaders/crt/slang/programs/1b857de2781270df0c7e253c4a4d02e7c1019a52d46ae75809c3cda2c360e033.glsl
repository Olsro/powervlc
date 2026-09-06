// Generated from crt/shaders/crt-gdv-mini.slang. See slang/upstream for licence/source.
#version 120
#pragma parameter gdv_mini_title 	"[ GDV MINI - DariusG ]:" 0.0 0.0 1.0 1.0
#pragma parameter brightboost 		"Bright boost" 1.0 0.5 2.0 0.05
#pragma parameter sat 				"Saturation adjustment" 1.0 0.0 2.0 0.05
#pragma parameter scanline          "Scanline Adjust" 8.0 1.0 12.0 1.0
#pragma parameter beam_min          "Scanline Dark" 1.35 0.5 3.0 0.05
#pragma parameter beam_max          "Scanline Bright" 1.05 0.5 3.0 0.05
#pragma parameter h_sharp           "Horizontal Sharpness" 2.0 1.0 5.0 0.05
#pragma parameter gamma_out 		"Gamma out" 0.5 0.2 0.6 0.01
#pragma parameter shadowMask 		"CRT Mask: 0:CGWG, 1-4:Lottes, 5-6:Trinitron" 0.0 -1.0 10.0 1.0
#pragma parameter masksize 			"CRT Mask Size (2.0 is nice in 4k)" 1.0 1.0 2.0 1.0
#pragma parameter mcut 				"Mask 5-7-10 cutoff" 0.2 0.0 0.5 0.05
#pragma parameter maskDark          "Lottes maskDark" 0.5 0.0 2.0 0.1
#pragma parameter maskLight 		"Lottes maskLight" 1.5 0.0 2.0 0.1
#pragma parameter CGWG              "CGWG Mask Str." 0.3 0.0 1.0 0.1
#pragma parameter warpX 			"CurvatureX (default 0.03)" 0.0 0.0 0.25 0.01
#pragma parameter warpY 			"CurvatureY (default 0.04)" 0.0 0.0 0.25 0.01
#pragma parameter vignette 			"Vignette On/Off" 0.0 0.0 1.0 1.0
#ifdef VERTEX

uniform mat4 MVPMatrix;
struct UBO
{
    mat4 MVP;
};



attribute vec4 VertexCoord;
varying vec2 RA_VARYING_0;
attribute vec2 TexCoord;

void main()
{
    gl_Position = (MVPMatrix) * VertexCoord;
    RA_VARYING_0 = TexCoord * 1.00010001659393310546875;
}


#endif
#ifdef FRAGMENT

uniform float CGWG;
uniform vec2 OrigTextureSize;
uniform vec2 OutputSize;
uniform vec2 TextureSize;
uniform float beam_max;
uniform float beam_min;
uniform float brightboost;
uniform float gamma_out;
uniform float h_sharp;
uniform float maskDark;
uniform float maskLight;
uniform float masksize;
uniform float mcut;
uniform float sat;
uniform float scanline;
uniform float shadowMask;
uniform float vignette;
uniform float warpX;
uniform float warpY;
struct Push
{
    vec4 SourceSize;
    vec4 OriginalSize;
    vec4 OutputSize;
    float brightboost;
    float sat;
    float scanline;
    float beam_min;
    float beam_max;
    float h_sharp;
    float shadowMask;
    float masksize;
    float mcut;
    float maskDark;
    float maskLight;
    float CGWG;
    float warpX;
    float warpY;
    float gamma_out;
    float vignette;
};



uniform sampler2D Texture;

varying vec2 RA_VARYING_0;

void main()
{
    vec2 _978 = (RA_VARYING_0 * 2.0) - vec2(1.0);
    float _980 = _978.y;
    float _989 = _978.x;
    vec2 _753 = (((_978 * vec2(1.0 + ((_980 * _980) * (warpX)), 1.0 + ((_989 * _989) * (warpY)))) * 0.5) + vec2(0.5)) * (vec4(TextureSize, 1.0 / TextureSize)).xy;
    vec2 _756 = fract(_753);
    vec2 _776 = (floor(_753) * (vec4(TextureSize, 1.0 / TextureSize)).zw) + ((vec4(TextureSize, 1.0 / TextureSize)).zw * 0.5);
    float _1748 = ((vec4(OrigTextureSize, 1.0 / OrigTextureSize)).y > 400.0) ? 1.0 : _756.y;
    vec4 _794 = texture2D(Texture, _776);
    vec4 _801 = texture2D(Texture, _776 - vec2((vec4(TextureSize, 1.0 / TextureSize)).z, 0.0));
    vec4 _808 = texture2D(Texture, _776 + vec2(0.0, (vec4(TextureSize, 1.0 / TextureSize)).w));
    vec4 _820 = texture2D(Texture, _776 + vec2(-(vec4(TextureSize, 1.0 / TextureSize)).z, (vec4(TextureSize, 1.0 / TextureSize)).w));
    float _824 = _756.x;
    float _829 = pow(_824, (h_sharp));
    float _837 = pow(1.0 - _824, (h_sharp));
    vec3 _849 = vec3(_829 + _837);
    vec3 _850 = ((_801.xyz * _837) + (_794.xyz * _829)) / _849;
    vec3 _863 = ((_820.xyz * _837) + (_808.xyz * _829)) / _849;
    vec3 _866 = _850 * _850;
    vec3 _869 = _863 * _863;
    float _875 = dot(_866, vec3(0.300000011920928955078125, 0.60000002384185791015625, 0.100000001490116119384765625));
    float _1677;
    if ((vignette) > 0.0)
    {
        float _889 = RA_VARYING_0.x - 0.5;
        _1677 = _889 * _889;
    }
    else
    {
        _1677 = 0.0;
    }
    float _1011 = (scanline) - 2.0;
    float _1019 = (beam_min) + _1677;
    float _1023 = (beam_max) + _1677;
    float _1028 = _1748 * mix(_1019, _1023, _875);
    float _905 = 1.0 - _1748;
    float _1060 = _905 * mix(_1019, _1023, dot(_869, vec3(0.300000011920928955078125, 0.60000002384185791015625, 0.100000001490116119384765625)));
    vec3 _913 = (_866 * exp2(((-mix(_1011, (scanline), _1748)) * _1028) * _1028)) + (_869 * exp2(((-mix(_1011, (scanline), _905)) * _1060) * _1060));
    vec3 _1703;
    do
    {
        vec2 _1102 = floor((RA_VARYING_0 * (vec4(OutputSize, 1.0 / OutputSize)).xy) / vec2((masksize)));
        vec3 _1109 = vec3((maskDark));
        vec3 _1924;
        if ((shadowMask) == (-1.0))
        {
            _1924 = vec3(1.0);
        }
        else
        {
            vec3 _1925;
            if ((shadowMask) == 0.0)
            {
                float _1126 = 1.0 - (CGWG);
                vec3 _1926;
                if (fract(_1102.x * 0.5) < 0.5)
                {
                    _1926 = vec3(1.10000002384185791015625, _1126, 1.10000002384185791015625);
                }
                else
                {
                    _1926 = vec3(_1126, 1.10000002384185791015625, _1126);
                }
                _1925 = _1926;
            }
            else
            {
                vec3 _1927;
                if ((shadowMask) == 1.0)
                {
                    float _1150 = _1102.x;
                    float _1700;
                    if (fract((_1102.y + float(fract(_1150 * 0.16666667163372039794921875) < 0.5)) * 0.5) < 0.5)
                    {
                        _1700 = (maskDark);
                    }
                    else
                    {
                        _1700 = (maskLight);
                    }
                    float _1170 = fract(_1150 * 0.3333333432674407958984375);
                    vec3 _1922;
                    if (_1170 < 0.333000004291534423828125)
                    {
                        vec3 _1792 = _1109;
                        _1792.z = (maskLight);
                        _1922 = _1792;
                    }
                    else
                    {
                        vec3 _1923;
                        if (_1170 < 0.66600000858306884765625)
                        {
                            vec3 _1795 = _1109;
                            _1795.y = (maskLight);
                            _1923 = _1795;
                        }
                        else
                        {
                            vec3 _1797 = _1109;
                            _1797.x = (maskLight);
                            _1923 = _1797;
                        }
                        _1922 = _1923;
                    }
                    _1927 = _1922 * _1700;
                }
                else
                {
                    vec3 _1928;
                    if ((shadowMask) == 2.0)
                    {
                        float _1204 = fract(_1102.x * 0.3333333432674407958984375);
                        vec3 _1929;
                        if (_1204 < 0.333000004291534423828125)
                        {
                            vec3 _1803 = _1109;
                            _1803.z = (maskLight);
                            _1929 = _1803;
                        }
                        else
                        {
                            vec3 _1930;
                            if (_1204 < 0.66600000858306884765625)
                            {
                                vec3 _1806 = _1109;
                                _1806.y = (maskLight);
                                _1930 = _1806;
                            }
                            else
                            {
                                vec3 _1808 = _1109;
                                _1808.x = (maskLight);
                                _1930 = _1808;
                            }
                            _1929 = _1930;
                        }
                        _1928 = _1929;
                    }
                    else
                    {
                        vec3 _1931;
                        if ((shadowMask) == 3.0)
                        {
                            float _1242 = fract((_1102.x + (_1102.y * 3.0)) * 0.16666667163372039794921875);
                            vec3 _1932;
                            if (_1242 < 0.333000004291534423828125)
                            {
                                vec3 _1818 = _1109;
                                _1818.z = (maskLight);
                                _1932 = _1818;
                            }
                            else
                            {
                                vec3 _1933;
                                if (_1242 < 0.66600000858306884765625)
                                {
                                    vec3 _1821 = _1109;
                                    _1821.y = (maskLight);
                                    _1933 = _1821;
                                }
                                else
                                {
                                    vec3 _1823 = _1109;
                                    _1823.x = (maskLight);
                                    _1933 = _1823;
                                }
                                _1932 = _1933;
                            }
                            _1931 = _1932;
                        }
                        else
                        {
                            vec3 _1934;
                            if ((shadowMask) == 4.0)
                            {
                                vec2 _1272 = floor(_1102 * vec2(1.0, 0.5));
                                float _1283 = fract((_1272.x + (_1272.y * 3.0)) * 0.16666667163372039794921875);
                                vec3 _1935;
                                if (_1283 < 0.333000004291534423828125)
                                {
                                    vec3 _1833 = _1109;
                                    _1833.z = (maskLight);
                                    _1935 = _1833;
                                }
                                else
                                {
                                    vec3 _1936;
                                    if (_1283 < 0.66600000858306884765625)
                                    {
                                        vec3 _1836 = _1109;
                                        _1836.y = (maskLight);
                                        _1936 = _1836;
                                    }
                                    else
                                    {
                                        vec3 _1838 = _1109;
                                        _1838.x = (maskLight);
                                        _1936 = _1838;
                                    }
                                    _1935 = _1936;
                                }
                                _1934 = _1935;
                            }
                            else
                            {
                                vec3 _1937;
                                if ((shadowMask) == 5.0)
                                {
                                    float _1318 = max(max(_913.x, _913.y), _913.z);
                                    vec3 _1339 = vec3(min((1.25 * max(_1318 - (mcut), 0.0)) / (1.0 - (mcut)), (maskDark) + ((0.20000000298023223876953125 * (1.0 - (maskDark))) * _1318)));
                                    float _1342 = 0.800000011920928955078125 * (maskLight);
                                    float _1354 = (_1342 - ((0.5 * (_1342 - 1.0)) * _1318)) + (0.75 * (1.0 - _1318));
                                    vec3 _1938;
                                    if (fract(_1102.x * 0.5) < 0.5)
                                    {
                                        vec3 _1847 = _1339;
                                        _1847.x = _1354;
                                        _1847.z = _1354;
                                        _1938 = _1847;
                                    }
                                    else
                                    {
                                        vec3 _1851 = _1339;
                                        _1851.y = _1354;
                                        _1938 = _1851;
                                    }
                                    _1937 = _1938;
                                }
                                else
                                {
                                    vec3 _1939;
                                    if ((shadowMask) == 6.0)
                                    {
                                        float _1385 = max(max(_913.x, _913.y), _913.z);
                                        vec3 _1406 = vec3(min((1.33000004291534423828125 * max(_1385 - (mcut), 0.0)) / (1.0 - (mcut)), (maskDark) + ((0.2249999940395355224609375 * (1.0 - (maskDark))) * _1385)));
                                        float _1409 = 0.800000011920928955078125 * (maskLight);
                                        float _1421 = (_1409 - ((0.5 * (_1409 - 1.0)) * _1385)) + (0.75 * (1.0 - _1385));
                                        float _1426 = fract(_1102.x * 0.3333333432674407958984375);
                                        vec3 _1940;
                                        if (_1426 < 0.333000004291534423828125)
                                        {
                                            vec3 _1860 = _1406;
                                            _1860.x = _1421;
                                            _1940 = _1860;
                                        }
                                        else
                                        {
                                            vec3 _1941;
                                            if (_1426 < 0.66600000858306884765625)
                                            {
                                                vec3 _1863 = _1406;
                                                _1863.y = _1421;
                                                _1941 = _1863;
                                            }
                                            else
                                            {
                                                vec3 _1865 = _1406;
                                                _1865.z = _1421;
                                                _1941 = _1865;
                                            }
                                            _1940 = _1941;
                                        }
                                        _1939 = _1940;
                                    }
                                    else
                                    {
                                        vec3 _1942;
                                        if ((shadowMask) == 7.0)
                                        {
                                            float _1461 = max(max(_913.x, _913.y), _913.z);
                                            vec3 _1943;
                                            if (fract(_1102.x * 0.5) < 0.5)
                                            {
                                                _1943 = vec3(1.0 + (0.60000002384185791015625 * (1.0 - _1461)));
                                            }
                                            else
                                            {
                                                _1943 = vec3(min((1.60000002384185791015625 * max(_1461 - (mcut), 0.0)) / (1.0 - (mcut)), 1.0 - (CGWG)));
                                            }
                                            _1942 = _1943;
                                        }
                                        else
                                        {
                                            vec3 _1944;
                                            if ((shadowMask) == 8.0)
                                            {
                                                float _1499 = _1102.x;
                                                float _1696;
                                                if (fract((_1102.y + float(fract(_1499 * 0.25) < 0.5)) * 0.5) < 0.5)
                                                {
                                                    _1696 = (maskDark);
                                                }
                                                else
                                                {
                                                    _1696 = (maskLight);
                                                }
                                                vec3 _1919;
                                                if (fract(_1499 * 0.5) < 0.5)
                                                {
                                                    vec3 _1880 = _1109;
                                                    _1880.x = (maskLight);
                                                    _1880.z = (maskLight);
                                                    _1919 = _1880;
                                                }
                                                else
                                                {
                                                    vec3 _1884 = _1109;
                                                    _1884.y = (maskLight);
                                                    _1919 = _1884;
                                                }
                                                _1944 = _1919 * _1696;
                                            }
                                            else
                                            {
                                                if ((shadowMask) == 9.0)
                                                {
                                                    float _1550 = _1102.x;
                                                    bool _1553 = fract(_1550 * 0.16666667163372039794921875) < 0.5;
                                                    float _1559 = fract(_1550 * 0.3333333432674407958984375);
                                                    vec3 _1914;
                                                    if (_1559 < 0.33329999446868896484375)
                                                    {
                                                        vec3 _1888 = _1109;
                                                        _1888.z = 0.89999997615814208984375;
                                                        _1914 = _1888;
                                                    }
                                                    else
                                                    {
                                                        vec3 _1915;
                                                        if (_1559 < 0.6665999889373779296875)
                                                        {
                                                            vec3 _1890 = _1109;
                                                            _1890.y = 0.89999997615814208984375;
                                                            _1915 = _1890;
                                                        }
                                                        else
                                                        {
                                                            vec3 _1892 = _1109;
                                                            _1892.x = 0.89999997615814208984375;
                                                            _1915 = _1892;
                                                        }
                                                        _1914 = _1915;
                                                    }
                                                    float _1575 = mod(_1102.y, 2.0);
                                                    bool _1579 = (_1575 == 1.0) && _1553;
                                                    bool _1590;
                                                    if (!_1579)
                                                    {
                                                        _1590 = (_1575 == 0.0) && (!_1553);
                                                    }
                                                    else
                                                    {
                                                        _1590 = _1579;
                                                    }
                                                    vec3 _1916;
                                                    if (_1590)
                                                    {
                                                        _1916 = _1914 * (maskLight);
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
                                                    if ((shadowMask) == 10.0)
                                                    {
                                                        float _1608 = _1102.x;
                                                        float _1626 = fract(_1608 * 0.3333333432674407958984375);
                                                        vec3 _1908;
                                                        if (_1626 > 0.33329999446868896484375)
                                                        {
                                                            vec3 _1899 = _1109;
                                                            _1899.x = 1.0;
                                                            _1899.z = 1.0;
                                                            _1908 = _1899;
                                                        }
                                                        else
                                                        {
                                                            vec3 _1909;
                                                            if (_1626 > 0.6665999889373779296875)
                                                            {
                                                                vec3 _1903 = _1109;
                                                                _1903.y = 1.0;
                                                                _1909 = _1903;
                                                            }
                                                            else
                                                            {
                                                                _1909 = vec3((mcut));
                                                            }
                                                            _1908 = _1909;
                                                        }
                                                        vec3 _1910;
                                                        if (_1626 > 0.333000004291534423828125)
                                                        {
                                                            _1910 = _1908 * ((fract((_1102.y + float(fract(_1608 * 0.16666667163372039794921875) < 0.5)) * 0.5) < 0.5) ? 1.0 : (maskLight));
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
    vec3 _931 = pow(_913 * _1703, vec3((gamma_out)));
    vec3 _949 = mix(vec3(dot(vec3(0.300000011920928955078125, 0.60000002384185791015625, 0.100000001490116119384765625), _931)), _931 * mix(1.0, (brightboost), _875), vec3((sat)));
    gl_FragData[0].x = _949.x;
    gl_FragData[0].y = _949.y;
    gl_FragData[0].z = _949.z;
}


#endif
