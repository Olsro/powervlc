// Generated from crt/shaders/glow/resolve.slang. See slang/upstream for licence/source.
cbuffer UBO : register(b0)
{
    float4 global_OutputSize : packoffset(c4);
    uint global_FrameCount : packoffset(c8);
};

cbuffer Push : register(b1)
{
    float params_BLOOM_STRENGTH : packoffset(c0);
    float params_OUTPUT_GAMMA : packoffset(c0.y);
    float params_CURVATURE : packoffset(c0.z);
    float params_warpX : packoffset(c0.w);
    float params_warpY : packoffset(c1);
    float params_shadowMask : packoffset(c1.y);
    float params_maskDark : packoffset(c1.z);
    float params_maskLight : packoffset(c1.w);
    float params_cornersize : packoffset(c2);
    float params_cornersmooth : packoffset(c2.y);
    float params_noise_amt : packoffset(c2.z);
};

Texture2D<float4> CRTPass : register(t2);
SamplerState _CRTPass_sampler : register(s2);
Texture2D<float4> Source : register(t1);
SamplerState _Source_sampler : register(s1);

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
    bool _449 = params_CURVATURE > 0.5f;
    float2 _1033;
    if (_449)
    {
        float _605 = float(global_FrameCount);
        float2 _607 = sin(gl_FragCoord.xy) * mod(_605, 361.0f);
        float2 _687 = floor(_607);
        float2 _689 = frac(_607);
        float2 _697 = (_689 * _689) * (3.0f.xx - (_689 * 2.0f));
        float _704 = _697.x;
        float _717 = lerp(lerp(frac(sin(dot(_687, float2(12.98980045318603515625f, 4.141399860382080078125f))) * 43758.546875f), frac(sin(dot(_687 + float2(1.0f, 0.0f), float2(12.98980045318603515625f, 4.141399860382080078125f))) * 43758.546875f), _704), lerp(frac(sin(dot(_687 + float2(0.0f, 1.0f), float2(12.98980045318603515625f, 4.141399860382080078125f))) * 43758.546875f), frac(sin(dot(_687 + 1.0f.xx, float2(12.98980045318603515625f, 4.141399860382080078125f))) * 43758.546875f), _704), _697.y);
        float2 _616 = cos(gl_FragCoord.yx) * mod(_605, 873.0f);
        float2 _759 = floor(_616);
        float2 _761 = frac(_616);
        float2 _769 = (_761 * _761) * (3.0f.xx - (_761 * 2.0f));
        float _776 = _769.x;
        float _789 = lerp(lerp(frac(sin(dot(_759, float2(12.98980045318603515625f, 4.141399860382080078125f))) * 43758.546875f), frac(sin(dot(_759 + float2(1.0f, 0.0f), float2(12.98980045318603515625f, 4.141399860382080078125f))) * 43758.546875f), _776), lerp(frac(sin(dot(_759 + float2(0.0f, 1.0f), float2(12.98980045318603515625f, 4.141399860382080078125f))) * 43758.546875f), frac(sin(dot(_759 + 1.0f.xx, float2(12.98980045318603515625f, 4.141399860382080078125f))) * 43758.546875f), _776), _769.y);
        float2 _630 = ((vTexCoord + ((float2(_717 * _717, _789 * _789) * 0.001000000047497451305389404296875f) * params_noise_amt)) * 2.0f) - 1.0f.xx;
        float _632 = _630.x;
        float _637 = _630.y;
        float _642 = sqrt((_632 * _632) + (_637 * _637));
        float2 _657 = 1.0f.xx / (1.0f.xx + ((float2(params_warpX, params_warpY) * 15.0f) * 0.20000000298023223876953125f));
        _1033 = ((((_630 / _642.xx) * (1.0f.xx - pow((1.0f - (_642 * 0.707106769084930419921875f)).xx, _657))) / (1.0f.xx - pow(0.292893230915069580078125f.xx, _657))) * 0.5f) + 0.5f.xx;
    }
    else
    {
        _1033 = vTexCoord;
    }
    FragColor = float4(pow(clamp((CRTPass.Sample(_CRTPass_sampler, _1033).xyz * 1.14999997615814208984375f) + (Source.Sample(_Source_sampler, _1033).xyz * params_BLOOM_STRENGTH), 0.0f.xxx, 1.0f.xxx), (1.0f / params_OUTPUT_GAMMA).xxx), 1.0f);
    bool _502 = _1033.x > 9.9999997473787516355514526367188e-05f;
    bool _509;
    if (_502)
    {
        _509 = _1033.x < 0.99989998340606689453125f;
    }
    else
    {
        _509 = _502;
    }
    bool _515;
    if (_509)
    {
        _515 = _1033.y > 9.9999997473787516355514526367188e-05f;
    }
    else
    {
        _515 = _509;
    }
    bool _521;
    if (_515)
    {
        _521 = _1033.y < 0.99989998340606689453125f;
    }
    else
    {
        _521 = _515;
    }
    if (_521)
    {
        float4 _524 = FragColor;
        FragColor.x = _524.x;
        FragColor.y = _524.y;
        FragColor.z = _524.z;
    }
    else
    {
        FragColor.x = 0.0f;
        FragColor.y = 0.0f;
        FragColor.z = 0.0f;
    }
    float _1034;
    if (_449)
    {
        float2 _835 = params_cornersize.xx;
        float2 _840 = _835 - min(min(_1033, 1.0f.xx - _1033) * float2(1.0f, 0.75f), _835);
        _1034 = clamp((params_cornersize - sqrt(dot(_840, _840))) * params_cornersmooth, 0.0f, 1.0f);
    }
    else
    {
        _1034 = 1.0f;
    }
    float4 _552 = FragColor;
    float3 _554 = _552.xyz * _1034;
    FragColor.x = _554.x;
    FragColor.y = _554.y;
    FragColor.z = _554.z;
    if (params_shadowMask > 0.0f)
    {
        float4 _566 = FragColor;
        float2 _578 = (vTexCoord * global_OutputSize.xy) * 1.00000095367431640625f;
        float3 _864 = params_maskDark.xxx;
        float3 _1122;
        if (params_shadowMask == 1.0f)
        {
            float _872 = _578.x;
            float _1037;
            if (frac((_578.y + float(frac(_872 * 0.16666667163372039794921875f) < 0.5f)) * 0.5f) < 0.5f)
            {
                _1037 = params_maskDark;
            }
            else
            {
                _1037 = params_maskLight;
            }
            float _892 = frac(_872 * 0.3333333432674407958984375f);
            float3 _1120;
            if (_892 < 0.333000004291534423828125f)
            {
                float3 _1067 = _864;
                _1067.x = params_maskLight;
                _1120 = _1067;
            }
            else
            {
                float3 _1121;
                if (_892 < 0.66600000858306884765625f)
                {
                    float3 _1070 = _864;
                    _1070.y = params_maskLight;
                    _1121 = _1070;
                }
                else
                {
                    float3 _1072 = _864;
                    _1072.z = params_maskLight;
                    _1121 = _1072;
                }
                _1120 = _1121;
            }
            _1122 = _1120 * _1037;
        }
        else
        {
            float3 _1123;
            if (params_shadowMask == 2.0f)
            {
                float _926 = frac(_578.x * 0.3333333432674407958984375f);
                float3 _1124;
                if (_926 < 0.333000004291534423828125f)
                {
                    float3 _1078 = _864;
                    _1078.x = params_maskLight;
                    _1124 = _1078;
                }
                else
                {
                    float3 _1125;
                    if (_926 < 0.66600000858306884765625f)
                    {
                        float3 _1081 = _864;
                        _1081.y = params_maskLight;
                        _1125 = _1081;
                    }
                    else
                    {
                        float3 _1083 = _864;
                        _1083.z = params_maskLight;
                        _1125 = _1083;
                    }
                    _1124 = _1125;
                }
                _1123 = _1124;
            }
            else
            {
                float3 _1126;
                if (params_shadowMask == 3.0f)
                {
                    float _964 = frac((_578.x + (_578.y * 3.0f)) * 0.16666667163372039794921875f);
                    float3 _1127;
                    if (_964 < 0.333000004291534423828125f)
                    {
                        float3 _1093 = _864;
                        _1093.x = params_maskLight;
                        _1127 = _1093;
                    }
                    else
                    {
                        float3 _1128;
                        if (_964 < 0.66600000858306884765625f)
                        {
                            float3 _1096 = _864;
                            _1096.y = params_maskLight;
                            _1128 = _1096;
                        }
                        else
                        {
                            float3 _1098 = _864;
                            _1098.z = params_maskLight;
                            _1128 = _1098;
                        }
                        _1127 = _1128;
                    }
                    _1126 = _1127;
                }
                else
                {
                    float3 _1129;
                    if (params_shadowMask == 4.0f)
                    {
                        float2 _994 = floor(_578 * float2(1.0f, 0.5f));
                        float _1005 = frac((_994.x + (_994.y * 3.0f)) * 0.16666667163372039794921875f);
                        float3 _1130;
                        if (_1005 < 0.333000004291534423828125f)
                        {
                            float3 _1108 = _864;
                            _1108.x = params_maskLight;
                            _1130 = _1108;
                        }
                        else
                        {
                            float3 _1131;
                            if (_1005 < 0.66600000858306884765625f)
                            {
                                float3 _1111 = _864;
                                _1111.y = params_maskLight;
                                _1131 = _1111;
                            }
                            else
                            {
                                float3 _1113 = _864;
                                _1113.z = params_maskLight;
                                _1131 = _1113;
                            }
                            _1130 = _1131;
                        }
                        _1129 = _1130;
                    }
                    else
                    {
                        _1129 = _864;
                    }
                    _1126 = _1129;
                }
                _1123 = _1126;
            }
            _1122 = _1123;
        }
        float3 _584 = pow(pow(_566.xyz, 2.2000000476837158203125f.xxx) * _1122, 0.4545454680919647216796875f.xxx);
        FragColor.x = _584.x;
        FragColor.y = _584.y;
        FragColor.z = _584.z;
    }
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
