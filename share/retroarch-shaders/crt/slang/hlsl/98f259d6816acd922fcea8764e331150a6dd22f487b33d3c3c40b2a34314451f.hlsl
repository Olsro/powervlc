// Generated from crt/shaders/crt-royale/src-fast/crt-royale-mask-resize-vertical.slang. See slang/upstream for licence/source.
static float _458;

cbuffer UBO : register(b0)
{
    row_major float4x4 global_MVP : packoffset(c0);
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
static float2 TexCoord;
static float2 src_tex_uv_wrap;
static float2 resize_magnification_scale;

struct SPIRV_Cross_Input
{
    float4 Position : TEXCOORD0;
    float2 TexCoord : TEXCOORD1;
};

struct SPIRV_Cross_Output
{
    float2 src_tex_uv_wrap : TEXCOORD0;
    float2 resize_magnification_scale : TEXCOORD1;
    float4 gl_Position : SV_Position;
};

void vert_main()
{
    gl_Position = mul(Position, global_MVP);
    float2 _415 = clamp(1.0f.xx * min(8.0f * lerp(global_mask_triad_size_desired, (params_OutputSize.xy * 16.0f.xx).x / global_mask_num_triads_desired, global_mask_specify_num_triads), 64.0f), 1.0f.xx * ceil(16.0f), params_OutputSize.xy / (1.0f + (ceil(0.5f) * 0.125f)).xx);
    float _417 = _415.y;
    float2 _342 = float2(min(64.0f, params_OutputSize.x), floor(float2(_458, min(_417, _417)) + 1.52587890625e-05f.xx).y);
    src_tex_uv_wrap = TexCoord * (params_OutputSize.xy / _342);
    resize_magnification_scale = _342 * 0.015625f.xx;
}

SPIRV_Cross_Output main(SPIRV_Cross_Input stage_input)
{
    Position = stage_input.Position;
    TexCoord = stage_input.TexCoord;
    vert_main();
    SPIRV_Cross_Output stage_output;
    stage_output.gl_Position = gl_Position;
    stage_output.src_tex_uv_wrap = src_tex_uv_wrap;
    stage_output.resize_magnification_scale = resize_magnification_scale;
    return stage_output;
}
