// Generated from crt/shaders/crt-royale/src-fast/crt-royale-brightpass.slang. See slang/upstream for licence/source.
static float _563;

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
    float4 params_OutputSize : packoffset(c2);
};


static float4 gl_Position;
static float4 Position;
static float2 tex_uv;
static float2 TexCoord;
static float center_weight;
static float undim_mask_contrast_factors;

struct SPIRV_Cross_Input
{
    float4 Position : TEXCOORD0;
    float2 TexCoord : TEXCOORD1;
};

struct SPIRV_Cross_Output
{
    float2 tex_uv : TEXCOORD0;
    float center_weight : TEXCOORD1;
    float undim_mask_contrast_factors : TEXCOORD2;
    float4 gl_Position : SV_Position;
};

void vert_main()
{
    gl_Position = mul(Position, global_MVP);
    tex_uv = TexCoord;
    float2 _468 = clamp(1.0f.xx * min(8.0f * lerp(global_mask_triad_size_desired, params_OutputSize.x / global_mask_num_triads_desired, global_mask_specify_num_triads), 64.0f), 1.0f.xx * ceil(16.0f), (params_OutputSize.xy * 0.0625f.xx) / (1.0f + (ceil(0.5f) * 0.125f)).xx);
    float2 _493 = floor(float2(min(_468.x, _468.y), _563) + 1.52587890625e-05f.xx);
    float _390 = _493.x;
    float _506 = ((-0.0516799986362457275390625f) + (_390 * 0.076412498950958251953125f)) - (_390 * 0.0092205703258514404296875f);
    center_weight = min(exp(exp(0.3483484089374542236328125f / (_506 - 0.086058728396892547607421875f))), 0.3993345797061920166015625f / _506);
    float _543;
    if (global_mask_type < 0.5f)
    {
        _543 = 4.811320781707763671875f;
    }
    else
    {
        _543 = (global_mask_type < 1.5f) ? 5.5434780120849609375f : 6.21951198577880859375f;
    }
    undim_mask_contrast_factors = (2.0f * _543) * global_levels_contrast;
}

SPIRV_Cross_Output main(SPIRV_Cross_Input stage_input)
{
    Position = stage_input.Position;
    TexCoord = stage_input.TexCoord;
    vert_main();
    SPIRV_Cross_Output stage_output;
    stage_output.gl_Position = gl_Position;
    stage_output.tex_uv = tex_uv;
    stage_output.center_weight = center_weight;
    stage_output.undim_mask_contrast_factors = undim_mask_contrast_factors;
    return stage_output;
}
