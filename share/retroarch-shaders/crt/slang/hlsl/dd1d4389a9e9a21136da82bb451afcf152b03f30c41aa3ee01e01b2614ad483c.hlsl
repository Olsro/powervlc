// Generated from crt/shaders/crtsim/present.slang. See slang/upstream for licence/source.
cbuffer UBO : register(b0)
{
    float4 global_SourceSize : packoffset(c4);
    float global_BloomPower : packoffset(c7.y);
    float global_BloomScalar : packoffset(c7.z);
    float global_Tuning_Overscan : packoffset(c7.w);
    float global_Tuning_Barrel : packoffset(c8);
    float global_mask_toggle : packoffset(c8.y);
};

cbuffer Push : register(b1)
{
    float params_CRTMask_Scale : packoffset(c0);
    float params_Tuning_Satur : packoffset(c0.y);
    float params_Tuning_Mask_Brightness : packoffset(c0.z);
    float params_Tuning_Mask_Opacity : packoffset(c0.w);
};

Texture2D<float4> shadowMaskSampler : register(t4);
SamplerState _shadowMaskSampler_sampler : register(s4);
Texture2D<float4> CRTPASS : register(t3);
SamplerState _CRTPASS_sampler : register(s3);
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
    float2 _145 = ((vTexCoord * global_Tuning_Overscan) - ((global_Tuning_Overscan - 1.0f) * 0.5f).xx) - 0.5f.xx;
    float _149 = _145.x;
    float _155 = _145.y;
    float2 _169 = (_145 + (_145 * (global_Tuning_Barrel * ((_149 * _149) + (_155 * _155))))) + 0.5f.xx;
    bool _176 = global_mask_toggle > 0.5f;
    bool2 _180 = _176.xx;
    float2 _181 = float2(_180.x ? vTexCoord.x : _169.x, _180.y ? vTexCoord.y : _169.y);
    float4 _295;
    if (_176)
    {
        float4 _263 = float4(CRTPASS.Sample(_CRTPASS_sampler, _181).xyz * lerp(1.0f.xxx, shadowMaskSampler.Sample(_shadowMaskSampler_sampler, frac((_181 * global_SourceSize.xy) / params_CRTMask_Scale.xx)).xyz + params_Tuning_Mask_Brightness.xxx, params_Tuning_Mask_Opacity.xxx), 1.0f);
        float _265 = dot(float4(0.2989999949932098388671875f, 0.58700001239776611328125f, 0.114000000059604644775390625f, 0.0f), _263);
        _295 = lerp(float4(_265, _265, _265, 1.0f), _263, params_Tuning_Satur.xxxx);
    }
    else
    {
        _295 = CRTPASS.Sample(_CRTPASS_sampler, _181);
    }
    float4 _202 = Source.Sample(_Source_sampler, _181);
    float _283 = dot(_202, float4(0.2989999949932098388671875f, 0.58700001239776611328125f, 0.114000000059604644775390625f, 0.0f));
    FragColor = _295 + (((_202 / _283.xxxx) * pow(_283, global_BloomPower)) * global_BloomScalar);
}

SPIRV_Cross_Output main(SPIRV_Cross_Input stage_input)
{
    vTexCoord = stage_input.vTexCoord;
    frag_main();
    SPIRV_Cross_Output stage_output;
    stage_output.FragColor = FragColor;
    return stage_output;
}
