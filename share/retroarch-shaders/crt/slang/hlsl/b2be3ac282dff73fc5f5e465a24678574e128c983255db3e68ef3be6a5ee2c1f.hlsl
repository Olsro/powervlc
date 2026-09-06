// Generated from crt/shaders/crt-royale/src-fast/crt-royale-bloom-horizontal-reconstitute.slang. See slang/upstream for licence/source.
static float _808;

cbuffer UBO : register(b0)
{
    row_major float4x4 global_MVP : packoffset(c0);
    float global_levels_contrast : packoffset(c4.z);
    float global_mask_type : packoffset(c9);
    float global_mask_num_triads_desired : packoffset(c9.y);
    float global_mask_triad_size_desired : packoffset(c9.z);
    float global_mask_specify_num_triads : packoffset(c9.w);
};

cbuffer Push : register(b1)
{
    float4 params_SourceSize : packoffset(c0);
    float4 params_OutputSize : packoffset(c2);
};


static float4 gl_Position;
static float4 Position;
static float2 video_uv;
static float2 TexCoord;
static float2 bloom_dxdy;
static float bloom_sigma_runtime;
static float4 w1_8;
static float4 w1_8_ratio;
static float weight_sum_inv;
static float undim_mask_contrast_factors;

struct SPIRV_Cross_Input
{
    float4 Position : TEXCOORD0;
    float2 TexCoord : TEXCOORD1;
};

struct SPIRV_Cross_Output
{
    float2 video_uv : TEXCOORD0;
    float2 bloom_dxdy : TEXCOORD1;
    float bloom_sigma_runtime : TEXCOORD2;
    float4 w1_8 : TEXCOORD3;
    float4 w1_8_ratio : TEXCOORD4;
    float weight_sum_inv : TEXCOORD5;
    float undim_mask_contrast_factors : TEXCOORD6;
    float4 gl_Position : SV_Position;
};

void vert_main()
{
    gl_Position = mul(Position, global_MVP);
    video_uv = TexCoord;
    bloom_dxdy = float2(1.0f / params_SourceSize.x, 0.0f);
    float2 _579 = clamp(1.0f.xx * min(8.0f * lerp(global_mask_triad_size_desired, params_OutputSize.x / global_mask_num_triads_desired, global_mask_specify_num_triads), 64.0f), 1.0f.xx * ceil(16.0f), (params_OutputSize.xy * 0.0625f.xx) / (1.0f + (ceil(0.5f) * 0.125f)).xx);
    float2 _604 = floor(float2(min(_579.x, _579.y), _808) + 1.52587890625e-05f.xx);
    float _490 = _604.x;
    bloom_sigma_runtime = ((-0.0516799986362457275390625f) + (_490 * 0.076412498950958251953125f)) - (_490 * 0.0092205703258514404296875f);
    float _633 = bloom_sigma_runtime * bloom_sigma_runtime;
    float _640 = exp((-2.0f) / _633);
    float _646 = exp((-8.0f) / _633);
    float _652 = exp((-18.0f) / _633);
    float _658 = exp((-32.0f) / _633);
    float _661 = exp((-0.5f) / _633) + _640;
    float _665 = exp((-4.5f) / _633) + _646;
    float _669 = exp((-12.5f) / _633) + _652;
    float _673 = exp((-24.5f) / _633) + _658;
    w1_8 = float4(_661, _665, _669, _673);
    w1_8_ratio = float4(_640 / _661, _646 / _665, _652 / _669, _658 / _673);
    weight_sum_inv = min(exp(exp(0.3483484089374542236328125f / (bloom_sigma_runtime - 0.086058728396892547607421875f))), 0.3993345797061920166015625f / bloom_sigma_runtime);
    float _760;
    if (global_mask_type < 0.5f)
    {
        _760 = 4.811320781707763671875f;
    }
    else
    {
        _760 = (global_mask_type < 1.5f) ? 5.5434780120849609375f : 6.21951198577880859375f;
    }
    undim_mask_contrast_factors = (2.0f * _760) * global_levels_contrast;
}

SPIRV_Cross_Output main(SPIRV_Cross_Input stage_input)
{
    Position = stage_input.Position;
    TexCoord = stage_input.TexCoord;
    vert_main();
    SPIRV_Cross_Output stage_output;
    stage_output.gl_Position = gl_Position;
    stage_output.video_uv = video_uv;
    stage_output.bloom_dxdy = bloom_dxdy;
    stage_output.bloom_sigma_runtime = bloom_sigma_runtime;
    stage_output.w1_8 = w1_8;
    stage_output.w1_8_ratio = w1_8_ratio;
    stage_output.weight_sum_inv = weight_sum_inv;
    stage_output.undim_mask_contrast_factors = undim_mask_contrast_factors;
    return stage_output;
}
