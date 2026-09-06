// Generated from crt/shaders/crt-royale/src-fast/crt-royale-brightpass.slang. See slang/upstream for licence/source.
cbuffer UBO : register(b0)
{
    float global_levels_contrast : packoffset(c4.z);
    float global_bloom_underestimate_levels : packoffset(c4.w);
    float global_bloom_excess : packoffset(c5);
};

Texture2D<float4> MASKED_SCANLINES : register(t2);
SamplerState _MASKED_SCANLINES_sampler : register(s2);
Texture2D<float4> ORIG_LINEARIZED : register(t3);
SamplerState _ORIG_LINEARIZED_sampler : register(s3);

static float2 tex_uv;
static float undim_mask_contrast_factors;
static float center_weight;
static float4 FragColor;

struct SPIRV_Cross_Input
{
    float2 tex_uv : TEXCOORD0;
    float center_weight : TEXCOORD1;
    float undim_mask_contrast_factors : TEXCOORD2;
};

struct SPIRV_Cross_Output
{
    float4 FragColor : SV_Target0;
};

void frag_main()
{
    float3 _207 = MASKED_SCANLINES.Sample(_MASKED_SCANLINES_sampler, tex_uv).xyz;
    float3 _213 = _207 * undim_mask_contrast_factors;
    FragColor = float4(_207 * lerp(clamp((((1.0f.xxx - (max(0.0f.xxx, (ORIG_LINEARIZED.Sample(_ORIG_LINEARIZED_sampler, tex_uv).xyz * global_levels_contrast) - (_213 * center_weight)) * global_bloom_underestimate_levels)) / (_213 * global_bloom_underestimate_levels)) - 1.0f.xxx) / (center_weight - 1.0f).xxx, 0.0f.xxx, 1.0f.xxx), 1.0f.xxx, global_bloom_excess.xxx), 1.0f);
}

SPIRV_Cross_Output main(SPIRV_Cross_Input stage_input)
{
    tex_uv = stage_input.tex_uv;
    undim_mask_contrast_factors = stage_input.undim_mask_contrast_factors;
    center_weight = stage_input.center_weight;
    frag_main();
    SPIRV_Cross_Output stage_output;
    stage_output.FragColor = FragColor;
    return stage_output;
}
