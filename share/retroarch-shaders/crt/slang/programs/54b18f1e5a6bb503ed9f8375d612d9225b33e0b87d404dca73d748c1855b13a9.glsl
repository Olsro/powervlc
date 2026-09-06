// Generated from crt/shaders/crt-pocket.slang. See slang/upstream for licence/source.
#version 130
#pragma parameter bogus_geom "[ GEOMETRY ]" 0.0 0.0 0.0 0.0
#pragma parameter warpX "Curvature X" 0.03 0.00 0.20 0.01 
#pragma parameter warpY "Curvature Y" 0.05 0.00 0.20 0.01
#pragma parameter corners "Corners cut On/Off" 1.0 0.0 1.0 1.0
#pragma parameter vignette "Vignette On/Off" 1.0 0.0 1.0 1.0
#pragma parameter vign "Vignette Strength" 0.10 0.0 0.50 0.01
#pragma parameter bogus_masks "[ MASK SETTINGS ]" 0.0 0.0 0.0 0.0
#pragma parameter shadowMask "Mask Style 0:cgwg,1-4:Lottes,5:Sin,Slot2" 1.0 -1.0 6.0 1.0
#pragma parameter size "Mask Size" 1.0 1.0 2.0 1.0
#pragma parameter maskl "Mask Low" 0.9 0.0 1.0 0.05
#pragma parameter maskh "Mask High" 0.6 0.0 1.0 0.05
#pragma parameter bgr "RGB/BGR subpixels" 1.0 0.0 1.0 1.0
#pragma parameter DOTMASK_STRENGTH "CGWG Dot Mask Strength" 0.7 0.0 1.0 0.05
#pragma parameter maskDark "Lottes maskDark" 0.5 0.0 2.0 0.1
#pragma parameter maskLight "Lottes maskLight" 1.5 0.0 2.0 0.1
#pragma parameter bogus_scan "[ SCANLINE SETTINGS ]" 0.0 0.0 0.0 0.0
#pragma parameter interlace "Interlace On/Off" 1.0 0.0 1.0 1.0
#pragma parameter progress "Force 240p" 0.0 0.0 1.0 1.0  
#pragma parameter beam1 "Scanline Beam Low" 6.0 1.0 15.0 0.5
#pragma parameter beam2 "Scanline Beam High" 8.0 1.0 15.0 0.5
#pragma parameter scanline1 "Scanline Low" 1.35 0.5 3.0 0.05
#pragma parameter scanline2 "Scanline High" 1.05 0.5 3.0 0.05
#pragma parameter bogus_col "[ COLOR SETTINGS ]" 0.0 0.0 0.0 0.0
#pragma parameter ntsc "NTSC Colors" 1.0 0.0 1.0 1.0
#pragma parameter TEMP "Color Temperature in Kelvins"  6500.0 1031.0 12047.0 72.0
#pragma parameter gammaout "Gamma Out" 2.2 1.0 4.0 0.05
#pragma parameter sat "Saturation" 1.0 0.0 2.0 0.01
#pragma parameter boost1 "Boost Dark Colors" 1.45 1.0 2.0 0.05
#pragma parameter boost2 "Boost Bright Colors" 1.25 1.0 2.0 0.05
#pragma parameter gl "Glow Strength" 0.15 0.0 1.0 0.01
#pragma parameter flick "Flicker Strength" 2.0 0.0 10.0 0.1
#ifdef VERTEX

uniform mat4 MVPMatrix;
struct UBO
{
    mat4 MVP;
};



in vec4 VertexCoord;
out vec2 RA_VARYING_0;
in vec2 TexCoord;

void main()
{
    gl_Position = (MVPMatrix) * VertexCoord;
    RA_VARYING_0 = TexCoord * 1.00010001659393310546875;
}


#endif
#ifdef FRAGMENT

