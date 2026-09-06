// Generated from crt/shaders/crt-royale/src-fast/crt-royale-scanlines-vertical-interlacing.slang. See slang/upstream for licence/source.
cbuffer UBO : register(b0)
{
    row_major float4x4 global_MVP : packoffset(c0);
    float global_interlace_1080i : packoffset(c11.y);
    float global_interlace_detect_toggle : packoffset(c11.z);
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
static float2 il_step_multiple;
static float2 uv_step;
static float pixel_height_in_scanlines;

struct SPIRV_Cross_Input
{
    float4 Position : TEXCOORD0;
    float2 TexCoord : TEXCOORD1;
};

struct SPIRV_Cross_Output
{
    float2 tex_uv : TEXCOORD0;
    float2 uv_step : TEXCOORD1;
    float2 il_step_multiple : TEXCOORD2;
    float pixel_height_in_scanlines : TEXCOORD3;
    float4 gl_Position : SV_Position;
};

void vert_main()
{
    gl_Position = mul(Position, global_MVP);
    tex_uv = TexCoord * 1.000010013580322265625f;
    bool _316;
    do
    {
        if (global_interlace_detect_toggle != 0.0f)
        {
            bool _314;
            if (global_interlace_1080i != 0.0f)
            {
                _314 = (params_SourceSize.y > 1079.5f) && (params_SourceSize.y < 1080.5f);
            }
            else
            {
                _314 = false;
            }
            _316 = ((params_SourceSize.y > 288.5f) && (params_SourceSize.y < 576.5f)) || _314;
            break;
        }
        else
        {
            _316 = false;
            break;
        }
        break; // unreachable workaround
    } while(false);
    il_step_multiple = float2(1.0f, _316 ? 2.0f : 1.0f);
    uv_step = il_step_multiple / params_SourceSize.xy;
    pixel_height_in_scanlines = (params_SourceSize.y / params_OutputSize.y) / il_step_multiple.y;
}

SPIRV_Cross_Output main(SPIRV_Cross_Input stage_input)
{
    Position = stage_input.Position;
    TexCoord = stage_input.TexCoord;
    vert_main();
    SPIRV_Cross_Output stage_output;
    stage_output.gl_Position = gl_Position;
    stage_output.tex_uv = tex_uv;
    stage_output.il_step_multiple = il_step_multiple;
    stage_output.uv_step = uv_step;
    stage_output.pixel_height_in_scanlines = pixel_height_in_scanlines;
    return stage_output;
}
