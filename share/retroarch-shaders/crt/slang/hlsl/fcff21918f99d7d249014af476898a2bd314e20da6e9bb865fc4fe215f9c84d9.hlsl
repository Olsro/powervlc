// Generated from crt/shaders/crt-royale/src/crt-royale-bloom-vertical.slang. See slang/upstream for licence/source.
static float _563;

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
};


static float4 gl_Position;
static float4 Position;
static float2 tex_uv;
static float2 TexCoord;
static float2 bloom_dxdy;
static float bloom_sigma_runtime;

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
    float4 gl_Position : SV_Position;
};

void vert_main()
{
    gl_Position = mul(Position, global_MVP);
    tex_uv = TexCoord * 1.00010001659393310546875f;
    bloom_dxdy = float2(0.0f, ((params_SourceSize.xy / params_OutputSize.xy) / params_SourceSize.xy).y);
    float2 _536;
    do
    {
        float _466 = 8.0f * lerp(global_mask_triad_size_desired, params_OutputSize.x / global_mask_num_triads_desired, global_mask_specify_num_triads);
        if (global_mask_sample_mode_desired > 0.5f)
        {
            _536 = 1.0f.xx * _466;
            break;
        }
        float2 _491 = clamp(1.0f.xx * min(_466, 64.0f), 1.0f.xx * ceil(16.0f), params_OutputSize.xy * 0.03125f.xx);
        _536 = floor(float2(min(_491.x, _491.y), _563) + 1.52587890625e-05f.xx);
        break;
    } while(false);
    bloom_sigma_runtime = ((-0.0516799986362457275390625f) + (_536.x * 0.076412498950958251953125f)) - (_536.x * 0.0092205703258514404296875f);
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
    return stage_output;
}
