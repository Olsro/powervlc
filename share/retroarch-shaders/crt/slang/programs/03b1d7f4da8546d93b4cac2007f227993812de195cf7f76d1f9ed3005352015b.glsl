// Generated from crt/shaders/crt-nobody.slang. See slang/upstream for licence/source.
#version 430
#pragma parameter CN_NONONO          "** CRT-NOBODY **"               0.0  0.0 0.0 1.0
#pragma parameter NO_NONONO          " "                              0.0  0.0 0.0 1.0
#pragma parameter col_nonono         "COLOR SETTINGS:"                0.0  0.0 0.0 1.0
#pragma parameter CN_InputGamma      "    Input Gamma"                2.4  0.0 4.0 0.1
#pragma parameter CN_OutputGamma     "    Output Gamma"               2.2  0.0 3.0 0.1
#pragma parameter CN_BRIGHTBOOST     "    Brightness Boost"           1.0  0.5 1.5 0.01
#pragma parameter CN_VIG_TOGGLE      "    Vignette Toggle"            0.0  0.0 1.0 1.0
#pragma parameter CN_VIG_BASE        "        Vignette Range"        48.0  2.0 100.0 2.0
#pragma parameter CN_VIG_EXP         "        Vignette Strength"      0.16  0.0 2.0 0.02
#pragma parameter scan_nonono        "SCANLINES SETTINGS:"           0.0  0.0 0.0 1.0
#pragma parameter CN_BEAM_MIN_WIDTH  "    Min Beam Width"           0.80 0.0 1.0 0.01
#pragma parameter CN_BEAM_MAX_WIDTH  "    Max Beam Width"           1.0  0.0 1.0 0.01
#pragma parameter CN_SCAN_SIZE       "    Scanlines Thickness"      0.86 0.0 1.0 0.01
#pragma parameter CN_VSCANLINES      "    Orientation [ HORIZONTAL, VERTICAL ]"    0.0 0.0 1.0 1.0
#pragma parameter msk_nonono           "MASK SETTINGS:"               0.0 0.0  0.0 1.0
#pragma parameter CN_PHOSPHOR_LAYOUT   "    Mask [1-6 APERT, 7-10 DOT, 11-14 SLOT, 15-17 LOTTES]" 1.0 0.0 17.0 1.0
#pragma parameter CN_MASK_STRENGTH     "    Mask Strength"            1.0 0.0 1.0 0.02
#pragma parameter CN_MaskGamma         "    Mask Gamma"               2.4 1.0 5.0 0.1
#pragma parameter CN_MONITOR_SUBPIXELS "    Monitor Subpixels Layout [ RGB, BGR ]" 0.0 0.0 1.0 1.0
#pragma parameter scl_nonono        "SCALING SETTINGS:"                 0.0 0.0    0.0 1.0
#pragma parameter fr_zoom           "    Zoom %"                      100.0 20.0 200.0 1.0
#pragma parameter fr_scale_x        "    Scale X%"                    100.0 20.0 200.0 0.2
#pragma parameter fr_scale_y        "    Scale Y%"                    100.0 20.0 200.0 0.2
#pragma parameter fr_center_x       "    Center X"                     0.0 -100.0 100.0 0.1
#pragma parameter fr_center_y       "    Center Y"                     0.0 -100.0 100.0 0.1
#pragma parameter h_nonono        "CURVATURE SETTINGS:"                  0.0  0.0 0.0 1.0
#pragma parameter h_curvature     "    Curvature Toggle"                 1.0 0.0 1.0 1.0
#pragma parameter h_shape         "        Shape [ SPHERE, CYLINDER ]"   0.0 0.0 1.0 1.0
#pragma parameter h_radius        "        Curvature Radius"             6.0 1.0 10.0 0.1
#pragma parameter h_cornersize    "        Corner Size"                  0.04 0.01 1.0 0.01
#pragma parameter h_cornersmooth  "        Corner Smoothness"            0.5 0.1 1.0 0.1
#pragma parameter h_angle_x       "        Angle X"                      0.0 -1.0 1.0 0.001
#pragma parameter h_angle_y       "        Angle Y"                      0.0 -1.0 1.0 0.001
#pragma parameter h_overscan_x    "        Curved Overscan X%"         100.0 20.0 200.0 0.2
#pragma parameter h_overscan_y    "        Curved Overscan Y%"         100.0 20.0 200.0 0.2
#ifdef VERTEX

