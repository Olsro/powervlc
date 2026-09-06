// Generated from crt/shaders/crt-beans/scanlines_fast_vertical.slang. See slang/upstream for licence/source.
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
#pragma parameter OddFieldFirst "Interlacing (0/1: bob/phase, 2: weave, 3: VGA, 4: off)" 0.0 0.0 4.0 1.0
#ifdef VERTEX

uniform mat4 MVPMatrix;
uniform float OverscanHorizontal;
uniform float OverscanVertical;
struct UBO
{
    mat4 MVP;
};



struct Push
{
    float OverscanHorizontal;
    float OverscanVertical;
};



in vec4 VertexCoord;
out vec2 RA_VARYING_0;
in vec2 TexCoord;
out vec2 RA_VARYING_1;

void main()
{
    gl_Position = (MVPMatrix) * VertexCoord;
    RA_VARYING_0 = ((vec2(1.0) - vec2((OverscanHorizontal), (OverscanVertical))) * (TexCoord - vec2(0.5))) + vec2(0.5);
    RA_VARYING_1 = TexCoord;
}


#endif
#ifdef FRAGMENT

uniform float DynamicMaskTriads;
uniform int FrameCount;
uniform float MaskType;
uniform float MaxSpotSize;
uniform float MinSpotSize;
uniform float OddFieldFirst;
uniform float OutputGamma;
uniform vec2 OutputSize;
uniform float SubpixelMaskPattern;
uniform float SubpixelPattern;
uniform vec2 TextureSize;
const vec3 _93[2] = vec3[](vec3(1.0, 0.0, 1.0), vec3(0.0, 1.0, 0.0));
const vec3 _112[3] = vec3[](vec3(0.0, 0.0, 1.0), vec3(0.0, 1.0, 0.0), vec3(1.0, 0.0, 0.0));
const vec3 _130[4] = vec3[](vec3(1.0, 0.0, 0.0), vec3(1.0, 1.0, 0.0), vec3(0.0, 1.0, 1.0), vec3(0.0, 0.0, 1.0));
const vec3 _146[5] = vec3[](vec3(1.0, 0.0, 0.0), vec3(1.0, 0.0, 1.0), vec3(0.0, 0.0, 1.0), vec3(0.0, 1.0, 0.0), vec3(0.0, 1.0, 0.0));
const vec3 _170[3] = vec3[](vec3(1.0, 0.0, 0.0), vec3(0.0, 1.0, 0.0), vec3(0.0, 0.0, 1.0));
const vec3 _182[4] = vec3[](vec3(0.0, 0.0, 1.0), vec3(0.0, 1.0, 1.0), vec3(1.0, 1.0, 0.0), vec3(1.0, 0.0, 0.0));
const vec3 _194[5] = vec3[](vec3(0.0, 0.0, 1.0), vec3(1.0, 0.0, 1.0), vec3(1.0, 0.0, 0.0), vec3(0.0, 1.0, 0.0), vec3(0.0, 1.0, 0.0));

struct Push
{
    vec4 SourceSize;
    vec4 OutputSize;
    uint FrameCount;
    float MaxSpotSize;
    float MinSpotSize;
    float OddFieldFirst;
    float MaskType;
    float SubpixelMaskPattern;
    float SubpixelPattern;
    float DynamicMaskTriads;
    float OutputGamma;
};



uniform sampler2D Texture;

in vec2 RA_VARYING_0;
out vec4 FragColor;

