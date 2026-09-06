// Generated from crt/shaders/crt-lottes-multipass/scanpass-glow.slang. See slang/upstream for licence/source.
#version 120
#pragma parameter hardScan "hardScan" -8.0 -20.0 0.0 1.0
#pragma parameter hardPix "hardPix" -3.0 -20.0 0.0 1.0
#pragma parameter warpX "warpX" 0.031 0.0 0.125 0.01
#pragma parameter warpY "warpY" 0.041 0.0 0.125 0.01
#pragma parameter maskDark "maskDark" 0.5 0.0 2.0 0.1
#pragma parameter maskLight "maskLight" 1.5 0.0 2.0 0.1
#pragma parameter scaleInLinearGamma "scaleInLinearGamma" 1.0 0.0 1.0 1.0
#pragma parameter shadowMask "shadowMask" 3.0 0.0 4.0 1.0
#pragma parameter brightBoost "brightness boost" 1.0 0.0 2.0 0.05
#pragma parameter hardBloomPix "bloom-x soft" -1.5 -2.0 -0.5 0.1
#pragma parameter hardBloomScan "bloom-y soft" -2.0 -4.0 -1.0 0.1
#pragma parameter bloomAmount "bloom amount" 0.40 0.0 1.0 0.05
#pragma parameter shape "filter kernel shape" 2.0 0.0 10.0 0.05
#pragma parameter DIFFUSION "Diffusion" 0.0 0.0 1.0 0.01
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
    RA_VARYING_0 = TexCoord * 1.000010013580322265625;
}


#endif
#ifdef FRAGMENT

uniform float DIFFUSION;
uniform vec2 OutputSize;
uniform vec2 TextureSize;
uniform float bloomAmount;
uniform float brightBoost;
uniform float hardPix;
uniform float hardScan;
uniform float maskDark;
uniform float maskLight;
uniform float shadowMask;
uniform float shape;
uniform float warpX;
uniform float warpY;
struct UBO
{
    vec4 OutputSize;
    vec4 SourceSize;
};



struct Push
{
    float hardScan;
    float hardPix;
    float warpX;
    float warpY;
    float maskDark;
    float maskLight;
    float shadowMask;
    float brightBoost;
    float bloomAmount;
    float shape;
    float DIFFUSION;
};



uniform sampler2D Pass2Texture;
uniform sampler2D Pass5Texture;
uniform sampler2D Pass6Texture;

varying vec2 RA_VARYING_0;

