// Generated from crt/shaders/hyllian/support/glow/blur-glow-mask-geom.slang. See slang/upstream for licence/source.
#version 430
#pragma parameter H_OUTPUT_GAMMA    "    Output Gamma"    2.2 1.0 3.0 0.05
#pragma parameter BRIGHTBOOST       "    Brightboost"     1.0 0.5 2.0 0.01
#pragma parameter GLOW_ENABLE    "    Enable Glow"   0.0  0.0 1.0 1.0
#pragma parameter GLOW_RADIUS    "        Radius"    4.0  2.0 4.0 0.1
#pragma parameter GLOW_STRENGTH  "        Strength"  0.05 0.0 1.0 0.01
#pragma parameter VSCANLINES         "    Orientation [ HORIZONTAL, VERTICAL ]"    0.0 0.0 1.0 1.0
#pragma parameter DISPLAY_RES       "    Target Resolution [ 1080P, 4K ]"                         0.0 0.0  1.0 1.0
#pragma parameter PRESET_OPTION     "    Mask Preset [CUSTOM, APERT1, APERT2, SLOT1, SLOT2, DOT]" 0.0 0.0  5.0 1.0
#pragma parameter PHOSPHOR_LAYOUT   "    * Mask [1-6 APERT, 7-10 DOT, 11-14 SLOT, 15-17 LOTTES]"  1.0 0.0 17.0 1.0
#pragma parameter MASK_STRENGTH     "    Mask Strength"                                           1.0 0.0  1.0 0.02
#pragma parameter H_MaskGamma       "    Mask Gamma"                                              2.4 1.0  3.0 0.05
#pragma parameter MONITOR_SUBPIXELS "    Monitor Subpixels Layout [ RGB, BGR ]"                   0.0 0.0  1.0 1.0
#pragma parameter h_nonono        "CURVATURE SETTINGS:"                 0.0  0.0  0.0 1.0
#pragma parameter h_curvature     "    Curvature Toggle"                0.0  0.0  1.0 1.0
#pragma parameter h_shape         "        Shape [ SPHERE, CYLINDER ]"  0.0  0.0  1.0 1.0
#pragma parameter h_radius        "        Radius"                      5.0  1.5 10.0 0.1
#pragma parameter h_cornersize    "        Corner Size"                 0.04 0.01 1.0 0.01
#pragma parameter h_cornersmooth  "        Corner Smoothness"           0.5  0.1  1.0 0.1
#ifdef VERTEX

uniform float DISPLAY_RES;
uniform float MASK_STRENGTH;
uniform mat4 MVPMatrix;
uniform float PHOSPHOR_LAYOUT;
uniform float PRESET_OPTION;
struct UBO
{
    mat4 MVP;
};



struct Push
{
    float PRESET_OPTION;
    float DISPLAY_RES;
    float PHOSPHOR_LAYOUT;
    float MASK_STRENGTH;
};



layout(location = 0) in vec4 VertexCoord;
layout(location = 0) out vec2 RA_VARYING_0;
layout(location = 1) in vec2 TexCoord;
layout(location = 1) out vec2 RA_VARYING_1;

