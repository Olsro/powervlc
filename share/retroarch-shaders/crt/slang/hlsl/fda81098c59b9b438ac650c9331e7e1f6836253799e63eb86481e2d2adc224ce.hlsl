// Generated from crt/shaders/crt-royale/src/crt-royale-brightpass.slang. See slang/upstream for licence/source.
cbuffer UBO : register(b0)
{
    float global_levels_contrast : packoffset(c4.z);
    float global_bloom_underestimate_levels : packoffset(c5.y);
    float global_bloom_excess : packoffset(c5.z);
    float global_mask_type : packoffset(c9.z);
};

Texture2D<float4> MASKED_SCANLINES : register(t2);
SamplerState _MASKED_SCANLINES_sampler : register(s2);
Texture2D<float4> BLOOM_APPROX : register(t3);
SamplerState _BLOOM_APPROX_sampler : register(s3);

static float2 scanline_tex_uv;
static float2 blur3x3_tex_uv;
static float bloom_sigma_runtime;
static float4 FragColor;

struct SPIRV_Cross_Input
{
    float2 scanline_tex_uv : TEXCOORD0;
    float2 blur3x3_tex_uv : TEXCOORD1;
    float bloom_sigma_runtime : TEXCOORD2;
};

struct SPIRV_Cross_Output
{
    float4 FragColor : SV_Target0;
};

void frag_main()
{
    float4 _565 = MASKED_SCANLINES.Sample(_MASKED_SCANLINES_sampler, scanline_tex_uv);
    float3 _457 = _565.xyz;
    float _763;
    if (global_mask_type < 0.5f)
    {
        _763 = 4.811320781707763671875f;
    }
    else
    {
        _763 = (global_mask_type < 1.5f) ? 5.5434780120849609375f : 6.21951198577880859375f;
    }
    float3 _474 = ((_457 * 2.0f) * _763) * global_levels_contrast;
    float _715 = min(exp(exp(0.3483484089374542236328125f / (bloom_sigma_runtime - 0.086058728396892547607421875f))), 0.3993345797061920166015625f / bloom_sigma_runtime);
    FragColor = float4(_457 * lerp(clamp((((1.0f.xxx - (max(0.0f.xxx, (BLOOM_APPROX.Sample(_BLOOM_APPROX_sampler, blur3x3_tex_uv).xyz * global_levels_contrast) - (_474 * _715)) * global_bloom_underestimate_levels)) / (_474 * global_bloom_underestimate_levels)) - 1.0f.xxx) / (_715 - 1.0f).xxx, 0.0f.xxx, 1.0f.xxx), 1.0f.xxx, global_bloom_excess.xxx), 1.0f);
}

SPIRV_Cross_Output main(SPIRV_Cross_Input stage_input)
{
    scanline_tex_uv = stage_input.scanline_tex_uv;
    blur3x3_tex_uv = stage_input.blur3x3_tex_uv;
    bloom_sigma_runtime = stage_input.bloom_sigma_runtime;
    frag_main();
    SPIRV_Cross_Output stage_output;
    stage_output.FragColor = FragColor;
    return stage_output;
}
