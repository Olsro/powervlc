// Generated from crt/shaders/crt-beans/scanlines_fast_vertical.slang. See slang/upstream for licence/source.
cbuffer UBO : register(b0)
{
    row_major float4x4 _19_MVP : packoffset(c0);
};

cbuffer Push : register(b1)
{
    float params_OverscanHorizontal : packoffset(c3);
    float params_OverscanVertical : packoffset(c3.y);
};


static float4 gl_Position;
static float4 Position;
static float2 vTexCoord;
static float2 TexCoord;
static float2 viewportCoord;

struct SPIRV_Cross_Input
{
    float4 Position : TEXCOORD0;
    float2 TexCoord : TEXCOORD1;
};

struct SPIRV_Cross_Output
{
    float2 vTexCoord : TEXCOORD0;
    float2 viewportCoord : TEXCOORD1;
    float4 gl_Position : SV_Position;
};

void vert_main()
{
    gl_Position = mul(Position, _19_MVP);
    vTexCoord = ((1.0f.xx - float2(params_OverscanHorizontal, params_OverscanVertical)) * (TexCoord - 0.5f.xx)) + 0.5f.xx;
    viewportCoord = TexCoord;
}

SPIRV_Cross_Output main(SPIRV_Cross_Input stage_input)
{
    Position = stage_input.Position;
    TexCoord = stage_input.TexCoord;
    vert_main();
    SPIRV_Cross_Output stage_output;
    stage_output.gl_Position = gl_Position;
    stage_output.vTexCoord = vTexCoord;
    stage_output.viewportCoord = viewportCoord;
    return stage_output;
}
