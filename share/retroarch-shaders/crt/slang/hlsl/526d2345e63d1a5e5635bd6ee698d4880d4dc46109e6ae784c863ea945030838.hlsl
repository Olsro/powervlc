// Generated from crt/shaders/crt-royale/src/crt-royale-mask-resize-horizontal.slang. See slang/upstream for licence/source.
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
static float2 TexCoord;
static float2 tile_uv_wrap;
static float2 tile_size_uv;
static float2 input_tiles_per_texture;
static float2 src_tex_uv_wrap;
static float2 resize_magnification_scale;
static float2 src_dxdy;

struct SPIRV_Cross_Input
{
    float4 Position : TEXCOORD0;
    float2 TexCoord : TEXCOORD1;
};

struct SPIRV_Cross_Output
{
    float2 src_tex_uv_wrap : TEXCOORD0;
    float2 tile_uv_wrap : TEXCOORD1;
    float2 resize_magnification_scale : TEXCOORD2;
    float2 src_dxdy : TEXCOORD3;
    float2 tile_size_uv : TEXCOORD4;
    float2 input_tiles_per_texture : TEXCOORD5;
    float4 gl_Position : SV_Position;
};

void vert_main()
{
    gl_Position = mul(Position, global_MVP);
    float2 _504;
    do
    {
        float _446 = 8.0f * lerp(global_mask_triad_size_desired, (params_OutputSize.xy * 16.0f.xx).x / global_mask_num_triads_desired, global_mask_specify_num_triads);
        if (global_mask_sample_mode_desired > 0.5f)
        {
            _504 = 1.0f.xx * _446;
            break;
        }
        float2 _471 = clamp(1.0f.xx * min(_446, 64.0f), 1.0f.xx * ceil(16.0f), params_OutputSize.xy * 0.5f.xx);
        float _473 = _471.y;
        _504 = floor(float2(min(_471.x, _473), min(_473, _473)) + 1.52587890625e-05f.xx);
        break;
    } while(false);
    tile_uv_wrap = TexCoord * (params_OutputSize.xy / _504);
    float2 _377 = float2(min(64.0f, params_SourceSize.x), _504.y);
    tile_size_uv = _377 / params_SourceSize.xy;
    input_tiles_per_texture = params_SourceSize.xy / _377;
    src_tex_uv_wrap = tile_uv_wrap * tile_size_uv;
    resize_magnification_scale = _504 / _377;
    src_dxdy = float2(1.0f / params_SourceSize.x, 0.0f);
}

SPIRV_Cross_Output main(SPIRV_Cross_Input stage_input)
{
    Position = stage_input.Position;
    TexCoord = stage_input.TexCoord;
    vert_main();
    SPIRV_Cross_Output stage_output;
    stage_output.gl_Position = gl_Position;
    stage_output.tile_uv_wrap = tile_uv_wrap;
    stage_output.tile_size_uv = tile_size_uv;
    stage_output.input_tiles_per_texture = input_tiles_per_texture;
    stage_output.src_tex_uv_wrap = src_tex_uv_wrap;
    stage_output.resize_magnification_scale = resize_magnification_scale;
    stage_output.src_dxdy = src_dxdy;
    return stage_output;
}