void main()
{
    gl_Position = (MVPMatrix) * VertexCoord;
    RA_VARYING_0 = TexCoord * vec2(1.00010001659393310546875);
    vec2 _187 = vec2((PHOSPHOR_LAYOUT), (MASK_STRENGTH));
    vec2 _246;
    if ((DISPLAY_RES) < 0.5)
    {
        bvec2 _259 = bvec2((PRESET_OPTION) == 1.0);
        vec2 _260 = vec2(_259.x ? vec2(1.0).x : _187.x, _259.y ? vec2(1.0).y : _187.y);
        bvec2 _261 = bvec2((PRESET_OPTION) == 2.0);
        vec2 _262 = vec2(_261.x ? vec2(2.0, 1.0).x : _260.x, _261.y ? vec2(2.0, 1.0).y : _260.y);
        bvec2 _263 = bvec2((PRESET_OPTION) == 3.0);
        vec2 _264 = vec2(_263.x ? vec2(11.0, 1.0).x : _262.x, _263.y ? vec2(11.0, 1.0).y : _262.y);
        bvec2 _265 = bvec2((PRESET_OPTION) == 4.0);
        vec2 _266 = vec2(_265.x ? vec2(11.0, 1.0).x : _264.x, _265.y ? vec2(11.0, 1.0).y : _264.y);
        bvec2 _267 = bvec2((PRESET_OPTION) == 5.0);
        _246 = vec2(_267.x ? vec2(7.0, 1.0).x : _266.x, _267.y ? vec2(7.0, 1.0).y : _266.y);
    }
    else
    {
        bvec2 _269 = bvec2((PRESET_OPTION) == 1.0);
        vec2 _270 = vec2(_269.x ? vec2(2.0, 1.0).x : _187.x, _269.y ? vec2(2.0, 1.0).y : _187.y);
        bvec2 _271 = bvec2((PRESET_OPTION) == 2.0);
        vec2 _272 = vec2(_271.x ? vec2(4.0, 1.0).x : _270.x, _271.y ? vec2(4.0, 1.0).y : _270.y);
        bvec2 _273 = bvec2((PRESET_OPTION) == 3.0);
        vec2 _274 = vec2(_273.x ? vec2(14.0, 1.0).x : _272.x, _273.y ? vec2(14.0, 1.0).y : _272.y);
        bvec2 _275 = bvec2((PRESET_OPTION) == 4.0);
        vec2 _276 = vec2(_275.x ? vec2(14.0, 1.0).x : _274.x, _275.y ? vec2(14.0, 1.0).y : _274.y);
        bvec2 _277 = bvec2((PRESET_OPTION) == 5.0);
        _246 = vec2(_277.x ? vec2(9.0, 1.0).x : _276.x, _277.y ? vec2(9.0, 1.0).y : _276.y);
    }
    RA_VARYING_1 = _246;
}


#endif
#ifdef FRAGMENT

