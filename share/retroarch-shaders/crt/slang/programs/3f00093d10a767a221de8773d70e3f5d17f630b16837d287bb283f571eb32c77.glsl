// Generated from crt/shaders/crt-super-xbr/crt-custom.slang. See slang/upstream for licence/source.
#version 430
#pragma parameter CRT_HYLLIAN_SINC "[CRT-HYLLIAN-SINC PARAMS]" 0.0 0.0 0.0 0.0
#pragma parameter BEAM_MIN_WIDTH "    MIN BEAM WIDTH" 0.92 0.0 1.0 0.01
#pragma parameter BEAM_MAX_WIDTH "    MAX BEAM WIDTH" 1.0 0.0 1.0 0.01
#pragma parameter SCANLINES_STRENGTH "    SCANLINES STRENGTH" 0.72 0.0 1.0 0.01
#pragma parameter COLOR_BOOST "    COLOR BOOST" 1.25 1.0 2.0 0.05
#pragma parameter SHARPNESS_HACK "    SHARPNESS_HACK" 1.0 1.0 4.0 1.0
#pragma parameter PHOSPHOR_LAYOUT "    PHOSPHOR LAYOUT" 4.0 0.0 24.0 1.0
#pragma parameter MASK_INTENSITY "    MASK INTENSITY" 0.7 0.0 1.0 0.1
#pragma parameter VSCANLINES "    SCANLINES DIRECTION" 0.0 0.0 1.0 1.0
#pragma parameter CRT_CURVATURE "CRT-Curvature" 1.0 0.0 1.0 1.0
#pragma parameter CRT_warpX "CRT-Curvature X-Axis" 0.015 0.0 0.125 0.005
#pragma parameter CRT_warpY "CRT-Curvature Y-Axis" 0.015 0.0 0.125 0.005
#pragma parameter CRT_cornersize "CRT-Corner Size" 0.01 0.001 1.0 0.005
#pragma parameter CRT_cornersmooth "CRT-Corner Smoothness" 380.0 80.0 2080.0 100.0
#pragma parameter CRT_ANTI_RINGING "CRT Anti-Ringing [ OFF | ON ]" 0.0 0.0 1.0 1.0
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
    RA_VARYING_0 = TexCoord;
}


#endif
#ifdef FRAGMENT

uniform float BEAM_MAX_WIDTH;
uniform float BEAM_MIN_WIDTH;
uniform float COLOR_BOOST;
uniform float CRT_ANTI_RINGING;
uniform float CRT_CURVATURE;
uniform float CRT_cornersize;
uniform float CRT_cornersmooth;
uniform float CRT_warpX;
uniform float CRT_warpY;
uniform float MASK_INTENSITY;
uniform vec2 OutputSize;
uniform float PHOSPHOR_LAYOUT;
uniform float SCANLINES_STRENGTH;
uniform float SHARPNESS_HACK;
uniform vec2 TextureSize;
uniform float VSCANLINES;
struct UBO
{
    vec4 OutputSize;
    vec4 SourceSize;
};



struct Push
{
    float BEAM_MIN_WIDTH;
    float BEAM_MAX_WIDTH;
    float SCANLINES_STRENGTH;
    float COLOR_BOOST;
    float SHARPNESS_HACK;
    float PHOSPHOR_LAYOUT;
    float MASK_INTENSITY;
    float VSCANLINES;
    float CRT_ANTI_RINGING;
    float CRT_CURVATURE;
    float CRT_warpX;
    float CRT_warpY;
    float CRT_cornersize;
    float CRT_cornersmooth;
};



layout(binding = 2) uniform sampler2D Texture;

layout(location = 0) in vec2 RA_VARYING_0;
layout(location = 0) out vec4 FragColor;

