// Generated from crt/shaders/crt-royale/src/crt-royale-bloom-approx.slang. See slang/upstream for licence/source.
cbuffer UBO : register(b0)
{
    row_major float4x4 global_MVP : packoffset(c0);
    float global_geom_aspect_ratio_x : packoffset(c13);
    float global_geom_aspect_ratio_y : packoffset(c13.y);
    float global_interlace_1080i : packoffset(c15);
    float global_interlace_detect_toggle : packoffset(c15.y);
};

cbuffer Push : register(b1)
{
    float4 params_SourceSize : packoffset(c0);
    float4 params_OutputSize : packoffset(c2);
};


static float4 gl_Position;
static float4 Position;
static float2 TexCoord;
static float2 tex_uv;
static float estimated_viewport_size_x;
static float2 texture_size_inv;
static float2 blur_dxdy;
static float2 tex_uv_to_pixel_scale;
static float2 uv_scanline_step;

struct SPIRV_Cross_Input
{
    float4 Position : TEXCOORD0;
    float2 TexCoord : TEXCOORD1;
};

struct SPIRV_Cross_Output
{
    float2 tex_uv : TEXCOORD0;
    float2 blur_dxdy : TEXCOORD1;
    float2 uv_scanline_step : TEXCOORD2;
    float estimated_viewport_size_x : TEXCOORD3;
    float2 texture_size_inv : TEXCOORD4;
    float2 tex_uv_to_pixel_scale : TEXCOORD5;
    float4 gl_Position : SV_Position;
};

void vert_main()
{
    gl_Position = mul(Position, global_MVP);
    tex_uv = TexCoord;
    estimated_viewport_size_x = (params_SourceSize.y * global_geom_aspect_ratio_x) / global_geom_aspect_ratio_y;
    texture_size_inv = 1.0f.xx / params_SourceSize.xy;
    blur_dxdy = max(params_SourceSize.xy / params_OutputSize.xy, 1.0f.xx) * texture_size_inv;
    tex_uv_to_pixel_scale = params_OutputSize.xy;
    bool _401;
    do
    {
        if (global_interlace_detect_toggle != 0.0f)
        {
            bool _399;
            if (global_interlace_1080i != 0.0f)
            {
                _399 = (params_SourceSize.y > 1079.5f) && (params_SourceSize.y < 1080.5f);
            }
            else
            {
                _399 = false;
            }
            _401 = ((params_SourceSize.y > 288.5f) && (params_SourceSize.y < 576.5f)) || _399;
            break;
        }
        else
        {
            _401 = false;
            break;
        }
        break; // unreachable workaround
    } while(false);
    uv_scanline_step = float2(1.0f, _401 ? 2.0f : 1.0f) / params_SourceSize.xy;
}

SPIRV_Cross_Output main(SPIRV_Cross_Input stage_input)
{
    Position = stage_input.Position;
    TexCoord = stage_input.TexCoord;
    vert_main();
    SPIRV_Cross_Output stage_output;
    stage_output.gl_Position = gl_Position;
    stage_output.tex_uv = tex_uv;
    stage_output.estimated_viewport_size_x = estimated_viewport_size_x;
    stage_output.texture_size_inv = texture_size_inv;
    stage_output.blur_dxdy = blur_dxdy;
    stage_output.tex_uv_to_pixel_scale = tex_uv_to_pixel_scale;
    stage_output.uv_scanline_step = uv_scanline_step;
    return stage_output;
}