uniform float BRIGHTBOOST;
uniform float GLOW_ENABLE;
uniform float GLOW_RADIUS;
uniform float GLOW_STRENGTH;
uniform float H_MaskGamma;
uniform float H_OUTPUT_GAMMA;
uniform float MASK_STRENGTH;
uniform float MONITOR_SUBPIXELS;
uniform vec2 OutputSize;
uniform vec2 TextureSize;
uniform float VSCANLINES;
uniform float h_cornersize;
uniform float h_cornersmooth;
uniform float h_curvature;
uniform float h_radius;
uniform float h_shape;
const vec3 _281[3] = vec3[](vec3(0.0, 0.0, 1.0), vec3(0.0, 1.0, 0.0), vec3(1.0, 0.0, 0.0));
const vec3 _299[3] = vec3[](vec3(0.0), vec3(1.0), vec3(0.0));
const vec3 _322[4] = vec3[](vec3(0.0, 0.0, 1.0), vec3(0.0, 1.0, 1.0), vec3(1.0, 1.0, 0.0), vec3(1.0, 0.0, 0.0));
const vec3 _341[4] = vec3[](vec3(0.0), vec3(0.0), vec3(1.0), vec3(1.0));
const vec3 _359[4] = vec3[](vec3(0.0, 0.0, 1.0), vec3(0.0, 1.0, 0.0), vec3(1.0, 0.0, 0.0), vec3(0.0));
const vec3 _407[2][4] = vec3[][](vec3[](vec3(0.0, 0.0, 1.0), vec3(0.0, 1.0, 1.0), vec3(1.0, 1.0, 0.0), vec3(1.0, 0.0, 0.0)), vec3[](vec3(1.0, 1.0, 0.0), vec3(1.0, 0.0, 0.0), vec3(0.0, 0.0, 1.0), vec3(0.0, 1.0, 1.0)));
const vec3 _433[2][4] = vec3[][](vec3[](vec3(0.0, 0.0, 1.0), vec3(0.0, 1.0, 0.0), vec3(1.0, 0.0, 0.0), vec3(0.0)), vec3[](vec3(1.0, 0.0, 0.0), vec3(0.0), vec3(0.0, 0.0, 1.0), vec3(0.0, 1.0, 0.0)));
const vec3 _458[4][4] = vec3[][](vec3[](vec3(0.0, 0.0, 1.0), vec3(0.0, 1.0, 1.0), vec3(1.0, 1.0, 0.0), vec3(1.0, 0.0, 0.0)), vec3[](vec3(0.0, 0.0, 1.0), vec3(0.0, 1.0, 1.0), vec3(1.0, 1.0, 0.0), vec3(1.0, 0.0, 0.0)), vec3[](vec3(1.0, 1.0, 0.0), vec3(1.0, 0.0, 0.0), vec3(0.0, 0.0, 1.0), vec3(0.0, 1.0, 1.0)), vec3[](vec3(1.0, 1.0, 0.0), vec3(1.0, 0.0, 0.0), vec3(0.0, 0.0, 1.0), vec3(0.0, 1.0, 1.0)));
const vec3 _489[4][6] = vec3[][](vec3[](vec3(0.0, 0.0, 1.0), vec3(0.0, 1.0, 0.0), vec3(1.0, 0.0, 0.0), vec3(0.0, 0.0, 1.0), vec3(0.0, 1.0, 0.0), vec3(1.0, 0.0, 0.0)), vec3[](vec3(0.0, 0.0, 1.0), vec3(0.0, 1.0, 0.0), vec3(1.0, 0.0, 0.0), vec3(0.0), vec3(0.0), vec3(0.0)), vec3[](vec3(0.0, 0.0, 1.0), vec3(0.0, 1.0, 0.0), vec3(1.0, 0.0, 0.0), vec3(0.0, 0.0, 1.0), vec3(0.0, 1.0, 0.0), vec3(1.0, 0.0, 0.0)), vec3[](vec3(0.0), vec3(0.0), vec3(0.0), vec3(0.0, 0.0, 1.0), vec3(0.0, 1.0, 0.0), vec3(1.0, 0.0, 0.0)));
const vec3 _517[4][6] = vec3[][](vec3[](vec3(0.0), vec3(1.0), vec3(0.0), vec3(0.0), vec3(1.0), vec3(0.0)), vec3[](vec3(0.0), vec3(1.0), vec3(0.0), vec3(0.0), vec3(0.0), vec3(0.0)), vec3[](vec3(0.0), vec3(1.0), vec3(0.0), vec3(0.0), vec3(1.0), vec3(0.0)), vec3[](vec3(0.0), vec3(0.0), vec3(0.0), vec3(0.0), vec3(1.0), vec3(0.0)));
const vec3 _547[4][8] = vec3[][](vec3[](vec3(0.0, 0.0, 1.0), vec3(0.0, 1.0, 0.0), vec3(1.0, 0.0, 0.0), vec3(0.0), vec3(0.0, 0.0, 1.0), vec3(0.0, 1.0, 0.0), vec3(1.0, 0.0, 0.0), vec3(0.0)), vec3[](vec3(0.0, 0.0, 1.0), vec3(0.0, 1.0, 0.0), vec3(1.0, 0.0, 0.0), vec3(0.0), vec3(0.0), vec3(0.0), vec3(0.0), vec3(0.0)), vec3[](vec3(0.0, 0.0, 1.0), vec3(0.0, 1.0, 0.0), vec3(1.0, 0.0, 0.0), vec3(0.0), vec3(0.0, 0.0, 1.0), vec3(0.0, 1.0, 0.0), vec3(1.0, 0.0, 0.0), vec3(0.0)), vec3[](vec3(0.0), vec3(0.0), vec3(0.0), vec3(0.0), vec3(0.0, 0.0, 1.0), vec3(0.0, 1.0, 0.0), vec3(1.0, 0.0, 0.0), vec3(0.0)));
const vec3 _577[4][10] = vec3[][](vec3[](vec3(0.0, 0.0, 1.0), vec3(0.0, 1.0, 1.0), vec3(0.0, 1.0, 0.0), vec3(1.0, 0.0, 0.0), vec3(1.0, 0.0, 0.0), vec3(0.0, 0.0, 1.0), vec3(0.0, 1.0, 1.0), vec3(0.0, 1.0, 0.0), vec3(1.0, 0.0, 0.0), vec3(1.0, 0.0, 0.0)), vec3[](vec3(0.0), vec3(0.0, 1.0, 0.0), vec3(0.0, 1.0, 0.0), vec3(1.0, 0.0, 0.0), vec3(1.0, 0.0, 0.0), vec3(0.0, 0.0, 1.0), vec3(0.0, 0.0, 1.0), vec3(0.0), vec3(0.0), vec3(0.0)), vec3[](vec3(0.0, 0.0, 1.0), vec3(0.0, 1.0, 1.0), vec3(0.0, 1.0, 0.0), vec3(1.0, 0.0, 0.0), vec3(1.0, 0.0, 0.0), vec3(0.0, 0.0, 1.0), vec3(0.0, 1.0, 1.0), vec3(0.0, 1.0, 0.0), vec3(1.0, 0.0, 0.0), vec3(1.0, 0.0, 0.0)), vec3[](vec3(0.0, 0.0, 1.0), vec3(0.0, 0.0, 1.0), vec3(0.0), vec3(0.0), vec3(0.0), vec3(0.0), vec3(0.0, 1.0, 0.0), vec3(0.0, 1.0, 0.0), vec3(1.0, 0.0, 0.0), vec3(1.0, 0.0, 0.0)));

