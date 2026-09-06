// Generated from crt/shaders/hyllian/crt-hyllian-pass1.slang. See slang/upstream for licence/source.
#version 430
#pragma parameter H_OUTPUT_GAMMA    "    Output Gamma"    2.2 1.0 3.0 0.05
#pragma parameter BRIGHTBOOST       "    Brightboost"     1.0 0.5 2.0 0.01
#pragma parameter scan_nonono        "SCANLINES SETTINGS:"                         0.0  0.0 0.0 1.0
#pragma parameter BEAM_MIN_WIDTH     "    Min Beam Width"                        0.72 0.0 1.0 0.01
#pragma parameter BEAM_MAX_WIDTH     "    Max Beam Width"                        1.0  0.0 1.0 0.01
#pragma parameter SCANLINES_STRENGTH "    Scanlines Strength"                    0.72 0.0 1.0 0.01
#pragma parameter SCANLINES_SHAPE    "    Scanlines Shape [ SHARP, SOFT ]"       1.0  0.0 1.0 1.0
#pragma parameter msk_nonono        "MASK SETTINGS:"                                             0.0 0.0  0.0 1.0
#pragma parameter PHOSPHOR_LAYOUT   "    Mask [1-6 APERT, 7-10 DOT, 11-14 SLOT, 15-17 LOTTES]" 1.0 0.0 17.0 1.0
#pragma parameter MASK_STRENGTH     "    Mask Strength"                                          1.0 0.0  1.0 0.02
#pragma parameter H_MaskGamma       "    Mask Gamma"                                             2.4 1.0  3.0 0.05
#pragma parameter MONITOR_SUBPIXELS "    Monitor Subpixels Layout [ RGB, BGR ]"                  0.0 0.0  1.0 1.0
#pragma parameter fil_nonono        "FILTERING SETTINGS:"                            0.0 0.0 0.0 1.0
#pragma parameter SHARPNESS_HACK    "    Sharpness Hack"                             1.0 1.0 4.0 1.0
#pragma parameter CRT_ANTI_RINGING  "    Anti Ringing"                               1.0 0.0 1.0 1.0
#pragma parameter h_nonono        "CURVATURE SETTINGS:"                 0.0  0.0  0.0 1.0
#pragma parameter CURVATURE         "    Curvature Toggle" 0.0 0.0 1.0 1.0
#pragma parameter WARP_X            "        Curvature-X" 0.015 0.0 0.125 0.005
#pragma parameter WARP_Y            "        Curvature-Y" 0.015 0.0 0.125 0.005
#pragma parameter CORNER_SIZE       "        Corner Size" 0.02 0.001 1.0 0.005
#pragma parameter CORNER_SMOOTHNESS "        Corner Smoothness" 1.10 1.0 2.2 0.02
#ifdef VERTEX

uniform mat4 MVPMatrix;
struct UBO
{
    mat4 MVP;
};



layout(location = 0) in vec4 VertexCoord;
layout(location = 0) out vec2 RA_VARYING_0;
layout(location = 1) in vec2 TexCoord;

void main()
{
    gl_Position = (MVPMatrix) * VertexCoord;
    RA_VARYING_0 = TexCoord * 1.00010001659393310546875;
}


#endif
#ifdef FRAGMENT

