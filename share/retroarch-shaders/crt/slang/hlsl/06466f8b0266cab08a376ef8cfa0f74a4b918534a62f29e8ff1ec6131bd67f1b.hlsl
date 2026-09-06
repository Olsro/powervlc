// Generated from crt/shaders/crt-royale/src/crt-royale-mask-resize-vertical.slang. See slang/upstream for licence/source.
static float _527;

cbuffer UBO : register(b0)
{
    row_major float4x4 global_MVP : packoffset(c0);
    float global_mask_sample_mode_desired : packoffset(c9.w);
    float global_mask_num_triads_desired : packoffset(c10);
    float global_mask_triad_size_desired : packoffset(c10.y);
    float global_mask_specify_num_triads : packoffset(c10.z);
    float global_geom_aspect_ratio_x : packoffset(c13);
    float global_geom_aspect_ratio_y : packoffset(c13.y);
};

cbuffer Push : register(b1)
{
    float4 params_SourceSize : packoffset(c0);
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
    float _345 = global_geom_aspect_ratio_x / global_geom_aspect_ratio_y;
    float2 _505;
    do
    {
        float _447 = 8.0f * lerp(global_mask_triad_size_desired, ((params_OutputSize.y * 16.0f) * _345) / global_mask_num_triads_desired, global_mask_specify_num_triads);
        if (global_mask_sample_mode_desired > 0.5f)
        {
            _505 = 1.0f.xx * _447;
            break;
        }
        float2 _472 = clamp(1.0f.xx * min(_447, 64.0f), 1.0f.xx * ceil(16.0f), float2(params_OutputSize.y * _345, params_OutputSize.y) * 0.5f.xx);
        float _474 = _472.y;
        _505 = floor(float2(_527, min(_474, _474)) + 1.52587890625e-05f.xx);
        break;
    } while(false);
    float2 _375 = float2(min(64.0f, params_OutputSize.x), _505.y);
    src_tex_uv_wrap = TexCoord * (params_OutputSize.xy / _375);
    resize_magnification_scale = _375 * 0.015625f.xx;
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
