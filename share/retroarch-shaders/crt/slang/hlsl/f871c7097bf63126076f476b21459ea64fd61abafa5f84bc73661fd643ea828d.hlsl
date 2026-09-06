// Generated from crt/shaders/crt-royale/src/crt-royale-first-pass-linearize-crt-gamma-bob-fields.slang. See slang/upstream for licence/source.
cbuffer UBO : register(b0)
{
    row_major float4x4 global_MVP : packoffset(c0);
    float global_interlace_1080i : packoffset(c15);
    float global_interlace_detect_toggle : packoffset(c15.y);
};

cbuffer Push : register(b1)
{
    float4 params_SourceSize : packoffset(c0);
};


static float4 gl_Position;
static float4 Position;
static float2 tex_uv;
static float2 TexCoord;
static float2 uv_step;
static float interlaced;

struct SPIRV_Cross_Input
{
    float4 Position : TEXCOORD0;
    float2 TexCoord : TEXCOORD1;
};

struct SPIRV_Cross_Output
{
    float2 tex_uv : TEXCOORD0;
    float2 uv_step : TEXCOORD1;
    float interlaced : TEXCOORD2;
    float4 gl_Position : SV_Position;
};

void vert_main()
{
    gl_Position = mul(Position, global_MVP);
    tex_uv = TexCoord * 1.000010013580322265625f;
    uv_step = 1.0f.xx / params_SourceSize.xy;
    bool _314;
    do
    {
        if (global_interlace_detect_toggle != 0.0f)
        {
            bool _312;
            if (global_interlace_1080i != 0.0f)
            {
                _312 = (params_SourceSize.y > 1079.5f) && (params_SourceSize.y < 1080.5f);
            }
            else
            {
                _312 = false;
            }
            _314 = ((params_SourceSize.y > 288.5f) && (params_SourceSize.y < 576.5f)) || _312;
            break;
        }
        else
        {
            _314 = false;
            break;
        }
        break; // unreachable workaround
    } while(false);
    interlaced = float(_314);
}

SPIRV_Cross_Output main(SPIRV_Cross_Input stage_input)
{
    Position = stage_input.Position;
    TexCoord = stage_input.TexCoord;
    vert_main();
    SPIRV_Cross_Output stage_output;
    stage_output.gl_Position = gl_Position;
    stage_output.tex_uv = tex_uv;
    stage_output.uv_step = uv_step;
    stage_output.interlaced = interlaced;
    return stage_output;
}