void main()
{
    vec2 _672 = (RA_VARYING_0 * 2.0) - vec2(1.0);
    float _674 = _672.y;
    float _683 = _672.x;
    vec2 _697 = ((_672 * vec2(1.0 + ((_674 * _674) * (warpX)), 1.0 + ((_683 * _683) * (warpY)))) * 0.5) + vec2(0.5);
    vec2 _818 = _697 * (vec4(TextureSize, 1.0 / TextureSize)).xy;
    vec2 _901 = floor(_818);
    vec2 _904 = vec2(0.5) - (_818 - _901);
    float _778 = _904.x;
    float _914 = exp2((hardPix) * pow(abs(_778 - 1.0), (shape)));
    float _924 = exp2((hardPix) * pow(abs(_778), (shape)));
    float _934 = exp2((hardPix) * pow(abs(_778 + 1.0), (shape)));
    vec3 _809 = vec3((_914 + _924) + _934);
    float _1202 = exp2((hardPix) * pow(abs(_778 - 2.0), (shape)));
    float _1242 = exp2((hardPix) * pow(abs(_778 + 2.0), (shape)));
    float _1445 = _904.y;
    vec3 _736 = ((((((texture2D(Pass2Texture, (floor(_818 + vec2(-1.0)) + vec2(0.5)) / (vec4(TextureSize, 1.0 / TextureSize)).xy).xyz * (brightBoost)) * _914) + ((texture2D(Pass2Texture, (floor(_818 + vec2(0.0, -1.0)) + vec2(0.5)) / (vec4(TextureSize, 1.0 / TextureSize)).xy).xyz * (brightBoost)) * _924)) + ((texture2D(Pass2Texture, (floor(_818 + vec2(1.0, -1.0)) + vec2(0.5)) / (vec4(TextureSize, 1.0 / TextureSize)).xy).xyz * (brightBoost)) * _934)) / _809) * exp2((hardScan) * pow(abs(_1445 + (-1.0)), (shape)))) + ((((((((texture2D(Pass2Texture, (floor(_818 + vec2(-2.0, 0.0)) + vec2(0.5)) / (vec4(TextureSize, 1.0 / TextureSize)).xy).xyz * (brightBoost)) * _1202) + ((texture2D(Pass2Texture, (floor(_818 + vec2(-1.0, 0.0)) + vec2(0.5)) / (vec4(TextureSize, 1.0 / TextureSize)).xy).xyz * (brightBoost)) * _914)) + ((texture2D(Pass2Texture, (_901 + vec2(0.5)) / (vec4(TextureSize, 1.0 / TextureSize)).xy).xyz * (brightBoost)) * _924)) + ((texture2D(Pass2Texture, (floor(_818 + vec2(1.0, 0.0)) + vec2(0.5)) / (vec4(TextureSize, 1.0 / TextureSize)).xy).xyz * (brightBoost)) * _934)) + ((texture2D(Pass2Texture, (floor(_818 + vec2(2.0, 0.0)) + vec2(0.5)) / (vec4(TextureSize, 1.0 / TextureSize)).xy).xyz * (brightBoost)) * _1242)) / vec3((((_1202 + _914) + _924) + _934) + _1242)) * exp2((hardScan) * pow(abs(_1445), (shape))));
    vec3 _740 = _736 + ((((((texture2D(Pass2Texture, (floor(_818 + vec2(-1.0, 1.0)) + vec2(0.5)) / (vec4(TextureSize, 1.0 / TextureSize)).xy).xyz * (brightBoost)) * _914) + ((texture2D(Pass2Texture, (floor(_818 + vec2(0.0, 1.0)) + vec2(0.5)) / (vec4(TextureSize, 1.0 / TextureSize)).xy).xyz * (brightBoost)) * _924)) + ((texture2D(Pass2Texture, (floor(_818 + vec2(1.0)) + vec2(0.5)) / (vec4(TextureSize, 1.0 / TextureSize)).xy).xyz * (brightBoost)) * _934)) / _809) * exp2((hardScan) * pow(abs(_1445 + 1.0), (shape))));
    vec4 _619 = texture2D(Pass5Texture, _697);
    vec3 _1769;
    if ((shadowMask) > 0.0)
    {
        vec2 _632 = (RA_VARYING_0 / (vec4(OutputSize, 1.0 / OutputSize)).zw) * 1.00000095367431640625;
        vec3 _1562 = vec3((maskDark));
        vec3 _1867;
        if ((shadowMask) == 1.0)
        {
            float _1570 = _632.x;
            float _1737;
            if (fract((_632.y + float(fract(_1570 * 0.16666667163372039794921875) < 0.5)) * 0.5) < 0.5)
            {
                _1737 = (maskDark);
            }
            else
            {
                _1737 = (maskLight);
            }
            float _1590 = fract(_1570 * 0.3333333432674407958984375);
            vec3 _1865;
            if (_1590 < 0.333000004291534423828125)
            {
                vec3 _1808 = _1562;
                _1808.x = (maskLight);
                _1865 = _1808;
            }
            else
            {
                vec3 _1866;
                if (_1590 < 0.66600000858306884765625)
                {
                    vec3 _1811 = _1562;
                    _1811.y = (maskLight);
                    _1866 = _1811;
                }
                else
                {
                    vec3 _1813 = _1562;
                    _1813.z = (maskLight);
                    _1866 = _1813;
                }
                _1865 = _1866;
            }
            _1867 = _1865 * _1737;
        }
        else
        {
            vec3 _1868;
            if ((shadowMask) == 2.0)
            {
                float _1624 = fract(_632.x * 0.3333333432674407958984375);
                vec3 _1869;
                if (_1624 < 0.333000004291534423828125)
                {
                    vec3 _1819 = _1562;
                    _1819.x = (maskLight);
                    _1869 = _1819;
                }
                else
                {
                    vec3 _1870;
                    if (_1624 < 0.66600000858306884765625)
                    {
                        vec3 _1822 = _1562;
                        _1822.y = (maskLight);
                        _1870 = _1822;
                    }
                    else
                    {
                        vec3 _1824 = _1562;
                        _1824.z = (maskLight);
                        _1870 = _1824;
                    }
                    _1869 = _1870;
                }
                _1868 = _1869;
            }
            else
            {
                vec3 _1871;
                if ((shadowMask) == 3.0)
                {
                    float _1662 = fract((_632.x + (_632.y * 3.0)) * 0.16666667163372039794921875);
                    vec3 _1872;
                    if (_1662 < 0.333000004291534423828125)
                    {
                        vec3 _1834 = _1562;
                        _1834.x = (maskLight);
                        _1872 = _1834;
                    }
                    else
                    {
                        vec3 _1873;
                        if (_1662 < 0.66600000858306884765625)
                        {
                            vec3 _1837 = _1562;
                            _1837.y = (maskLight);
                            _1873 = _1837;
                        }
                        else
                        {
                            vec3 _1839 = _1562;
                            _1839.z = (maskLight);
                            _1873 = _1839;
                        }
                        _1872 = _1873;
                    }
                    _1871 = _1872;
                }
                else
                {
                    vec3 _1874;
                    if ((shadowMask) == 4.0)
                    {
                        vec2 _1692 = floor(_632 * vec2(1.0, 0.5));
                        float _1703 = fract((_1692.x + (_1692.y * 3.0)) * 0.16666667163372039794921875);
                        vec3 _1875;
                        if (_1703 < 0.333000004291534423828125)
                        {
                            vec3 _1849 = _1562;
                            _1849.x = (maskLight);
                            _1875 = _1849;
                        }
                        else
                        {
                            vec3 _1876;
                            if (_1703 < 0.66600000858306884765625)
                            {
                                vec3 _1852 = _1562;
                                _1852.y = (maskLight);
                                _1876 = _1852;
                            }
                            else
                            {
                                vec3 _1854 = _1562;
                                _1854.z = (maskLight);
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
    gl_FragData[0] = vec4(pow((_1769 + mix(vec3(0.0), texture2D(Pass6Texture, _697).xyz, vec3((bloomAmount)))) + (_619.xyz * (DIFFUSION)), vec3(0.4545454680919647216796875)), 1.0);
}


#endif