uniform float BEAM_MAX_WIDTH;
uniform float BEAM_MIN_WIDTH;
uniform float BRIGHTBOOST;
uniform float CORNER_SIZE;
uniform float CORNER_SMOOTHNESS;
uniform float CURVATURE;
uniform float H_MaskGamma;
uniform float H_OUTPUT_GAMMA;
uniform float MASK_STRENGTH;
uniform float MONITOR_SUBPIXELS;
uniform vec2 OutputSize;
uniform float PHOSPHOR_LAYOUT;
uniform float SCANLINES_SHAPE;
uniform float SCANLINES_STRENGTH;
uniform vec2 TextureSize;
uniform float WARP_Y;
const vec3 _341[3] = vec3[](vec3(0.0, 0.0, 1.0), vec3(0.0, 1.0, 0.0), vec3(1.0, 0.0, 0.0));
const vec3 _359[3] = vec3[](vec3(0.0), vec3(1.0), vec3(0.0));
const vec3 _382[4] = vec3[](vec3(0.0, 0.0, 1.0), vec3(0.0, 1.0, 1.0), vec3(1.0, 1.0, 0.0), vec3(1.0, 0.0, 0.0));
const vec3 _401[4] = vec3[](vec3(0.0), vec3(0.0), vec3(1.0), vec3(1.0));
const vec3 _419[4] = vec3[](vec3(0.0, 0.0, 1.0), vec3(0.0, 1.0, 0.0), vec3(1.0, 0.0, 0.0), vec3(0.0));
const vec3 _467[2][4] = vec3[][](vec3[](vec3(0.0, 0.0, 1.0), vec3(0.0, 1.0, 1.0), vec3(1.0, 1.0, 0.0), vec3(1.0, 0.0, 0.0)), vec3[](vec3(1.0, 1.0, 0.0), vec3(1.0, 0.0, 0.0), vec3(0.0, 0.0, 1.0), vec3(0.0, 1.0, 1.0)));
const vec3 _493[2][4] = vec3[][](vec3[](vec3(0.0, 0.0, 1.0), vec3(0.0, 1.0, 0.0), vec3(1.0, 0.0, 0.0), vec3(0.0)), vec3[](vec3(1.0, 0.0, 0.0), vec3(0.0), vec3(0.0, 0.0, 1.0), vec3(0.0, 1.0, 0.0)));
const vec3 _517[4][4] = vec3[][](vec3[](vec3(0.0, 0.0, 1.0), vec3(0.0, 1.0, 1.0), vec3(1.0, 1.0, 0.0), vec3(1.0, 0.0, 0.0)), vec3[](vec3(0.0, 0.0, 1.0), vec3(0.0, 1.0, 1.0), vec3(1.0, 1.0, 0.0), vec3(1.0, 0.0, 0.0)), vec3[](vec3(1.0, 1.0, 0.0), vec3(1.0, 0.0, 0.0), vec3(0.0, 0.0, 1.0), vec3(0.0, 1.0, 1.0)), vec3[](vec3(1.0, 1.0, 0.0), vec3(1.0, 0.0, 0.0), vec3(0.0, 0.0, 1.0), vec3(0.0, 1.0, 1.0)));
const vec3 _548[4][6] = vec3[][](vec3[](vec3(0.0, 0.0, 1.0), vec3(0.0, 1.0, 0.0), vec3(1.0, 0.0, 0.0), vec3(0.0, 0.0, 1.0), vec3(0.0, 1.0, 0.0), vec3(1.0, 0.0, 0.0)), vec3[](vec3(0.0, 0.0, 1.0), vec3(0.0, 1.0, 0.0), vec3(1.0, 0.0, 0.0), vec3(0.0), vec3(0.0), vec3(0.0)), vec3[](vec3(0.0, 0.0, 1.0), vec3(0.0, 1.0, 0.0), vec3(1.0, 0.0, 0.0), vec3(0.0, 0.0, 1.0), vec3(0.0, 1.0, 0.0), vec3(1.0, 0.0, 0.0)), vec3[](vec3(0.0), vec3(0.0), vec3(0.0), vec3(0.0, 0.0, 1.0), vec3(0.0, 1.0, 0.0), vec3(1.0, 0.0, 0.0)));
const vec3 _576[4][6] = vec3[][](vec3[](vec3(0.0), vec3(1.0), vec3(0.0), vec3(0.0), vec3(1.0), vec3(0.0)), vec3[](vec3(0.0), vec3(1.0), vec3(0.0), vec3(0.0), vec3(0.0), vec3(0.0)), vec3[](vec3(0.0), vec3(1.0), vec3(0.0), vec3(0.0), vec3(1.0), vec3(0.0)), vec3[](vec3(0.0), vec3(0.0), vec3(0.0), vec3(0.0), vec3(1.0), vec3(0.0)));
const vec3 _606[4][8] = vec3[][](vec3[](vec3(0.0, 0.0, 1.0), vec3(0.0, 1.0, 0.0), vec3(1.0, 0.0, 0.0), vec3(0.0), vec3(0.0, 0.0, 1.0), vec3(0.0, 1.0, 0.0), vec3(1.0, 0.0, 0.0), vec3(0.0)), vec3[](vec3(0.0, 0.0, 1.0), vec3(0.0, 1.0, 0.0), vec3(1.0, 0.0, 0.0), vec3(0.0), vec3(0.0), vec3(0.0), vec3(0.0), vec3(0.0)), vec3[](vec3(0.0, 0.0, 1.0), vec3(0.0, 1.0, 0.0), vec3(1.0, 0.0, 0.0), vec3(0.0), vec3(0.0, 0.0, 1.0), vec3(0.0, 1.0, 0.0), vec3(1.0, 0.0, 0.0), vec3(0.0)), vec3[](vec3(0.0), vec3(0.0), vec3(0.0), vec3(0.0), vec3(0.0, 0.0, 1.0), vec3(0.0, 1.0, 0.0), vec3(1.0, 0.0, 0.0), vec3(0.0)));
const vec3 _636[4][10] = vec3[][](vec3[](vec3(0.0, 0.0, 1.0), vec3(0.0, 1.0, 1.0), vec3(0.0, 1.0, 0.0), vec3(1.0, 0.0, 0.0), vec3(1.0, 0.0, 0.0), vec3(0.0, 0.0, 1.0), vec3(0.0, 1.0, 1.0), vec3(0.0, 1.0, 0.0), vec3(1.0, 0.0, 0.0), vec3(1.0, 0.0, 0.0)), vec3[](vec3(0.0), vec3(0.0, 1.0, 0.0), vec3(0.0, 1.0, 0.0), vec3(1.0, 0.0, 0.0), vec3(1.0, 0.0, 0.0), vec3(0.0, 0.0, 1.0), vec3(0.0, 0.0, 1.0), vec3(0.0), vec3(0.0), vec3(0.0)), vec3[](vec3(0.0, 0.0, 1.0), vec3(0.0, 1.0, 1.0), vec3(0.0, 1.0, 0.0), vec3(1.0, 0.0, 0.0), vec3(1.0, 0.0, 0.0), vec3(0.0, 0.0, 1.0), vec3(0.0, 1.0, 1.0), vec3(0.0, 1.0, 0.0), vec3(1.0, 0.0, 0.0), vec3(1.0, 0.0, 0.0)), vec3[](vec3(0.0, 0.0, 1.0), vec3(0.0, 0.0, 1.0), vec3(0.0), vec3(0.0), vec3(0.0), vec3(0.0), vec3(0.0, 1.0, 0.0), vec3(0.0, 1.0, 0.0), vec3(1.0, 0.0, 0.0), vec3(1.0, 0.0, 0.0)));