uniform float DOTMASK_STRENGTH;
uniform int FrameCount;
uniform vec2 OrigTextureSize;
uniform vec2 OutputSize;
uniform float TEMP;
uniform vec2 TextureSize;
uniform float beam1;
uniform float beam2;
uniform float bgr;
uniform float boost1;
uniform float boost2;
uniform float corners;
uniform float flick;
uniform float gammaout;
uniform float gl;
uniform float interlace;
uniform float maskDark;
uniform float maskLight;
uniform float maskh;
uniform float maskl;
uniform float ntsc;
uniform float progress;
uniform float sat;
uniform float scanline1;
uniform float scanline2;
uniform float shadowMask;
uniform float size;
uniform float vign;
uniform float vignette;
uniform float warpX;
uniform float warpY;
vec3 _2446;

struct UBO
{
    float DOTMASK_STRENGTH;
    float maskDark;
    float maskLight;
    float shadowMask;
    float bgr;
    float maskl;
    float maskh;
    float gl;
    float ntsc;
    float TEMP;
    float size;
};



struct Push
{
    vec4 SourceSize;
    vec4 OriginalSize;
    vec4 OutputSize;
    uint FrameCount;
    float gammaout;
    float warpX;
    float warpY;
    float vignette;
    float vign;
    float corners;
    float beam1;
    float beam2;
    float scanline1;
    float scanline2;
    float interlace;
    float progress;
    float boost1;
    float boost2;
    float sat;
    float flick;
};



uniform sampler2D Texture;

in vec2 RA_VARYING_0;
out vec4 FragColor;

