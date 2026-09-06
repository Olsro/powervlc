// Generated from crt/shaders/crtsim/screen.slang. See slang/upstream for licence/source.
cbuffer UBO : register(b0)
{
    float4 global_SourceSize : packoffset(c4);
};

cbuffer Push : register(b1)
{
    float params_CRTMask_Scale : packoffset(c0);
    float params_Tuning_Satur : packoffset(c0.y);
    float params_Tuning_Mask_Brightness : packoffset(c0.z);
    float params_Tuning_Mask_Opacity : packoffset(c0.w);
};

Texture2D<float4> shadowMaskSampler : register(t3);
SamplerState _shadowMaskSampler_sampler : register(s3);
Texture2D<float4> Source : register(t2);
SamplerState _Source_sampler : register(s2);

static float4 FragColor;
static float2 vTexCoord;

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
    float4 _155 = float4(Source.Sample(_Source_sampler, vTexCoord).xyz * lerp(1.0f.xxx, shadowMaskSampler.Sample(_shadowMaskSampler_sampler, frac((vTexCoord * global_SourceSize.xy) / params_CRTMask_Scale.xx)).xyz + params_Tuning_Mask_Brightness.xxx, params_Tuning_Mask_Opacity.xxx), 1.0f);
    float _157 = dot(float4(0.2989999949932098388671875f, 0.58700001239776611328125f, 0.114000000059604644775390625f, 0.0f), _155);
    FragColor = lerp(float4(_157, _157, _157, 1.0f), _155, params_Tuning_Satur.xxxx);
}

SPIRV_Cross_Output main(SPIRV_Cross_Input stage_input)
{
    vTexCoord = stage_input.vTexCoord;
    frag_main();
    SPIRV_Cross_Output stage_output;
    stage_output.FragColor = FragColor;
    return stage_output;
}
