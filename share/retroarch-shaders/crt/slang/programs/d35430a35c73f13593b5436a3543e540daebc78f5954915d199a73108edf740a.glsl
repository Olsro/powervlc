// Generated from crt/shaders/crt-beans/scanlines_analytical.slang. See slang/upstream for licence/source.
#version 130
#pragma parameter OutputGamma "Output gamma (0: sRGB, 1: 2.2 gamma)" 1.0 0.0 1.0 1.0
#pragma parameter OverscanHorizontal "Horizontal overscan (proportion to crop)" 0.0 0.0 0.1 0.01
#pragma parameter OverscanVertical "Vertical overscan (proportion to crop)" 0.0 0.0 0.1 0.01
#pragma parameter MaxSpotSize "Maximum spot size (proportion of scanline)" 0.90 0.6 1.0 0.05
#pragma parameter MinSpotSize "Minimum spot size (proportion of maximum)" 0.4 0.3 1.0 0.1
#pragma parameter MaskType "Mask type (0: disabled, 1: subpixel, 2: dynamic)" 2.0 0.0 2.0 1.0
#pragma parameter SubpixelPattern "Monitor subpixel pattern (0: RGB, 1: BGR)" 0.0 0.0 1.0 1.0
#pragma parameter SubpixelMaskPattern "Subpixel mask width (pixels per triad)" 4.0 2.0 5.0 1.0
#pragma parameter DynamicMaskTriads "Dynamic mask phosphor triads (per screen width)" 550.0 400.0 800.0 25.0
#pragma parameter GlowSigma "Glow width (proportion of screen height)" 0.05 0.01 0.10 0.01
#pragma parameter GlowAmount "Glow amount (mix ratio)" 0.04 0.0 0.10 0.005
#pragma parameter OddFieldFirst "Interlacing (0/1: bob/phase, 2: weave, 3: VGA, 4: off)" 0.0 0.0 4.0 1.0
#ifdef VERTEX

uniform mat4 MVPMatrix;
uniform float OddFieldFirst;
uniform vec2 OutputSize;
uniform float OverscanHorizontal;
uniform float OverscanVertical;
uniform vec2 TextureSize;
struct UBO
{
    mat4 MVP;
};



struct Push
{
    vec4 SourceSize;
    vec4 OutputSize;
    float OddFieldFirst;
    float OverscanHorizontal;
    float OverscanVertical;
};



in vec4 VertexCoord;
out vec2 RA_VARYING_0;
in vec2 TexCoord;
flat out float RA_VARYING_1;
out vec2 RA_VARYING_2;

void main()
{
    gl_Position = (MVPMatrix) * VertexCoord;
    RA_VARYING_0 = ((vec2(1.0) - vec2((OverscanHorizontal), (OverscanVertical))) * (TexCoord - vec2(0.5))) + vec2(0.5);
    RA_VARYING_1 = (((((vec4(OutputSize, 1.0 / OutputSize)).x * (vec4(OutputSize, 1.0 / OutputSize)).w) * (vec4(TextureSize, 1.0 / TextureSize)).y) * (vec4(TextureSize, 1.0 / TextureSize)).z) * (1.0 - (OverscanVertical))) / (1.0 - (OverscanHorizontal));
    bool _85 = (OddFieldFirst) <= 2.0;
    bool _92;
    if (_85)
    {
        _92 = (vec4(TextureSize, 1.0 / TextureSize)).y > 300.0;
    }
    else
    {
        _92 = _85;
    }
    if (_92)
    {
        RA_VARYING_1 = 0.5 * RA_VARYING_1;
    }
    else
    {
        bool _101 = (OddFieldFirst) == 3.0;
        bool _108;
        if (_101)
        {
            _108 = (vec4(TextureSize, 1.0 / TextureSize)).y < 350.0;
        }
        else
        {
            _108 = _101;
        }
        if (_108)
        {
            RA_VARYING_1 = 2.0 * RA_VARYING_1;
        }
    }
    RA_VARYING_2 = TexCoord;
}


#endif
#ifdef FRAGMENT