void main()
{
    vec2 _1220 = (RA_VARYING_0 * 2.0) - vec2(1.0);
    float _1222 = _1220.y;
    float _1231 = _1220.x;
    vec2 _1243 = (_1220 * vec2(1.0 + ((_1222 * _1222) * (warpX)), 1.0 + ((_1231 * _1231) * (warpY)))) * 0.5;
    vec2 _1245 = _1243 + vec2(0.5);
    float _961 = _1245.y;
    float _964 = _961 * (vec4(TextureSize, 1.0 / TextureSize)).y;
    bool _977 = (vec4(OrigTextureSize, 1.0 / OrigTextureSize)).y > 400.0;
    bool _984;
    if (_977)
    {
        _984 = (interlace) == 1.0;
    }
    else
    {
        _984 = _977;
    }
    float _2141;
    if (_984)
    {
        _2141 = (sin(float((uint(FrameCount))) * 2.0) > 0.0) ? fract(0.5 + (_964 * 0.5)) : fract(((_961 - 0.5) * (vec4(TextureSize, 1.0 / TextureSize)).y) * 0.5);
    }
    else
    {
        _2141 = fract(0.5 + _964);
    }
    bool _1024;
    if (_977)
    {
        _1024 = (interlace) == 0.0;
    }
    else
    {
        _1024 = _977;
    }
    bool _1031;
    if (_1024)
    {
        _1031 = (progress) == 1.0;
    }
    else
    {
        _1031 = _1024;
    }
    float _2138;
    if (_1031)
    {
        _2138 = fract(0.5 + (_964 * 0.5));
    }
    else
    {
        _2138 = _2141;
    }
    vec2 _1268 = _1245 * (vec4(TextureSize, 1.0 / TextureSize)).xy;
    vec2 _1271 = floor(_1268) + vec2(0.5);
    vec2 _1281 = fract(_1268) - vec2(0.5);
    float _2118;
    vec3 _2119;
    vec3 _2120;
    vec3 _2121;
    _2121 = vec3(-10000000.0);
    _2120 = vec3(10000000.0);
    _2119 = vec3(0.0);
    _2118 = 0.0;
    vec3 _2234;
    vec3 _2235;
    vec3 _2250;
    float _2255;
    for (float _2117 = -2.0; _2117 < 3.0; _2121 = _2235, _2120 = _2234, _2119 = _2250, _2118 = _2255, _2117 += 1.0)
    {
        _2255 = _2118;
        _2250 = _2119;
        _2235 = _2121;
        _2234 = _2120;
        vec3 _1304;
        vec3 _1307;
        vec3 _1325;
        float _1328;
        for (float _2228 = -1.0; _2228 < 2.0; _2255 = _1328, _2250 = _1325, _2235 = _1307, _2234 = _1304, _2228 += 1.0)
        {
            vec4 _1300 = texture(Texture, (vec4(TextureSize, 1.0 / TextureSize)).zw * (_1271 + vec2(_2117, _2228)));
            vec3 _1301 = _1300.xyz;
            _1304 = min(_2234, _1301);
            _1307 = max(_2235, _1301);
            float _1311 = _2117 - _1281.x;
            float _2237;
            if (_1311 == 0.0)
            {
                _2237 = 1.0;
            }
            else
            {
                float _2236;
                if (abs(_1311) < 2.0)
                {
                    float _1376 = _1311 * 3.1415920257568359375;
                    float _1384 = _1311 * 1.57079601287841796875;
                    _2236 = (sin(_1376) / _1376) * (sin(_1384) / _1384);
                }
                else
                {
                    _2236 = 0.0;
                }
                _2237 = _2236;
            }
            float _1316 = _2228 - _1281.y;
            float _2241;
            if (_1316 == 0.0)
            {
                _2241 = 1.0;
            }
            else
            {
                float _2240;
                if (abs(_1316) < 1.0)
                {
                    float _1419 = _1316 * 3.1415920257568359375;
                    float _1423 = sin(_1419) / _1419;
                    _2240 = _1423 * _1423;
                }
                else
                {
                    _2240 = 0.0;
                }
                _2241 = _2240;
            }
            float _1320 = _2237 * _2241;
            _1325 = _2250 + (_1301 * _1320);
            _1328 = _2255 + _1320;
        }
    }
    vec3 _1344 = clamp(_2119 / vec3(_2118), _2120, _2121);
    float _1054 = dot(vec3(0.300000011920928955078125, 0.60000002384185791015625, 0.100000001490116119384765625), _1344);
    vec3 _1062 = mix(vec3(_1054), _1344, vec3((sat)));
    vec3 _2436;
    if ((ntsc) == 1.0)
    {
        _2436 = mat3(vec3(1.01429998874664306640625, -0.0164999999105930328369140625, 0.03070000000298023223876953125), vec3(0.07230000197887420654296875, 0.91250002384185791015625, 0.01730000041425228118896484375), vec3(0.01750000007450580596923828125, -0.041900001466274261474609375, 1.1101000308990478515625)) * _1062;
    }
    else
    {
        _2436 = _1062;
    }
    float _2129;
    float _2130;
    vec3 _2131;
    _2131 = vec3(0.0);
    _2130 = 0.0;
    _2129 = -2.0;
    vec3 _2226;
    float _2227;
    for (; _2129 < 3.0; _2131 = _2226, _2130 = _2227, _2129 += 1.0)
    {
        _2227 = _2130;
        _2226 = _2131;
        for (float _2222 = -2.0; _2222 < 3.0; )
        {
            float _1469 = exp(((-0.1500000059604644775390625) * _2129) * _2129) + exp(((-0.4000000059604644775390625) * _2222) * _2222);
            _2227 += _1469;
            _2226 += (texture(Texture, _1245 + (vec2(_2129, _2222) * (vec4(TextureSize, 1.0 / TextureSize)).zw)).xyz * _1469);
            _2222 += 1.0;
            continue;
        }
    }
    vec3 _1500 = _2131 / vec3(_2130);
    float _1517 = clamp((TEMP), 1000.0, 40000.0) * 0.00999999977648258209228515625;
    vec3 _2447;
    if (_1517 <= 66.0)
    {
        vec3 _2321;
        _2321.x = 1.0;
        _2321.y = clamp((0.390081584453582763671875 * log(_1517)) - 0.6318414211273193359375, 0.0, 1.0);
        _2447 = _2321;
    }
    else
    {
        float _1530 = _1517 - 60.0;
        vec3 _2325;
        _2325.x = clamp(1.29293620586395263671875 * pow(_1530, -0.133204758167266845703125), 0.0, 1.0);
        _2325.y = clamp(1.129890918731689453125 * pow(_1530, -0.075514845550060272216796875), 0.0, 1.0);
        _2447 = _2325;
    }
    vec3 _2448;
    if (_1517 >= 66.0)
    {
        vec3 _2329 = _2447;
        _2329.z = 1.0;
        _2448 = _2329;
    }
    else
    {
        vec3 _2449;
        if (_1517 <= 19.0)
        {
            vec3 _2331 = _2447;
            _2331.z = 0.0;
            _2449 = _2331;
        }
        else
        {
            vec3 _2333 = _2447;
            _2333.z = clamp((0.54320681095123291015625 * log(_1517 - 10.0)) - 1.19625413417816162109375, 0.0, 1.0);
            _2449 = _2333;
        }
        _2448 = _2449;
    }
    vec3 _1084 = (clamp(_2436, vec3(0.0), vec3(1.0)) + ((_1500 * _1500) * (gl))) * _2448;
    float _1093 = max(max(_1084.x, _1084.y), _1084.z);
    float _1594 = mix((scanline1), (scanline2), _1093);
    float _1597 = _2138 * _1594;
    float _1104 = abs(1.0 - _2138);
    float _1624 = _1104 * _1594;
    vec2 _1129 = floor(((RA_VARYING_0 * (vec4(OutputSize, 1.0 / OutputSize)).xy) / vec2((size))) + vec2(0.5));
    vec3 _2157;
    do
    {
        vec3 _1663 = vec3((maskDark));
        vec3 _2462;
        if ((shadowMask) == 0.0)
        {
            float _1670 = 1.0 - (DOTMASK_STRENGTH);
            _2157 = mix(vec3(1.0, _1670, 1.0), vec3(_1670, 1.0, _1670), vec3(floor(mod((((RA_VARYING_0.x * (vec4(TextureSize, 1.0 / TextureSize)).x) * (vec4(OutputSize, 1.0 / OutputSize)).x) / (size)) / (vec4(TextureSize, 1.0 / TextureSize)).x, 2.0))));
            break;
        }
        else
        {
            if ((shadowMask) == 1.0)
            {
                float _1703 = _1129.x;
                float _2153;
                if (fract((_1129.y + float(fract(_1703 * 0.16666667163372039794921875) < 0.5)) * 0.5) < 0.5)
                {
                    _2153 = (maskDark);
                }
                else
                {
                    _2153 = (maskLight);
                }
                float _1723 = fract(_1703 * 0.3333333432674407958984375);
                vec3 _2458;
                if (_1723 < 0.333000004291534423828125)
                {
                    vec3 _2459;
                    if ((bgr) == 1.0)
                    {
                        vec3 _2344 = _1663;
                        _2344.z = (maskLight);
                        _2459 = _2344;
                    }
                    else
                    {
                        vec3 _2346 = _1663;
                        _2346.x = (maskLight);
                        _2459 = _2346;
                    }
                    _2458 = _2459;
                }
                else
                {
                    vec3 _2460;
                    if (_1723 < 0.66600000858306884765625)
                    {
                        vec3 _2349 = _1663;
                        _2349.y = (maskLight);
                        _2460 = _2349;
                    }
                    else
                    {
                        vec3 _2461;
                        if ((bgr) == 1.0)
                        {
                            vec3 _2351 = _1663;
                            _2351.x = (maskLight);
                            _2461 = _2351;
                        }
                        else
                        {
                            vec3 _2353 = _1663;
                            _2353.z = (maskLight);
                            _2461 = _2353;
                        }
                        _2460 = _2461;
                    }
                    _2458 = _2460;
                }
                _2462 = _2458 * _2153;
            }
            else
            {
                vec3 _2463;
                if ((shadowMask) == 2.0)
                {
                    float _1775 = fract(_1129.x * 0.3333333432674407958984375);
                    vec3 _2464;
                    if (_1775 < 0.333000004291534423828125)
                    {
                        vec3 _2465;
                        if ((bgr) == 1.0)
                        {
                            vec3 _2359 = _1663;
                            _2359.z = (maskLight);
                            _2465 = _2359;
                        }
                        else
                        {
                            vec3 _2361 = _1663;
                            _2361.x = (maskLight);
                            _2465 = _2361;
                        }
                        _2464 = _2465;
                    }
                    else
                    {
                        vec3 _2466;
                        if (_1775 < 0.66600000858306884765625)
                        {
                            vec3 _2364 = _1663;
                            _2364.y = (maskLight);
                            _2466 = _2364;
                        }
                        else
                        {
                            vec3 _2467;
                            if ((bgr) == 1.0)
                            {
                                vec3 _2366 = _1663;
                                _2366.x = (maskLight);
                                _2467 = _2366;
                            }
                            else
                            {
                                vec3 _2368 = _1663;
                                _2368.z = (maskLight);
                                _2467 = _2368;
                            }
                            _2466 = _2467;
                        }
                        _2464 = _2466;
                    }
                    _2463 = _2464;
                }
                else
                {
                    vec3 _2468;
                    if ((shadowMask) == 3.0)
                    {
                        float _1831 = fract((_1129.x + (_1129.y * 3.0)) * 0.16666667163372039794921875);
                        vec3 _2469;
                        if (_1831 < 0.333000004291534423828125)
                        {
                            vec3 _2470;
                            if ((bgr) == 1.0)
                            {
                                vec3 _2378 = _1663;
                                _2378.z = (maskLight);
                                _2470 = _2378;
                            }
                            else
                            {
                                vec3 _2380 = _1663;
                                _2380.x = (maskLight);
                                _2470 = _2380;
                            }
                            _2469 = _2470;
                        }
                        else
                        {
                            vec3 _2471;
                            if (_1831 < 0.66600000858306884765625)
                            {
                                vec3 _2383 = _1663;
                                _2383.y = (maskLight);
                                _2471 = _2383;
                            }
                            else
                            {
                                vec3 _2472;
                                if ((bgr) == 1.0)
                                {
                                    vec3 _2385 = _1663;
                                    _2385.x = (maskLight);
                                    _2472 = _2385;
                                }
                                else
                                {
                                    vec3 _2387 = _1663;
                                    _2387.z = (maskLight);
                                    _2472 = _2387;
                                }
                                _2471 = _2472;
                            }
                            _2469 = _2471;
                        }
                        _2468 = _2469;
                    }
                    else
                    {
                        vec3 _2473;
                        if ((shadowMask) == 4.0)
                        {
                            vec2 _1879 = floor(_1129 * vec2(1.0, 0.5));
                            float _1890 = fract((_1879.x + (_1879.y * 3.0)) * 0.16666667163372039794921875);
                            vec3 _2474;
                            if (_1890 < 0.333000004291534423828125)
                            {
                                vec3 _2475;
                                if ((bgr) == 1.0)
                                {
                                    vec3 _2397 = _1663;
                                    _2397.z = (maskLight);
                                    _2475 = _2397;
                                }
                                else
                                {
                                    vec3 _2399 = _1663;
                                    _2399.x = (maskLight);
                                    _2475 = _2399;
                                }
                                _2474 = _2475;
                            }
                            else
                            {
                                vec3 _2476;
                                if (_1890 < 0.66600000858306884765625)
                                {
                                    vec3 _2402 = _1663;
                                    _2402.y = (maskLight);
                                    _2476 = _2402;
                                }
                                else
                                {
                                    vec3 _2477;
                                    if ((bgr) == 1.0)
                                    {
                                        vec3 _2404 = _1663;
                                        _2404.x = (maskLight);
                                        _2477 = _2404;
                                    }
                                    else
                                    {
                                        vec3 _2406 = _1663;
                                        _2406.z = (maskLight);
                                        _2477 = _2406;
                                    }
                                    _2476 = _2477;
                                }
                                _2474 = _2476;
                            }
                            _2473 = _2474;
                        }
                        else
                        {
                            vec3 _2478;
                            if ((shadowMask) == 5.0)
                            {
                                float _1941 = ((vec4(OutputSize, 1.0 / OutputSize)).x * RA_VARYING_0.x) * 3.1415920257568359375;
                                float _1950 = (RA_VARYING_0.y * (vec4(OutputSize, 1.0 / OutputSize)).y) * 1.57079601287841796875;
                                float _1954 = (sin(_1941 + _1950) * 0.5) + 0.5;
                                float _1973 = (sin((_1941 + 4.18877887725830078125) + _1950) * 0.5) + 0.5;
                                float _1992 = (sin((_1941 + 2.09440517425537109375) + _1950) * 0.5) + 0.5;
                                vec3 _2149;
                                if ((bgr) == 1.0)
                                {
                                    _2149 = vec3(_1992, _1973, _1954);
                                }
                                else
                                {
                                    _2149 = vec3(_1954, _1973, _1992);
                                }
                                _2157 = min(_2149 * 2.0, vec3(1.0));
                                break;
                            }
                            else
                            {
                                if ((shadowMask) == 6.0)
                                {
                                    float _2020 = _1129.x;
                                    float _2147;
                                    if (fract((_1129.y + float(fract(_2020 * 0.25) < 0.5)) * 0.5) < 0.5)
                                    {
                                        _2147 = (maskDark);
                                    }
                                    else
                                    {
                                        _2147 = (maskLight);
                                    }
                                    vec3 _2455;
                                    if (fract(_2020 * 0.5) < 0.5)
                                    {
                                        vec3 _2414 = _1663;
                                        _2414.x = (maskLight);
                                        _2414.z = (maskLight);
                                        _2455 = _2414;
                                    }
                                    else
                                    {
                                        vec3 _2418 = _1663;
                                        _2418.y = (maskLight);
                                        _2455 = _2418;
                                    }
                                    _2478 = _2455 * _2147;
                                }
                                else
                                {
                                    vec3 _2479;
                                    if ((shadowMask) == (-1.0))
                                    {
                                        _2479 = vec3(1.0);
                                    }
                                    else
                                    {
                                        _2479 = _1663;
                                    }
                                    _2478 = _2479;
                                }
                            }
                            _2473 = _2478;
                        }
                        _2468 = _2473;
                    }
                    _2463 = _2468;
                }
                _2462 = _2463;
            }
        }
        _2157 = _2462;
        break;
    } while(false);
    vec2 _2087 = RA_VARYING_0 * (vec2(1.0) - RA_VARYING_0);
    float _2309 = ((vignette) == 0.0) ? 1.0 : min(pow((_2087.x * _2087.y) * 50.0, (vign)), 1.0);
    vec2 _1174 = min(_1245, vec2(0.5) - _1243);
    float _1178 = 9.9999997473787516355514526367188e-05 / _1174.x;
    bool _1182 = (corners) == 1.0;
    bool _1190;
    if (_1182)
    {
        _1190 = _1174.y <= _1178;
    }
    else
    {
        _1190 = _1182;
    }
    bool _1197;
    if (!_1190)
    {
        _1197 = _1178 < 9.9999997473787516355514526367188e-05;
    }
    else
    {
        _1197 = _1190;
    }
    vec3 _2507;
    if (_1197)
    {
        _2507 = vec3(0.0);
    }
    else
    {
        _2507 = (pow((((_1084 * exp2(((-mix((beam1), (beam2), _2138)) * _1597) * _1597)) + (_1084 * exp2(((-mix((beam1), (beam2), _1104)) * _1624) * _1624))) * mix(vec3(1.0), _2157, vec3(mix((maskl), (maskh), _1093)))) * mix((boost1), (boost2), _1054), vec3(1.0 / (gammaout))) * mat3(vec3(_2309, 0.0, 0.0), vec3(0.0, _2309, 0.0), vec3(0.0, 0.0, _2309))) + vec3((sin(float((uint(FrameCount))) * 2.0) * (flick)) * 0.001000000047497451305389404296875);
    }
    FragColor = vec4(_2507, 1.0);
}


#endif
