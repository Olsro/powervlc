// Generated from crt/shaders/vt220/vt220.slang. See slang/upstream for licence/source.
cbuffer UBO : register(b0)
{
    float global_ntsc_toggle : packoffset(c4);
    float global_curvature : packoffset(c4.y);
    float global_width : packoffset(c4.z);
    float global_height : packoffset(c4.w);
    float global_smoothness : packoffset(c5);
    float global_shine : packoffset(c5.y);
    float global_blur_size : packoffset(c5.z);
    float global_dimmer : packoffset(c5.w);
    float global_csize : packoffset(c6);
    float global_mask : packoffset(c6.y);
    float global_zoom : packoffset(c6.z);
    float global_mask_strength : packoffset(c6.w);
    float global_SCANLINE_SINE_COMP_B : packoffset(c7.z);
};

cbuffer Push : register(b1)
{
    float4 params_SourceSize : packoffset(c0);
    float4 params_OutputSize : packoffset(c2);
};

Texture2D<float4> Source : register(t2);
SamplerState _Source_sampler : register(s2);
Texture2D<float4> vt220_refpass : register(t3);
SamplerState _vt220_refpass_sampler : register(s3);

static float4 gl_FragCoord;
static float2 vTexCoord;
static float4 FragColor;

struct SPIRV_Cross_Input
{
    float2 vTexCoord : TEXCOORD0;
    float4 gl_FragCoord : SV_Position;
};

struct SPIRV_Cross_Output
{
    float4 FragColor : SV_Target0;
};

float mod(float x, float y)
{
    return x - y * floor(x / y);
}

float2 mod(float2 x, float2 y)
{
    return x - y * floor(x / y);
}

float3 mod(float3 x, float3 y)
{
    return x - y * floor(x / y);
}

float4 mod(float4 x, float4 y)
{
    return x - y * floor(x / y);
}

