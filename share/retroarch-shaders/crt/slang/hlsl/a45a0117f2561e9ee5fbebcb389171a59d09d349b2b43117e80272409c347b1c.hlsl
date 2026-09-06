// Generated from crt/shaders/crt-royale/src/crt-royale-scanlines-horizontal-apply-mask-fake-bloom-intel.slang. See slang/upstream for licence/source.
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
    float4 params_VERTICAL_SCANLINESSize : packoffset(c3);
    float4 params_BLOOM_APPROXSize : packoffset(c4);
    float4 params_HALATION_BLURSize : packoffset(c5);
};


static float4 gl_Position;
static float4 Position;
static float2 TexCoord;
static float2 video_uv;
static float2 scanline_texture_size_inv;
static float2 scanline_tex_uv;
static float2 blur3x3_tex_uv;
static float2 halation_tex_uv;
static float4 mask_tile_start_uv_and_size;
static float2 mask_tiles_per_screen;

struct SPIRV_Cross_Input
{
    float4 Position : TEXCOORD0;
    float2 TexCoord : TEXCOORD1;
};

struct SPIRV_Cross_Output
{
    float2 video_uv : TEXCOORD0;
    float2 scanline_tex_uv : TEXCOORD1;
    float2 blur3x3_tex_uv : TEXCOORD2;
    float2 halation_tex_uv : TEXCOORD3;
    float2 scanline_texture_size_inv : TEXCOORD4;
    float4 mask_tile_start_uv_and_size : TEXCOORD5;
    float2 mask_tiles_per_screen : TEXCOORD6;
    float4 gl_Position : SV_Position;
};

void vert_main()
{
    gl_Position = mul(Position, global_MVP);
    video_uv = TexCoord;
    scanline_texture_size_inv = 1.0f.xx / params_VERTICAL_SCANLINESSize.xy;
    scanline_tex_uv = (video_uv * params_VERTICAL_SCANLINESSize.xy) * scanline_texture_size_inv;
    blur3x3_tex_uv = video_uv;
    halation_tex_uv = video_uv;
    float2 _678;
    if (clamp(global_mask_sample_mode_desired, 1.0f, 2.0f) > 1.5f)
    {
        _678 = params_OutputSize.xy * 0.001953125f.xx;
    }
    else
    {
        _678 = params_OutputSize.xy / (1.0f.xx * (8.0f * lerp(global_mask_triad_size_desired, params_OutputSize.x / global_mask_num_triads_desired, global_mask_specify_num_triads)));
    }
    mask_tiles_per_screen = _678;
    mask_tile_start_uv_and_size = float4(0.0f, 0.0f, 1.0f, 1.0f);
}

SPIRV_Cross_Output main(SPIRV_Cross_Input stage_input)
{
    Position = stage_input.Position;
    TexCoord = stage_input.TexCoord;
    vert_main();
    SPIRV_Cross_Output stage_output;
    stage_output.gl_Position = gl_Position;
    stage_output.video_uv = video_uv;
    stage_output.scanline_texture_size_inv = scanline_texture_size_inv;
    stage_output.scanline_tex_uv = scanline_tex_uv;
    stage_output.blur3x3_tex_uv = blur3x3_tex_uv;
    stage_output.halation_tex_uv = halation_tex_uv;
    stage_output.mask_tile_start_uv_and_size = mask_tile_start_uv_and_size;
    stage_output.mask_tiles_per_screen = mask_tiles_per_screen;
    return stage_output;
}