struct UBO
{
    vec4 SourceSize;
    vec4 OutputSize;
};



struct Push
{
    float GLOW_ENABLE;
    float GLOW_RADIUS;
    float GLOW_STRENGTH;
    float MASK_STRENGTH;
    float BRIGHTBOOST;
    float MONITOR_SUBPIXELS;
    float VSCANLINES;
    float H_OUTPUT_GAMMA;
    float H_MaskGamma;
    float h_curvature;
    float h_shape;
    float h_radius;
    float h_cornersize;
    float h_cornersmooth;
};



layout(binding = 2) uniform sampler2D Texture;
layout(binding = 3) uniform sampler2D Pass2Texture;

layout(location = 0) in vec2 RA_VARYING_0;
layout(location = 1) in vec2 RA_VARYING_1;
layout(location = 0) out vec4 FragColor;

void main()
{
    float _49 = (h_radius) * (h_radius);
    float _57 = _49 - 1.0;
    float _76 = (vec4(OutputSize, 1.0 / OutputSize)).y / (vec4(OutputSize, 1.0 / OutputSize)).x;
    vec2 _77 = vec2(1.0, _76);
    float _87 = (h_cornersize) * min(1.0, _76);
    bool _772 = (h_curvature) > 0.5;
    vec2 _1495;
    if (_772)
    {
        vec2 _932 = (RA_VARYING_0 * 2.0) - vec2(1.0);
        float _935 = _932.x;
        _1495 = ((_932 * mix(vec2(sqrt(_57 / (_49 - dot(_932, _932)))), vec2(sqrt((_49 - 2.0) / _57), 1.0) * sqrt((_49 - (_935 * _935)) / (_49 - ((2.0 * _935) * _935))), vec2((h_shape)))) * 0.5) + vec2(0.5);
    }
    else
    {
        _1495 = RA_VARYING_0;
    }
    float _1498;
    if (_772)
    {
        vec2 _989 = abs(((_1495 * 2.0) - vec2(1.0)) * _77) - (_77 - vec2(_87));
        _1498 = smoothstep((h_cornersmooth) * 0.00999999977648258209228515625, (h_cornersmooth) * (-0.00999999977648258209228515625), (length(max(_989, vec2(0.0))) + min(max(_989.x, _989.y), 0.0)) - _87);
    }
    else
    {
        _1498 = 1.0;
    }
    vec2 _803 = vec2(0.0, (GLOW_RADIUS) * (vec4(TextureSize, 1.0 / TextureSize)).w);
    vec3 _1500;
    if ((GLOW_ENABLE) > 0.5)
    {
        vec2 _1013 = _803 * 4.0;
        vec2 _1023 = _803 * 3.0;
        vec2 _1033 = _803 * 2.0;
        _1500 = ((((((((texture(Texture, _1495 - _1013).xyz * 0.001234402996487915515899658203125) + (texture(Texture, _1495 - _1023).xyz * 0.01430468820035457611083984375)) + (texture(Texture, _1495 - _1033).xyz * 0.0823177993297576904296875)) + (texture(Texture, _1495 - _803).xyz * 0.2352355420589447021484375)) + (texture(Texture, _1495).xyz * 0.3338151276111602783203125)) + (texture(Texture, _1495 + _803).xyz * 0.2352355420589447021484375)) + (texture(Texture, _1495 + _1033).xyz * 0.0823177993297576904296875)) + (texture(Texture, _1495 + _1023).xyz * 0.01430468820035457611083984375)) + (texture(Texture, _1495 + _1013).xyz * 0.001234402996487915515899658203125);
    }
    else
    {
        _1500 = vec3(0.0);
    }
    vec2 _825 = RA_VARYING_0 * (vec4(OutputSize, 1.0 / OutputSize)).xy;
    vec2 _833 = mix(_825, _825.yx, vec2((VSCANLINES)));
    vec3 _1506;
    do
    {
        if (RA_VARYING_1.x > 14.0)
        {
            vec3 _1639;
            if (RA_VARYING_1.x == 15.0)
            {
                float _1388 = _833.x;
                float _1406 = fract(_1388 * 0.3333333432674407958984375);
                vec3 _1637;
                if (_1406 < 0.333000004291534423828125)
                {
                    _1637 = vec3(0.0, 0.0, 1.0);
                }
                else
                {
                    vec3 _1638;
                    if (_1406 < 0.66600000858306884765625)
                    {
                        _1638 = vec3(0.0, 1.0, 0.0);
                    }
                    else
                    {
                        _1638 = vec3(1.0, 0.0, 0.0);
                    }
                    _1637 = _1638;
                }
                _1639 = _1637 * ((fract((_833.y + float(fract(_1388 * 0.16666667163372039794921875) < 0.5)) * 0.5) < 0.5) ? 0.0 : 1.0);
            }
            else
            {
                vec3 _1640;
                if (RA_VARYING_1.x == 16.0)
                {
                    float _1440 = fract((_833.x + (_833.y * 3.0)) * 0.16666667163372039794921875);
                    vec3 _1644;
                    if (_1440 < 0.333000004291534423828125)
                    {
                        _1644 = vec3(0.0, 0.0, 1.0);
                    }
                    else
                    {
                        vec3 _1645;
                        if (_1440 < 0.66600000858306884765625)
                        {
                            _1645 = vec3(0.0, 1.0, 0.0);
                        }
                        else
                        {
                            _1645 = vec3(1.0, 0.0, 0.0);
                        }
                        _1644 = _1645;
                    }
                    _1640 = _1644;
                }
                else
                {
                    vec3 _1641;
                    if (RA_VARYING_1.x == 17.0)
                    {
                        vec2 _1463 = floor(_833 * vec2(1.0, 0.5));
                        float _1474 = fract((_1463.x + (_1463.y * 3.0)) * 0.16666667163372039794921875);
                        vec3 _1642;
                        if (_1474 < 0.333000004291534423828125)
                        {
                            _1642 = vec3(0.0, 0.0, 1.0);
                        }
                        else
                        {
                            vec3 _1643;
                            if (_1474 < 0.66600000858306884765625)
                            {
                                _1643 = vec3(0.0, 1.0, 0.0);
                            }
                            else
                            {
                                _1643 = vec3(1.0, 0.0, 0.0);
                            }
                            _1642 = _1643;
                        }
                        _1641 = _1642;
                    }
                    else
                    {
                        _1641 = vec3(0.0);
                    }
                    _1640 = _1641;
                }
                _1639 = _1640;
            }
            _1506 = _1639;
            break;
        }
        float _1128 = _833.x;
        vec3 _1131 = vec3(floor(mod(_1128, 2.0)));
        vec3 _1132 = mix(vec3(1.0, 0.0, 1.0), vec3(0.0, 1.0, 0.0), _1131);
        if (RA_VARYING_1.x == 0.0)
        {
            _1506 = vec3(1.0);
            break;
        }
        else
        {
            if (RA_VARYING_1.x == 1.0)
            {
                _1506 = _1132;
                break;
            }
            else
            {
                if (RA_VARYING_1.x == 2.0)
                {
                    _1506 = _281[int(floor(mod(_1128, 3.0)))];
                    break;
                }
                else
                {
                    if (RA_VARYING_1.x == 3.0)
                    {
                        _1506 = _299[int(floor(mod(_1128, 3.0)))];
                        break;
                    }
                    else
                    {
                        if (RA_VARYING_1.x == 4.0)
                        {
                            _1506 = _322[int(floor(mod(_1128, 4.0)))];
                            break;
                        }
                        else
                        {
                            if (RA_VARYING_1.x == 5.0)
                            {
                                _1506 = _341[int(floor(mod(_1128, 4.0)))];
                                break;
                            }
                            else
                            {
                                if (RA_VARYING_1.x == 6.0)
                                {
                                    _1506 = _359[int(floor(mod(_1128, 4.0)))];
                                    break;
                                }
                                else
                                {
                                    if (RA_VARYING_1.x == 7.0)
                                    {
                                        _1506 = mix(_1132, mix(vec3(0.0, 1.0, 0.0), vec3(1.0, 0.0, 1.0), _1131), vec3(floor(mod(_833.y, 2.0))));
                                        break;
                                    }
                                    else
                                    {
                                        if (RA_VARYING_1.x == 8.0)
                                        {
                                            _1506 = _407[int(floor(mod(_833.y, 2.0)))][int(floor(mod(_1128, 4.0)))];
                                            break;
                                        }
                                        else
                                        {
                                            if (RA_VARYING_1.x == 9.0)
                                            {
                                                _1506 = _433[int(floor(mod(_833.y, 2.0)))][int(floor(mod(_1128, 4.0)))];
                                                break;
                                            }
                                            else
                                            {
                                                if (RA_VARYING_1.x == 10.0)
                                                {
                                                    _1506 = _458[int(floor(mod(_833.y, 4.0)))][int(floor(mod(_1128, 4.0)))];
                                                    break;
                                                }
                                                else
                                                {
                                                    if (RA_VARYING_1.x == 11.0)
                                                    {
                                                        _1506 = _489[int(floor(mod(_833.y, 4.0)))][int(floor(mod(_1128, 6.0)))];
                                                        break;
                                                    }
                                                    else
                                                    {
                                                        if (RA_VARYING_1.x == 12.0)
                                                        {
                                                            _1506 = _517[int(floor(mod(_833.y, 4.0)))][int(floor(mod(_1128, 6.0)))];
                                                            break;
                                                        }
                                                        else
                                                        {
                                                            if (RA_VARYING_1.x == 13.0)
                                                            {
                                                                _1506 = _547[int(floor(mod(_833.y, 4.0)))][int(floor(mod(_1128, 8.0)))];
                                                                break;
                                                            }
                                                            else
                                                            {
                                                                if (RA_VARYING_1.x == 14.0)
                                                                {
                                                                    _1506 = _577[int(floor(mod(_833.y, 4.0)))][int(floor(mod(_1128, 10.0)))];
                                                                    break;
                                                                }
                                                                else
                                                                {
                                                                    _1506 = vec3(1.0);
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
    vec3 _1507;
    if ((MONITOR_SUBPIXELS) > 0.5)
    {
        _1507 = _1506.zyx;
    }
    else
    {
        _1507 = _1506;
    }
    FragColor = vec4((_1507 + ((vec3(1.0) - (_1507 * 2.0)) * pow(abs(_1507 - pow(clamp((texture(Pass2Texture, _1495).xyz * (BRIGHTBOOST)) + (_1500 * (GLOW_STRENGTH)), vec3(0.0), vec3(1.0)), vec3(1.0 / (H_OUTPUT_GAMMA)))), ((_1507 * (MASK_STRENGTH)) * ((H_MaskGamma) - 1.0)) + vec3(1.0)))) * _1498, 1.0);
}


#endif
