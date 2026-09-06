// Generated from crt/shaders/crt-beans/scanlines_analytical.slang. See slang/upstream for licence/source.
cbuffer UBO : register(b0)
{
    row_major float4x4 _19_MVP : packoffset(c0);
};

cbuffer Push : register(b1)
{
    float4 params_SourceSize : packoffset(c0);
    float4 params_OutputSize : packoffset(c1);
    float params_OddFieldFirst : packoffset(c2.w);
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
    bool _85 = params_OddFieldFirst <= 2.0f;
    bool _92;
    if (_85)
    {
        _92 = params_SourceSize.y > 300.0f;
    }
    else
    {
        _92 = _85;
    }
    if (_92)
    {
        delta = 0.5f * delta;
    }
    else
    {
        bool _101 = params_OddFieldFirst == 3.0f;
        bool _108;
        if (_101)
        {
            _108 = params_SourceSize.y < 350.0f;
        }
        else
        {
            _108 = _101;
        }
        if (_108)
        {
            delta = 2.0f * delta;
        }
    }
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
