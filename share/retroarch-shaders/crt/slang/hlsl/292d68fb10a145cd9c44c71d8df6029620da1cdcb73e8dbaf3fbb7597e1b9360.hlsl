// Generated from crt/shaders/crt-beans/scanlines_cubic.slang. See slang/upstream for licence/source.
cbuffer UBO : register(b0)
{
    row_major float4x4 _19_MVP : packoffset(c0);
};

cbuffer Push : register(b1)
{
    float4 params_SourceSize : packoffset(c0);
    float4 params_OutputSize : packoffset(c1);
    float params_OverscanHorizontal : packoffset(c3);
    float params_OverscanVertical : packoffset(c3.y);
};


static float4 gl_Position;
static float4 Position;
static float2 vTexCoord;
static float2 TexCoord;
static float delta;
static float2 viewportCoord;

struct SPIRV_Cross_Input
{
    float4 Position : TEXCOORD0;
    float2 TexCoord : TEXCOORD1;
};

struct SPIRV_Cross_Output
{
    float2 vTexCoord : TEXCOORD0;
    nointerpolation float delta : TEXCOORD1;
    float2 viewportCoord : TEXCOORD2;
    float4 gl_Position : SV_Position;
};

void vert_main()
{
    gl_Position = mul(Position, _19_MVP);
    vTexCoord = ((1.0f.xx - float2(params_OverscanHorizontal, params_OverscanVertical)) * (TexCoord - 0.5f.xx)) + 0.5f.xx;
    delta = ((((params_OutputSize.x * params_OutputSize.w) * params_SourceSize.y) * params_SourceSize.z) * (1.0f - params_OverscanVertical)) / (1.0f - params_OverscanHorizontal);
    float _96;
    if (params_SourceSize.y > 300.0f)
    {
        _96 = 0.5f * delta;
    }
    else
    {
        _96 = delta;
    }
    delta = _96;
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
    stage_output.delta = delta;
    stage_output.viewportCoord = viewportCoord;
    return stage_output;
}