uniform int FrameCount;
uniform mat4 MVPMatrix;
uniform vec2 TextureSize;
uniform float fr_center_x;
uniform float fr_center_y;
uniform float fr_scale_x;
uniform float fr_scale_y;
uniform float fr_zoom;
uniform float h_curvature;
struct UBO
{
    mat4 MVP;
    vec4 SourceSize;
    uint FrameCount;
};



struct Push
{
    float fr_zoom;
    float fr_scale_x;
    float fr_scale_y;
    float fr_center_x;
    float fr_center_y;
    float h_curvature;
};



layout(location = 0) in vec4 VertexCoord;
layout(location = 1) in vec2 TexCoord;
layout(location = 0) out vec2 RA_VARYING_0;
layout(location = 1) out vec4 RA_VARYING_1;

void main()
{
    gl_Position = (MVPMatrix) * VertexCoord;
    RA_VARYING_0 = (vec2(0.5) + (((TexCoord * vec2(1.00000095367431640625)) - vec2(0.5)) / ((vec2((fr_scale_x), (fr_scale_y)) * (fr_zoom)) * vec2(9.9999997473787516355514526367188e-05)))) - (vec2((fr_center_x), (fr_center_y)) * vec2(0.00999999977648258209228515625));
    RA_VARYING_0 = mix(RA_VARYING_0, (RA_VARYING_0 * 2.0) - vec2(1.0), vec2((h_curvature)));
    vec4 _237 = vec4((vec4(TextureSize, 1.0 / TextureSize)).y, (vec4(TextureSize, 1.0 / TextureSize)).w, 0.5, 0.0);
    bool _240 = (vec4(TextureSize, 1.0 / TextureSize)).y > 288.5;
    bool _246;
    if (_240)
    {
        _246 = (vec4(TextureSize, 1.0 / TextureSize)).y < 576.5;
    }
    else
    {
        _246 = _240;
    }
    vec4 _293;
    if (_246)
    {
        float _251 = mod(float((uint(FrameCount))), 2.0);
        vec2 _254 = _237.xy * vec2(0.5, 2.0);
        float _256 = _254.x;
        vec4 _281 = _237;
        _281.x = _256;
        _281.y = _254.y;
        _293 = vec4(_256, _254.y, _281.zw + (vec2(_251 - 0.5, _251) * 0.5));
    }
    else
    {
        _293 = _237;
    }
    RA_VARYING_1 = _293;
}


#endif
#ifdef FRAGMENT