void frag_main()
{
    int _92 = int(global_mask);
    float2 _2144 = float2(vTexCoord.x, 1.0f - vTexCoord.y);
    float2 _2148 = _2144 * params_OutputSize.xy;
    float _2296 = params_OutputSize.y / params_OutputSize.x;
    float2 _2298 = (_2144 - 0.5f.xx) / float2(_2296, 1.0f);
    float2 _2302 = (_2298 * 1.87999999523162841796875f) * global_zoom;
    float _2333 = global_curvature * global_curvature;
    float _2308 = 0.4799999892711639404296875f * global_width;
    float _2311 = 0.300000011920928955078125f * global_height;
    float2 _2312 = float2(_2308, _2311);
    float2 _2321 = (((_2302 * global_curvature) / sqrt(_2333 - dot(_2302, _2302)).xx) * (0.5f.xx / _2312)) * float2(0.492500007152557373046875f, 0.4749999940395355224609375f);
    float2 _2323 = _2321 + 0.5f.xx;
    bool _2164 = global_ntsc_toggle > 0.5f;
    float3 _6492;
    if (_2164)
    {
        _6492 = Source.Sample(_Source_sampler, float2(_2323.x, 1.0f - _2323.y)).xyz;
    }
    else
    {
        _6492 = vt220_refpass.Sample(_vt220_refpass_sampler, float2(_2323.x, 1.0f - _2323.y)).xyz;
    }
    float2 _2451 = _2321 * 1.0f;
    float _2466 = max(global_csize, 0.00200000009499490261077880859375f);
    float2 _2467 = _2466.xx;
    float2 _2472 = _2467 - min(min(_2451 + 0.5f.xx, 0.5f.xx - _2451) * float2(1.0f, _2296), _2467);
    float3 _6494;
    do
    {
        float _2525 = 1.0f - global_mask_strength;
        float3 _2528 = float3(1.0f, _2525, _2525);
        float3 _2532 = float3(_2525, 1.0f, _2525);
        float3 _2535 = float3(_2525, _2525, 1.0f);
        float3 _2539 = float3(1.0f, _2525, 1.0f);
        float3 _2542 = float3(1.0f, 1.0f, _2525);
        float3 _2545 = float3(_2525, 1.0f, 1.0f);
        float3 _2547 = _2525.xxx;
        float3 _2556 = floor(mod(gl_FragCoord.x, 2.0f)).xxx;
        float3 _2557 = lerp(_2539, _2532, _2556);
        if (_92 == 0)
        {
            _6494 = 1.0f.xxx;
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
                    _6494 = lerp(_2557, lerp(_2532, _2539, _2556), floor(mod(gl_FragCoord.y, 2.0f)).xxx);
                    break;
                }
                else
                {
                    if (_92 == 3)
                    {
                        float3 _3303[4] = { _2539, _2532, _2547, _2547 };
                        float3 _3308[4] = { _2539, _2532, _2539, _2532 };
                        float3 _3312[4] = { _2547, _2547, _2539, _2532 };
                        float3 _3313[3][4] = { _3303, _3308, _3312 };
                        float3 _2499[3][4] = _3313;
                        _6494 = _2499[int(floor(mod(gl_FragCoord.y, 3.0f)))][int(floor(mod(gl_FragCoord.x, 4.0f)))];
                        break;
                    }
                    else
                    {
                        if (_92 == 4)
                        {
                            _6494 = lerp(_2542, _2535, _2556);
                            break;
                        }
                        else
                        {
                            if (_92 == 5)
                            {
                                _6494 = lerp(lerp(_2542, _2535, _2556), lerp(_2535, _2542, _2556), floor(mod(gl_FragCoord.y, 2.0f)).xxx);
                                break;
                            }
                            else
                            {
                                if (_92 == 6)
                                {
                                    float3 _3251[4] = { _2528, _2532, _2535, _2547 };
                                    float3 _2502[4] = _3251;
                                    _6494 = _2502[int(floor(mod(gl_FragCoord.x, 4.0f)))];
                                    break;
                                }
                                else
                                {
                                    if (_92 == 7)
                                    {
                                        float3 _3235[5] = { _2528, _2539, _2535, _2532, _2532 };
                                        float3 _2503[5] = _3235;
                                        _6494 = _2503[int(floor(mod(gl_FragCoord.x, 5.0f)))];
                                        break;
                                    }
                                    else
                                    {
                                        if (_92 == 8)
                                        {
                                            float3 _3219[7] = { _2528, _2528, _2542, _2532, _2545, _2535, _2535 };
                                            float3 _2504[7] = _3219;
                                            _6494 = _2504[int(floor(mod(gl_FragCoord.x, 7.0f)))];
                                            break;
                                        }
                                        else
                                        {
                                            if (_92 == 9)
                                            {
                                                float3 _3202[4] = { _2528, _2542, _2545, _2535 };
                                                float3 _2505[4] = _3202;
                                                _6494 = _2505[int(floor(mod(gl_FragCoord.x, 4.0f)))];
                                                break;
                                            }
                                            else
                                            {
                                                if (_92 == 10)
                                                {
                                                    float3 _3186[4] = { _2528, _2539, _2545, _2532 };
                                                    float3 _2506[4] = _3186;
                                                    _6494 = _2506[int(floor(mod(gl_FragCoord.x, 4.0f)))];
                                                    break;
                                                }
                                                else
                                                {
                                                    if (_92 == 11)
                                                    {
                                                        float3 _3158[4] = { _2528, _2532, _2535, _2547 };
                                                        float3 _3163[4] = { _2535, _2547, _2528, _2532 };
                                                        float3 _3164[2][4] = { _3158, _3163 };
                                                        float3 _2507[2][4] = _3164;
                                                        _6494 = _2507[int(floor(mod(gl_FragCoord.y, 2.0f)))][int(floor(mod(gl_FragCoord.x, 4.0f)))];
                                                        break;
                                                    }
                                                    else
                                                    {
                                                        if (_92 == 12)
                                                        {
                                                            float3 _3130[4] = { _2528, _2542, _2545, _2535 };
                                                            float3 _3135[4] = { _2545, _2535, _2528, _2542 };
                                                            float3 _3136[2][4] = { _3130, _3135 };
                                                            float3 _2508[2][4] = _3136;
                                                            _6494 = _2508[int(floor(mod(gl_FragCoord.y, 2.0f)))][int(floor(mod(gl_FragCoord.x, 4.0f)))];
                                                            break;
                                                        }
                                                        else
                                                        {
                                                            if (_92 == 13)
                                                            {
                                                                float3 _3092[4] = { _2528, _2542, _2545, _2535 };
                                                                float3 _3102[4] = { _2545, _2535, _2528, _2542 };
                                                                float3 _3108[4][4] = { _3092, _3092, _3102, _3102 };
                                                                float3 _2509[4][4] = _3108;
                                                                _6494 = _2509[int(floor(mod(gl_FragCoord.y, 4.0f)))][int(floor(mod(gl_FragCoord.x, 4.0f)))];
                                                                break;
                                                            }
                                                            else
                                                            {
                                                                if (_92 == 14)
                                                                {
                                                                    float3 _3057[6] = { _2539, _2532, _2547, _2547, _2547, _2547 };
                                                                    float3 _3064[6] = { _2539, _2532, _2547, _2539, _2532, _2547 };
                                                                    float3 _3069[6] = { _2547, _2547, _2547, _2539, _2532, _2547 };
                                                                    float3 _3070[3][6] = { _3057, _3064, _3069 };
                                                                    float3 _2510[3][6] = _3070;
                                                                    _6494 = _2510[int(floor(mod(gl_FragCoord.y, 3.0f)))][int(floor(mod(gl_FragCoord.x, 6.0f)))];
                                                                    break;
                                                                }
                                                                else
                                                                {
                                                                    if (_92 == 15)
                                                                    {
                                                                        float3 _3014[8] = { _2528, _2542, _2545, _2535, _2528, _2542, _2545, _2535 };
                                                                        float3 _3020[8] = { _2528, _2542, _2545, _2535, _2547, _2547, _2547, _2547 };
                                                                        float3 _3035[8] = { _2547, _2547, _2547, _2547, _2528, _2542, _2545, _2535 };
                                                                        float3 _3036[4][8] = { _3014, _3020, _3014, _3035 };
                                                                        float3 _2511[4][8] = _3036;
                                                                        _6494 = _2511[int(floor(mod(gl_FragCoord.y, 4.0f)))][int(floor(mod(gl_FragCoord.x, 8.0f)))];
                                                                        break;
                                                                    }
                                                                    else
                                                                    {
                                                                        if (_92 == 16)
                                                                        {
                                                                            float3 _2978[4] = { _2542, _2535, _2547, _2547 };
                                                                            float3 _2983[4] = { _2542, _2535, _2542, _2535 };
                                                                            float3 _2987[4] = { _2547, _2547, _2542, _2535 };
                                                                            float3 _2988[3][4] = { _2978, _2983, _2987 };
                                                                            float3 _2512[3][4] = _2988;
                                                                            _6494 = _2512[int(floor(mod(gl_FragCoord.y, 3.0f)))][int(floor(mod(gl_FragCoord.x, 4.0f)))];
                                                                            break;
                                                                        }
                                                                        else
                                                                        {
                                                                            if (_92 == 17)
                                                                            {
                                                                                float3 _2936[10] = { _2528, _2539, _2535, _2532, _2532, _2528, _2539, _2535, _2532, _2532 };
                                                                                float3 _2942[10] = { _2547, _2535, _2535, _2532, _2532, _2528, _2528, _2547, _2547, _2547 };
                                                                                float3 _2956[10] = { _2528, _2528, _2547, _2547, _2547, _2547, _2535, _2535, _2532, _2532 };
                                                                                float3 _2957[4][10] = { _2936, _2942, _2936, _2956 };
                                                                                float3 _2513[4][10] = _2957;
                                                                                _6494 = _2513[int(floor(mod(gl_FragCoord.y, 4.0f)))][int(floor(mod(gl_FragCoord.x, 10.0f)))];
                                                                                break;
                                                                            }
                                                                            else
                                                                            {
                                                                                if (_92 == 18)
                                                                                {
                                                                                    float3 _2889[10] = { _2528, _2542, _2532, _2535, _2535, _2528, _2542, _2532, _2535, _2535 };
                                                                                    float3 _2895[10] = { _2547, _2532, _2532, _2535, _2535, _2528, _2528, _2547, _2547, _2547 };
                                                                                    float3 _2909[10] = { _2528, _2528, _2547, _2547, _2547, _2547, _2532, _2532, _2535, _2535 };
                                                                                    float3 _2910[4][10] = { _2889, _2895, _2889, _2909 };
                                                                                    float3 _2514[4][10] = _2910;
                                                                                    _6494 = _2514[int(floor(mod(gl_FragCoord.y, 4.0f)))][int(floor(mod(gl_FragCoord.x, 10.0f)))];
                                                                                    break;
                                                                                }
                                                                                else
                                                                                {
                                                                                    if (_92 == 19)
                                                                                    {
                                                                                        float3 _2815[14] = { _2528, _2528, _2542, _2532, _2545, _2535, _2535, _2528, _2528, _2542, _2532, _2545, _2535, _2535 };
                                                                                        float3 _2833[14] = { _2528, _2528, _2542, _2532, _2545, _2535, _2535, _2547, _2547, _2547, _2547, _2547, _2547, _2547 };
                                                                                        float3 _2862[14] = { _2547, _2547, _2547, _2547, _2547, _2547, _2547, _2547, _2528, _2528, _2542, _2532, _2545, _2535 };
                                                                                        float3 _2863[6][14] = { _2815, _2815, _2833, _2815, _2815, _2862 };
                                                                                        float3 _2515[6][14] = _2863;
                                                                                        _6494 = _2515[int(floor(mod(gl_FragCoord.y, 6.0f)))][int(floor(mod(gl_FragCoord.x, 14.0f)))];
                                                                                        break;
                                                                                    }
                                                                                    else
                                                                                    {
                                                                                        if (_92 == 20)
                                                                                        {
                                                                                            float3 _2771[4] = { _2532, _2539, _2532, _2539 };
                                                                                            float3 _2776[4] = { _2547, _2535, _2532, _2528 };
                                                                                            float3 _2786[4] = { _2532, _2528, _2547, _2535 };
                                                                                            float3 _2787[4][4] = { _2771, _2776, _2771, _2786 };
                                                                                            float3 _2516[4][4] = _2787;
                                                                                            _6494 = _2516[int(floor(mod(gl_FragCoord.y, 4.0f)))][int(floor(mod(gl_FragCoord.x, 4.0f)))];
                                                                                            break;
                                                                                        }
                                                                                        else
                                                                                        {
                                                                                            if (_92 == 21)
                                                                                            {
                                                                                                float3 _2728[8] = { _2528, _2532, _2535, _2547, _2528, _2532, _2535, _2547 };
                                                                                                float3 _2733[8] = { _2528, _2532, _2535, _2547, _2547, _2547, _2547, _2547 };
                                                                                                float3 _2748[8] = { _2547, _2547, _2547, _2547, _2528, _2532, _2535, _2547 };
                                                                                                float3 _2749[4][8] = { _2728, _2733, _2728, _2748 };
                                                                                                float3 _2517[4][8] = _2749;
                                                                                                _6494 = _2517[int(floor(mod(gl_FragCoord.y, 4.0f)))][int(floor(mod(gl_FragCoord.x, 8.0f)))];
                                                                                                break;
                                                                                            }
                                                                                            else
                                                                                            {
                                                                                                if (_92 == 22)
                                                                                                {
                                                                                                    float3 _2708[3] = { _2547, 1.0f.xxx, 1.0f.xxx };
                                                                                                    float3 _2518[3] = _2708;
                                                                                                    _6494 = _2518[int(floor(mod(gl_FragCoord.x, 3.0f)))];
                                                                                                    break;
                                                                                                }
                                                                                                else
                                                                                                {
                                                                                                    if (_92 == 23)
                                                                                                    {
                                                                                                        float3 _2694[4] = { _2547, _2547, 1.0f.xxx, 1.0f.xxx };
                                                                                                        float3 _2519[4] = _2694;
                                                                                                        _6494 = _2519[int(floor(mod(gl_FragCoord.x, 4.0f)))];
                                                                                                        break;
                                                                                                    }
                                                                                                    else
                                                                                                    {
                                                                                                        if (_92 == 24)
                                                                                                        {
                                                                                                            float3 _2641[10] = { _2532, _2545, _2535, _2535, _2535, _2528, _2528, _2528, _2542, _2532 };
                                                                                                            float3 _2661[10] = { _2528, _2528, _2528, _2542, _2532, _2532, _2545, _2535, _2535, _2535 };
                                                                                                            float3 _2674[6][10] = { _2641, _2641, _2641, _2661, _2661, _2661 };
                                                                                                            float3 _2520[6][10] = _2674;
                                                                                                            _6494 = _2520[int(floor(mod(gl_FragCoord.y, 6.0f)))][int(floor(mod(gl_FragCoord.x, 10.0f)))];
                                                                                                            break;
                                                                                                        }
                                                                                                        else
                                                                                                        {
                                                                                                            _6494 = 1.0f.xxx;
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
    float4 _2211 = float4((_6492 * clamp((_2466 - sqrt(dot(_2472, _2472))) * 800.0f, 0.0f, 1.0f)) * _6494, 1.0f);
    float3 _2216 = pow(_2211.xyz, 1.13636362552642822265625f.xxx);
    float4 _6662 = _2211;
    _6662.x = _2216.x;
    _6662.y = _2216.y;
    _6662.z = _2216.z;
    float3 _3378 = _6662.xyz * ((1.0f - (global_SCANLINE_SINE_COMP_B * 0.3333333432674407958984375f)) + dot(float2(0.0f, global_SCANLINE_SINE_COMP_B) * sin(_2323 * float2(3.1415927410125732421875f * params_OutputSize.x, 6.283185482025146484375f * params_SourceSize.y)), 1.0f.xx));
    float4 _6671 = _6662;
    _6671.x = _3378.x;
    _6671.y = _3378.y;
    _6671.z = _3378.z;
    float4 _6535;
    if (_2164)
    {
        float2 _5666 = (_2298 * 2.0f) * global_zoom;
        float _5687 = dot(_5666, _5666);
        float2 _5672 = ((_5666 * global_curvature) / sqrt(_2333 - _5687).xx) * 0.5f.xx;
        float2 _5674 = _5672 + 0.5f.xx;
        float2 _5724 = ((_5666 * (global_curvature * 1.25f)) / sqrt((1.5625f * _2333) - _5687).xx) * 0.5f.xx;
        float _5050 = distance(_5674, 0.5f.xx);
        float _5056 = 0.0040000001899898052215576171875f * global_smoothness;
        float _5059 = (-0.0040000001899898052215576171875f) * global_smoothness;
        float _5854 = length(max(abs(_5672) - _2312, 0.0f.xx)) - 0.0500000007450580596923828125f;
        float _5062 = smoothstep(_5056, _5059, _5854);
        float2 _5889 = _5724 + 0.5f.xx;
        float4 _6519;
        _6519 = 0.0f.xxxx;
        for (int _6518 = 0; _6518 < 12; )
        {
            float2 _5077 = float(_6518).xx;
            _6519 += ((clamp((frac(sin(dot(_5889 + _5077, float2(12.98980045318603515625f, 78.233001708984375f))) * 43758.546875f) * 0.0500000007450580596923828125f).xxxx + float4(0.775000035762786865234375f, 0.775000035762786865234375f, 0.5750000476837158203125f, -0.02500000037252902984619140625f), 0.0f.xxxx, 1.0f.xxxx) + ((frac(sin(dot((_5724 + 1.5f.xx) + _5077, float2(12.98980045318603515625f, 78.233001708984375f))) * 43758.546875f) * 0.25f) * cos((_5889.x - 0.5f) * 4.712249755859375f)).xxxx) * 0.083333335816860198974609375f.xxxx);
            _6518++;
            continue;
        }
        float _5120 = (global_height * 0.3125000298023223876953125f) * global_width;
        float _5125 = _5120 - 0.02500000037252902984619140625f;
        float _5127 = _5120 + 0.02500000037252902984619140625f;
        float _5130 = _5674.x - 0.5f;
        float _5132 = _5674.y;
        float _5163 = smoothstep(_5059, _5056, _5854);
        float2 _5967 = _2312 + 0.0500000007450580596923828125f.xx;
        float2 _5972 = abs(_5724);
        float _5979 = length(max(_5972 - _5967, 0.0f.xx)) - 0.0500000007450580596923828125f;
        float _5173 = smoothstep(_5056, _5059, _5979);
        float4 _5179 = _6519 - 0.4000000059604644775390625f.xxxx;
        float _5183 = global_smoothness * (-0.008000000379979610443115234375f);
        float _5187 = global_smoothness * 0.008000000379979610443115234375f;
        float2 _5983 = abs(_5724 + float2(0.0f, -0.00499999523162841796875f));
        float2 _5994 = abs(_5724 + float2(0.0f, 0.00499999523162841796875f));
        float _5245 = smoothstep(_5059, _5056, _5979);
        float2 _5263 = _2312 + 0.1500000059604644775390625f.xx;
        float _6023 = length(max(_5972 - _5263, 0.0f.xx)) - 0.0500000007450580596923828125f;
        float _5265 = smoothstep(_5056, _5059, _6023);
        float4 _5268 = ((((max(0.0f, (0.660000026226043701171875f * global_shine) - distance(_5674, float2(0.5f, 1.0f))) * smoothstep(global_smoothness * 0.00200000009499490261077880859375f, global_smoothness * (-0.00200000009499490261077880859375f), length(max(abs(_5672 + float2(0.0f, 0.0300000011920928955078125f)) - _2312, 0.0f.xx)) - 0.0500000007450580596923828125f)).xxxx + (max(0.0f, 0.100000001490116119384765625f - (0.5f * _5050)) * _5062).xxxx) + ((((_6519 * 0.3333333432674407958984375f.xxxx) * ((1.0f + smoothstep(_5125, _5127, abs(atan2(_5130, _5132 - 0.5f)) * 0.318319261074066162109375f)) + smoothstep(_5127, _5125, abs(atan2(_5130, 0.5f - _5132)) * 0.318319261074066162109375f))) * _5163) * _5173)) + ((_5179 * smoothstep(_5183, _5187, length(max(_5983 - _5967, 0.0f.xx)) - 0.0500000007450580596923828125f)) * smoothstep(_5187, _5183, length(max(_5994 - _5967, 0.0f.xx)) - 0.0500000007450580596923828125f))) + ((_6519 * _5245) * _5265);
        float4 _6524;
        _6524 = (((max(0.0f, 0.20000000298023223876953125f - (0.300000011920928955078125f * _5050)) * _5062).xxxx + ((float4(0.11200000345706939697265625f, 0.11200000345706939697265625f, 0.083999998867511749267578125f, 0.0f) * _5163) * _5173)) - ((float4(0.800000011920928955078125f, 0.800000011920928955078125f, 0.60000002384185791015625f, 0.0f) * smoothstep(_5183, global_smoothness * 0.0400000028312206268310546875f, _5979)) * smoothstep(_5187, _5183, _5979))) + ((float4(0.16000001132488250732421875f, 0.16000001132488250732421875f, 0.12000000476837158203125f, 0.0f) * _5245) * _5265);
        for (int _6523 = 0; _6523 < 5; )
        {
            float2 _5469 = _2323 + float(_6523).xx;
            float2 _5486 = _2323 + (((float2(frac(sin(dot(_5469, float2(12.98980045318603515625f, 78.233001708984375f))) * 43758.546875f), frac(sin(dot(_5469 + 0.100000001490116119384765625f.xx, float2(12.98980045318603515625f, 78.233001708984375f))) * 43758.546875f)) - 0.5f.xx) * 0.039999999105930328369140625f) * global_blur_size);
            _6524 += (((Source.Sample(_Source_sampler, 1.0f.xx - (float2(1.0f - _5486.x, _5486.y) + ((float2(length(max(abs(_5486 - float2(0.50010001659393310546875f, 0.5f)) - 0.52499997615814208984375f.xx, 0.0f.xx)) - length(max(abs(_5486 + float2(-0.4999000132083892822265625f, -0.5f)) - 0.52499997615814208984375f.xx, 0.0f.xx)), length(max(abs(_5486 - float2(0.5f, 0.50010001659393310546875f)) - 0.52499997615814208984375f.xx, 0.0f.xx)) - length(max(abs(_5486 + float2(-0.5f, -0.4999000132083892822265625f)) - 0.52499997615814208984375f.xx, 0.0f.xx))) * 10000.0f.xx) * (length(max(abs(_5486 - 0.5f.xx) - 0.52499997615814208984375f.xx, 0.0f.xx)) - 0.01666666753590106964111328125f)))) * float4(0.117999993264675140380859375f, 0.117999993264675140380859375f, 0.12600000202655792236328125f, 0.0f)) * _5163) * _5173);
            _6523++;
            continue;
        }
        float4 _5534 = lerp(_6524, (_5268 + ((_5179 * smoothstep(_5183, _5187, length(max(_5994 - _5263, 0.0f.xx)) - 0.0500000007450580596923828125f)) * smoothstep(_5187, _5183, length(max(_5983 - _5263, 0.0f.xx)) - 0.0500000007450580596923828125f))) + (((float4(1.0f, 1.0f, 1.0f, 0.0f) * max(0.0f, 1.0f - ((2.0f * _2148.y) / params_OutputSize.y))) * smoothstep(-0.25f, 0.25f, length(max(abs(_2321 + float2(0.0f, 0.699999988079071044921875f)) - float2(_2308 + 0.25f, _2311 - 0.1500000059604644775390625f), 0.0f.xx)) - 0.100000001490116119384765625f)) * smoothstep(_5183, _5187, _6023)), global_dimmer.xxxx);
        float _5536 = _2323.x;
        bool _5537 = _5536 > 0.0f;
        bool _5543;
        if (_5537)
        {
            _5543 = _5536 < 1.0f;
        }
        else
        {
            _5543 = _5537;
        }
        bool _5549;
        if (_5543)
        {
            _5549 = _2323.y > 0.0f;
        }
        else
        {
            _5549 = _5543;
        }
        bool _5555;
        if (_5549)
        {
            _5555 = _2323.y < 1.0f;
        }
        else
        {
            _5555 = _5549;
        }
        float4 _6534;
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
        float2 _4113 = (_2298 * 2.0f) * global_zoom;
        float _4134 = dot(_4113, _4113);
        float2 _4119 = ((_4113 * global_curvature) / sqrt(_2333 - _4134).xx) * 0.5f.xx;
        float2 _4121 = _4119 + 0.5f.xx;
        float2 _4171 = ((_4113 * (global_curvature * 1.25f)) / sqrt((1.5625f * _2333) - _4134).xx) * 0.5f.xx;
        float _3497 = distance(_4121, 0.5f.xx);
        float _3503 = 0.0040000001899898052215576171875f * global_smoothness;
        float _3506 = (-0.0040000001899898052215576171875f) * global_smoothness;
        float _4301 = length(max(abs(_4119) - _2312, 0.0f.xx)) - 0.0500000007450580596923828125f;
        float _3509 = smoothstep(_3503, _3506, _4301);
        float2 _4336 = _4171 + 0.5f.xx;
        float4 _6500;
        _6500 = 0.0f.xxxx;
        for (int _6499 = 0; _6499 < 12; )
        {
            float2 _3524 = float(_6499).xx;
            _6500 += ((clamp((frac(sin(dot(_4336 + _3524, float2(12.98980045318603515625f, 78.233001708984375f))) * 43758.546875f) * 0.0500000007450580596923828125f).xxxx + float4(0.775000035762786865234375f, 0.775000035762786865234375f, 0.5750000476837158203125f, -0.02500000037252902984619140625f), 0.0f.xxxx, 1.0f.xxxx) + ((frac(sin(dot((_4171 + 1.5f.xx) + _3524, float2(12.98980045318603515625f, 78.233001708984375f))) * 43758.546875f) * 0.25f) * cos((_4336.x - 0.5f) * 4.712249755859375f)).xxxx) * 0.083333335816860198974609375f.xxxx);
            _6499++;
            continue;
        }
        float _3567 = (global_height * 0.3125000298023223876953125f) * global_width;
        float _3572 = _3567 - 0.02500000037252902984619140625f;
        float _3574 = _3567 + 0.02500000037252902984619140625f;
        float _3577 = _4121.x - 0.5f;
        float _3579 = _4121.y;
        float _3610 = smoothstep(_3506, _3503, _4301);
        float2 _4414 = _2312 + 0.0500000007450580596923828125f.xx;
        float2 _4419 = abs(_4171);
        float _4426 = length(max(_4419 - _4414, 0.0f.xx)) - 0.0500000007450580596923828125f;
        float _3620 = smoothstep(_3503, _3506, _4426);
        float4 _3626 = _6500 - 0.4000000059604644775390625f.xxxx;
        float _3630 = global_smoothness * (-0.008000000379979610443115234375f);
        float _3634 = global_smoothness * 0.008000000379979610443115234375f;
        float2 _4430 = abs(_4171 + float2(0.0f, -0.00499999523162841796875f));
        float2 _4441 = abs(_4171 + float2(0.0f, 0.00499999523162841796875f));
        float _3692 = smoothstep(_3506, _3503, _4426);
        float2 _3710 = _2312 + 0.1500000059604644775390625f.xx;
        float _4470 = length(max(_4419 - _3710, 0.0f.xx)) - 0.0500000007450580596923828125f;
        float _3712 = smoothstep(_3503, _3506, _4470);
        float4 _3715 = ((((max(0.0f, (0.660000026226043701171875f * global_shine) - distance(_4121, float2(0.5f, 1.0f))) * smoothstep(global_smoothness * 0.00200000009499490261077880859375f, global_smoothness * (-0.00200000009499490261077880859375f), length(max(abs(_4119 + float2(0.0f, 0.0300000011920928955078125f)) - _2312, 0.0f.xx)) - 0.0500000007450580596923828125f)).xxxx + (max(0.0f, 0.100000001490116119384765625f - (0.5f * _3497)) * _3509).xxxx) + ((((_6500 * 0.3333333432674407958984375f.xxxx) * ((1.0f + smoothstep(_3572, _3574, abs(atan2(_3577, _3579 - 0.5f)) * 0.318319261074066162109375f)) + smoothstep(_3574, _3572, abs(atan2(_3577, 0.5f - _3579)) * 0.318319261074066162109375f))) * _3610) * _3620)) + ((_3626 * smoothstep(_3630, _3634, length(max(_4430 - _4414, 0.0f.xx)) - 0.0500000007450580596923828125f)) * smoothstep(_3634, _3630, length(max(_4441 - _4414, 0.0f.xx)) - 0.0500000007450580596923828125f))) + ((_6500 * _3692) * _3712);
        float4 _6505;
        _6505 = (((max(0.0f, 0.20000000298023223876953125f - (0.300000011920928955078125f * _3497)) * _3509).xxxx + ((float4(0.11200000345706939697265625f, 0.11200000345706939697265625f, 0.083999998867511749267578125f, 0.0f) * _3610) * _3620)) - ((float4(0.800000011920928955078125f, 0.800000011920928955078125f, 0.60000002384185791015625f, 0.0f) * smoothstep(_3630, global_smoothness * 0.0400000028312206268310546875f, _4426)) * smoothstep(_3634, _3630, _4426))) + ((float4(0.16000001132488250732421875f, 0.16000001132488250732421875f, 0.12000000476837158203125f, 0.0f) * _3692) * _3712);
        for (int _6504 = 0; _6504 < 5; )
        {
            float2 _3916 = _2323 + float(_6504).xx;
            float2 _3933 = _2323 + (((float2(frac(sin(dot(_3916, float2(12.98980045318603515625f, 78.233001708984375f))) * 43758.546875f), frac(sin(dot(_3916 + 0.100000001490116119384765625f.xx, float2(12.98980045318603515625f, 78.233001708984375f))) * 43758.546875f)) - 0.5f.xx) * 0.039999999105930328369140625f) * global_blur_size);
            _6505 += (((vt220_refpass.Sample(_vt220_refpass_sampler, 1.0f.xx - (float2(1.0f - _3933.x, _3933.y) + ((float2(length(max(abs(_3933 - float2(0.50010001659393310546875f, 0.5f)) - 0.52499997615814208984375f.xx, 0.0f.xx)) - length(max(abs(_3933 + float2(-0.4999000132083892822265625f, -0.5f)) - 0.52499997615814208984375f.xx, 0.0f.xx)), length(max(abs(_3933 - float2(0.5f, 0.50010001659393310546875f)) - 0.52499997615814208984375f.xx, 0.0f.xx)) - length(max(abs(_3933 + float2(-0.5f, -0.4999000132083892822265625f)) - 0.52499997615814208984375f.xx, 0.0f.xx))) * 10000.0f.xx) * (length(max(abs(_3933 - 0.5f.xx) - 0.52499997615814208984375f.xx, 0.0f.xx)) - 0.01666666753590106964111328125f)))) * float4(0.117999993264675140380859375f, 0.117999993264675140380859375f, 0.12600000202655792236328125f, 0.0f)) * _3610) * _3620);
            _6504++;
            continue;
        }
        float4 _3981 = lerp(_6505, (_3715 + ((_3626 * smoothstep(_3630, _3634, length(max(_4441 - _3710, 0.0f.xx)) - 0.0500000007450580596923828125f)) * smoothstep(_3634, _3630, length(max(_4430 - _3710, 0.0f.xx)) - 0.0500000007450580596923828125f))) + (((float4(1.0f, 1.0f, 1.0f, 0.0f) * max(0.0f, 1.0f - ((2.0f * _2148.y) / params_OutputSize.y))) * smoothstep(-0.25f, 0.25f, length(max(abs(_2321 + float2(0.0f, 0.699999988079071044921875f)) - float2(_2308 + 0.25f, _2311 - 0.1500000059604644775390625f), 0.0f.xx)) - 0.100000001490116119384765625f)) * smoothstep(_3630, _3634, _4470)), global_dimmer.xxxx);
        float _3983 = _2323.x;
        bool _3984 = _3983 > 0.0f;
        bool _3990;
        if (_3984)
        {
            _3990 = _3983 < 1.0f;
        }
        else
        {
            _3990 = _3984;
        }
        bool _3996;
        if (_3990)
        {
            _3996 = _2323.y > 0.0f;
        }
        else
        {
            _3996 = _3990;
        }
        bool _4002;
        if (_3996)
        {
            _4002 = _2323.y < 1.0f;
        }
        else
        {
            _4002 = _3996;
        }
        float4 _6515;
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

SPIRV_Cross_Output main(SPIRV_Cross_Input stage_input)
{
    gl_FragCoord = stage_input.gl_FragCoord;
    gl_FragCoord.w = 1.0 / gl_FragCoord.w;
    vTexCoord = stage_input.vTexCoord;
    frag_main();
    SPIRV_Cross_Output stage_output;
    stage_output.FragColor = FragColor;
    return stage_output;
}
