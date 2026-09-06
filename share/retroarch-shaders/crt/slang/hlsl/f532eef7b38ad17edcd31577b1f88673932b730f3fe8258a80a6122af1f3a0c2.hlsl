// Generated from crt/shaders/crt-royale/src-fast/crt-royale-bloom-horizontal-reconstitute.slang. See slang/upstream for licence/source.
cbuffer UBO : register(b0)
{
    float global_lcd_gamma : packoffset(c4.y);
};

Texture2D<float4> Source : register(t2);
SamplerState _Source_sampler : register(s2);
Texture2D<float4> MASKED_SCANLINES : register(t4);
SamplerState _MASKED_SCANLINES_sampler : register(s4);
Texture2D<float4> BRIGHTPASS : register(t3);
SamplerState _BRIGHTPASS_sampler : register(s3);

static float2 video_uv;
static float2 bloom_dxdy;
static float weight_sum_inv;
static float4 w1_8;
static float4 w1_8_ratio;
static float undim_mask_contrast_factors;
static float4 FragColor;

struct SPIRV_Cross_Input
{
    float2 video_uv : TEXCOORD0;
    float2 bloom_dxdy : TEXCOORD1;
    float4 w1_8 : TEXCOORD3;
    float4 w1_8_ratio : TEXCOORD4;
    float weight_sum_inv : TEXCOORD5;
    float undim_mask_contrast_factors : TEXCOORD6;
};

struct SPIRV_Cross_Output
{
    float4 FragColor : SV_Target0;
};

void frag_main()
{
    float2 _419 = bloom_dxdy * (7.0f + w1_8_ratio.w);
    float2 _434 = bloom_dxdy * (5.0f + w1_8_ratio.z);
    float2 _449 = bloom_dxdy * (3.0f + w1_8_ratio.y);
    float2 _464 = bloom_dxdy * (1.0f + w1_8_ratio.x);
    float3 _401 = pow(((MASKED_SCANLINES.Sample(_MASKED_SCANLINES_sampler, video_uv).xyz - BRIGHTPASS.Sample(_BRIGHTPASS_sampler, video_uv).xyz) + ((((((((((Source.Sample(_Source_sampler, video_uv - _419).xyz * w1_8.w) + (Source.Sample(_Source_sampler, video_uv - _434).xyz * w1_8.z)) + (Source.Sample(_Source_sampler, video_uv - _449).xyz * w1_8.y)) + (Source.Sample(_Source_sampler, video_uv - _464).xyz * w1_8.x)) + (Source.Sample(_Source_sampler, video_uv).xyz * 1.0f)) + (Source.Sample(_Source_sampler, video_uv + _464).xyz * w1_8.x)) + (Source.Sample(_Source_sampler, video_uv + _449).xyz * w1_8.y)) + (Source.Sample(_Source_sampler, video_uv + _434).xyz * w1_8.z)) + (Source.Sample(_Source_sampler, video_uv + _419).xyz * w1_8.w)) * weight_sum_inv)) * undim_mask_contrast_factors, (1.0f / global_lcd_gamma).xxx);
    FragColor = float4(_401, 1.0f);
}

SPIRV_Cross_Output main(SPIRV_Cross_Input stage_input)
{
    video_uv = stage_input.video_uv;
    bloom_dxdy = stage_input.bloom_dxdy;
    weight_sum_inv = stage_input.weight_sum_inv;
    w1_8 = stage_input.w1_8;
    w1_8_ratio = stage_input.w1_8_ratio;
    undim_mask_contrast_factors = stage_input.undim_mask_contrast_factors;
    frag_main();
    SPIRV_Cross_Output stage_output;
    stage_output.FragColor = FragColor;
    return stage_output;
}