uniform float DynamicMaskTriads;
uniform int FrameCount;
uniform float MaskType;
uniform float MaxSpotSize;
uniform float OddFieldFirst;
uniform vec2 OutputSize;
uniform float SubpixelMaskPattern;
uniform float SubpixelPattern;
uniform vec2 TextureSize;
const vec3 _95[2] = vec3[](vec3(1.0, 0.0, 1.0), vec3(0.0, 1.0, 0.0));
const vec3 _114[3] = vec3[](vec3(0.0, 0.0, 1.0), vec3(0.0, 1.0, 0.0), vec3(1.0, 0.0, 0.0));
const vec3 _132[4] = vec3[](vec3(1.0, 0.0, 0.0), vec3(1.0, 1.0, 0.0), vec3(0.0, 1.0, 1.0), vec3(0.0, 0.0, 1.0));
const vec3 _148[5] = vec3[](vec3(1.0, 0.0, 0.0), vec3(1.0, 0.0, 1.0), vec3(0.0, 0.0, 1.0), vec3(0.0, 1.0, 0.0), vec3(0.0, 1.0, 0.0));
const vec3 _172[3] = vec3[](vec3(1.0, 0.0, 0.0), vec3(0.0, 1.0, 0.0), vec3(0.0, 0.0, 1.0));
const vec3 _184[4] = vec3[](vec3(0.0, 0.0, 1.0), vec3(0.0, 1.0, 1.0), vec3(1.0, 1.0, 0.0), vec3(1.0, 0.0, 0.0));
const vec3 _196[5] = vec3[](vec3(0.0, 0.0, 1.0), vec3(1.0, 0.0, 1.0), vec3(1.0, 0.0, 0.0), vec3(0.0, 1.0, 0.0), vec3(0.0, 1.0, 0.0));

struct Push
{
    vec4 SourceSize;
    vec4 OutputSize;
    uint FrameCount;
    float MaxSpotSize;
    float OddFieldFirst;
    float MaskType;
    float SubpixelMaskPattern;
    float SubpixelPattern;
    float DynamicMaskTriads;
};



uniform sampler2D Pass1Texture;
uniform sampler2D Texture;

flat in float RA_VARYING_1;
in vec2 RA_VARYING_0;
in vec2 RA_VARYING_2;
out vec4 FragColor;

