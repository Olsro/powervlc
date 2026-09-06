// Generated from crt/shaders/crt-royale/src-fast/crt-royale-bloom-vertical.slang. See slang/upstream for licence/source.
static float _752;

cbuffer UBO : register(b0)
{
    row_major float4x4 global_MVP : packoffset(c0);
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
static float2 tex_uv;
static float2 TexCoord;
static float2 bloom_dxdy;
static float bloom_sigma_runtime;
static float4 w1_8;
static float4 w1_8_ratio;
static float weight_sum_inv;

struct SPIRV_Cross_Input
{
    float4 Position : TEXCOORD0;
    float2 TexCoord : TEXCOORD1;
};

struct SPIRV_Cross_Output
{
    float2 tex_uv : TEXCOORD0;
    float2 bloom_dxdy : TEXCOORD1;
    float bloom_sigma_runtime : TEXCOORD2;
    float4 w1_8 : TEXCOORD3;
    float4 w1_8_ratio : TEXCOORD4;
    float weight_sum_inv : TEXCOORD5;
    float4 gl_Position : SV_Position;
};

void vert_main()
{
    gl_Position = mul(Position, global_MVP);
    tex_uv = TexCoord * 1.00010001659393310546875f;
    bloom_dxdy = float2(0.0f, ((params_SourceSize.xy / params_OutputSize.xy) / params_SourceSize.xy).y);
    float2 _552 = clamp(1.0f.xx * min(8.0f * lerp(global_mask_triad_size_desired, params_OutputSize.x / global_mask_num_triads_desired, global_mask_specify_num_triads), 64.0f), 1.0f.xx * ceil(16.0f), (params_OutputSize.xy * 0.0625f.xx) / (1.0f + (ceil(0.5f) * 0.125f)).xx);
    float2 _577 = floor(float2(min(_552.x, _552.y), _752) + 1.52587890625e-05f.xx);
    float _474 = _577.x;
    bloom_sigma_runtime = ((-0.0516799986362457275390625f) + (_474 * 0.076412498950958251953125f)) - (_474 * 0.0092205703258514404296875f);
    float _606 = bloom_sigma_runtime * bloom_sigma_runtime;
    float _613 = exp((-2.0f) / _606);
    float _619 = exp((-8.0f) / _606);
    float _625 = exp((-18.0f) / _606);
    float _631 = exp((-32.0f) / _606);
    float _634 = exp((-0.5f) / _606) + _613;
    float _638 = exp((-4.5f) / _606) + _619;
    float _642 = exp((-12.5f) / _606) + _625;
    float _646 = exp((-24.5f) / _606) + _631;
    w1_8 = float4(_634, _638, _642, _646);
    w1_8_ratio = float4(_613 / _634, _619 / _638, _625 / _642, _631 / _646);
    weight_sum_inv = min(exp(exp(0.3483484089374542236328125f / (bloom_sigma_runtime - 0.086058728396892547607421875f))), 0.3993345797061920166015625f / bloom_sigma_runtime);
}

SPIRV_Cross_Output main(SPIRV_Cross_Input stage_input)
{
    Position = stage_input.Position;
    TexCoord = stage_input.TexCoord;
    vert_main();
    SPIRV_Cross_Output stage_output;
    stage_output.gl_Position = gl_Position;
    stage_output.tex_uv = tex_uv;
    stage_output.bloom_dxdy = bloom_dxdy;
    stage_output.bloom_sigma_runtime = bloom_sigma_runtime;
    stage_output.w1_8 = w1_8;
    stage_output.w1_8_ratio = w1_8_ratio;
    stage_output.weight_sum_inv = weight_sum_inv;
    return stage_output;
}
