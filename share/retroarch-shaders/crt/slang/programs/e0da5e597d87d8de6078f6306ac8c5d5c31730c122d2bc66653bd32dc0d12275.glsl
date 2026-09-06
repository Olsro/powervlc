// Generated from crt/shaders/crt-beans/scanlines_cubic.slang. See slang/upstream for licence/source.
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
#pragma parameter YIQ "Composite (0: RGB, 1: YIQ/composite)" 0.0 0.0 1.0 1.0
#pragma parameter Cutoff "RGB/Y bandwidth (MHz)" 4.0 0.6 6.0 0.2
#pragma parameter ICutoff "I bandwidth (MHz)" 0.6 0.6 6.0 0.2
#pragma parameter QCutoff "Q bandwidth (MHz)" 0.6 0.6 6.0 0.2
#pragma parameter OddFieldFirst "Interlacing (0/1: bob/phase, 2: weave)" 0.0 0.0 2.0 1.0
#ifdef VERTEX

uniform mat4 MVPMatrix;
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
    float _96;
    if ((vec4(TextureSize, 1.0 / TextureSize)).y > 300.0)
    {
        _96 = 0.5 * RA_VARYING_1;
    }
    else
    {
        _96 = RA_VARYING_1;
    }
    RA_VARYING_1 = _96;
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
const vec3 _89[2] = vec3[](vec3(1.0, 0.0, 1.0), vec3(0.0, 1.0, 0.0));
const vec3 _108[3] = vec3[](vec3(0.0, 0.0, 1.0), vec3(0.0, 1.0, 0.0), vec3(1.0, 0.0, 0.0));
const vec3 _126[4] = vec3[](vec3(1.0, 0.0, 0.0), vec3(1.0, 1.0, 0.0), vec3(0.0, 1.0, 1.0), vec3(0.0, 0.0, 1.0));
const vec3 _142[5] = vec3[](vec3(1.0, 0.0, 0.0), vec3(1.0, 0.0, 1.0), vec3(0.0, 0.0, 1.0), vec3(0.0, 1.0, 0.0), vec3(0.0, 1.0, 0.0));
const vec3 _166[3] = vec3[](vec3(1.0, 0.0, 0.0), vec3(0.0, 1.0, 0.0), vec3(0.0, 0.0, 1.0));
const vec3 _178[4] = vec3[](vec3(0.0, 0.0, 1.0), vec3(0.0, 1.0, 1.0), vec3(1.0, 1.0, 0.0), vec3(1.0, 0.0, 0.0));
const vec3 _190[5] = vec3[](vec3(0.0, 0.0, 1.0), vec3(1.0, 0.0, 1.0), vec3(1.0, 0.0, 0.0), vec3(0.0, 1.0, 0.0), vec3(0.0, 1.0, 0.0));

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



uniform sampler2D Pass2Texture;
uniform sampler2D Texture;

flat in float RA_VARYING_1;
in vec2 RA_VARYING_0;
in vec2 RA_VARYING_2;
out vec4 FragColor;

