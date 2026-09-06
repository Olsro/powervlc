// Generated from crt/shaders/vt220/vt220.slang. See slang/upstream for licence/source.
#version 430
#pragma parameter curvature "Curve Radius" 3.0 0.0 10.0 0.1
#pragma parameter width "Width" 1.0 0.0 2.0 0.01
#pragma parameter height "Height" 1.12 0.0 2.0 0.01
#pragma parameter smoothness "Border Blur" 1.0 0.0 10.0 0.1
#pragma parameter shine "Screen Reflection" 1.0 0.0 10.0 0.1
#pragma parameter blur_size "Reflection Blur" 3.0 0.0 5.0 0.05
#pragma parameter dimmer "Ambient Brightness" 0.5 0.0 1.0 0.05
#pragma parameter csize "Corner size" 0.045 0.0 0.07 0.01
#pragma parameter mask "Mask Type" 2.0 0.0 19.0 1.0
#pragma parameter mask_strength "Mask Strength" 0.5 0.0 1.0 0.05
#pragma parameter zoom "Viewing Distance" 0.85 0.0 2.0 0.01
#pragma parameter SCANLINE_SINE_COMP_B "Scanline Darkness" 0.15 0.0 1.0 0.05
#pragma parameter ntsc_toggle "NTSC Toggle" 0.0 0.0 1.0 1.0
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

uniform vec2 OutputSize;
uniform float SCANLINE_SINE_COMP_B;
uniform vec2 TextureSize;
uniform float blur_size;
uniform float csize;
uniform float curvature;
uniform float dimmer;
uniform float height;
uniform float mask;
uniform float mask_strength;
uniform float ntsc_toggle;
uniform float shine;
uniform float smoothness;
uniform float width;
uniform float zoom;
struct UBO
{
    float ntsc_toggle;
    float curvature;
    float width;
    float height;
    float smoothness;
    float shine;
    float blur_size;
    float dimmer;
    float csize;
    float mask;
    float zoom;
    float mask_strength;
    float SCANLINE_SINE_COMP_B;
};



struct Push
{
    vec4 SourceSize;
    vec4 OutputSize;
};



layout(binding = 2) uniform sampler2D Texture;
layout(binding = 3) uniform sampler2D Pass1Texture;

layout(location = 0) in vec2 RA_VARYING_0;
layout(location = 0) out vec4 FragColor;

