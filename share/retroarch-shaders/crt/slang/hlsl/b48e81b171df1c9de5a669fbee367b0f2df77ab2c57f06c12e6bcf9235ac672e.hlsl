// Generated from crt/shaders/crt-beans/scanlines_fast_horizontal.slang. See slang/upstream for licence/source.
cbuffer UBO : register(b0)
{
    row_major float4x4 _19_MVP : packoffset(c0);
};

cbuffer Push : register(b1)
{
    float4 params_SourceSize : packoffset(c0);
    float4 params_FinalViewportSize : packoffset(c2);
    float params_OverscanHorizontal : packoffset(c3.z);
    float params_OverscanVertical : packoffset(c3.w);
    float params_OddFieldFirst : packoffset(c4);
};


static float4 gl_Position;
static float4 Position;
static float2 vTexCoord;
static float2 TexCoord;
static float delta;

struct SPIRV_Cross_Input
{
    float4 Position : TEXCOORD0;
    float2 TexCoord : TEXCOORD1;
};

struct SPIRV_Cross_Output
{
    float2 vTexCoord : TEXCOORD0;
    nointerpolation float delta : TEXCOORD1;
    float4 gl_Position : SV_Position;
};

void vert_main()
{
    gl_Position = mul(Position, _19_MVP);
    vTexCoord = TexCoord;
    delta = ((((params_FinalViewportSize.x * params_FinalViewportSize.w) * params_SourceSize.y) * params_SourceSize.z) * (1.0f - params_OverscanVertical)) / (1.0f - params_OverscanHorizontal);
    bool _72 = params_OddFieldFirst <= 2.0f;
    bool _79;
    if (_72)
    {
        _79 = params_SourceSize.y > 300.0f;
    }
    else
    {
        _79 = _72;
    }
    if (_79)
    {
        delta = 0.5f * delta;
    }
    else
    {
        bool _89 = params_OddFieldFirst == 3.0f;
        bool _96;
        if (_89)
        {
            _96 = params_SourceSize.y < 350.0f;
        }
        else
        {
            _96 = _89;
        }
        if (_96)
        {
            delta = 2.0f * delta;
        }
    }
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
    return stage_output;
}