void main()
{
    vec3 _2752;
    if ((vec4(TextureSize, 1.0 / TextureSize)).y <= 300.0)
    {
        float _931 = RA_VARYING_0.y * (vec4(TextureSize, 1.0 / TextureSize)).y;
        float _932 = round(_931);
        float _933 = _932 + 0.5;
        float _941 = _933 - _931;
        float _943 = _941 - 1.0;
        float _947 = _933 * (vec4(TextureSize, 1.0 / TextureSize)).w;
        float _951 = (_932 + (-0.5)) * (vec4(TextureSize, 1.0 / TextureSize)).w;
        float _981 = RA_VARYING_0.x * (vec4(TextureSize, 1.0 / TextureSize)).x;
        float _985 = (MaxSpotSize) / RA_VARYING_1;
        float _989 = (vec4(TextureSize, 1.0 / TextureSize)).z * (round(_981 - _985) + 0.5);
        float _1002 = (vec4(TextureSize, 1.0 / TextureSize)).z * round(_981 + _985);
        float _1010 = (RA_VARYING_1 * (vec4(TextureSize, 1.0 / TextureSize)).x) * (_989 - RA_VARYING_0.x);
        vec3 _2748;
        _2748 = vec3(0.0);
        for (float _2746 = _989, _2787 = _1010; _2746 < _1002; )
        {
            vec2 _1022 = vec2(_2746, _947);
            vec3 _1031 = textureLod(Texture, _1022, 0.0).xyz;
            vec2 _1036 = vec2(_2746, _951);
            vec3 _1045 = textureLod(Texture, _1036, 0.0).xyz;
            float _1082 = abs(_2787);
            vec3 _1087 = clamp(_1031 * _1082, vec3(0.0), vec3(1.0));
            vec3 _1094 = clamp(_1031 * abs(_941), vec3(0.0), vec3(1.0));
            vec3 _1132 = clamp(_1045 * _1082, vec3(0.0), vec3(1.0));
            vec3 _1139 = clamp(_1045 * abs(_943), vec3(0.0), vec3(1.0));
            _2787 += RA_VARYING_1;
            _2748 = (_2748 + ((((textureLod(Pass2Texture, _1022, 0.0).xyz * _1031) * _1031) * (((_1087 * _1087) * ((_1087 * 2.0) - vec3(3.0))) + vec3(1.0))) * (((_1094 * _1094) * ((_1094 * 2.0) - vec3(3.0))) + vec3(1.0)))) + ((((textureLod(Pass2Texture, _1036, 0.0).xyz * _1045) * _1045) * (((_1132 * _1132) * ((_1132 * 2.0) - vec3(3.0))) + vec3(1.0))) * (((_1139 * _1139) * ((_1139 * 2.0) - vec3(3.0))) + vec3(1.0)));
            _2746 += (vec4(TextureSize, 1.0 / TextureSize)).z;
            continue;
        }
        _2752 = _2748 * (RA_VARYING_1 * (MaxSpotSize));
    }
    else
    {
        vec3 _2753;
        if ((OddFieldFirst) == 2.0)
        {
            float _1177 = (0.5 * RA_VARYING_0.y) * (vec4(TextureSize, 1.0 / TextureSize)).y;
            float _1180 = ceil(_1177 - 0.25) * 2.0;
            float _1181 = _1180 + 0.5;
            float _1188 = RA_VARYING_0.y * (vec4(TextureSize, 1.0 / TextureSize)).y;
            float _1190 = 0.5 * (_1181 - _1188);
            float _1192 = _1190 - 1.0;
            float _1196 = _1181 * (vec4(TextureSize, 1.0 / TextureSize)).w;
            float _1200 = (_1180 + (-1.5)) * (vec4(TextureSize, 1.0 / TextureSize)).w;
            float _1230 = RA_VARYING_0.x * (vec4(TextureSize, 1.0 / TextureSize)).x;
            float _1234 = (MaxSpotSize) / RA_VARYING_1;
            float _1238 = (vec4(TextureSize, 1.0 / TextureSize)).z * (round(_1230 - _1234) + 0.5);
            float _1251 = (vec4(TextureSize, 1.0 / TextureSize)).z * round(_1230 + _1234);
            float _1259 = (RA_VARYING_1 * (vec4(TextureSize, 1.0 / TextureSize)).x) * (_1238 - RA_VARYING_0.x);
            vec3 _2732;
            _2732 = vec3(0.0);
            for (float _2730 = _1238, _2743 = _1259; _2730 < _1251; )
            {
                vec2 _1271 = vec2(_2730, _1196);
                vec3 _1280 = textureLod(Texture, _1271, 0.0).xyz;
                vec2 _1285 = vec2(_2730, _1200);
                vec3 _1294 = textureLod(Texture, _1285, 0.0).xyz;
                float _1331 = abs(_2743);
                vec3 _1336 = clamp(_1280 * _1331, vec3(0.0), vec3(1.0));
                vec3 _1343 = clamp(_1280 * abs(_1190), vec3(0.0), vec3(1.0));
                vec3 _1381 = clamp(_1294 * _1331, vec3(0.0), vec3(1.0));
                vec3 _1388 = clamp(_1294 * abs(_1192), vec3(0.0), vec3(1.0));
                _2743 += RA_VARYING_1;
                _2732 = (_2732 + ((((textureLod(Pass2Texture, _1271, 0.0).xyz * _1280) * _1280) * (((_1336 * _1336) * ((_1336 * 2.0) - vec3(3.0))) + vec3(1.0))) * (((_1343 * _1343) * ((_1343 * 2.0) - vec3(3.0))) + vec3(1.0)))) + ((((textureLod(Pass2Texture, _1285, 0.0).xyz * _1294) * _1294) * (((_1381 * _1381) * ((_1381 * 2.0) - vec3(3.0))) + vec3(1.0))) * (((_1388 * _1388) * ((_1388 * 2.0) - vec3(3.0))) + vec3(1.0)));
                _2730 += (vec4(TextureSize, 1.0 / TextureSize)).z;
                continue;
            }
            float _1323 = RA_VARYING_1 * (MaxSpotSize);
            float _1429 = ceil(_1177 + 0.25) * 2.0;
            float _1430 = _1429 - 0.5;
            float _1439 = 0.5 * (_1430 - _1188);
            float _1441 = _1439 - 1.0;
            float _1445 = _1430 * (vec4(TextureSize, 1.0 / TextureSize)).w;
            float _1449 = (_1429 - 2.5) * (vec4(TextureSize, 1.0 / TextureSize)).w;
            vec3 _2735;
            _2735 = vec3(0.0);
            for (float _2733 = _1238, _2738 = _1259; _2733 < _1251; )
            {
                vec2 _1520 = vec2(_2733, _1445);
                vec3 _1529 = textureLod(Texture, _1520, 0.0).xyz;
                vec2 _1534 = vec2(_2733, _1449);
                vec3 _1543 = textureLod(Texture, _1534, 0.0).xyz;
                float _1580 = abs(_2738);
                vec3 _1585 = clamp(_1529 * _1580, vec3(0.0), vec3(1.0));
                vec3 _1592 = clamp(_1529 * abs(_1439), vec3(0.0), vec3(1.0));
                vec3 _1630 = clamp(_1543 * _1580, vec3(0.0), vec3(1.0));
                vec3 _1637 = clamp(_1543 * abs(_1441), vec3(0.0), vec3(1.0));
                _2738 += RA_VARYING_1;
                _2735 = (_2735 + ((((textureLod(Pass2Texture, _1520, 0.0).xyz * _1529) * _1529) * (((_1585 * _1585) * ((_1585 * 2.0) - vec3(3.0))) + vec3(1.0))) * (((_1592 * _1592) * ((_1592 * 2.0) - vec3(3.0))) + vec3(1.0)))) + ((((textureLod(Pass2Texture, _1534, 0.0).xyz * _1543) * _1543) * (((_1630 * _1630) * ((_1630 * 2.0) - vec3(3.0))) + vec3(1.0))) * (((_1637 * _1637) * ((_1637 * 2.0) - vec3(3.0))) + vec3(1.0)));
                _2733 += (vec4(TextureSize, 1.0 / TextureSize)).z;
                continue;
            }
            _2753 = ((_2732 * _1323) + (_2735 * _1323)) * 0.5;
        }
        else
        {
            vec3 _2754;
            if ((((uint(FrameCount)) + uint((OddFieldFirst) == 1.0)) % 2u) == 0u)
            {
                float _1678 = ceil(((0.5 * RA_VARYING_0.y) * (vec4(TextureSize, 1.0 / TextureSize)).y) + 0.25) * 2.0;
                float _1679 = _1678 - 0.5;
                float _1688 = 0.5 * (_1679 - (RA_VARYING_0.y * (vec4(TextureSize, 1.0 / TextureSize)).y));
                float _1690 = _1688 - 1.0;
                float _1694 = _1679 * (vec4(TextureSize, 1.0 / TextureSize)).w;
                float _1698 = (_1678 - 2.5) * (vec4(TextureSize, 1.0 / TextureSize)).w;
                float _1728 = RA_VARYING_0.x * (vec4(TextureSize, 1.0 / TextureSize)).x;
                float _1732 = (MaxSpotSize) / RA_VARYING_1;
                float _1736 = (vec4(TextureSize, 1.0 / TextureSize)).z * (round(_1728 - _1732) + 0.5);
                float _1749 = (vec4(TextureSize, 1.0 / TextureSize)).z * round(_1728 + _1732);
                float _1757 = (RA_VARYING_1 * (vec4(TextureSize, 1.0 / TextureSize)).x) * (_1736 - RA_VARYING_0.x);
                vec3 _2724;
                _2724 = vec3(0.0);
                for (float _2722 = _1736, _2727 = _1757; _2722 < _1749; )
                {
                    vec2 _1769 = vec2(_2722, _1694);
                    vec3 _1778 = textureLod(Texture, _1769, 0.0).xyz;
                    vec2 _1783 = vec2(_2722, _1698);
                    vec3 _1792 = textureLod(Texture, _1783, 0.0).xyz;
                    float _1829 = abs(_2727);
                    vec3 _1834 = clamp(_1778 * _1829, vec3(0.0), vec3(1.0));
                    vec3 _1841 = clamp(_1778 * abs(_1688), vec3(0.0), vec3(1.0));
                    vec3 _1879 = clamp(_1792 * _1829, vec3(0.0), vec3(1.0));
                    vec3 _1886 = clamp(_1792 * abs(_1690), vec3(0.0), vec3(1.0));
                    _2727 += RA_VARYING_1;
                    _2724 = (_2724 + ((((textureLod(Pass2Texture, _1769, 0.0).xyz * _1778) * _1778) * (((_1834 * _1834) * ((_1834 * 2.0) - vec3(3.0))) + vec3(1.0))) * (((_1841 * _1841) * ((_1841 * 2.0) - vec3(3.0))) + vec3(1.0)))) + ((((textureLod(Pass2Texture, _1783, 0.0).xyz * _1792) * _1792) * (((_1879 * _1879) * ((_1879 * 2.0) - vec3(3.0))) + vec3(1.0))) * (((_1886 * _1886) * ((_1886 * 2.0) - vec3(3.0))) + vec3(1.0)));
                    _2722 += (vec4(TextureSize, 1.0 / TextureSize)).z;
                    continue;
                }
                _2754 = _2724 * (RA_VARYING_1 * (MaxSpotSize));
            }
            else
            {
                float _1927 = ceil(((0.5 * RA_VARYING_0.y) * (vec4(TextureSize, 1.0 / TextureSize)).y) - 0.25) * 2.0;
                float _1928 = _1927 + 0.5;
                float _1937 = 0.5 * (_1928 - (RA_VARYING_0.y * (vec4(TextureSize, 1.0 / TextureSize)).y));
                float _1939 = _1937 - 1.0;
                float _1943 = _1928 * (vec4(TextureSize, 1.0 / TextureSize)).w;
                float _1947 = (_1927 + (-1.5)) * (vec4(TextureSize, 1.0 / TextureSize)).w;
                float _1977 = RA_VARYING_0.x * (vec4(TextureSize, 1.0 / TextureSize)).x;
                float _1981 = (MaxSpotSize) / RA_VARYING_1;
                float _1985 = (vec4(TextureSize, 1.0 / TextureSize)).z * (round(_1977 - _1981) + 0.5);
                float _1998 = (vec4(TextureSize, 1.0 / TextureSize)).z * round(_1977 + _1981);
                float _2006 = (RA_VARYING_1 * (vec4(TextureSize, 1.0 / TextureSize)).x) * (_1985 - RA_VARYING_0.x);
                vec3 _2716;
                _2716 = vec3(0.0);
                for (float _2714 = _1985, _2719 = _2006; _2714 < _1998; )
                {
                    vec2 _2018 = vec2(_2714, _1943);
                    vec3 _2027 = textureLod(Texture, _2018, 0.0).xyz;
                    vec2 _2032 = vec2(_2714, _1947);
                    vec3 _2041 = textureLod(Texture, _2032, 0.0).xyz;
                    float _2078 = abs(_2719);
                    vec3 _2083 = clamp(_2027 * _2078, vec3(0.0), vec3(1.0));
                    vec3 _2090 = clamp(_2027 * abs(_1937), vec3(0.0), vec3(1.0));
                    vec3 _2128 = clamp(_2041 * _2078, vec3(0.0), vec3(1.0));
                    vec3 _2135 = clamp(_2041 * abs(_1939), vec3(0.0), vec3(1.0));
                    _2719 += RA_VARYING_1;
                    _2716 = (_2716 + ((((textureLod(Pass2Texture, _2018, 0.0).xyz * _2027) * _2027) * (((_2083 * _2083) * ((_2083 * 2.0) - vec3(3.0))) + vec3(1.0))) * (((_2090 * _2090) * ((_2090 * 2.0) - vec3(3.0))) + vec3(1.0)))) + ((((textureLod(Pass2Texture, _2032, 0.0).xyz * _2041) * _2041) * (((_2128 * _2128) * ((_2128 * 2.0) - vec3(3.0))) + vec3(1.0))) * (((_2135 * _2135) * ((_2135 * 2.0) - vec3(3.0))) + vec3(1.0)));
                    _2714 += (vec4(TextureSize, 1.0 / TextureSize)).z;
                    continue;
                }
                _2754 = _2716 * (RA_VARYING_1 * (MaxSpotSize));
            }
            _2753 = _2754;
        }
        _2752 = _2753;
    }
    vec3 _2783;
    if ((MaskType) == 1.0)
    {
        float _2180 = RA_VARYING_2.x * (vec4(OutputSize, 1.0 / OutputSize)).x;
        vec3 _2756;
        float _2765;
        if ((SubpixelPattern) == 0.0)
        {
            vec3 _2757;
            float _2766;
            if ((SubpixelMaskPattern) == 2.0)
            {
                _2766 = 2.0;
                _2757 = _89[int(mod(_2180, 2.0))];
            }
            else
            {
                vec3 _2758;
                float _2767;
                if ((SubpixelMaskPattern) == 3.0)
                {
                    _2767 = 3.0;
                    _2758 = _108[int(mod(_2180, 3.0))];
                }
                else
                {
                    vec3 _2759;
                    float _2768;
                    if ((SubpixelMaskPattern) == 4.0)
                    {
                        _2768 = 2.0;
                        _2759 = _126[int(mod(_2180, 4.0))];
                    }
                    else
                    {
                        bool _2212 = (SubpixelMaskPattern) == 5.0;
                        vec3 _2760;
                        if (_2212)
                        {
                            _2760 = _142[int(mod(_2180, 5.0))];
                        }
                        else
                        {
                            _2760 = vec3(1.0);
                        }
                        _2768 = _2212 ? 2.5 : 1.0;
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
            vec3 _2761;
            float _2770;
            if ((SubpixelMaskPattern) == 2.0)
            {
                _2770 = 2.0;
                _2761 = _89[int(mod(_2180, 2.0))];
            }
            else
            {
                vec3 _2762;
                float _2771;
                if ((SubpixelMaskPattern) == 3.0)
                {
                    _2771 = 3.0;
                    _2762 = _166[int(mod(_2180, 3.0))];
                }
                else
                {
                    vec3 _2763;
                    float _2772;
                    if ((SubpixelMaskPattern) == 4.0)
                    {
                        _2772 = 2.0;
                        _2763 = _178[int(mod(_2180, 4.0))];
                    }
                    else
                    {
                        bool _2252 = (SubpixelMaskPattern) == 5.0;
                        vec3 _2764;
                        if (_2252)
                        {
                            _2764 = _190[int(mod(_2180, 5.0))];
                        }
                        else
                        {
                            _2764 = vec3(1.0);
                        }
                        _2772 = _2252 ? 2.5 : 1.0;
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
        vec3 _2279 = vec3(1.0 - _2765);
        _2783 = ((clamp((_2752 - vec3(1.0)) / _2279, vec3(0.0), _2752) * _2765) * vec4(_2756, _2765).xyz) + clamp((vec3(1.0) - (_2752 * _2765)) / _2279, vec3(0.0), _2752);
    }
    else
    {
        vec3 _2784;
        if ((MaskType) == 2.0)
        {
            float _2325 = 3.0 * (DynamicMaskTriads);
            float _2328 = _2325 * (vec4(OutputSize, 1.0 / OutputSize)).z;
            float _2333 = _2325 * RA_VARYING_2.x;
            vec3 _2749;
            if (_2328 < 0.5)
            {
                float _2339 = round(_2333);
                float _2343 = clamp((_2333 - _2339) / _2328, -1.0, 1.0);
                int _2349 = int(mod(_2339 - 1.0, 3.0) + 0.001000000047497451305389404296875);
                _2749 = ((_166[_2349] + _166[_2349].zxy) + ((_166[_2349].zxy - _166[_2349]) * (_2343 + (sin(3.1415927410125732421875 * _2343) * 0.3183098733425140380859375)))) * 0.5;
            }
            else
            {
                vec3 _2750;
                if (_2328 < 1.0)
                {
                    float _2376 = floor(_2333);
                    float _2381 = clamp((_2333 - _2376) / _2328, -1.0, 1.0);
                    float _2389 = clamp((_2333 - (_2376 + 1.0)) / _2328, -1.0, 1.0);
                    int _2395 = int(mod(_2376 - 1.0, 3.0) + 0.001000000047497451305389404296875);
                    _2750 = (((_166[_2395] + _166[_2395].yzx) + ((_166[_2395].zxy - _166[_2395]) * (_2381 + (sin(3.1415927410125732421875 * _2381) * 0.3183098733425140380859375)))) + ((_166[_2395].yzx - _166[_2395].zxy) * (_2389 + (sin(3.1415927410125732421875 * _2389) * 0.3183098733425140380859375)))) * 0.5;
                }
                else
                {
                    float _2432 = round(_2333);
                    float _2437 = clamp((_2333 - (_2432 - 1.0)) / _2328, -1.0, 1.0);
                    float _2445 = clamp((_2333 - _2432) / _2328, -1.0, 1.0);
                    float _2453 = clamp((_2333 - (_2432 + 1.0)) / _2328, -1.0, 1.0);
                    int _2459 = int(mod(_2432 - 2.0, 3.0) + 0.001000000047497451305389404296875);
                    _2750 = ((((_166[_2459] + _166[_2459].xyz) + ((_166[_2459].zxy - _166[_2459]) * (_2437 + (sin(3.1415927410125732421875 * _2437) * 0.3183098733425140380859375)))) + ((_166[_2459].yzx - _166[_2459].zxy) * (_2445 + (sin(3.1415927410125732421875 * _2445) * 0.3183098733425140380859375)))) + ((_166[_2459].xyz - _166[_2459].yzx) * (_2453 + (sin(3.1415927410125732421875 * _2453) * 0.3183098733425140380859375)))) * 0.5;
                }
                _2749 = _2750;
            }
            _2784 = ((clamp((_2752 - vec3(1.0)) * vec3(-0.5), vec3(0.0), _2752) * 3.0) * vec4(_2749, 3.0).xyz) + clamp((vec3(1.0) - (_2752 * 3.0)) * vec3(-0.5), vec3(0.0), _2752);
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


#endif
