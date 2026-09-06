// Generated from crt/shaders/crt-royale/src/crt-royale-bloom-horizontal-reconstitute.slang. See slang/upstream for licence/source.
static float _589;

cbuffer UBO : register(b0)
{
    row_major float4x4 global_MVP : packoffset(c0);
    float global_mask_sample_mode_desired : packoffset(c9.w);
    float global_mask_num_triads_desired : packoffset(c10);
    float global_mask_triad_size_desired : packoffset(c10.y);
    float global_mask_specify_num_triads : packoffset(c10.z);
};

cbuffer Push : register(b1)
{
    float4 params_SourceSize : packoffset(c0);
    float4 params_OutputSize : packoffset(c2);
    float4 params_MASKED_SCANLINESSize : packoffset(c3);
    float4 params_HALATION_BLURSize : packoffset(c4);
    float4 params_BRIGHTPASSSize : packoffset(c5);
};


static float4 gl_Position;
static float4 Position;
static float2 TexCoord;
static float2 scanline_tex_uv;
static float2 halation_tex_uv;
static float2 brightpass_tex_uv;
static float2 bloom_tex_uv;
static float2 bloom_dxdy;
static float bloom_sigma_runtime;
static float2 video_uv;

struct SPIRV_Cross_Input
{
    float4 Position : TEXCOORD0;
    float2 TexCoord : TEXCOORD1;
};

struct SPIRV_Cross_Output
{
    float2 video_uv : TEXCOORD0;
    float2 scanline_tex_uv : TEXCOORD1;
    float2 halation_tex_uv : TEXCOORD2;
    float2 brightpass_tex_uv : TEXCOORD3;
    float2 bloom_tex_uv : TEXCOORD4;
    float2 bloom_dxdy : TEXCOORD5;
    float bloom_sigma_runtime : TEXCOORD6;
    float4 gl_Position : SV_Position;
};

void vert_main()
{
    gl_Position = mul(Position, global_MVP);
    scanline_tex_uv = TexCoord;
    halation_tex_uv = TexCoord;
    brightpass_tex_uv = TexCoord;
    bloom_tex_uv = TexCoord;
    bloom_dxdy = float2(1.0f / params_SourceSize.x, 0.0f);
    float2 _564;
    do
    {
        float _494 = 8.0f * lerp(global_mask_triad_size_desired, params_OutputSize.x / global_mask_num_triads_desired, global_mask_specify_num_triads);
        if (global_mask_sample_mode_desired > 0.5f)
        {
            _564 = 1.0f.xx * _494;
            break;
        }
        float2 _519 = clamp(1.0f.xx * min(_494, 64.0f), 1.0f.xx * ceil(16.0f), params_OutputSize.xy * 0.03125f.xx);
        _564 = floor(float2(min(_519.x, _519.y), _589) + 1.52587890625e-05f.xx);
        break;
    } while(false);
    bloom_sigma_runtime = ((-0.0516799986362457275390625f) + (_564.x * 0.076412498950958251953125f)) - (_564.x * 0.0092205703258514404296875f);
}

SPIRV_Cross_Output main(SPIRV_Cross_Input stage_input)
{
    Position = stage_input.Position;
    TexCoord = stage_input.TexCoord;
    vert_main();
    SPIRV_Cross_Output stage_output;
    stage_output.gl_Position = gl_Position;
    stage_output.scanline_tex_uv = scanline_tex_uv;
    stage_output.halation_tex_uv = halation_tex_uv;
    stage_output.brightpass_tex_uv = brightpass_tex_uv;
    stage_output.bloom_tex_uv = bloom_tex_uv;
    stage_output.bloom_dxdy = bloom_dxdy;
    stage_output.bloom_sigma_runtime = bloom_sigma_runtime;
    stage_output.video_uv = video_uv;
    return stage_output;
}