void main()
{
    bool _831 = (OddFieldFirst) == 3.0;
    bool _838;
    if (_831)
    {
        _838 = (vec4(TextureSize, 1.0 / TextureSize)).y < 350.0;
    }
    else
    {
        _838 = _831;
    }
    vec3 _3397;
    if (_838)
    {
        float _1051 = RA_VARYING_0.y * (vec4(TextureSize, 1.0 / TextureSize)).y;
        float _1052 = 2.0 * _1051;
        float _1061 = (ceil(_1052 - 0.5) + 0.5) - _1052;
        float _1063 = _1061 - 1.0;
        float _1073 = (ceil(_1051 + 0.25) - 0.5) * (vec4(TextureSize, 1.0 / TextureSize)).w;
        float _1083 = (ceil(_1051 - 0.25) - 0.5) * (vec4(TextureSize, 1.0 / TextureSize)).w;
        float _1119 = RA_VARYING_0.x * (vec4(TextureSize, 1.0 / TextureSize)).x;
        float _1123 = (MaxSpotSize) / RA_VARYING_1;
        float _1127 = (vec4(TextureSize, 1.0 / TextureSize)).z * (floor(_1119 - _1123) + 0.5);
        float _1141 = (vec4(TextureSize, 1.0 / TextureSize)).z * (floor(_1119 + _1123) + 1.0);
        float _1147 = _1119 * RA_VARYING_1;
        vec3 _3393;
        _3393 = vec3(0.0);
        for (float _3391 = _1127; _3391 < _1141; )
        {
            vec2 _1159 = vec2(_3391, _1073);
            vec3 _1168 = textureLod(Texture, _1159, 0.0).xyz;
            vec2 _1173 = vec2(_3391, _1083);
            vec3 _1182 = textureLod(Texture, _1173, 0.0).xyz;
            float _1189 = RA_VARYING_1 * (((vec4(TextureSize, 1.0 / TextureSize)).x * _3391) - 0.5);
            float _1232 = _1147 - _1189;
            float _1240 = _1147 - (_1189 + RA_VARYING_1);
            vec3 _1251 = clamp(_1168 * abs(_1061), vec3(0.0), vec3(1.0));
            vec3 _1267 = clamp(_1168 * _1232, vec3(-1.0), vec3(1.0)) * 3.1415927410125732421875;
            vec3 _1273 = clamp(_1168 * _1240, vec3(-1.0), vec3(1.0)) * 3.1415927410125732421875;
            vec3 _1307 = clamp(_1182 * abs(_1063), vec3(0.0), vec3(1.0));
            vec3 _1323 = clamp(_1182 * _1232, vec3(-1.0), vec3(1.0)) * 3.1415927410125732421875;
            vec3 _1329 = clamp(_1182 * _1240, vec3(-1.0), vec3(1.0)) * 3.1415927410125732421875;
            _3393 = (_3393 + (((textureLod(Pass1Texture, _1159, 0.0).xyz * _1168) * (((_1251 * _1251) * ((_1251 * 2.0) - vec3(3.0))) + vec3(1.0))) * (((_1267 + sin(_1267)) - _1273) - sin(_1273)))) + (((textureLod(Pass1Texture, _1173, 0.0).xyz * _1182) * (((_1307 * _1307) * ((_1307 * 2.0) - vec3(3.0))) + vec3(1.0))) * (((_1323 + sin(_1323)) - _1329) - sin(_1329)));
            _3391 += (vec4(TextureSize, 1.0 / TextureSize)).z;
            continue;
        }
        _3397 = _3393 * ((MaxSpotSize) * 0.15915493667125701904296875);
    }
    else
    {
        bool _861 = (OddFieldFirst) == 4.0;
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
            _876 = (vec4(TextureSize, 1.0 / TextureSize)).y <= 300.0;
        }
        else
        {
            _876 = _868;
        }
        vec3 _3398;
        if (_876)
        {
            float _1345 = RA_VARYING_0.y * (vec4(TextureSize, 1.0 / TextureSize)).y;
            float _1346 = round(_1345);
            float _1347 = _1346 + 0.5;
            float _1355 = _1347 - _1345;
            float _1357 = _1355 - 1.0;
            float _1361 = _1347 * (vec4(TextureSize, 1.0 / TextureSize)).w;
            float _1365 = (_1346 + (-0.5)) * (vec4(TextureSize, 1.0 / TextureSize)).w;
            float _1401 = RA_VARYING_0.x * (vec4(TextureSize, 1.0 / TextureSize)).x;
            float _1405 = (MaxSpotSize) / RA_VARYING_1;
            float _1409 = (vec4(TextureSize, 1.0 / TextureSize)).z * (floor(_1401 - _1405) + 0.5);
            float _1423 = (vec4(TextureSize, 1.0 / TextureSize)).z * (floor(_1401 + _1405) + 1.0);
            float _1429 = _1401 * RA_VARYING_1;
            vec3 _3385;
            _3385 = vec3(0.0);
            for (float _3383 = _1409; _3383 < _1423; )
            {
                vec2 _1441 = vec2(_3383, _1361);
                vec3 _1450 = textureLod(Texture, _1441, 0.0).xyz;
                vec2 _1455 = vec2(_3383, _1365);
                vec3 _1464 = textureLod(Texture, _1455, 0.0).xyz;
                float _1471 = RA_VARYING_1 * (((vec4(TextureSize, 1.0 / TextureSize)).x * _3383) - 0.5);
                float _1514 = _1429 - _1471;
                float _1522 = _1429 - (_1471 + RA_VARYING_1);
                vec3 _1533 = clamp(_1450 * abs(_1355), vec3(0.0), vec3(1.0));
                vec3 _1549 = clamp(_1450 * _1514, vec3(-1.0), vec3(1.0)) * 3.1415927410125732421875;
                vec3 _1555 = clamp(_1450 * _1522, vec3(-1.0), vec3(1.0)) * 3.1415927410125732421875;
                vec3 _1589 = clamp(_1464 * abs(_1357), vec3(0.0), vec3(1.0));
                vec3 _1605 = clamp(_1464 * _1514, vec3(-1.0), vec3(1.0)) * 3.1415927410125732421875;
                vec3 _1611 = clamp(_1464 * _1522, vec3(-1.0), vec3(1.0)) * 3.1415927410125732421875;
                _3385 = (_3385 + (((textureLod(Pass1Texture, _1441, 0.0).xyz * _1450) * (((_1533 * _1533) * ((_1533 * 2.0) - vec3(3.0))) + vec3(1.0))) * (((_1549 + sin(_1549)) - _1555) - sin(_1555)))) + (((textureLod(Pass1Texture, _1455, 0.0).xyz * _1464) * (((_1589 * _1589) * ((_1589 * 2.0) - vec3(3.0))) + vec3(1.0))) * (((_1605 + sin(_1605)) - _1611) - sin(_1611)));
                _3383 += (vec4(TextureSize, 1.0 / TextureSize)).z;
                continue;
            }
            _3398 = _3385 * ((MaxSpotSize) * 0.15915493667125701904296875);
        }
        else
        {
            vec3 _3399;
            if ((OddFieldFirst) == 2.0)
            {
                float _1628 = (0.5 * RA_VARYING_0.y) * (vec4(TextureSize, 1.0 / TextureSize)).y;
                float _1631 = ceil(_1628 - 0.25) * 2.0;
                float _1632 = _1631 + 0.5;
                float _1639 = RA_VARYING_0.y * (vec4(TextureSize, 1.0 / TextureSize)).y;
                float _1641 = 0.5 * (_1632 - _1639);
                float _1643 = _1641 - 1.0;
                float _1647 = _1632 * (vec4(TextureSize, 1.0 / TextureSize)).w;
                float _1651 = (_1631 + (-1.5)) * (vec4(TextureSize, 1.0 / TextureSize)).w;
                float _1670 = ceil(_1628 + 0.25) * 2.0;
                float _1671 = _1670 - 0.5;
                float _1680 = 0.5 * (_1671 - _1639);
                float _1682 = _1680 - 1.0;
                float _1686 = _1671 * (vec4(TextureSize, 1.0 / TextureSize)).w;
                float _1690 = (_1670 - 2.5) * (vec4(TextureSize, 1.0 / TextureSize)).w;
                float _1726 = RA_VARYING_0.x * (vec4(TextureSize, 1.0 / TextureSize)).x;
                float _1730 = (MaxSpotSize) / RA_VARYING_1;
                float _1734 = (vec4(TextureSize, 1.0 / TextureSize)).z * (floor(_1726 - _1730) + 0.5);
                float _1748 = (vec4(TextureSize, 1.0 / TextureSize)).z * (floor(_1726 + _1730) + 1.0);
                float _1754 = _1726 * RA_VARYING_1;
                vec3 _3365;
                _3365 = vec3(0.0);
                for (float _3363 = _1734; _3363 < _1748; )
                {
                    vec2 _1766 = vec2(_3363, _1647);
                    vec3 _1775 = textureLod(Texture, _1766, 0.0).xyz;
                    vec2 _1780 = vec2(_3363, _1651);
                    vec3 _1789 = textureLod(Texture, _1780, 0.0).xyz;
                    float _1796 = RA_VARYING_1 * (((vec4(TextureSize, 1.0 / TextureSize)).x * _3363) - 0.5);
                    float _1839 = _1754 - _1796;
                    float _1847 = _1754 - (_1796 + RA_VARYING_1);
                    vec3 _1858 = clamp(_1775 * abs(_1641), vec3(0.0), vec3(1.0));
                    vec3 _1874 = clamp(_1775 * _1839, vec3(-1.0), vec3(1.0)) * 3.1415927410125732421875;
                    vec3 _1880 = clamp(_1775 * _1847, vec3(-1.0), vec3(1.0)) * 3.1415927410125732421875;
                    vec3 _1914 = clamp(_1789 * abs(_1643), vec3(0.0), vec3(1.0));
                    vec3 _1930 = clamp(_1789 * _1839, vec3(-1.0), vec3(1.0)) * 3.1415927410125732421875;
                    vec3 _1936 = clamp(_1789 * _1847, vec3(-1.0), vec3(1.0)) * 3.1415927410125732421875;
                    _3365 = (_3365 + (((textureLod(Pass1Texture, _1766, 0.0).xyz * _1775) * (((_1858 * _1858) * ((_1858 * 2.0) - vec3(3.0))) + vec3(1.0))) * (((_1874 + sin(_1874)) - _1880) - sin(_1880)))) + (((textureLod(Pass1Texture, _1780, 0.0).xyz * _1789) * (((_1914 * _1914) * ((_1914 * 2.0) - vec3(3.0))) + vec3(1.0))) * (((_1930 + sin(_1930)) - _1936) - sin(_1936)));
                    _3363 += (vec4(TextureSize, 1.0 / TextureSize)).z;
                    continue;
                }
                float _1828 = (MaxSpotSize) * 0.15915493667125701904296875;
                vec3 _3372;
                _3372 = vec3(0.0);
                for (float _3370 = _1734; _3370 < _1748; )
                {
                    vec2 _2013 = vec2(_3370, _1686);
                    vec3 _2022 = textureLod(Texture, _2013, 0.0).xyz;
                    vec2 _2027 = vec2(_3370, _1690);
                    vec3 _2036 = textureLod(Texture, _2027, 0.0).xyz;
                    float _2043 = RA_VARYING_1 * (((vec4(TextureSize, 1.0 / TextureSize)).x * _3370) - 0.5);
                    float _2086 = _1754 - _2043;
                    float _2094 = _1754 - (_2043 + RA_VARYING_1);
                    vec3 _2105 = clamp(_2022 * abs(_1680), vec3(0.0), vec3(1.0));
                    vec3 _2121 = clamp(_2022 * _2086, vec3(-1.0), vec3(1.0)) * 3.1415927410125732421875;
                    vec3 _2127 = clamp(_2022 * _2094, vec3(-1.0), vec3(1.0)) * 3.1415927410125732421875;
                    vec3 _2161 = clamp(_2036 * abs(_1682), vec3(0.0), vec3(1.0));
                    vec3 _2177 = clamp(_2036 * _2086, vec3(-1.0), vec3(1.0)) * 3.1415927410125732421875;
                    vec3 _2183 = clamp(_2036 * _2094, vec3(-1.0), vec3(1.0)) * 3.1415927410125732421875;
                    _3372 = (_3372 + (((textureLod(Pass1Texture, _2013, 0.0).xyz * _2022) * (((_2105 * _2105) * ((_2105 * 2.0) - vec3(3.0))) + vec3(1.0))) * (((_2121 + sin(_2121)) - _2127) - sin(_2127)))) + (((textureLod(Pass1Texture, _2027, 0.0).xyz * _2036) * (((_2161 * _2161) * ((_2161 * 2.0) - vec3(3.0))) + vec3(1.0))) * (((_2177 + sin(_2177)) - _2183) - sin(_2183)));
                    _3370 += (vec4(TextureSize, 1.0 / TextureSize)).z;
                    continue;
                }
                _3399 = ((_3365 * _1828) + (_3372 * _1828)) * 0.5;
            }
            else
            {
                vec3 _3400;
                if ((((uint(FrameCount)) + uint((OddFieldFirst) == 1.0)) % 2u) == 0u)
                {
                    float _2203 = ceil(((0.5 * RA_VARYING_0.y) * (vec4(TextureSize, 1.0 / TextureSize)).y) + 0.25) * 2.0;
                    float _2204 = _2203 - 0.5;
                    float _2213 = 0.5 * (_2204 - (RA_VARYING_0.y * (vec4(TextureSize, 1.0 / TextureSize)).y));
                    float _2215 = _2213 - 1.0;
                    float _2219 = _2204 * (vec4(TextureSize, 1.0 / TextureSize)).w;
                    float _2223 = (_2203 - 2.5) * (vec4(TextureSize, 1.0 / TextureSize)).w;
                    float _2259 = RA_VARYING_0.x * (vec4(TextureSize, 1.0 / TextureSize)).x;
                    float _2263 = (MaxSpotSize) / RA_VARYING_1;
                    float _2267 = (vec4(TextureSize, 1.0 / TextureSize)).z * (floor(_2259 - _2263) + 0.5);
                    float _2281 = (vec4(TextureSize, 1.0 / TextureSize)).z * (floor(_2259 + _2263) + 1.0);
                    float _2287 = _2259 * RA_VARYING_1;
                    vec3 _3357;
                    _3357 = vec3(0.0);
                    for (float _3355 = _2267; _3355 < _2281; )
                    {
                        vec2 _2299 = vec2(_3355, _2219);
                        vec3 _2308 = textureLod(Texture, _2299, 0.0).xyz;
                        vec2 _2313 = vec2(_3355, _2223);
                        vec3 _2322 = textureLod(Texture, _2313, 0.0).xyz;
                        float _2329 = RA_VARYING_1 * (((vec4(TextureSize, 1.0 / TextureSize)).x * _3355) - 0.5);
                        float _2372 = _2287 - _2329;
                        float _2380 = _2287 - (_2329 + RA_VARYING_1);
                        vec3 _2391 = clamp(_2308 * abs(_2213), vec3(0.0), vec3(1.0));
                        vec3 _2407 = clamp(_2308 * _2372, vec3(-1.0), vec3(1.0)) * 3.1415927410125732421875;
                        vec3 _2413 = clamp(_2308 * _2380, vec3(-1.0), vec3(1.0)) * 3.1415927410125732421875;
                        vec3 _2447 = clamp(_2322 * abs(_2215), vec3(0.0), vec3(1.0));
                        vec3 _2463 = clamp(_2322 * _2372, vec3(-1.0), vec3(1.0)) * 3.1415927410125732421875;
                        vec3 _2469 = clamp(_2322 * _2380, vec3(-1.0), vec3(1.0)) * 3.1415927410125732421875;
                        _3357 = (_3357 + (((textureLod(Pass1Texture, _2299, 0.0).xyz * _2308) * (((_2391 * _2391) * ((_2391 * 2.0) - vec3(3.0))) + vec3(1.0))) * (((_2407 + sin(_2407)) - _2413) - sin(_2413)))) + (((textureLod(Pass1Texture, _2313, 0.0).xyz * _2322) * (((_2447 * _2447) * ((_2447 * 2.0) - vec3(3.0))) + vec3(1.0))) * (((_2463 + sin(_2463)) - _2469) - sin(_2469)));
                        _3355 += (vec4(TextureSize, 1.0 / TextureSize)).z;
                        continue;
                    }
                    _3400 = _3357 * ((MaxSpotSize) * 0.15915493667125701904296875);
                }
                else
                {
                    float _2489 = ceil(((0.5 * RA_VARYING_0.y) * (vec4(TextureSize, 1.0 / TextureSize)).y) - 0.25) * 2.0;
                    float _2490 = _2489 + 0.5;
                    float _2499 = 0.5 * (_2490 - (RA_VARYING_0.y * (vec4(TextureSize, 1.0 / TextureSize)).y));
                    float _2501 = _2499 - 1.0;
                    float _2505 = _2490 * (vec4(TextureSize, 1.0 / TextureSize)).w;
                    float _2509 = (_2489 + (-1.5)) * (vec4(TextureSize, 1.0 / TextureSize)).w;
                    float _2545 = RA_VARYING_0.x * (vec4(TextureSize, 1.0 / TextureSize)).x;
                    float _2549 = (MaxSpotSize) / RA_VARYING_1;
                    float _2553 = (vec4(TextureSize, 1.0 / TextureSize)).z * (floor(_2545 - _2549) + 0.5);
                    float _2567 = (vec4(TextureSize, 1.0 / TextureSize)).z * (floor(_2545 + _2549) + 1.0);
                    float _2573 = _2545 * RA_VARYING_1;
                    vec3 _3349;
                    _3349 = vec3(0.0);
                    for (float _3347 = _2553; _3347 < _2567; )
                    {
                        vec2 _2585 = vec2(_3347, _2505);
                        vec3 _2594 = textureLod(Texture, _2585, 0.0).xyz;
                        vec2 _2599 = vec2(_3347, _2509);
                        vec3 _2608 = textureLod(Texture, _2599, 0.0).xyz;
                        float _2615 = RA_VARYING_1 * (((vec4(TextureSize, 1.0 / TextureSize)).x * _3347) - 0.5);
                        float _2658 = _2573 - _2615;
                        float _2666 = _2573 - (_2615 + RA_VARYING_1);
                        vec3 _2677 = clamp(_2594 * abs(_2499), vec3(0.0), vec3(1.0));
                        vec3 _2693 = clamp(_2594 * _2658, vec3(-1.0), vec3(1.0)) * 3.1415927410125732421875;
                        vec3 _2699 = clamp(_2594 * _2666, vec3(-1.0), vec3(1.0)) * 3.1415927410125732421875;
                        vec3 _2733 = clamp(_2608 * abs(_2501), vec3(0.0), vec3(1.0));
                        vec3 _2749 = clamp(_2608 * _2658, vec3(-1.0), vec3(1.0)) * 3.1415927410125732421875;
                        vec3 _2755 = clamp(_2608 * _2666, vec3(-1.0), vec3(1.0)) * 3.1415927410125732421875;
                        _3349 = (_3349 + (((textureLod(Pass1Texture, _2585, 0.0).xyz * _2594) * (((_2677 * _2677) * ((_2677 * 2.0) - vec3(3.0))) + vec3(1.0))) * (((_2693 + sin(_2693)) - _2699) - sin(_2699)))) + (((textureLod(Pass1Texture, _2599, 0.0).xyz * _2608) * (((_2733 * _2733) * ((_2733 * 2.0) - vec3(3.0))) + vec3(1.0))) * (((_2749 + sin(_2749)) - _2755) - sin(_2755)));
                        _3347 += (vec4(TextureSize, 1.0 / TextureSize)).z;
                        continue;
                    }
                    _3400 = _3349 * ((MaxSpotSize) * 0.15915493667125701904296875);
                }
                _3399 = _3400;
            }
            _3398 = _3399;
        }
        _3397 = _3398;
    }
    vec3 _3429;
    if ((MaskType) == 1.0)
    {
        float _2779 = RA_VARYING_2.x * (vec4(OutputSize, 1.0 / OutputSize)).x;
        vec3 _3402;
        float _3411;
        if ((SubpixelPattern) == 0.0)
        {
            vec3 _3403;
            float _3412;
            if ((SubpixelMaskPattern) == 2.0)
            {
                _3412 = 2.0;
                _3403 = _95[int(mod(_2779, 2.0))];
            }
            else
            {
                vec3 _3404;
                float _3413;
                if ((SubpixelMaskPattern) == 3.0)
                {
                    _3413 = 3.0;
                    _3404 = _114[int(mod(_2779, 3.0))];
                }
                else
                {
                    vec3 _3405;
                    float _3414;
                    if ((SubpixelMaskPattern) == 4.0)
                    {
                        _3414 = 2.0;
                        _3405 = _132[int(mod(_2779, 4.0))];
                    }
                    else
                    {
                        bool _2811 = (SubpixelMaskPattern) == 5.0;
                        vec3 _3406;
                        if (_2811)
                        {
                            _3406 = _148[int(mod(_2779, 5.0))];
                        }
                        else
                        {
                            _3406 = vec3(1.0);
                        }
                        _3414 = _2811 ? 2.5 : 1.0;
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
            vec3 _3407;
            float _3416;
            if ((SubpixelMaskPattern) == 2.0)
            {
                _3416 = 2.0;
                _3407 = _95[int(mod(_2779, 2.0))];
            }
            else
            {
                vec3 _3408;
                float _3417;
                if ((SubpixelMaskPattern) == 3.0)
                {
                    _3417 = 3.0;
                    _3408 = _172[int(mod(_2779, 3.0))];
                }
                else
                {
                    vec3 _3409;
                    float _3418;
                    if ((SubpixelMaskPattern) == 4.0)
                    {
                        _3418 = 2.0;
                        _3409 = _184[int(mod(_2779, 4.0))];
                    }
                    else
                    {
                        bool _2851 = (SubpixelMaskPattern) == 5.0;
                        vec3 _3410;
                        if (_2851)
                        {
                            _3410 = _196[int(mod(_2779, 5.0))];
                        }
                        else
                        {
                            _3410 = vec3(1.0);
                        }
                        _3418 = _2851 ? 2.5 : 1.0;
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
        vec3 _2878 = vec3(1.0 - _3411);
        _3429 = ((clamp((_3397 - vec3(1.0)) / _2878, vec3(0.0), _3397) * _3411) * vec4(_3402, _3411).xyz) + clamp((vec3(1.0) - (_3397 * _3411)) / _2878, vec3(0.0), _3397);
    }
    else
    {
        vec3 _3430;
        if ((MaskType) == 2.0)
        {
            float _2924 = 3.0 * (DynamicMaskTriads);
            float _2927 = _2924 * (vec4(OutputSize, 1.0 / OutputSize)).z;
            float _2932 = _2924 * RA_VARYING_2.x;
            vec3 _3394;
            if (_2927 < 0.5)
            {
                float _2938 = round(_2932);
                float _2942 = clamp((_2932 - _2938) / _2927, -1.0, 1.0);
                int _2948 = int(mod(_2938 - 1.0, 3.0) + 0.001000000047497451305389404296875);
                _3394 = ((_172[_2948] + _172[_2948].zxy) + ((_172[_2948].zxy - _172[_2948]) * (_2942 + (sin(3.1415927410125732421875 * _2942) * 0.3183098733425140380859375)))) * 0.5;
            }
            else
            {
                vec3 _3395;
                if (_2927 < 1.0)
                {
                    float _2975 = floor(_2932);
                    float _2980 = clamp((_2932 - _2975) / _2927, -1.0, 1.0);
                    float _2988 = clamp((_2932 - (_2975 + 1.0)) / _2927, -1.0, 1.0);
                    int _2994 = int(mod(_2975 - 1.0, 3.0) + 0.001000000047497451305389404296875);
                    _3395 = (((_172[_2994] + _172[_2994].yzx) + ((_172[_2994].zxy - _172[_2994]) * (_2980 + (sin(3.1415927410125732421875 * _2980) * 0.3183098733425140380859375)))) + ((_172[_2994].yzx - _172[_2994].zxy) * (_2988 + (sin(3.1415927410125732421875 * _2988) * 0.3183098733425140380859375)))) * 0.5;
                }
                else
                {
                    float _3031 = round(_2932);
                    float _3036 = clamp((_2932 - (_3031 - 1.0)) / _2927, -1.0, 1.0);
                    float _3044 = clamp((_2932 - _3031) / _2927, -1.0, 1.0);
                    float _3052 = clamp((_2932 - (_3031 + 1.0)) / _2927, -1.0, 1.0);
                    int _3058 = int(mod(_3031 - 2.0, 3.0) + 0.001000000047497451305389404296875);
                    _3395 = ((((_172[_3058] + _172[_3058].xyz) + ((_172[_3058].zxy - _172[_3058]) * (_3036 + (sin(3.1415927410125732421875 * _3036) * 0.3183098733425140380859375)))) + ((_172[_3058].yzx - _172[_3058].zxy) * (_3044 + (sin(3.1415927410125732421875 * _3044) * 0.3183098733425140380859375)))) + ((_172[_3058].xyz - _172[_3058].yzx) * (_3052 + (sin(3.1415927410125732421875 * _3052) * 0.3183098733425140380859375)))) * 0.5;
                }
                _3394 = _3395;
            }
            _3430 = ((clamp((_3397 - vec3(1.0)) * vec3(-0.5), vec3(0.0), _3397) * 3.0) * vec4(_3394, 3.0).xyz) + clamp((vec3(1.0) - (_3397 * 3.0)) * vec3(-0.5), vec3(0.0), _3397);
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


#endif
