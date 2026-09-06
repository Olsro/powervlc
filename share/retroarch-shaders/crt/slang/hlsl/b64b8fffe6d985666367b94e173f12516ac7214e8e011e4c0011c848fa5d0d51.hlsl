// Generated from crt/shaders/fakelottes.slang. See slang/upstream for licence/source.
cbuffer Push : register(b1)
{
    float4 params_SourceSize : packoffset(c0);
    float4 params_OutputSize : packoffset(c2);
    float params_shadowMask : packoffset(c3.y);
    float params_SCANLINE_SINE_COMP_B : packoffset(c3.z);
    float params_warpX : packoffset(c3.w);
    float params_warpY : packoffset(c4);
    float params_maskDark : packoffset(c4.y);
    float params_maskLight : packoffset(c4.z);
    float params_monitor_gamma : packoffset(c4.w);
    float params_crt_gamma : packoffset(c5);
    float params_SCANLINE_SINE_COMP_A : packoffset(c5.y);
    float params_SCANLINE_BASE_BRIGHTNESS : packoffset(c5.z);
};

Texture2D<float4> Source : register(t2);
SamplerState _Source_sampler : register(s2);

static float2 vTexCoord;
static float4 FragColor;

struct SPIRV_Cross_Input
{
    float2 vTexCoord : TEXCOORD0;
};

struct SPIRV_Cross_Output
{
    float4 FragColor : SV_Target0;
};

void frag_main()
{
    float2 _391 = (vTexCoord * 2.0f) - 1.0f.xx;
    float _393 = _391.y;
    float _402 = _391.x;
    float2 _416 = ((_391 * float2(1.0f + ((_393 * _393) * params_warpX), 1.0f + ((_402 * _402) * params_warpY))) * 0.5f) + 0.5f.xx;
    float _336 = 1.0f / params_monitor_gamma;
    float4 _351 = Source.Sample(_Source_sampler, _416);
    float2 _361 = (vTexCoord * params_OutputSize.xy) * 1.00010001659393310546875f;
    float3 _428 = params_maskDark.xxx;
    float3 _764;
    if (params_shadowMask == 1.0f)
    {
        float _436 = _361.x;
        float _643;
        if (frac((_361.y + float(frac(_436 * 0.16666667163372039794921875f) < 0.5f)) * 0.5f) < 0.5f)
        {
            _643 = params_maskDark;
        }
        else
        {
            _643 = params_maskLight;
        }
        float _456 = frac(_436 * 0.3333333432674407958984375f);
        float3 _762;
        if (_456 < 0.333000004291534423828125f)
        {
            float3 _701 = _428;
            _701.x = params_maskLight;
            _762 = _701;
        }
        else
        {
            float3 _763;
            if (_456 < 0.66600000858306884765625f)
            {
                float3 _704 = _428;
                _704.y = params_maskLight;
                _763 = _704;
            }
            else
            {
                float3 _706 = _428;
                _706.z = params_maskLight;
                _763 = _706;
            }
            _762 = _763;
        }
        _764 = _762 * _643;
    }
    else
    {
        float3 _765;
        if (params_shadowMask == 2.0f)
        {
            float _490 = frac(_361.x * 0.3333333432674407958984375f);
            float3 _766;
            if (_490 < 0.333000004291534423828125f)
            {
                float3 _712 = _428;
                _712.x = params_maskLight;
                _766 = _712;
            }
            else
            {
                float3 _767;
                if (_490 < 0.66600000858306884765625f)
                {
                    float3 _715 = _428;
                    _715.y = params_maskLight;
                    _767 = _715;
                }
                else
                {
                    float3 _717 = _428;
                    _717.z = params_maskLight;
                    _767 = _717;
                }
                _766 = _767;
            }
            _765 = _766;
        }
        else
        {
            float3 _768;
            if (params_shadowMask == 3.0f)
            {
                float _528 = frac((_361.x + (_361.y * 3.0f)) * 0.16666667163372039794921875f);
                float3 _769;
                if (_528 < 0.333000004291534423828125f)
                {
                    float3 _727 = _428;
                    _727.x = params_maskLight;
                    _769 = _727;
                }
                else
                {
                    float3 _770;
                    if (_528 < 0.66600000858306884765625f)
                    {
                        float3 _730 = _428;
                        _730.y = params_maskLight;
                        _770 = _730;
                    }
                    else
                    {
                        float3 _732 = _428;
                        _732.z = params_maskLight;
                        _770 = _732;
                    }
                    _769 = _770;
                }
                _768 = _769;
            }
            else
            {
                float3 _771;
                if (params_shadowMask == 4.0f)
                {
                    float2 _558 = floor(_361 * float2(1.0f, 0.5f));
                    float _569 = frac((_558.x + (_558.y * 3.0f)) * 0.16666667163372039794921875f);
                    float3 _772;
                    if (_569 < 0.333000004291534423828125f)
                    {
                        float3 _742 = _428;
                        _742.x = params_maskLight;
                        _772 = _742;
                    }
                    else
                    {
                        float3 _773;
                        if (_569 < 0.66600000858306884765625f)
                        {
                            float3 _745 = _428;
                            _745.y = params_maskLight;
                            _773 = _745;
                        }
                        else
                        {
                            float3 _747 = _428;
                            _747.z = params_maskLight;
                            _773 = _747;
                        }
                        _772 = _773;
                    }
                    _771 = _772;
                }
                else
                {
                    _771 = 1.0f.xxx;
                }
                _768 = _771;
            }
            _765 = _768;
        }
        _764 = _765;
    }
    FragColor = pow(float4((pow(_351, float4(params_crt_gamma, params_crt_gamma, params_crt_gamma, 1.0f)) * float4(_764, 1.0f)).xyz * (params_SCANLINE_BASE_BRIGHTNESS + dot(float2(params_SCANLINE_SINE_COMP_A, params_SCANLINE_SINE_COMP_B) * sin((_416 - float2(0.0f, 0.25f * params_SourceSize.w)) * float2(3.141499996185302734375f * params_OutputSize.x, 6.28299999237060546875f * params_SourceSize.y)), 1.0f.xx)), 1.0f), float4(_336, _336, _336, 1.0f));
}

SPIRV_Cross_Output main(SPIRV_Cross_Input stage_input)
{
    vTexCoord = stage_input.vTexCoord;
    frag_main();
    SPIRV_Cross_Output stage_output;
    stage_output.FragColor = FragColor;
    return stage_output;
}