struct Push
{
    vec4 SourceSize;
    vec4 OutputSize;
    float H_OUTPUT_GAMMA;
    float PHOSPHOR_LAYOUT;
    float MASK_STRENGTH;
    float MONITOR_SUBPIXELS;
    float BRIGHTBOOST;
    float SCANLINES_SHAPE;
    float SCANLINES_STRENGTH;
    float BEAM_MIN_WIDTH;
    float BEAM_MAX_WIDTH;
    float CURVATURE;
    float WARP_Y;
    float CORNER_SIZE;
    float CORNER_SMOOTHNESS;
    float H_MaskGamma;
};



layout(binding = 2) uniform sampler2D Texture;

layout(location = 0) in vec2 RA_VARYING_0;
layout(location = 0) out vec4 FragColor;

void main()
{
    bool _792 = (CURVATURE) > 0.5;
    vec2 _1699;
    if (_792)
    {
        vec2 _1020 = (RA_VARYING_0 * 2.0) - vec2(1.0);
        float _1022 = _1020.x;
        float _1027 = _1020.y;
        float _1032 = sqrt((_1022 * _1022) + (_1027 * _1027));
        vec2 _1047 = vec2(1.0) / (vec2(1.0) + ((vec2(0.0, (WARP_Y)) * 15.0) * 0.20000000298023223876953125));
        _1699 = ((((_1020 / vec2(_1032)) * (vec2(1.0) - pow(vec2(1.0 - (_1032 * 0.707106769084930419921875)), _1047))) / (vec2(1.0) - pow(vec2(0.292893230915069580078125), _1047))) * 0.5) + vec2(0.5);
    }
    else
    {
        _1699 = RA_VARYING_0;
    }
    vec2 _808 = (_1699 * (vec4(TextureSize, 1.0 / TextureSize)).xy) + vec2(0.0, -0.5);
    vec2 _814 = (floor(_808) + vec2(0.5)) / (vec4(TextureSize, 1.0 / TextureSize)).xy;
    vec2 _817 = fract(_808);
    vec4 _825 = texture(Texture, _814);
    vec3 _826 = _825.xyz;
    vec4 _832 = texture(Texture, _814 + vec2(0.0, 1.0 / (vec4(TextureSize, 1.0 / TextureSize)).y));
    vec3 _833 = _832.xyz;
    float _836 = _817.y;
    vec3 _845 = vec3((BEAM_MIN_WIDTH));
    vec3 _849 = vec3((BEAM_MAX_WIDTH));
    vec3 _851 = mix(_845, _849, _826);
    vec3 _860 = mix(_845, _849, _833);
    float _869 = ((-0.1599999964237213134765625) * (SCANLINES_SHAPE)) + (SCANLINES_STRENGTH);
    vec3 _879 = vec3(_869 * _836) / ((_851 * _851) + vec3(9.9999997473787516355514526367188e-06));
    vec3 _895 = vec3(_869 * (1.0 - _836)) / ((_860 * _860) + vec3(9.9999997473787516355514526367188e-06));
    vec3 _1717;
    vec3 _1728;
    if ((SCANLINES_SHAPE) > 0.5)
    {
        _1728 = exp((_895 * (-16.0)) * _895);
        _1717 = exp((_879 * (-16.0)) * _879);
    }
    else
    {
        vec3 _1090 = clamp(_879 * 2.0, vec3(0.0), vec3(1.0));
        vec3 _1095 = clamp(_895 * 2.0, vec3(0.0), vec3(1.0));
        float _1115 = _1090.x;
        float _1701;
        if (_1115 <= 0.001000000047497451305389404296875)
        {
            _1701 = 1.0;
        }
        else
        {
            _1701 = (sin(_1115 * 1.57079637050628662109375) * sin(_1115 * 3.1415927410125732421875)) / ((4.93480205535888671875 * _1115) * _1115);
        }
        float _1139 = _1090.y;
        float _1702;
        if (_1139 <= 0.001000000047497451305389404296875)
        {
            _1702 = 1.0;
        }
        else
        {
            _1702 = (sin(_1139 * 1.57079637050628662109375) * sin(_1139 * 3.1415927410125732421875)) / ((4.93480205535888671875 * _1139) * _1139);
        }
        float _1163 = _1090.z;
        float _1703;
        if (_1163 <= 0.001000000047497451305389404296875)
        {
            _1703 = 1.0;
        }
        else
        {
            _1703 = (sin(_1163 * 1.57079637050628662109375) * sin(_1163 * 3.1415927410125732421875)) / ((4.93480205535888671875 * _1163) * _1163);
        }
        float _1194 = _1095.x;
        float _1707;
        if (_1194 <= 0.001000000047497451305389404296875)
        {
            _1707 = 1.0;
        }
        else
        {
            _1707 = (sin(_1194 * 1.57079637050628662109375) * sin(_1194 * 3.1415927410125732421875)) / ((4.93480205535888671875 * _1194) * _1194);
        }
        float _1218 = _1095.y;
        float _1708;
        if (_1218 <= 0.001000000047497451305389404296875)
        {
            _1708 = 1.0;
        }
        else
        {
            _1708 = (sin(_1218 * 1.57079637050628662109375) * sin(_1218 * 3.1415927410125732421875)) / ((4.93480205535888671875 * _1218) * _1218);
        }
        float _1242 = _1095.z;
        float _1709;
        if (_1242 <= 0.001000000047497451305389404296875)
        {
            _1709 = 1.0;
        }
        else
        {
            _1709 = (sin(_1242 * 1.57079637050628662109375) * sin(_1242 * 3.1415927410125732421875)) / ((4.93480205535888671875 * _1242) * _1242);
        }
        _1728 = vec3(_1707, _1708, _1709);
        _1717 = vec3(_1701, _1702, _1703);
    }
    vec2 _933 = RA_VARYING_0 * (vec4(OutputSize, 1.0 / OutputSize)).xy;
    vec3 _1734;
    do
    {
        if ((PHOSPHOR_LAYOUT) > 14.0)
        {
            vec3 _1915;
            if ((PHOSPHOR_LAYOUT) == 15.0)
            {
                float _1558 = _933.x;
                float _1576 = fract(_1558 * 0.3333333432674407958984375);
                vec3 _1913;
                if (_1576 < 0.333000004291534423828125)
                {
                    _1913 = vec3(0.0, 0.0, 1.0);
                }
                else
                {
                    vec3 _1914;
                    if (_1576 < 0.66600000858306884765625)
                    {
                        _1914 = vec3(0.0, 1.0, 0.0);
                    }
                    else
                    {
                        _1914 = vec3(1.0, 0.0, 0.0);
                    }
                    _1913 = _1914;
                }
                _1915 = _1913 * ((fract((_933.y + float(fract(_1558 * 0.16666667163372039794921875) < 0.5)) * 0.5) < 0.5) ? 0.0 : 1.0);
            }
            else
            {
                vec3 _1916;
                if ((PHOSPHOR_LAYOUT) == 16.0)
                {
                    float _1610 = fract((_933.x + (_933.y * 3.0)) * 0.16666667163372039794921875);
                    vec3 _1920;
                    if (_1610 < 0.333000004291534423828125)
                    {
                        _1920 = vec3(0.0, 0.0, 1.0);
                    }
                    else
                    {
                        vec3 _1921;
                        if (_1610 < 0.66600000858306884765625)
                        {
                            _1921 = vec3(0.0, 1.0, 0.0);
                        }
                        else
                        {
                            _1921 = vec3(1.0, 0.0, 0.0);
                        }
                        _1920 = _1921;
                    }
                    _1916 = _1920;
                }
                else
                {
                    vec3 _1917;
                    if ((PHOSPHOR_LAYOUT) == 17.0)
                    {
                        vec2 _1633 = floor(_933 * vec2(1.0, 0.5));
                        float _1644 = fract((_1633.x + (_1633.y * 3.0)) * 0.16666667163372039794921875);
                        vec3 _1918;
                        if (_1644 < 0.333000004291534423828125)
                        {
                            _1918 = vec3(0.0, 0.0, 1.0);
                        }
                        else
                        {
                            vec3 _1919;
                            if (_1644 < 0.66600000858306884765625)
                            {
                                _1919 = vec3(0.0, 1.0, 0.0);
                            }
                            else
                            {
                                _1919 = vec3(1.0, 0.0, 0.0);
                            }
                            _1918 = _1919;
                        }
                        _1917 = _1918;
                    }
                    else
                    {
                        _1917 = vec3(0.0);
                    }
                    _1916 = _1917;
                }
                _1915 = _1916;
            }
            _1734 = _1915;
            break;
        }
        float _1298 = _933.x;
        vec3 _1301 = vec3(floor(mod(_1298, 2.0)));
        vec3 _1302 = mix(vec3(1.0, 0.0, 1.0), vec3(0.0, 1.0, 0.0), _1301);
        if ((PHOSPHOR_LAYOUT) == 0.0)
        {
            _1734 = vec3(1.0);
            break;
        }
        else
        {
            if ((PHOSPHOR_LAYOUT) == 1.0)
            {
                _1734 = _1302;
                break;
            }
            else
            {
                if ((PHOSPHOR_LAYOUT) == 2.0)
                {
                    _1734 = _341[int(floor(mod(_1298, 3.0)))];
                    break;
                }
                else
                {
                    if ((PHOSPHOR_LAYOUT) == 3.0)
                    {
                        _1734 = _359[int(floor(mod(_1298, 3.0)))];
                        break;
                    }
                    else
                    {
                        if ((PHOSPHOR_LAYOUT) == 4.0)
                        {
                            _1734 = _382[int(floor(mod(_1298, 4.0)))];
                            break;
                        }
                        else
                        {
                            if ((PHOSPHOR_LAYOUT) == 5.0)
                            {
                                _1734 = _401[int(floor(mod(_1298, 4.0)))];
                                break;
                            }
                            else
                            {
                                if ((PHOSPHOR_LAYOUT) == 6.0)
                                {
                                    _1734 = _419[int(floor(mod(_1298, 4.0)))];
                                    break;
                                }
                                else
                                {
                                    if ((PHOSPHOR_LAYOUT) == 7.0)
                                    {
                                        _1734 = mix(_1302, mix(vec3(0.0, 1.0, 0.0), vec3(1.0, 0.0, 1.0), _1301), vec3(floor(mod(_933.y, 2.0))));
                                        break;
                                    }
                                    else
                                    {
                                        if ((PHOSPHOR_LAYOUT) == 8.0)
                                        {
                                            _1734 = _467[int(floor(mod(_933.y, 2.0)))][int(floor(mod(_1298, 4.0)))];
                                            break;
                                        }
                                        else
                                        {
                                            if ((PHOSPHOR_LAYOUT) == 9.0)
                                            {
                                                _1734 = _493[int(floor(mod(_933.y, 2.0)))][int(floor(mod(_1298, 4.0)))];
                                                break;
                                            }
                                            else
                                            {
                                                if ((PHOSPHOR_LAYOUT) == 10.0)
                                                {
                                                    _1734 = _517[int(floor(mod(_933.y, 4.0)))][int(floor(mod(_1298, 4.0)))];
                                                    break;
                                                }
                                                else
                                                {
                                                    if ((PHOSPHOR_LAYOUT) == 11.0)
                                                    {
                                                        _1734 = _548[int(floor(mod(_933.y, 4.0)))][int(floor(mod(_1298, 6.0)))];
                                                        break;
                                                    }
                                                    else
                                                    {
                                                        if ((PHOSPHOR_LAYOUT) == 12.0)
                                                        {
                                                            _1734 = _576[int(floor(mod(_933.y, 4.0)))][int(floor(mod(_1298, 6.0)))];
                                                            break;
                                                        }
                                                        else
                                                        {
                                                            if ((PHOSPHOR_LAYOUT) == 13.0)
                                                            {
                                                                _1734 = _606[int(floor(mod(_933.y, 4.0)))][int(floor(mod(_1298, 8.0)))];
                                                                break;
                                                            }
                                                            else
                                                            {
                                                                if ((PHOSPHOR_LAYOUT) == 14.0)
                                                                {
                                                                    _1734 = _636[int(floor(mod(_933.y, 4.0)))][int(floor(mod(_1298, 10.0)))];
                                                                    break;
                                                                }
                                                                else
                                                                {
                                                                    _1734 = vec3(1.0);
                                                                    break;
                                                                }
                                                                break; // unreachable workaround
                                                            }
                                                            break; // unreachable workaround
                                                        }
                                                        break; // unreachable workaround
                                                    }
                                                    break; // unreachable workaround
                                                }
                                                break; // unreachable workaround
                                            }
                                            break; // unreachable workaround
                                        }
                                        break; // unreachable workaround
                                    }
                                    break; // unreachable workaround
                                }
                                break; // unreachable workaround
                            }
                            break; // unreachable workaround
                        }
                        break; // unreachable workaround
                    }
                    break; // unreachable workaround
                }
                break; // unreachable workaround
            }
            break; // unreachable workaround
        }
        break; // unreachable workaround
    } while(false);
    vec3 _1735;
    if ((MONITOR_SUBPIXELS) > 0.5)
    {
        _1735 = _1734.zyx;
    }
    else
    {
        _1735 = _1734;
    }
    FragColor = vec4(_1735 + ((vec3(1.0) - (_1735 * 2.0)) * pow(abs(_1735 - pow(clamp(((_826 * _1717) + (_833 * _1728)) * (BRIGHTBOOST), vec3(0.0), vec3(1.0)), vec3(1.0 / (H_OUTPUT_GAMMA)))), ((_1735 * (MASK_STRENGTH)) * (vec3((H_MaskGamma)) - vec3(1.0))) + vec3(1.0))), 1.0);
    float _1769;
    if (_792)
    {
        vec2 _1679 = vec2((CORNER_SIZE));
        vec2 _1684 = _1679 - min(min(_1699, vec2(1.0) - _1699) * vec2(1.0, 0.75), _1679);
        _1769 = clamp(((CORNER_SIZE) - sqrt(dot(_1684, _1684))) * (80.0 * pow((CORNER_SMOOTHNESS), 10.0)), 0.0, 1.0);
    }
    else
    {
        _1769 = 1.0;
    }
    FragColor *= _1769;
}


#endif