uniform float CN_BEAM_MAX_WIDTH;
uniform float CN_BEAM_MIN_WIDTH;
uniform float CN_BRIGHTBOOST;
uniform float CN_InputGamma;
uniform float CN_MASK_STRENGTH;
uniform float CN_MONITOR_SUBPIXELS;
uniform float CN_MaskGamma;
uniform float CN_OutputGamma;
uniform float CN_PHOSPHOR_LAYOUT;
uniform float CN_SCAN_SIZE;
uniform float CN_VIG_BASE;
uniform float CN_VIG_EXP;
uniform float CN_VIG_TOGGLE;
uniform float CN_VSCANLINES;
uniform vec2 OutputSize;
uniform vec2 TextureSize;
uniform float fr_scale_x;
uniform float fr_scale_y;
uniform float fr_zoom;
uniform float h_angle_x;
uniform float h_angle_y;
uniform float h_cornersize;
uniform float h_cornersmooth;
uniform float h_curvature;
uniform float h_overscan_x;
uniform float h_overscan_y;
uniform float h_radius;
uniform float h_shape;
const vec3 _336[3] = vec3[](vec3(0.0, 0.0, 1.0), vec3(0.0, 1.0, 0.0), vec3(1.0, 0.0, 0.0));
const vec3 _354[3] = vec3[](vec3(0.0), vec3(1.0), vec3(0.0));
const vec3 _377[4] = vec3[](vec3(0.0, 0.0, 1.0), vec3(0.0, 1.0, 1.0), vec3(1.0, 1.0, 0.0), vec3(1.0, 0.0, 0.0));
const vec3 _396[4] = vec3[](vec3(0.0), vec3(0.0), vec3(1.0), vec3(1.0));
const vec3 _414[4] = vec3[](vec3(0.0, 0.0, 1.0), vec3(0.0, 1.0, 0.0), vec3(1.0, 0.0, 0.0), vec3(0.0));
const vec3 _462[2][4] = vec3[][](vec3[](vec3(0.0, 0.0, 1.0), vec3(0.0, 1.0, 1.0), vec3(1.0, 1.0, 0.0), vec3(1.0, 0.0, 0.0)), vec3[](vec3(1.0, 1.0, 0.0), vec3(1.0, 0.0, 0.0), vec3(0.0, 0.0, 1.0), vec3(0.0, 1.0, 1.0)));
const vec3 _488[2][4] = vec3[][](vec3[](vec3(0.0, 0.0, 1.0), vec3(0.0, 1.0, 0.0), vec3(1.0, 0.0, 0.0), vec3(0.0)), vec3[](vec3(1.0, 0.0, 0.0), vec3(0.0), vec3(0.0, 0.0, 1.0), vec3(0.0, 1.0, 0.0)));
const vec3 _513[4][4] = vec3[][](vec3[](vec3(0.0, 0.0, 1.0), vec3(0.0, 1.0, 1.0), vec3(1.0, 1.0, 0.0), vec3(1.0, 0.0, 0.0)), vec3[](vec3(0.0, 0.0, 1.0), vec3(0.0, 1.0, 1.0), vec3(1.0, 1.0, 0.0), vec3(1.0, 0.0, 0.0)), vec3[](vec3(1.0, 1.0, 0.0), vec3(1.0, 0.0, 0.0), vec3(0.0, 0.0, 1.0), vec3(0.0, 1.0, 1.0)), vec3[](vec3(1.0, 1.0, 0.0), vec3(1.0, 0.0, 0.0), vec3(0.0, 0.0, 1.0), vec3(0.0, 1.0, 1.0)));
const vec3 _544[4][6] = vec3[][](vec3[](vec3(0.0, 0.0, 1.0), vec3(0.0, 1.0, 0.0), vec3(1.0, 0.0, 0.0), vec3(0.0, 0.0, 1.0), vec3(0.0, 1.0, 0.0), vec3(1.0, 0.0, 0.0)), vec3[](vec3(0.0, 0.0, 1.0), vec3(0.0, 1.0, 0.0), vec3(1.0, 0.0, 0.0), vec3(0.0), vec3(0.0), vec3(0.0)), vec3[](vec3(0.0, 0.0, 1.0), vec3(0.0, 1.0, 0.0), vec3(1.0, 0.0, 0.0), vec3(0.0, 0.0, 1.0), vec3(0.0, 1.0, 0.0), vec3(1.0, 0.0, 0.0)), vec3[](vec3(0.0), vec3(0.0), vec3(0.0), vec3(0.0, 0.0, 1.0), vec3(0.0, 1.0, 0.0), vec3(1.0, 0.0, 0.0)));
const vec3 _572[4][6] = vec3[][](vec3[](vec3(0.0), vec3(1.0), vec3(0.0), vec3(0.0), vec3(1.0), vec3(0.0)), vec3[](vec3(0.0), vec3(1.0), vec3(0.0), vec3(0.0), vec3(0.0), vec3(0.0)), vec3[](vec3(0.0), vec3(1.0), vec3(0.0), vec3(0.0), vec3(1.0), vec3(0.0)), vec3[](vec3(0.0), vec3(0.0), vec3(0.0), vec3(0.0), vec3(1.0), vec3(0.0)));
const vec3 _602[4][8] = vec3[][](vec3[](vec3(0.0, 0.0, 1.0), vec3(0.0, 1.0, 0.0), vec3(1.0, 0.0, 0.0), vec3(0.0), vec3(0.0, 0.0, 1.0), vec3(0.0, 1.0, 0.0), vec3(1.0, 0.0, 0.0), vec3(0.0)), vec3[](vec3(0.0, 0.0, 1.0), vec3(0.0, 1.0, 0.0), vec3(1.0, 0.0, 0.0), vec3(0.0), vec3(0.0), vec3(0.0), vec3(0.0), vec3(0.0)), vec3[](vec3(0.0, 0.0, 1.0), vec3(0.0, 1.0, 0.0), vec3(1.0, 0.0, 0.0), vec3(0.0), vec3(0.0, 0.0, 1.0), vec3(0.0, 1.0, 0.0), vec3(1.0, 0.0, 0.0), vec3(0.0)), vec3[](vec3(0.0), vec3(0.0), vec3(0.0), vec3(0.0), vec3(0.0, 0.0, 1.0), vec3(0.0, 1.0, 0.0), vec3(1.0, 0.0, 0.0), vec3(0.0)));
const vec3 _632[4][10] = vec3[][](vec3[](vec3(0.0, 0.0, 1.0), vec3(0.0, 1.0, 1.0), vec3(0.0, 1.0, 0.0), vec3(1.0, 0.0, 0.0), vec3(1.0, 0.0, 0.0), vec3(0.0, 0.0, 1.0), vec3(0.0, 1.0, 1.0), vec3(0.0, 1.0, 0.0), vec3(1.0, 0.0, 0.0), vec3(1.0, 0.0, 0.0)), vec3[](vec3(0.0), vec3(0.0, 1.0, 0.0), vec3(0.0, 1.0, 0.0), vec3(1.0, 0.0, 0.0), vec3(1.0, 0.0, 0.0), vec3(0.0, 0.0, 1.0), vec3(0.0, 0.0, 1.0), vec3(0.0), vec3(0.0), vec3(0.0)), vec3[](vec3(0.0, 0.0, 1.0), vec3(0.0, 1.0, 1.0), vec3(0.0, 1.0, 0.0), vec3(1.0, 0.0, 0.0), vec3(1.0, 0.0, 0.0), vec3(0.0, 0.0, 1.0), vec3(0.0, 1.0, 1.0), vec3(0.0, 1.0, 0.0), vec3(1.0, 0.0, 0.0), vec3(1.0, 0.0, 0.0)), vec3[](vec3(0.0, 0.0, 1.0), vec3(0.0, 0.0, 1.0), vec3(0.0), vec3(0.0), vec3(0.0), vec3(0.0), vec3(0.0, 1.0, 0.0), vec3(0.0, 1.0, 0.0), vec3(1.0, 0.0, 0.0), vec3(1.0, 0.0, 0.0)));

