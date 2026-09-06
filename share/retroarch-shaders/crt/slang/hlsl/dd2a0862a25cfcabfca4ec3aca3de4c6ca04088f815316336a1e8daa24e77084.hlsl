// Generated from crt/shaders/crt-royale/src-fast/crt-royale-mask-resize-horizontal.slang. See slang/upstream for licence/source.
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
    float2 _431 = clamp(1.0f.xx * min(8.0f * lerp(global_mask_triad_size_desired, (params_OutputSize.xy * 16.0f.xx).x / global_mask_num_triads_desired, global_mask_specify_num_triads), 64.0f), 1.0f.xx * ceil(16.0f), params_OutputSize.xy / (1.0f + (ceil(0.5f) * 0.125f)).xx);
    float _433 = _431.y;
    float2 _456 = floor(float2(min(_431.x, _433), min(_433, _433)) + 1.52587890625e-05f.xx);
    tile_uv_wrap = TexCoord * (params_OutputSize.xy / _456);
    float2 _352 = float2(min(64.0f, params_SourceSize.x), _456.y);
    tile_size_uv = _352 / params_SourceSize.xy;
    input_tiles_per_texture = params_SourceSize.xy / _352;
    src_tex_uv_wrap = tile_uv_wrap * tile_size_uv;
    resize_magnification_scale = _456 / _352;
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