void main()
{
    int _92 = int((mask));
    vec2 _2144 = vec2(RA_VARYING_0.x, 1.0 - RA_VARYING_0.y);
    vec2 _2148 = _2144 * (vec4(OutputSize, 1.0 / OutputSize)).xy;
    float _2296 = (vec4(OutputSize, 1.0 / OutputSize)).y / (vec4(OutputSize, 1.0 / OutputSize)).x;
    vec2 _2298 = (_2144 - vec2(0.5)) / vec2(_2296, 1.0);
    vec2 _2302 = (_2298 * 1.87999999523162841796875) * (zoom);
    float _2333 = (curvature) * (curvature);
    float _2308 = 0.4799999892711639404296875 * (width);
    float _2311 = 0.300000011920928955078125 * (height);
    vec2 _2312 = vec2(_2308, _2311);
    vec2 _2321 = (((_2302 * (curvature)) / vec2(sqrt(_2333 - dot(_2302, _2302)))) * (vec2(0.5) / _2312)) * vec2(0.492500007152557373046875, 0.4749999940395355224609375);
    vec2 _2323 = _2321 + vec2(0.5);
    bool _2164 = (ntsc_toggle) > 0.5;
    vec3 _6492;
    if (_2164)
    {
        _6492 = texture(Texture, vec2(_2323.x, 1.0 - _2323.y)).xyz;
    }
    else
    {
        _6492 = texture(Pass1Texture, vec2(_2323.x, 1.0 - _2323.y)).xyz;
    }
    vec2 _2451 = _2321 * 1.0;
    float _2466 = max((csize), 0.00200000009499490261077880859375);
    vec2 _2467 = vec2(_2466);
    vec2 _2472 = _2467 - min(min(_2451 + vec2(0.5), vec2(0.5) - _2451) * vec2(1.0, _2296), _2467);
    vec3 _6494;
    do
    {
        float _2525 = 1.0 - (mask_strength);
        vec3 _2528 = vec3(1.0, _2525, _2525);
        vec3 _2532 = vec3(_2525, 1.0, _2525);
        vec3 _2535 = vec3(_2525, _2525, 1.0);
        vec3 _2539 = vec3(1.0, _2525, 1.0);
        vec3 _2542 = vec3(1.0, 1.0, _2525);
        vec3 _2545 = vec3(_2525, 1.0, 1.0);
        vec3 _2547 = vec3(_2525);
        vec3 _2556 = vec3(floor(mod(gl_FragCoord.x, 2.0)));
        vec3 _2557 = mix(_2539, _2532, _2556);
        if (_92 == 0)
        {
            _6494 = vec3(1.0);
            break;
        }
        else
        {
            if (_92 == 1)
            {
                _6494 = _2557;
                break;
            }
            else
            {
                if (_92 == 2)
                {
                    _6494 = mix(_2557, mix(_2532, _2539, _2556), vec3(floor(mod(gl_FragCoord.y, 2.0))));
                    break;
                }
                else
                {
                    if (_92 == 3)
                    {
                        vec3 _2499[3][4] = vec3[][](vec3[](_2539, _2532, _2547, _2547), vec3[](_2539, _2532, _2539, _2532), vec3[](_2547, _2547, _2539, _2532));
                        _6494 = _2499[int(floor(mod(gl_FragCoord.y, 3.0)))][int(floor(mod(gl_FragCoord.x, 4.0)))];
                        break;
                    }
                    else
                    {
                        if (_92 == 4)
                        {
                            _6494 = mix(_2542, _2535, _2556);
                            break;
                        }
                        else
                        {
                            if (_92 == 5)
                            {
                                _6494 = mix(mix(_2542, _2535, _2556), mix(_2535, _2542, _2556), vec3(floor(mod(gl_FragCoord.y, 2.0))));
                                break;
                            }
                            else
                            {
                                if (_92 == 6)
                                {
                                    vec3 _2502[4] = vec3[](_2528, _2532, _2535, _2547);
                                    _6494 = _2502[int(floor(mod(gl_FragCoord.x, 4.0)))];
                                    break;
                                }
                                else
                                {
                                    if (_92 == 7)
                                    {
                                        vec3 _2503[5] = vec3[](_2528, _2539, _2535, _2532, _2532);
                                        _6494 = _2503[int(floor(mod(gl_FragCoord.x, 5.0)))];
                                        break;
                                    }
                                    else
                                    {
                                        if (_92 == 8)
                                        {
                                            vec3 _2504[7] = vec3[](_2528, _2528, _2542, _2532, _2545, _2535, _2535);
                                            _6494 = _2504[int(floor(mod(gl_FragCoord.x, 7.0)))];
                                            break;
                                        }
                                        else
                                        {
                                            if (_92 == 9)
                                            {
                                                vec3 _2505[4] = vec3[](_2528, _2542, _2545, _2535);
                                                _6494 = _2505[int(floor(mod(gl_FragCoord.x, 4.0)))];
                                                break;
                                            }
                                            else
                                            {
                                                if (_92 == 10)
                                                {
                                                    vec3 _2506[4] = vec3[](_2528, _2539, _2545, _2532);
                                                    _6494 = _2506[int(floor(mod(gl_FragCoord.x, 4.0)))];
                                                    break;
                                                }
                                                else
                                                {
                                                    if (_92 == 11)
                                                    {
                                                        vec3 _2507[2][4] = vec3[][](vec3[](_2528, _2532, _2535, _2547), vec3[](_2535, _2547, _2528, _2532));
                                                        _6494 = _2507[int(floor(mod(gl_FragCoord.y, 2.0)))][int(floor(mod(gl_FragCoord.x, 4.0)))];
                                                        break;
                                                    }
                                                    else
                                                    {
                                                        if (_92 == 12)
                                                        {
                                                            vec3 _2508[2][4] = vec3[][](vec3[](_2528, _2542, _2545, _2535), vec3[](_2545, _2535, _2528, _2542));
                                                            _6494 = _2508[int(floor(mod(gl_FragCoord.y, 2.0)))][int(floor(mod(gl_FragCoord.x, 4.0)))];
                                                            break;
                                                        }
                                                        else
                                                        {
                                                            if (_92 == 13)
                                                            {
                                                                vec3 _3092[4] = vec3[](_2528, _2542, _2545, _2535);
                                                                vec3 _3102[4] = vec3[](_2545, _2535, _2528, _2542);
                                                                vec3 _2509[4][4] = vec3[][](_3092, _3092, _3102, _3102);
                                                                _6494 = _2509[int(floor(mod(gl_FragCoord.y, 4.0)))][int(floor(mod(gl_FragCoord.x, 4.0)))];
                                                                break;
                                                            }
                                                            else
                                                            {
                                                                if (_92 == 14)
                                                                {
                                                                    vec3 _2510[3][6] = vec3[][](vec3[](_2539, _2532, _2547, _2547, _2547, _2547), vec3[](_2539, _2532, _2547, _2539, _2532, _2547), vec3[](_2547, _2547, _2547, _2539, _2532, _2547));
                                                                    _6494 = _2510[int(floor(mod(gl_FragCoord.y, 3.0)))][int(floor(mod(gl_FragCoord.x, 6.0)))];
                                                                    break;
                                                                }
                                                                else
                                                                {
                                                                    if (_92 == 15)
                                                                    {
                                                                        vec3 _3014[8] = vec3[](_2528, _2542, _2545, _2535, _2528, _2542, _2545, _2535);
                                                                        vec3 _2511[4][8] = vec3[][](_3014, vec3[](_2528, _2542, _2545, _2535, _2547, _2547, _2547, _2547), _3014, vec3[](_2547, _2547, _2547, _2547, _2528, _2542, _2545, _2535));
                                                                        _6494 = _2511[int(floor(mod(gl_FragCoord.y, 4.0)))][int(floor(mod(gl_FragCoord.x, 8.0)))];
                                                                        break;
                                                                    }
                                                                    else
                                                                    {
                                                                        if (_92 == 16)
                                                                        {
                                                                            vec3 _2512[3][4] = vec3[][](vec3[](_2542, _2535, _2547, _2547), vec3[](_2542, _2535, _2542, _2535), vec3[](_2547, _2547, _2542, _2535));
                                                                            _6494 = _2512[int(floor(mod(gl_FragCoord.y, 3.0)))][int(floor(mod(gl_FragCoord.x, 4.0)))];
                                                                            break;
                                                                        }
                                                                        else
                                                                        {
                                                                            if (_92 == 17)
                                                                            {
                                                                                vec3 _2936[10] = vec3[](_2528, _2539, _2535, _2532, _2532, _2528, _2539, _2535, _2532, _2532);
                                                                                vec3 _2513[4][10] = vec3[][](_2936, vec3[](_2547, _2535, _2535, _2532, _2532, _2528, _2528, _2547, _2547, _2547), _2936, vec3[](_2528, _2528, _2547, _2547, _2547, _2547, _2535, _2535, _2532, _2532));
                                                                                _6494 = _2513[int(floor(mod(gl_FragCoord.y, 4.0)))][int(floor(mod(gl_FragCoord.x, 10.0)))];
                                                                                break;
                                                                            }
                                                                            else
                                                                            {
                                                                                if (_92 == 18)
                                                                                {
                                                                                    vec3 _2889[10] = vec3[](_2528, _2542, _2532, _2535, _2535, _2528, _2542, _2532, _2535, _2535);
                                                                                    vec3 _2514[4][10] = vec3[][](_2889, vec3[](_2547, _2532, _2532, _2535, _2535, _2528, _2528, _2547, _2547, _2547), _2889, vec3[](_2528, _2528, _2547, _2547, _2547, _2547, _2532, _2532, _2535, _2535));
                                                                                    _6494 = _2514[int(floor(mod(gl_FragCoord.y, 4.0)))][int(floor(mod(gl_FragCoord.x, 10.0)))];
                                                                                    break;
                                                                                }
                                                                                else
                                                                                {
                                                                                    if (_92 == 19)
                                                                                    {
                                                                                        vec3 _2815[14] = vec3[](_2528, _2528, _2542, _2532, _2545, _2535, _2535, _2528, _2528, _2542, _2532, _2545, _2535, _2535);
                                                                                        vec3 _2515[6][14] = vec3[][](_2815, _2815, vec3[](_2528, _2528, _2542, _2532, _2545, _2535, _2535, _2547, _2547, _2547, _2547, _2547, _2547, _2547), _2815, _2815, vec3[](_2547, _2547, _2547, _2547, _2547, _2547, _2547, _2547, _2528, _2528, _2542, _2532, _2545, _2535));
                                                                                        _6494 = _2515[int(floor(mod(gl_FragCoord.y, 6.0)))][int(floor(mod(gl_FragCoord.x, 14.0)))];
                                                                                        break;
                                                                                    }
                                                                                    else
                                                                                    {
                                                                                        if (_92 == 20)
                                                                                        {
                                                                                            vec3 _2771[4] = vec3[](_2532, _2539, _2532, _2539);
                                                                                            vec3 _2516[4][4] = vec3[][](_2771, vec3[](_2547, _2535, _2532, _2528), _2771, vec3[](_2532, _2528, _2547, _2535));
                                                                                            _6494 = _2516[int(floor(mod(gl_FragCoord.y, 4.0)))][int(floor(mod(gl_FragCoord.x, 4.0)))];
                                                                                            break;
                                                                                        }
                                                                                        else
                                                                                        {
                                                                                            if (_92 == 21)
                                                                                            {
                                                                                                vec3 _2728[8] = vec3[](_2528, _2532, _2535, _2547, _2528, _2532, _2535, _2547);
                                                                                                vec3 _2517[4][8] = vec3[][](_2728, vec3[](_2528, _2532, _2535, _2547, _2547, _2547, _2547, _2547), _2728, vec3[](_2547, _2547, _2547, _2547, _2528, _2532, _2535, _2547));
                                                                                                _6494 = _2517[int(floor(mod(gl_FragCoord.y, 4.0)))][int(floor(mod(gl_FragCoord.x, 8.0)))];
                                                                                                break;
                                                                                            }
                                                                                            else
                                                                                            {
                                                                                                if (_92 == 22)
                                                                                                {
                                                                                                    vec3 _2518[3] = vec3[](_2547, vec3(1.0), vec3(1.0));
                                                                                                    _6494 = _2518[int(floor(mod(gl_FragCoord.x, 3.0)))];
                                                                                                    break;
                                                                                                }
                                                                                                else
                                                                                                {
                                                                                                    if (_92 == 23)
                                                                                                    {
                                                                                                        vec3 _2519[4] = vec3[](_2547, _2547, vec3(1.0), vec3(1.0));
                                                                                                        _6494 = _2519[int(floor(mod(gl_FragCoord.x, 4.0)))];
                                                                                                        break;
                                                                                                    }
                                                                                                    else
                                                                                                    {
                                                                                                        if (_92 == 24)
                                                                                                        {
                                                                                                            vec3 _2641[10] = vec3[](_2532, _2545, _2535, _2535, _2535, _2528, _2528, _2528, _2542, _2532);
                                                                                                            vec3 _2661[10] = vec3[](_2528, _2528, _2528, _2542, _2532, _2532, _2545, _2535, _2535, _2535);
                                                                                                            vec3 _2520[6][10] = vec3[][](_2641, _2641, _2641, _2661, _2661, _2661);
                                                                                                            _6494 = _2520[int(floor(mod(gl_FragCoord.y, 6.0)))][int(floor(mod(gl_FragCoord.x, 10.0)))];
                                                                                                            break;
                                                                                                        }
                                                                                                        else
                                                                                                        {
                                                                                                            _6494 = vec3(1.0);
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
    vec4 _2211 = vec4((_6492 * clamp((_2466 - sqrt(dot(_2472, _2472))) * 800.0, 0.0, 1.0)) * _6494, 1.0);
    vec3 _2216 = pow(_2211.xyz, vec3(1.13636362552642822265625));
    vec4 _6662 = _2211;
    _6662.x = _2216.x;
    _6662.y = _2216.y;
    _6662.z = _2216.z;
    vec3 _3378 = _6662.xyz * ((1.0 - ((SCANLINE_SINE_COMP_B) * 0.3333333432674407958984375)) + dot(vec2(0.0, (SCANLINE_SINE_COMP_B)) * sin(_2323 * vec2(3.1415927410125732421875 * (vec4(OutputSize, 1.0 / OutputSize)).x, 6.283185482025146484375 * (vec4(TextureSize, 1.0 / TextureSize)).y)), vec2(1.0)));
    vec4 _6671 = _6662;
    _6671.x = _3378.x;
    _6671.y = _3378.y;
    _6671.z = _3378.z;
    vec4 _6535;
    if (_2164)
    {
        vec2 _5666 = (_2298 * 2.0) * (zoom);
        float _5687 = dot(_5666, _5666);
        vec2 _5672 = ((_5666 * (curvature)) / vec2(sqrt(_2333 - _5687))) * vec2(0.5);
        vec2 _5674 = _5672 + vec2(0.5);
        vec2 _5724 = ((_5666 * ((curvature) * 1.25)) / vec2(sqrt((1.5625 * _2333) - _5687))) * vec2(0.5);
        float _5050 = distance(_5674, vec2(0.5));
        float _5056 = 0.0040000001899898052215576171875 * (smoothness);
        float _5059 = (-0.0040000001899898052215576171875) * (smoothness);
        float _5854 = length(max(abs(_5672) - _2312, vec2(0.0))) - 0.0500000007450580596923828125;
        float _5062 = smoothstep(_5056, _5059, _5854);
        vec2 _5889 = _5724 + vec2(0.5);
        vec4 _6519;
        _6519 = vec4(0.0);
        for (int _6518 = 0; _6518 < 12; )
        {
            vec2 _5077 = vec2(float(_6518));
            _6519 += ((clamp(vec4(fract(sin(dot(_5889 + _5077, vec2(12.98980045318603515625, 78.233001708984375))) * 43758.546875) * 0.0500000007450580596923828125) + vec4(0.775000035762786865234375, 0.775000035762786865234375, 0.5750000476837158203125, -0.02500000037252902984619140625), vec4(0.0), vec4(1.0)) + vec4((fract(sin(dot((_5724 + vec2(1.5)) + _5077, vec2(12.98980045318603515625, 78.233001708984375))) * 43758.546875) * 0.25) * cos((_5889.x - 0.5) * 4.712249755859375))) * vec4(0.083333335816860198974609375));
            _6518++;
            continue;
        }
        float _5120 = ((height) * 0.3125000298023223876953125) * (width);
        float _5125 = _5120 - 0.02500000037252902984619140625;
        float _5127 = _5120 + 0.02500000037252902984619140625;
        float _5130 = _5674.x - 0.5;
        float _5132 = _5674.y;
        float _5163 = smoothstep(_5059, _5056, _5854);
        vec2 _5967 = _2312 + vec2(0.0500000007450580596923828125);
        vec2 _5972 = abs(_5724);
        float _5979 = length(max(_5972 - _5967, vec2(0.0))) - 0.0500000007450580596923828125;
        float _5173 = smoothstep(_5056, _5059, _5979);
        vec4 _5179 = _6519 - vec4(0.4000000059604644775390625);
        float _5183 = (smoothness) * (-0.008000000379979610443115234375);
        float _5187 = (smoothness) * 0.008000000379979610443115234375;
        vec2 _5983 = abs(_5724 + vec2(0.0, -0.00499999523162841796875));
        vec2 _5994 = abs(_5724 + vec2(0.0, 0.00499999523162841796875));
        float _5245 = smoothstep(_5059, _5056, _5979);
        vec2 _5263 = _2312 + vec2(0.1500000059604644775390625);
        float _6023 = length(max(_5972 - _5263, vec2(0.0))) - 0.0500000007450580596923828125;
        float _5265 = smoothstep(_5056, _5059, _6023);
        vec4 _5268 = (((vec4(max(0.0, (0.660000026226043701171875 * (shine)) - distance(_5674, vec2(0.5, 1.0))) * smoothstep((smoothness) * 0.00200000009499490261077880859375, (smoothness) * (-0.00200000009499490261077880859375), length(max(abs(_5672 + vec2(0.0, 0.0300000011920928955078125)) - _2312, vec2(0.0))) - 0.0500000007450580596923828125)) + vec4(max(0.0, 0.100000001490116119384765625 - (0.5 * _5050)) * _5062)) + ((((_6519 * vec4(0.3333333432674407958984375)) * ((1.0 + smoothstep(_5125, _5127, abs(atan(_5130, _5132 - 0.5)) * 0.318319261074066162109375)) + smoothstep(_5127, _5125, abs(atan(_5130, 0.5 - _5132)) * 0.318319261074066162109375))) * _5163) * _5173)) + ((_5179 * smoothstep(_5183, _5187, length(max(_5983 - _5967, vec2(0.0))) - 0.0500000007450580596923828125)) * smoothstep(_5187, _5183, length(max(_5994 - _5967, vec2(0.0))) - 0.0500000007450580596923828125))) + ((_6519 * _5245) * _5265);
        vec4 _6524;
        _6524 = ((vec4(max(0.0, 0.20000000298023223876953125 - (0.300000011920928955078125 * _5050)) * _5062) + ((vec4(0.11200000345706939697265625, 0.11200000345706939697265625, 0.083999998867511749267578125, 0.0) * _5163) * _5173)) - ((vec4(0.800000011920928955078125, 0.800000011920928955078125, 0.60000002384185791015625, 0.0) * smoothstep(_5183, (smoothness) * 0.0400000028312206268310546875, _5979)) * smoothstep(_5187, _5183, _5979))) + ((vec4(0.16000001132488250732421875, 0.16000001132488250732421875, 0.12000000476837158203125, 0.0) * _5245) * _5265);
        for (int _6523 = 0; _6523 < 5; )
        {
            vec2 _5469 = _2323 + vec2(float(_6523));
            vec2 _5486 = _2323 + (((vec2(fract(sin(dot(_5469, vec2(12.98980045318603515625, 78.233001708984375))) * 43758.546875), fract(sin(dot(_5469 + vec2(0.100000001490116119384765625), vec2(12.98980045318603515625, 78.233001708984375))) * 43758.546875)) - vec2(0.5)) * 0.039999999105930328369140625) * (blur_size));
            _6524 += (((texture(Texture, vec2(1.0) - (vec2(1.0 - _5486.x, _5486.y) + ((vec2(length(max(abs(_5486 - vec2(0.50010001659393310546875, 0.5)) - vec2(0.52499997615814208984375), vec2(0.0))) - length(max(abs(_5486 + vec2(-0.4999000132083892822265625, -0.5)) - vec2(0.52499997615814208984375), vec2(0.0))), length(max(abs(_5486 - vec2(0.5, 0.50010001659393310546875)) - vec2(0.52499997615814208984375), vec2(0.0))) - length(max(abs(_5486 + vec2(-0.5, -0.4999000132083892822265625)) - vec2(0.52499997615814208984375), vec2(0.0)))) * vec2(10000.0)) * (length(max(abs(_5486 - vec2(0.5)) - vec2(0.52499997615814208984375), vec2(0.0))) - 0.01666666753590106964111328125)))) * vec4(0.117999993264675140380859375, 0.117999993264675140380859375, 0.12600000202655792236328125, 0.0)) * _5163) * _5173);
            _6523++;
            continue;
        }
        vec4 _5534 = mix(_6524, (_5268 + ((_5179 * smoothstep(_5183, _5187, length(max(_5994 - _5263, vec2(0.0))) - 0.0500000007450580596923828125)) * smoothstep(_5187, _5183, length(max(_5983 - _5263, vec2(0.0))) - 0.0500000007450580596923828125))) + (((vec4(1.0, 1.0, 1.0, 0.0) * max(0.0, 1.0 - ((2.0 * _2148.y) / (vec4(OutputSize, 1.0 / OutputSize)).y))) * smoothstep(-0.25, 0.25, length(max(abs(_2321 + vec2(0.0, 0.699999988079071044921875)) - vec2(_2308 + 0.25, _2311 - 0.1500000059604644775390625), vec2(0.0))) - 0.100000001490116119384765625)) * smoothstep(_5183, _5187, _6023)), vec4((dimmer)));
        float _5536 = _2323.x;
        bool _5537 = _5536 > 0.0;
        bool _5543;
        if (_5537)
        {
            _5543 = _5536 < 1.0;
        }
        else
        {
            _5543 = _5537;
        }
        bool _5549;
        if (_5543)
        {
            _5549 = _2323.y > 0.0;
        }
        else
        {
            _5549 = _5543;
        }
        bool _5555;
        if (_5549)
        {
            _5555 = _2323.y < 1.0;
        }
        else
        {
            _5555 = _5549;
        }
        vec4 _6534;
        if (_5555)
        {
            _6534 = _5534 + _6671;
        }
        else
        {
            _6534 = _5534;
        }
        _6535 = _6534;
    }
    else
    {
        vec2 _4113 = (_2298 * 2.0) * (zoom);
        float _4134 = dot(_4113, _4113);
        vec2 _4119 = ((_4113 * (curvature)) / vec2(sqrt(_2333 - _4134))) * vec2(0.5);
        vec2 _4121 = _4119 + vec2(0.5);
        vec2 _4171 = ((_4113 * ((curvature) * 1.25)) / vec2(sqrt((1.5625 * _2333) - _4134))) * vec2(0.5);
        float _3497 = distance(_4121, vec2(0.5));
        float _3503 = 0.0040000001899898052215576171875 * (smoothness);
        float _3506 = (-0.0040000001899898052215576171875) * (smoothness);
        float _4301 = length(max(abs(_4119) - _2312, vec2(0.0))) - 0.0500000007450580596923828125;
        float _3509 = smoothstep(_3503, _3506, _4301);
        vec2 _4336 = _4171 + vec2(0.5);
        vec4 _6500;
        _6500 = vec4(0.0);
        for (int _6499 = 0; _6499 < 12; )
        {
            vec2 _3524 = vec2(float(_6499));
            _6500 += ((clamp(vec4(fract(sin(dot(_4336 + _3524, vec2(12.98980045318603515625, 78.233001708984375))) * 43758.546875) * 0.0500000007450580596923828125) + vec4(0.775000035762786865234375, 0.775000035762786865234375, 0.5750000476837158203125, -0.02500000037252902984619140625), vec4(0.0), vec4(1.0)) + vec4((fract(sin(dot((_4171 + vec2(1.5)) + _3524, vec2(12.98980045318603515625, 78.233001708984375))) * 43758.546875) * 0.25) * cos((_4336.x - 0.5) * 4.712249755859375))) * vec4(0.083333335816860198974609375));
            _6499++;
            continue;
        }
        float _3567 = ((height) * 0.3125000298023223876953125) * (width);
        float _3572 = _3567 - 0.02500000037252902984619140625;
        float _3574 = _3567 + 0.02500000037252902984619140625;
        float _3577 = _4121.x - 0.5;
        float _3579 = _4121.y;
        float _3610 = smoothstep(_3506, _3503, _4301);
        vec2 _4414 = _2312 + vec2(0.0500000007450580596923828125);
        vec2 _4419 = abs(_4171);
        float _4426 = length(max(_4419 - _4414, vec2(0.0))) - 0.0500000007450580596923828125;
        float _3620 = smoothstep(_3503, _3506, _4426);
        vec4 _3626 = _6500 - vec4(0.4000000059604644775390625);
        float _3630 = (smoothness) * (-0.008000000379979610443115234375);
        float _3634 = (smoothness) * 0.008000000379979610443115234375;
        vec2 _4430 = abs(_4171 + vec2(0.0, -0.00499999523162841796875));
        vec2 _4441 = abs(_4171 + vec2(0.0, 0.00499999523162841796875));
        float _3692 = smoothstep(_3506, _3503, _4426);
        vec2 _3710 = _2312 + vec2(0.1500000059604644775390625);
        float _4470 = length(max(_4419 - _3710, vec2(0.0))) - 0.0500000007450580596923828125;
        float _3712 = smoothstep(_3503, _3506, _4470);
        vec4 _3715 = (((vec4(max(0.0, (0.660000026226043701171875 * (shine)) - distance(_4121, vec2(0.5, 1.0))) * smoothstep((smoothness) * 0.00200000009499490261077880859375, (smoothness) * (-0.00200000009499490261077880859375), length(max(abs(_4119 + vec2(0.0, 0.0300000011920928955078125)) - _2312, vec2(0.0))) - 0.0500000007450580596923828125)) + vec4(max(0.0, 0.100000001490116119384765625 - (0.5 * _3497)) * _3509)) + ((((_6500 * vec4(0.3333333432674407958984375)) * ((1.0 + smoothstep(_3572, _3574, abs(atan(_3577, _3579 - 0.5)) * 0.318319261074066162109375)) + smoothstep(_3574, _3572, abs(atan(_3577, 0.5 - _3579)) * 0.318319261074066162109375))) * _3610) * _3620)) + ((_3626 * smoothstep(_3630, _3634, length(max(_4430 - _4414, vec2(0.0))) - 0.0500000007450580596923828125)) * smoothstep(_3634, _3630, length(max(_4441 - _4414, vec2(0.0))) - 0.0500000007450580596923828125))) + ((_6500 * _3692) * _3712);
        vec4 _6505;
        _6505 = ((vec4(max(0.0, 0.20000000298023223876953125 - (0.300000011920928955078125 * _3497)) * _3509) + ((vec4(0.11200000345706939697265625, 0.11200000345706939697265625, 0.083999998867511749267578125, 0.0) * _3610) * _3620)) - ((vec4(0.800000011920928955078125, 0.800000011920928955078125, 0.60000002384185791015625, 0.0) * smoothstep(_3630, (smoothness) * 0.0400000028312206268310546875, _4426)) * smoothstep(_3634, _3630, _4426))) + ((vec4(0.16000001132488250732421875, 0.16000001132488250732421875, 0.12000000476837158203125, 0.0) * _3692) * _3712);
        for (int _6504 = 0; _6504 < 5; )
        {
            vec2 _3916 = _2323 + vec2(float(_6504));
            vec2 _3933 = _2323 + (((vec2(fract(sin(dot(_3916, vec2(12.98980045318603515625, 78.233001708984375))) * 43758.546875), fract(sin(dot(_3916 + vec2(0.100000001490116119384765625), vec2(12.98980045318603515625, 78.233001708984375))) * 43758.546875)) - vec2(0.5)) * 0.039999999105930328369140625) * (blur_size));
            _6505 += (((texture(Pass1Texture, vec2(1.0) - (vec2(1.0 - _3933.x, _3933.y) + ((vec2(length(max(abs(_3933 - vec2(0.50010001659393310546875, 0.5)) - vec2(0.52499997615814208984375), vec2(0.0))) - length(max(abs(_3933 + vec2(-0.4999000132083892822265625, -0.5)) - vec2(0.52499997615814208984375), vec2(0.0))), length(max(abs(_3933 - vec2(0.5, 0.50010001659393310546875)) - vec2(0.52499997615814208984375), vec2(0.0))) - length(max(abs(_3933 + vec2(-0.5, -0.4999000132083892822265625)) - vec2(0.52499997615814208984375), vec2(0.0)))) * vec2(10000.0)) * (length(max(abs(_3933 - vec2(0.5)) - vec2(0.52499997615814208984375), vec2(0.0))) - 0.01666666753590106964111328125)))) * vec4(0.117999993264675140380859375, 0.117999993264675140380859375, 0.12600000202655792236328125, 0.0)) * _3610) * _3620);
            _6504++;
            continue;
        }
        vec4 _3981 = mix(_6505, (_3715 + ((_3626 * smoothstep(_3630, _3634, length(max(_4441 - _3710, vec2(0.0))) - 0.0500000007450580596923828125)) * smoothstep(_3634, _3630, length(max(_4430 - _3710, vec2(0.0))) - 0.0500000007450580596923828125))) + (((vec4(1.0, 1.0, 1.0, 0.0) * max(0.0, 1.0 - ((2.0 * _2148.y) / (vec4(OutputSize, 1.0 / OutputSize)).y))) * smoothstep(-0.25, 0.25, length(max(abs(_2321 + vec2(0.0, 0.699999988079071044921875)) - vec2(_2308 + 0.25, _2311 - 0.1500000059604644775390625), vec2(0.0))) - 0.100000001490116119384765625)) * smoothstep(_3630, _3634, _4470)), vec4((dimmer)));
        float _3983 = _2323.x;
        bool _3984 = _3983 > 0.0;
        bool _3990;
        if (_3984)
        {
            _3990 = _3983 < 1.0;
        }
        else
        {
            _3990 = _3984;
        }
        bool _3996;
        if (_3990)
        {
            _3996 = _2323.y > 0.0;
        }
        else
        {
            _3996 = _3990;
        }
        bool _4002;
        if (_3996)
        {
            _4002 = _2323.y < 1.0;
        }
        else
        {
            _4002 = _3996;
        }
        vec4 _6515;
        if (_4002)
        {
            _6515 = _3981 + _6671;
        }
        else
        {
            _6515 = _3981;
        }
        _6535 = _6515;
    }
    FragColor = _6535;
}


#endif