void main()
{
    vec2 _1286 = vec2((VSCANLINES));
    vec2 _1287 = mix(vec2((vec4(TextureSize, 1.0 / TextureSize)).x * (SHARPNESS_HACK), (vec4(TextureSize, 1.0 / TextureSize)).y), vec2((vec4(TextureSize, 1.0 / TextureSize)).x, (vec4(TextureSize, 1.0 / TextureSize)).y * (SHARPNESS_HACK)), _1286);
    vec2 _1292 = vec2(1.0 / _1287.x, 0.0);
    vec2 _1296 = vec2(0.0, 1.0 / _1287.y);
    vec2 _1300 = mix(_1292, _1296, _1286);
    vec2 _1313 = mix(_1296, _1292, _1286);
    bool _1320 = (CRT_CURVATURE) > 0.5;
    vec2 _2988;
    if (_1320)
    {
        vec2 _1700 = (RA_VARYING_0 * 2.0) - vec2(1.0);
        float _1702 = _1700.x;
        float _1707 = _1700.y;
        float _1712 = sqrt((_1702 * _1702) + (_1707 * _1707));
        vec2 _1727 = vec2(1.0) / (vec2(1.0) + ((vec2((CRT_warpX), (CRT_warpY)) * 15.0) * 0.20000000298023223876953125));
        _2988 = ((((_1700 / vec2(_1712)) * (vec2(1.0) - pow(vec2(1.0 - (_1712 * 0.707106769084930419921875)), _1727))) / (vec2(1.0) - pow(vec2(0.292893230915069580078125), _1727))) * 0.5) + vec2(0.5);
    }
    else
    {
        _2988 = RA_VARYING_0;
    }
    vec2 _1336 = (_2988 * _1287) + vec2(-0.5, 0.5);
    vec2 _1339 = floor(_1336);
    vec2 _1353 = mix((_1339 + vec2(0.5)) / _1287, (_1339 + vec2(1.5, -0.5)) / _1287, _1286);
    vec2 _1363 = mix(fract(_1336), fract(_1336.yx), _1286);
    vec2 _1372 = _1353 - _1300;
    vec4 _1375 = texture(Texture, _1372 - _1313);
    vec4 _1382 = texture(Texture, _1353 - _1313);
    vec3 _1383 = _1382.xyz;
    vec2 _1388 = _1353 + _1300;
    vec4 _1391 = texture(Texture, _1388 - _1313);
    vec3 _1392 = _1391.xyz;
    vec2 _1398 = _1353 + (_1300 * 2.0);
    vec4 _1401 = texture(Texture, _1398 - _1313);
    vec4 _1408 = texture(Texture, _1372);
    vec4 _1413 = texture(Texture, _1353);
    vec3 _1414 = _1413.xyz;
    vec4 _1420 = texture(Texture, _1388);
    vec3 _1421 = _1420.xyz;
    vec4 _1428 = texture(Texture, _1398);
    float _1479 = _1363.x;
    float _2991;
    do
    {
        float _1771 = abs((-1.0) - _1479);
        if (_1771 < 1.0)
        {
            _2991 = ((((_1771 - 1.7999999523162841796875) * _1771) - 0.20000000298023223876953125) * _1771) + 1.0;
            break;
        }
        else
        {
            if ((_1771 >= 1.0) && (_1771 < 2.0))
            {
                float _1791 = _1771 - 1.0;
                _2991 = (((((-0.3333333432674407958984375) * _1791) + 0.800000011920928955078125) * _1791) - 0.4666666686534881591796875) * _1791;
                break;
            }
            else
            {
                _2991 = 0.0;
                break;
            }
            break; // unreachable workaround
        }
        break; // unreachable workaround
    } while(false);
    float _2993;
    do
    {
        float _1812 = abs(-_1479);
        if (_1812 < 1.0)
        {
            _2993 = ((((_1812 - 1.7999999523162841796875) * _1812) - 0.20000000298023223876953125) * _1812) + 1.0;
            break;
        }
        else
        {
            if ((_1812 >= 1.0) && (_1812 < 2.0))
            {
                float _1832 = _1812 - 1.0;
                _2993 = (((((-0.3333333432674407958984375) * _1832) + 0.800000011920928955078125) * _1832) - 0.4666666686534881591796875) * _1832;
                break;
            }
            else
            {
                _2993 = 0.0;
                break;
            }
            break; // unreachable workaround
        }
        break; // unreachable workaround
    } while(false);
    float _2995;
    do
    {
        float _1853 = abs(1.0 - _1479);
        if (_1853 < 1.0)
        {
            _2995 = ((((_1853 - 1.7999999523162841796875) * _1853) - 0.20000000298023223876953125) * _1853) + 1.0;
            break;
        }
        else
        {
            if ((_1853 >= 1.0) && (_1853 < 2.0))
            {
                float _1873 = _1853 - 1.0;
                _2995 = (((((-0.3333333432674407958984375) * _1873) + 0.800000011920928955078125) * _1873) - 0.4666666686534881591796875) * _1873;
                break;
            }
            else
            {
                _2995 = 0.0;
                break;
            }
            break; // unreachable workaround
        }
        break; // unreachable workaround
    } while(false);
    float _2997;
    do
    {
        float _1894 = abs(2.0 - _1479);
        if (_1894 < 1.0)
        {
            _2997 = ((((_1894 - 1.7999999523162841796875) * _1894) - 0.20000000298023223876953125) * _1894) + 1.0;
            break;
        }
        else
        {
            if ((_1894 >= 1.0) && (_1894 < 2.0))
            {
                float _1914 = _1894 - 1.0;
                _2997 = (((((-0.3333333432674407958984375) * _1914) + 0.800000011920928955078125) * _1914) - 0.4666666686534881591796875) * _1914;
                break;
            }
            else
            {
                _2997 = 0.0;
                break;
            }
            break; // unreachable workaround
        }
        break; // unreachable workaround
    } while(false);
    vec4 _1764 = vec4(_2991, _2993, _2995, _2997);
    vec3 _1490 = vec3(dot(_1764, vec4(1.0)));
    vec3 _1491 = (mat4x3(vec3(_1375.xyz), vec3(_1382.xyz), vec3(_1391.xyz), vec3(_1401.xyz)) * _1764) / _1490;
    vec3 _1499 = (mat4x3(vec3(_1408.xyz), vec3(_1413.xyz), vec3(_1420.xyz), vec3(_1428.xyz)) * _1764) / _1490;
    vec3 _1536 = mix(_1491, clamp(_1491, min(_1383, _1392), max(_1383, _1392)), step(vec3(0.0), (_1375.xyz - _1383) * (_1392 - _1401.xyz)) * (CRT_ANTI_RINGING));
    vec3 _1556 = mix(_1499, clamp(_1499, min(_1414, _1421), max(_1414, _1421)), step(vec3(0.0), (_1408.xyz - _1414) * (_1421 - _1428.xyz)) * (CRT_ANTI_RINGING));
    float _1559 = _1363.y;
    vec3 _1567 = vec3((BEAM_MIN_WIDTH));
    vec3 _1570 = vec3((BEAM_MAX_WIDTH));
    vec3 _1572 = mix(_1567, _1570, _1536);
    vec3 _1581 = mix(_1567, _1570, _1556);
    float _1585 = 2.0 * (SCANLINES_STRENGTH);
    vec3 _1598 = clamp(vec3(_1585 * _1559) / ((_1572 * _1572) + vec3(1.0000000116860974230803549289703e-07)), vec3(0.0), vec3(1.0));
    vec3 _1614 = clamp(vec3(_1585 * (1.0 - _1559)) / ((_1581 * _1581) + vec3(1.0000000116860974230803549289703e-07)), vec3(0.0), vec3(1.0));
    float _1936 = _1598.x;
    float _3038;
    if (_1936 <= 0.001000000047497451305389404296875)
    {
        _3038 = 4.93480205535888671875;
    }
    else
    {
        _3038 = (sin(_1936 * 1.57079637050628662109375) * sin(_1936 * 3.1415927410125732421875)) / (_1936 * _1936);
    }
    float _1959 = _1598.y;
    float _3039;
    if (_1959 <= 0.001000000047497451305389404296875)
    {
        _3039 = 4.93480205535888671875;
    }
    else
    {
        _3039 = (sin(_1959 * 1.57079637050628662109375) * sin(_1959 * 3.1415927410125732421875)) / (_1959 * _1959);
    }
    float _1982 = _1598.z;
    float _3040;
    if (_1982 <= 0.001000000047497451305389404296875)
    {
        _3040 = 4.93480205535888671875;
    }
    else
    {
        _3040 = (sin(_1982 * 1.57079637050628662109375) * sin(_1982 * 3.1415927410125732421875)) / (_1982 * _1982);
    }
    float _2012 = _1614.x;
    float _3044;
    if (_2012 <= 0.001000000047497451305389404296875)
    {
        _3044 = 4.93480205535888671875;
    }
    else
    {
        _3044 = (sin(_2012 * 1.57079637050628662109375) * sin(_2012 * 3.1415927410125732421875)) / (_2012 * _2012);
    }
    float _2035 = _1614.y;
    float _3045;
    if (_2035 <= 0.001000000047497451305389404296875)
    {
        _3045 = 4.93480205535888671875;
    }
    else
    {
        _3045 = (sin(_2035 * 1.57079637050628662109375) * sin(_2035 * 3.1415927410125732421875)) / (_2035 * _2035);
    }
    float _2058 = _1614.z;
    float _3046;
    if (_2058 <= 0.001000000047497451305389404296875)
    {
        _3046 = 4.93480205535888671875;
    }
    else
    {
        _3046 = (sin(_2058 * 1.57079637050628662109375) * sin(_2058 * 3.1415927410125732421875)) / (_2058 * _2058);
    }
    vec2 _1640 = RA_VARYING_0 * (vec4(OutputSize, 1.0 / OutputSize)).xy;
    vec2 _1647 = mix(_1640, _1640.yx, _1286);
    int _1650 = int((PHOSPHOR_LAYOUT));
    vec3 _3062;
    do
    {
        float _2123 = 1.0 - (MASK_INTENSITY);
        vec3 _2126 = vec3(1.0, _2123, _2123);
        vec3 _2130 = vec3(_2123, 1.0, _2123);
        vec3 _2133 = vec3(_2123, _2123, 1.0);
        vec3 _2137 = vec3(1.0, _2123, 1.0);
        vec3 _2140 = vec3(1.0, 1.0, _2123);
        vec3 _2143 = vec3(_2123, 1.0, 1.0);
        vec3 _2145 = vec3(_2123);
        float _2151 = _1647.x;
        vec3 _2154 = vec3(floor(mod(_2151, 2.0)));
        vec3 _2155 = mix(_2137, _2130, _2154);
        if (_1650 == 0)
        {
            _3062 = vec3(1.0);
            break;
        }
        else
        {
            if (_1650 == 1)
            {
                _3062 = _2155;
                break;
            }
            else
            {
                if (_1650 == 2)
                {
                    _3062 = mix(_2155, mix(_2130, _2137, _2154), vec3(floor(mod(_1647.y, 2.0))));
                    break;
                }
                else
                {
                    if (_1650 == 3)
                    {
                        vec3 _2097[3][4] = vec3[][](vec3[](_2137, _2130, _2145, _2145), vec3[](_2137, _2130, _2137, _2130), vec3[](_2145, _2145, _2137, _2130));
                        _3062 = _2097[int(floor(mod(_1647.y, 3.0)))][int(floor(mod(_2151, 4.0)))];
                        break;
                    }
                    else
                    {
                        if (_1650 == 4)
                        {
                            _3062 = mix(_2140, _2133, _2154);
                            break;
                        }
                        else
                        {
                            if (_1650 == 5)
                            {
                                _3062 = mix(mix(_2140, _2133, _2154), mix(_2133, _2140, _2154), vec3(floor(mod(_1647.y, 2.0))));
                                break;
                            }
                            else
                            {
                                if (_1650 == 6)
                                {
                                    vec3 _2100[4] = vec3[](_2126, _2130, _2133, _2145);
                                    _3062 = _2100[int(floor(mod(_2151, 4.0)))];
                                    break;
                                }
                                else
                                {
                                    if (_1650 == 7)
                                    {
                                        vec3 _2101[5] = vec3[](_2126, _2137, _2133, _2130, _2130);
                                        _3062 = _2101[int(floor(mod(_2151, 5.0)))];
                                        break;
                                    }
                                    else
                                    {
                                        if (_1650 == 8)
                                        {
                                            vec3 _2102[7] = vec3[](_2126, _2126, _2140, _2130, _2143, _2133, _2133);
                                            _3062 = _2102[int(floor(mod(_2151, 7.0)))];
                                            break;
                                        }
                                        else
                                        {
                                            if (_1650 == 9)
                                            {
                                                vec3 _2103[4] = vec3[](_2126, _2140, _2143, _2133);
                                                _3062 = _2103[int(floor(mod(_2151, 4.0)))];
                                                break;
                                            }
                                            else
                                            {
                                                if (_1650 == 10)
                                                {
                                                    vec3 _2104[4] = vec3[](_2126, _2137, _2143, _2130);
                                                    _3062 = _2104[int(floor(mod(_2151, 4.0)))];
                                                    break;
                                                }
                                                else
                                                {
                                                    if (_1650 == 11)
                                                    {
                                                        vec3 _2105[2][4] = vec3[][](vec3[](_2126, _2130, _2133, _2145), vec3[](_2133, _2145, _2126, _2130));
                                                        _3062 = _2105[int(floor(mod(_1647.y, 2.0)))][int(floor(mod(_2151, 4.0)))];
                                                        break;
                                                    }
                                                    else
                                                    {
                                                        if (_1650 == 12)
                                                        {
                                                            vec3 _2106[2][4] = vec3[][](vec3[](_2126, _2140, _2143, _2133), vec3[](_2143, _2133, _2126, _2140));
                                                            _3062 = _2106[int(floor(mod(_1647.y, 2.0)))][int(floor(mod(_2151, 4.0)))];
                                                            break;
                                                        }
                                                        else
                                                        {
                                                            if (_1650 == 13)
                                                            {
                                                                vec3 _2420[4] = vec3[](_2126, _2140, _2143, _2133);
                                                                vec3 _2430[4] = vec3[](_2143, _2133, _2126, _2140);
                                                                vec3 _2107[4][4] = vec3[][](_2420, _2420, _2430, _2430);
                                                                _3062 = _2107[int(floor(mod(_1647.y, 4.0)))][int(floor(mod(_2151, 4.0)))];
                                                                break;
                                                            }
                                                            else
                                                            {
                                                                if (_1650 == 14)
                                                                {
                                                                    vec3 _2108[3][6] = vec3[][](vec3[](_2137, _2130, _2145, _2145, _2145, _2145), vec3[](_2137, _2130, _2145, _2137, _2130, _2145), vec3[](_2145, _2145, _2145, _2137, _2130, _2145));
                                                                    _3062 = _2108[int(floor(mod(_1647.y, 3.0)))][int(floor(mod(_2151, 6.0)))];
                                                                    break;
                                                                }
                                                                else
                                                                {
                                                                    if (_1650 == 15)
                                                                    {
                                                                        vec3 _2500[8] = vec3[](_2126, _2140, _2143, _2133, _2126, _2140, _2143, _2133);
                                                                        vec3 _2109[4][8] = vec3[][](_2500, vec3[](_2126, _2140, _2143, _2133, _2145, _2145, _2145, _2145), _2500, vec3[](_2145, _2145, _2145, _2145, _2126, _2140, _2143, _2133));
                                                                        _3062 = _2109[int(floor(mod(_1647.y, 4.0)))][int(floor(mod(_2151, 8.0)))];
                                                                        break;
                                                                    }
                                                                    else
                                                                    {
                                                                        if (_1650 == 16)
                                                                        {
                                                                            vec3 _2110[3][4] = vec3[][](vec3[](_2140, _2133, _2145, _2145), vec3[](_2140, _2133, _2140, _2133), vec3[](_2145, _2145, _2140, _2133));
                                                                            _3062 = _2110[int(floor(mod(_1647.y, 3.0)))][int(floor(mod(_2151, 4.0)))];
                                                                            break;
                                                                        }
                                                                        else
                                                                        {
                                                                            if (_1650 == 17)
                                                                            {
                                                                                vec3 _2583[10] = vec3[](_2126, _2137, _2133, _2130, _2130, _2126, _2137, _2133, _2130, _2130);
                                                                                vec3 _2111[4][10] = vec3[][](_2583, vec3[](_2145, _2133, _2133, _2130, _2130, _2126, _2126, _2145, _2145, _2145), _2583, vec3[](_2126, _2126, _2145, _2145, _2145, _2145, _2133, _2133, _2130, _2130));
                                                                                _3062 = _2111[int(floor(mod(_1647.y, 4.0)))][int(floor(mod(_2151, 10.0)))];
                                                                                break;
                                                                            }
                                                                            else
                                                                            {
                                                                                if (_1650 == 18)
                                                                                {
                                                                                    vec3 _2632[10] = vec3[](_2126, _2140, _2130, _2133, _2133, _2126, _2140, _2130, _2133, _2133);
                                                                                    vec3 _2112[4][10] = vec3[][](_2632, vec3[](_2145, _2130, _2130, _2133, _2133, _2126, _2126, _2145, _2145, _2145), _2632, vec3[](_2126, _2126, _2145, _2145, _2145, _2145, _2130, _2130, _2133, _2133));
                                                                                    _3062 = _2112[int(floor(mod(_1647.y, 4.0)))][int(floor(mod(_2151, 10.0)))];
                                                                                    break;
                                                                                }
                                                                                else
                                                                                {
                                                                                    if (_1650 == 19)
                                                                                    {
                                                                                        vec3 _2683[14] = vec3[](_2126, _2126, _2140, _2130, _2143, _2133, _2133, _2126, _2126, _2140, _2130, _2143, _2133, _2133);
                                                                                        vec3 _2113[6][14] = vec3[][](_2683, _2683, vec3[](_2126, _2126, _2140, _2130, _2143, _2133, _2133, _2145, _2145, _2145, _2145, _2145, _2145, _2145), _2683, _2683, vec3[](_2145, _2145, _2145, _2145, _2145, _2145, _2145, _2145, _2126, _2126, _2140, _2130, _2143, _2133));
                                                                                        _3062 = _2113[int(floor(mod(_1647.y, 6.0)))][int(floor(mod(_2151, 14.0)))];
                                                                                        break;
                                                                                    }
                                                                                    else
                                                                                    {
                                                                                        if (_1650 == 20)
                                                                                        {
                                                                                            vec3 _2755[4] = vec3[](_2130, _2137, _2130, _2137);
                                                                                            vec3 _2114[4][4] = vec3[][](_2755, vec3[](_2145, _2133, _2130, _2126), _2755, vec3[](_2130, _2126, _2145, _2133));
                                                                                            _3062 = _2114[int(floor(mod(_1647.y, 4.0)))][int(floor(mod(_2151, 4.0)))];
                                                                                            break;
                                                                                        }
                                                                                        else
                                                                                        {
                                                                                            if (_1650 == 21)
                                                                                            {
                                                                                                vec3 _2799[8] = vec3[](_2126, _2130, _2133, _2145, _2126, _2130, _2133, _2145);
                                                                                                vec3 _2115[4][8] = vec3[][](_2799, vec3[](_2126, _2130, _2133, _2145, _2145, _2145, _2145, _2145), _2799, vec3[](_2145, _2145, _2145, _2145, _2126, _2130, _2133, _2145));
                                                                                                _3062 = _2115[int(floor(mod(_1647.y, 4.0)))][int(floor(mod(_2151, 8.0)))];
                                                                                                break;
                                                                                            }
                                                                                            else
                                                                                            {
                                                                                                if (_1650 == 22)
                                                                                                {
                                                                                                    vec3 _2116[3] = vec3[](_2145, vec3(1.0), vec3(1.0));
                                                                                                    _3062 = _2116[int(floor(mod(_2151, 3.0)))];
                                                                                                    break;
                                                                                                }
                                                                                                else
                                                                                                {
                                                                                                    if (_1650 == 23)
                                                                                                    {
                                                                                                        vec3 _2117[4] = vec3[](_2145, _2145, vec3(1.0), vec3(1.0));
                                                                                                        _3062 = _2117[int(floor(mod(_2151, 4.0)))];
                                                                                                        break;
                                                                                                    }
                                                                                                    else
                                                                                                    {
                                                                                                        if (_1650 == 24)
                                                                                                        {
                                                                                                            vec3 _2878[10] = vec3[](_2130, _2143, _2133, _2133, _2133, _2126, _2126, _2126, _2140, _2130);
                                                                                                            vec3 _2898[10] = vec3[](_2126, _2126, _2126, _2140, _2130, _2130, _2143, _2133, _2133, _2133);
                                                                                                            vec3 _2118[6][10] = vec3[][](_2878, _2878, _2878, _2898, _2898, _2898);
                                                                                                            _3062 = _2118[int(floor(mod(_1647.y, 6.0)))][int(floor(mod(_2151, 10.0)))];
                                                                                                            break;
                                                                                                        }
                                                                                                        else
                                                                                                        {
                                                                                                            _3062 = vec3(1.0);
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
    FragColor = vec4(((((_1536 * vec3(_3038, _3039, _3040)) + (_1556 * vec3(_3044, _3045, _3046))) * (COLOR_BOOST)) * vec3(0.20264236629009246826171875)) * _3062, 1.0);
    float _3075;
    if (_1320)
    {
        vec2 _2970 = vec2((CRT_cornersize));
        vec2 _2975 = _2970 - min(min(_2988, vec2(1.0) - _2988) * vec2(1.0, 0.75), _2970);
        _3075 = clamp(((CRT_cornersize) - sqrt(dot(_2975, _2975))) * (CRT_cornersmooth), 0.0, 1.0);
    }
    else
    {
        _3075 = 1.0;
    }
    FragColor *= _3075;
}


#endif