void main()
{
    bool _792 = (OddFieldFirst) == 3.0;
    bool _799;
    if (_792)
    {
        _799 = (vec4(TextureSize, 1.0 / TextureSize)).y < 350.0;
    }
    else
    {
        _799 = _792;
    }
    vec3 _2556;
    if (_799)
    {
        float _1026 = RA_VARYING_0.y * (vec4(TextureSize, 1.0 / TextureSize)).y;
        float _1027 = 2.0 * _1026;
        float _1036 = (ceil(_1027 - 0.5) + 0.5) - _1027;
        vec3 _1080 = textureLod(Texture, vec2(RA_VARYING_0.x, (ceil(_1026 + 0.25) - 0.5) * (vec4(TextureSize, 1.0 / TextureSize)).w), 0.0).xyz;
        float _1085 = (MinSpotSize) * (MaxSpotSize);
        float _1095 = _1085 - (MaxSpotSize);
        vec3 _1097 = vec3(_1085);
        vec3 _1100 = vec3(1.0) / (_1097 - (sqrt(_1080) * _1095));
        vec3 _1108 = clamp(_1100 * abs(_1036), vec3(0.0), vec3(1.0));
        vec3 _1129 = textureLod(Texture, vec2(RA_VARYING_0.x, (ceil(_1026 - 0.25) - 0.5) * (vec4(TextureSize, 1.0 / TextureSize)).w), 0.0).xyz;
        vec3 _1149 = vec3(1.0) / (_1097 - (sqrt(_1129) * _1095));
        vec3 _1157 = clamp(_1149 * abs(_1036 - 1.0), vec3(0.0), vec3(1.0));
        _2556 = (((_1080 * _1100) * (((_1108 * _1108) * ((_1108 * 2.0) - vec3(3.0))) + vec3(1.0))) + ((_1129 * _1149) * (((_1157 * _1157) * ((_1157 * 2.0) - vec3(3.0))) + vec3(1.0)))) * (MaxSpotSize);
    }
    else
    {
        bool _823 = (OddFieldFirst) == 4.0;
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
            _838 = (vec4(TextureSize, 1.0 / TextureSize)).y <= 300.0;
        }
        else
        {
            _838 = _830;
        }
        vec3 _2557;
        if (_838)
        {
            float _1187 = RA_VARYING_0.y * (vec4(TextureSize, 1.0 / TextureSize)).y;
            float _1188 = round(_1187);
            float _1189 = _1188 + 0.5;
            float _1197 = _1189 - _1187;
            vec3 _1229 = textureLod(Texture, vec2(RA_VARYING_0.x, _1189 * (vec4(TextureSize, 1.0 / TextureSize)).w), 0.0).xyz;
            float _1234 = (MinSpotSize) * (MaxSpotSize);
            float _1244 = _1234 - (MaxSpotSize);
            vec3 _1246 = vec3(_1234);
            vec3 _1249 = vec3(1.0) / (_1246 - (sqrt(_1229) * _1244));
            vec3 _1257 = clamp(_1249 * abs(_1197), vec3(0.0), vec3(1.0));
            vec3 _1278 = textureLod(Texture, vec2(RA_VARYING_0.x, (_1188 + (-0.5)) * (vec4(TextureSize, 1.0 / TextureSize)).w), 0.0).xyz;
            vec3 _1298 = vec3(1.0) / (_1246 - (sqrt(_1278) * _1244));
            vec3 _1306 = clamp(_1298 * abs(_1197 - 1.0), vec3(0.0), vec3(1.0));
            _2557 = (((_1229 * _1249) * (((_1257 * _1257) * ((_1257 * 2.0) - vec3(3.0))) + vec3(1.0))) + ((_1278 * _1298) * (((_1306 * _1306) * ((_1306 * 2.0) - vec3(3.0))) + vec3(1.0)))) * (MaxSpotSize);
        }
        else
        {
            vec3 _2558;
            if ((OddFieldFirst) == 2.0)
            {
                float _1337 = (0.5 * RA_VARYING_0.y) * (vec4(TextureSize, 1.0 / TextureSize)).y;
                float _1340 = ceil(_1337 - 0.25) * 2.0;
                float _1341 = _1340 + 0.5;
                float _1348 = RA_VARYING_0.y * (vec4(TextureSize, 1.0 / TextureSize)).y;
                float _1350 = 0.5 * (_1341 - _1348);
                float _1379 = ceil(_1337 + 0.25) * 2.0;
                float _1380 = _1379 - 0.5;
                float _1389 = 0.5 * (_1380 - _1348);
                vec3 _1421 = textureLod(Texture, vec2(RA_VARYING_0.x, _1341 * (vec4(TextureSize, 1.0 / TextureSize)).w), 0.0).xyz;
                float _1426 = (MinSpotSize) * (MaxSpotSize);
                float _1436 = _1426 - (MaxSpotSize);
                vec3 _1438 = vec3(_1426);
                vec3 _1441 = vec3(1.0) / (_1438 - (sqrt(_1421) * _1436));
                vec3 _1449 = clamp(_1441 * abs(_1350), vec3(0.0), vec3(1.0));
                vec3 _1470 = textureLod(Texture, vec2(RA_VARYING_0.x, (_1340 + (-1.5)) * (vec4(TextureSize, 1.0 / TextureSize)).w), 0.0).xyz;
                vec3 _1490 = vec3(1.0) / (_1438 - (sqrt(_1470) * _1436));
                vec3 _1498 = clamp(_1490 * abs(_1350 - 1.0), vec3(0.0), vec3(1.0));
                vec3 _1535 = textureLod(Texture, vec2(RA_VARYING_0.x, _1380 * (vec4(TextureSize, 1.0 / TextureSize)).w), 0.0).xyz;
                vec3 _1555 = vec3(1.0) / (_1438 - (sqrt(_1535) * _1436));
                vec3 _1563 = clamp(_1555 * abs(_1389), vec3(0.0), vec3(1.0));
                vec3 _1584 = textureLod(Texture, vec2(RA_VARYING_0.x, (_1379 - 2.5) * (vec4(TextureSize, 1.0 / TextureSize)).w), 0.0).xyz;
                vec3 _1604 = vec3(1.0) / (_1438 - (sqrt(_1584) * _1436));
                vec3 _1612 = clamp(_1604 * abs(_1389 - 1.0), vec3(0.0), vec3(1.0));
                _2558 = (((((_1421 * _1441) * (((_1449 * _1449) * ((_1449 * 2.0) - vec3(3.0))) + vec3(1.0))) + ((_1470 * _1490) * (((_1498 * _1498) * ((_1498 * 2.0) - vec3(3.0))) + vec3(1.0)))) * (MaxSpotSize)) + ((((_1535 * _1555) * (((_1563 * _1563) * ((_1563 * 2.0) - vec3(3.0))) + vec3(1.0))) + ((_1584 * _1604) * (((_1612 * _1612) * ((_1612 * 2.0) - vec3(3.0))) + vec3(1.0)))) * (MaxSpotSize))) * 0.5;
            }
            else
            {
                vec3 _2559;
                if ((((uint(FrameCount)) + uint((OddFieldFirst) == 1.0)) % 2u) == 0u)
                {
                    float _1646 = ceil(((0.5 * RA_VARYING_0.y) * (vec4(TextureSize, 1.0 / TextureSize)).y) + 0.25) * 2.0;
                    float _1647 = _1646 - 0.5;
                    float _1656 = 0.5 * (_1647 - (RA_VARYING_0.y * (vec4(TextureSize, 1.0 / TextureSize)).y));
                    vec3 _1688 = textureLod(Texture, vec2(RA_VARYING_0.x, _1647 * (vec4(TextureSize, 1.0 / TextureSize)).w), 0.0).xyz;
                    float _1693 = (MinSpotSize) * (MaxSpotSize);
                    float _1703 = _1693 - (MaxSpotSize);
                    vec3 _1705 = vec3(_1693);
                    vec3 _1708 = vec3(1.0) / (_1705 - (sqrt(_1688) * _1703));
                    vec3 _1716 = clamp(_1708 * abs(_1656), vec3(0.0), vec3(1.0));
                    vec3 _1737 = textureLod(Texture, vec2(RA_VARYING_0.x, (_1646 - 2.5) * (vec4(TextureSize, 1.0 / TextureSize)).w), 0.0).xyz;
                    vec3 _1757 = vec3(1.0) / (_1705 - (sqrt(_1737) * _1703));
                    vec3 _1765 = clamp(_1757 * abs(_1656 - 1.0), vec3(0.0), vec3(1.0));
                    _2559 = (((_1688 * _1708) * (((_1716 * _1716) * ((_1716 * 2.0) - vec3(3.0))) + vec3(1.0))) + ((_1737 * _1757) * (((_1765 * _1765) * ((_1765 * 2.0) - vec3(3.0))) + vec3(1.0)))) * (MaxSpotSize);
                }
                else
                {
                    float _1799 = ceil(((0.5 * RA_VARYING_0.y) * (vec4(TextureSize, 1.0 / TextureSize)).y) - 0.25) * 2.0;
                    float _1800 = _1799 + 0.5;
                    float _1809 = 0.5 * (_1800 - (RA_VARYING_0.y * (vec4(TextureSize, 1.0 / TextureSize)).y));
                    vec3 _1841 = textureLod(Texture, vec2(RA_VARYING_0.x, _1800 * (vec4(TextureSize, 1.0 / TextureSize)).w), 0.0).xyz;
                    float _1846 = (MinSpotSize) * (MaxSpotSize);
                    float _1856 = _1846 - (MaxSpotSize);
                    vec3 _1858 = vec3(_1846);
                    vec3 _1861 = vec3(1.0) / (_1858 - (sqrt(_1841) * _1856));
                    vec3 _1869 = clamp(_1861 * abs(_1809), vec3(0.0), vec3(1.0));
                    vec3 _1890 = textureLod(Texture, vec2(RA_VARYING_0.x, (_1799 + (-1.5)) * (vec4(TextureSize, 1.0 / TextureSize)).w), 0.0).xyz;
                    vec3 _1910 = vec3(1.0) / (_1858 - (sqrt(_1890) * _1856));
                    vec3 _1918 = clamp(_1910 * abs(_1809 - 1.0), vec3(0.0), vec3(1.0));
                    _2559 = (((_1841 * _1861) * (((_1869 * _1869) * ((_1869 * 2.0) - vec3(3.0))) + vec3(1.0))) + ((_1890 * _1910) * (((_1918 * _1918) * ((_1918 * 2.0) - vec3(3.0))) + vec3(1.0)))) * (MaxSpotSize);
                }
                _2558 = _2559;
            }
            _2557 = _2558;
        }
        _2556 = _2557;
    }
    vec3 _2588;
    if ((MaskType) == 1.0)
    {
        float _1956 = RA_VARYING_0.x * (vec4(OutputSize, 1.0 / OutputSize)).x;
        vec3 _2561;
        float _2570;
        if ((SubpixelPattern) == 0.0)
        {
            vec3 _2562;
            float _2571;
            if ((SubpixelMaskPattern) == 2.0)
            {
                _2571 = 2.0;
                _2562 = _93[int(mod(_1956, 2.0))];
            }
            else
            {
                vec3 _2563;
                float _2572;
                if ((SubpixelMaskPattern) == 3.0)
                {
                    _2572 = 3.0;
                    _2563 = _112[int(mod(_1956, 3.0))];
                }
                else
                {
                    vec3 _2564;
                    float _2573;
                    if ((SubpixelMaskPattern) == 4.0)
                    {
                        _2573 = 2.0;
                        _2564 = _130[int(mod(_1956, 4.0))];
                    }
                    else
                    {
                        bool _1988 = (SubpixelMaskPattern) == 5.0;
                        vec3 _2565;
                        if (_1988)
                        {
                            _2565 = _146[int(mod(_1956, 5.0))];
                        }
                        else
                        {
                            _2565 = vec3(1.0);
                        }
                        _2573 = _1988 ? 2.5 : 1.0;
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
            vec3 _2566;
            float _2575;
            if ((SubpixelMaskPattern) == 2.0)
            {
                _2575 = 2.0;
                _2566 = _93[int(mod(_1956, 2.0))];
            }
            else
            {
                vec3 _2567;
                float _2576;
                if ((SubpixelMaskPattern) == 3.0)
                {
                    _2576 = 3.0;
                    _2567 = _170[int(mod(_1956, 3.0))];
                }
                else
                {
                    vec3 _2568;
                    float _2577;
                    if ((SubpixelMaskPattern) == 4.0)
                    {
                        _2577 = 2.0;
                        _2568 = _182[int(mod(_1956, 4.0))];
                    }
                    else
                    {
                        bool _2028 = (SubpixelMaskPattern) == 5.0;
                        vec3 _2569;
                        if (_2028)
                        {
                            _2569 = _194[int(mod(_1956, 5.0))];
                        }
                        else
                        {
                            _2569 = vec3(1.0);
                        }
                        _2577 = _2028 ? 2.5 : 1.0;
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
        vec3 _2055 = vec3(1.0 - _2570);
        _2588 = ((clamp((_2556 - vec3(1.0)) / _2055, vec3(0.0), _2556) * _2570) * vec4(_2561, _2570).xyz) + clamp((vec3(1.0) - (_2556 * _2570)) / _2055, vec3(0.0), _2556);
    }
    else
    {
        vec3 _2589;
        if ((MaskType) == 2.0)
        {
            float _2101 = 3.0 * (DynamicMaskTriads);
            float _2104 = _2101 * (vec4(OutputSize, 1.0 / OutputSize)).z;
            float _2109 = _2101 * RA_VARYING_0.x;
            vec3 _2553;
            if (_2104 < 0.5)
            {
                float _2115 = round(_2109);
                float _2119 = clamp((_2109 - _2115) / _2104, -1.0, 1.0);
                int _2125 = int(mod(_2115 - 1.0, 3.0) + 0.001000000047497451305389404296875);
                _2553 = ((_170[_2125] + _170[_2125].zxy) + ((_170[_2125].zxy - _170[_2125]) * (_2119 + (sin(3.1415927410125732421875 * _2119) * 0.3183098733425140380859375)))) * 0.5;
            }
            else
            {
                vec3 _2554;
                if (_2104 < 1.0)
                {
                    float _2152 = floor(_2109);
                    float _2157 = clamp((_2109 - _2152) / _2104, -1.0, 1.0);
                    float _2165 = clamp((_2109 - (_2152 + 1.0)) / _2104, -1.0, 1.0);
                    int _2171 = int(mod(_2152 - 1.0, 3.0) + 0.001000000047497451305389404296875);
                    _2554 = (((_170[_2171] + _170[_2171].yzx) + ((_170[_2171].zxy - _170[_2171]) * (_2157 + (sin(3.1415927410125732421875 * _2157) * 0.3183098733425140380859375)))) + ((_170[_2171].yzx - _170[_2171].zxy) * (_2165 + (sin(3.1415927410125732421875 * _2165) * 0.3183098733425140380859375)))) * 0.5;
                }
                else
                {
                    float _2208 = round(_2109);
                    float _2213 = clamp((_2109 - (_2208 - 1.0)) / _2104, -1.0, 1.0);
                    float _2221 = clamp((_2109 - _2208) / _2104, -1.0, 1.0);
                    float _2229 = clamp((_2109 - (_2208 + 1.0)) / _2104, -1.0, 1.0);
                    int _2235 = int(mod(_2208 - 2.0, 3.0) + 0.001000000047497451305389404296875);
                    _2554 = ((((_170[_2235] + _170[_2235].xyz) + ((_170[_2235].zxy - _170[_2235]) * (_2213 + (sin(3.1415927410125732421875 * _2213) * 0.3183098733425140380859375)))) + ((_170[_2235].yzx - _170[_2235].zxy) * (_2221 + (sin(3.1415927410125732421875 * _2221) * 0.3183098733425140380859375)))) + ((_170[_2235].xyz - _170[_2235].yzx) * (_2229 + (sin(3.1415927410125732421875 * _2229) * 0.3183098733425140380859375)))) * 0.5;
                }
                _2553 = _2554;
            }
            _2589 = ((clamp((_2556 - vec3(1.0)) * vec3(-0.5), vec3(0.0), _2556) * 3.0) * vec4(_2553, 3.0).xyz) + clamp((vec3(1.0) - (_2556 * 3.0)) * vec3(-0.5), vec3(0.0), _2556);
        }
        else
        {
            _2589 = _2556;
        }
        _2588 = _2589;
    }
    vec3 _2590;
    if ((OutputGamma) < 0.5)
    {
        vec3 _2328 = clamp(_2588, vec3(0.0), vec3(1.0));
        bvec3 _2330 = lessThan(_2328, vec3(0.003130800090730190277099609375));
        vec3 _2334 = (vec3(1.05499994754791259765625) * pow(_2328, vec3(0.4166666567325592041015625))) - vec3(0.054999999701976776123046875);
        vec3 _2336 = _2328 * vec3(12.9200000762939453125);
        _2590 = vec3(_2330.x ? _2336.x : _2334.x, _2330.y ? _2336.y : _2334.y, _2330.z ? _2336.z : _2334.z);
    }
    else
    {
        _2590 = pow(clamp(_2588, vec3(0.0), vec3(1.0)), vec3(0.4545454680919647216796875));
    }
    FragColor.x = _2590.x;
    FragColor.y = _2590.y;
    FragColor.z = _2590.z;
}


#endif