struct UBO
{
    vec4 SourceSize;
    vec4 OutputSize;
};



struct Push
{
    float CN_VSCANLINES;
    float CN_BEAM_MIN_WIDTH;
    float CN_BEAM_MAX_WIDTH;
    float CN_SCAN_SIZE;
    float CN_BRIGHTBOOST;
    float CN_VIG_TOGGLE;
    float CN_VIG_BASE;
    float CN_VIG_EXP;
    float CN_PHOSPHOR_LAYOUT;
    float CN_MASK_STRENGTH;
    float CN_MONITOR_SUBPIXELS;
    float CN_InputGamma;
    float CN_OutputGamma;
    float CN_MaskGamma;
    float fr_zoom;
    float fr_scale_x;
    float fr_scale_y;
    float h_shape;
    float h_radius;
    float h_cornersize;
    float h_cornersmooth;
    float h_overscan_x;
    float h_overscan_y;
    float h_angle_x;
    float h_angle_y;
    float h_curvature;
};



layout(binding = 2) uniform sampler2D Texture;

layout(location = 0) in vec2 RA_VARYING_0;
layout(location = 1) in vec4 RA_VARYING_1;
layout(location = 0) out vec4 FragColor;

void main()
{
    float _54 = mix((CN_SCAN_SIZE), 1.11111104488372802734375, (CN_VSCANLINES));
    vec2 _112 = vec2((h_overscan_x), (h_overscan_y)) * vec2(0.00999999977648258209228515625);
    float _119 = (h_radius) * (h_radius);
    float _137 = (vec4(OutputSize, 1.0 / OutputSize)).y / (vec4(OutputSize, 1.0 / OutputSize)).x;
    vec2 _138 = vec2(1.0, _137);
    float _148 = (h_cornersize) * min(1.0, _137);
    bool _823 = (h_curvature) > 0.5;
    vec2 _1761;
    if (_823)
    {
        float _1190 = _119 + 2.0;
        float _1210 = _119 + 1.0;
        vec2 _1214 = vec2((h_radius) / sqrt(_1210), 1.0) * sqrt((_1190 - (RA_VARYING_0.x * RA_VARYING_0.x)) / (_1190 - ((2.0 * RA_VARYING_0.x) * RA_VARYING_0.x)));
        vec2 _1225 = vec2((h_radius)) / vec2(sqrt(_1210 - dot(RA_VARYING_0, RA_VARYING_0)));
        bvec2 _1254 = bvec2((h_shape) > 0.5);
        _1761 = (((RA_VARYING_0 * (vec2(_1254.x ? _1214.x : _1225.x, _1254.y ? _1214.y : _1225.y) / _112)) - (vec2((h_angle_x), (h_angle_y)) * 2.0)) * 0.5) + vec2(0.5);
    }
    else
    {
        _1761 = RA_VARYING_0;
    }
    float _1765;
    if (_823)
    {
        vec2 _1288 = abs((((_1761 * 2.0) - vec2(1.0)) * _138) * _112) - (_138 - vec2(_148));
        _1765 = smoothstep((h_cornersmooth) * 0.00999999977648258209228515625, (h_cornersmooth) * (-0.00999999977648258209228515625), (length(max(_1288, vec2(0.0))) + min(max(_1288.x, _1288.y), 0.0)) - _148) * step(0.0, fract(_1761.y));
    }
    else
    {
        _1765 = 1.0;
    }
    float _1766;
    if ((CN_VIG_TOGGLE) > 0.5)
    {
        _1766 = clamp(pow((CN_VIG_BASE) * (((_1761.x * _1761.y) * (1.0 - _1761.x)) * (1.0 - _1761.y)), (CN_VIG_EXP)), 0.0, 1.0);
    }
    else
    {
        _1766 = 1.0;
    }
    vec4 _879 = vec4((vec4(TextureSize, 1.0 / TextureSize)).x, RA_VARYING_1.x, (vec4(TextureSize, 1.0 / TextureSize)).z, RA_VARYING_1.y);
    vec2 _883 = vec2(0.5, RA_VARYING_1.z);
    vec2 _894 = (_1761 * _879.xy) - vec2(0.0, RA_VARYING_1.w);
    vec2 _902 = (floor(_894) + _883) * _879.zw;
    vec2 _907 = fract(_894) - _883;
    vec2 _910 = sign(_907);
    vec2 _912 = abs(_907);
    vec2 _924 = _910 * vec2(0.0, RA_VARYING_1.y);
    vec3 _942 = vec3((CN_InputGamma));
    vec2 _950 = _902 + (_910 * vec2((vec4(TextureSize, 1.0 / TextureSize)).z, 0.0));
    float _1007 = _912.x;
    vec2 _1335 = clamp(vec2(_1007, 1.0 - _1007) / vec2(mix(1.11111104488372802734375, (CN_SCAN_SIZE), (CN_VSCANLINES))), vec2(-1.0), vec2(1.0));
    vec2 _1340 = vec2(1.0) - (_1335 * _1335);
    vec2 _1345 = (_1340 * _1340) * _1340;
    vec3 _1020 = mat2x3(pow(texture(Texture, _902).xyz, _942) * (CN_BRIGHTBOOST), pow(texture(Texture, _950).xyz, _942) * (CN_BRIGHTBOOST)) * _1345;
    vec3 _1023 = mat2x3(pow(texture(Texture, _902 + _924).xyz, _942) * (CN_BRIGHTBOOST), pow(texture(Texture, _950 + _924).xyz, _942) * (CN_BRIGHTBOOST)) * _1345;
    vec2 _1076 = vec2((CN_VSCANLINES));
    float _1082 = _912.y;
    vec2 _1351 = clamp(vec2(_1082, 1.0 - _1082) / mix(vec2(mix((CN_BEAM_MIN_WIDTH), (CN_BEAM_MAX_WIDTH), max(_1020.x, max(_1020.y, _1020.z))), mix((CN_BEAM_MIN_WIDTH), (CN_BEAM_MAX_WIDTH), max(_1023.x, max(_1023.y, _1023.z)))) * _54, vec2(_54), _1076), vec2(-1.0), vec2(1.0));
    vec2 _1356 = vec2(1.0) - (_1351 * _1351);
    vec2 _1096 = RA_VARYING_0 * (((vec4(OutputSize, 1.0 / OutputSize)).xy * ((vec2((fr_scale_x), (fr_scale_y)) * (fr_zoom)) * vec2(9.9999997473787516355514526367188e-05))) * (1.0 - (0.5 * (h_curvature))));
    vec2 _1103 = mix(_1096, _1096.yx, _1076);
    vec3 _1781;
    do
    {
        if ((CN_PHOSPHOR_LAYOUT) > 14.0)
        {
            vec3 _1924;
            if ((CN_PHOSPHOR_LAYOUT) == 15.0)
            {
                float _1654 = _1103.x;
                float _1672 = fract(_1654 * 0.3333333432674407958984375);
                vec3 _1922;
                if (_1672 < 0.333000004291534423828125)
                {
                    _1922 = vec3(0.0, 0.0, 1.0);
                }
                else
                {
                    vec3 _1923;
                    if (_1672 < 0.66600000858306884765625)
                    {
                        _1923 = vec3(0.0, 1.0, 0.0);
                    }
                    else
                    {
                        _1923 = vec3(1.0, 0.0, 0.0);
                    }
                    _1922 = _1923;
                }
                _1924 = _1922 * ((fract((_1103.y + float(fract(_1654 * 0.16666667163372039794921875) < 0.5)) * 0.5) < 0.5) ? 0.0 : 1.0);
            }
            else
            {
                vec3 _1925;
                if ((CN_PHOSPHOR_LAYOUT) == 16.0)
                {
                    float _1706 = fract((_1103.x + (_1103.y * 3.0)) * 0.16666667163372039794921875);
                    vec3 _1929;
                    if (_1706 < 0.333000004291534423828125)
                    {
                        _1929 = vec3(0.0, 0.0, 1.0);
                    }
                    else
                    {
                        vec3 _1930;
                        if (_1706 < 0.66600000858306884765625)
                        {
                            _1930 = vec3(0.0, 1.0, 0.0);
                        }
                        else
                        {
                            _1930 = vec3(1.0, 0.0, 0.0);
                        }
                        _1929 = _1930;
                    }
                    _1925 = _1929;
                }
                else
                {
                    vec3 _1926;
                    if ((CN_PHOSPHOR_LAYOUT) == 17.0)
                    {
                        vec2 _1729 = floor(_1103 * vec2(1.0, 0.5));
                        float _1740 = fract((_1729.x + (_1729.y * 3.0)) * 0.16666667163372039794921875);
                        vec3 _1927;
                        if (_1740 < 0.333000004291534423828125)
                        {
                            _1927 = vec3(0.0, 0.0, 1.0);
                        }
                        else
                        {
                            vec3 _1928;
                            if (_1740 < 0.66600000858306884765625)
                            {
                                _1928 = vec3(0.0, 1.0, 0.0);
                            }
                            else
                            {
                                _1928 = vec3(1.0, 0.0, 0.0);
                            }
                            _1927 = _1928;
                        }
                        _1926 = _1927;
                    }
                    else
                    {
                        _1926 = vec3(0.0);
                    }
                    _1925 = _1926;
                }
                _1924 = _1925;
            }
            _1781 = _1924;
            break;
        }
        float _1394 = _1103.x;
        vec3 _1397 = vec3(floor(mod(_1394, 2.0)));
        vec3 _1398 = mix(vec3(1.0, 0.0, 1.0), vec3(0.0, 1.0, 0.0), _1397);
        if ((CN_PHOSPHOR_LAYOUT) == 0.0)
        {
            _1781 = vec3(1.0);
            break;
        }
        else
        {
            if ((CN_PHOSPHOR_LAYOUT) == 1.0)
            {
                _1781 = _1398;
                break;
            }
            else
            {
                if ((CN_PHOSPHOR_LAYOUT) == 2.0)
                {
                    _1781 = _336[int(floor(mod(_1394, 3.0)))];
                    break;
                }
                else
                {
                    if ((CN_PHOSPHOR_LAYOUT) == 3.0)
                    {
                        _1781 = _354[int(floor(mod(_1394, 3.0)))];
                        break;
                    }
                    else
                    {
                        if ((CN_PHOSPHOR_LAYOUT) == 4.0)
                        {
                            _1781 = _377[int(floor(mod(_1394, 4.0)))];
                            break;
                        }
                        else
                        {
                            if ((CN_PHOSPHOR_LAYOUT) == 5.0)
                            {
                                _1781 = _396[int(floor(mod(_1394, 4.0)))];
                                break;
                            }
                            else
                            {
                                if ((CN_PHOSPHOR_LAYOUT) == 6.0)
                                {
                                    _1781 = _414[int(floor(mod(_1394, 4.0)))];
                                    break;
                                }
                                else
                                {
                                    if ((CN_PHOSPHOR_LAYOUT) == 7.0)
                                    {
                                        _1781 = mix(_1398, mix(vec3(0.0, 1.0, 0.0), vec3(1.0, 0.0, 1.0), _1397), vec3(floor(mod(_1103.y, 2.0))));
                                        break;
                                    }
                                    else
                                    {
                                        if ((CN_PHOSPHOR_LAYOUT) == 8.0)
                                        {
                                            _1781 = _462[int(floor(mod(_1103.y, 2.0)))][int(floor(mod(_1394, 4.0)))];
                                            break;
                                        }
                                        else
                                        {
                                            if ((CN_PHOSPHOR_LAYOUT) == 9.0)
                                            {
                                                _1781 = _488[int(floor(mod(_1103.y, 2.0)))][int(floor(mod(_1394, 4.0)))];
                                                break;
                                            }
                                            else
                                            {
                                                if ((CN_PHOSPHOR_LAYOUT) == 10.0)
                                                {
                                                    _1781 = _513[int(floor(mod(_1103.y, 4.0)))][int(floor(mod(_1394, 4.0)))];
                                                    break;
                                                }
                                                else
                                                {
                                                    if ((CN_PHOSPHOR_LAYOUT) == 11.0)
                                                    {
                                                        _1781 = _544[int(floor(mod(_1103.y, 4.0)))][int(floor(mod(_1394, 6.0)))];
                                                        break;
                                                    }
                                                    else
                                                    {
                                                        if ((CN_PHOSPHOR_LAYOUT) == 12.0)
                                                        {
                                                            _1781 = _572[int(floor(mod(_1103.y, 4.0)))][int(floor(mod(_1394, 6.0)))];
                                                            break;
                                                        }
                                                        else
                                                        {
                                                            if ((CN_PHOSPHOR_LAYOUT) == 13.0)
                                                            {
                                                                _1781 = _602[int(floor(mod(_1103.y, 4.0)))][int(floor(mod(_1394, 8.0)))];
                                                                break;
                                                            }
                                                            else
                                                            {
                                                                if ((CN_PHOSPHOR_LAYOUT) == 14.0)
                                                                {
                                                                    _1781 = _632[int(floor(mod(_1103.y, 4.0)))][int(floor(mod(_1394, 10.0)))];
                                                                    break;
                                                                }
                                                                else
                                                                {
                                                                    _1781 = vec3(1.0);
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
    vec3 _1782;
    if ((CN_MONITOR_SUBPIXELS) > 0.5)
    {
        _1782 = _1781.zyx;
    }
    else
    {
        _1782 = _1781;
    }
    FragColor = vec4(pow(_1782 + ((vec3(1.0) - (_1782 * 2.0)) * pow(abs(_1782 - clamp((mat2x3(_1020, _1023) * ((_1356 * _1356) * _1356)) * _1766, vec3(0.0), vec3(1.0))), ((_1782 * (CN_MASK_STRENGTH)) * ((CN_MaskGamma) - 1.0)) + vec3(1.0))), vec3(1.0 / (CN_OutputGamma))) * _1765, _1765);
}


#endif
