// Generated from crt/shaders/fake-crt-geom.slang. See slang/upstream for licence/source.
cbuffer UBO : register(b0)
{
    row_major float4x4 global_MVP : packoffset(c0);
};

cbuffer Push : register(b1)
{
    float4 params_SourceSize : packoffset(c0);
    float4 params_OriginalSize : packoffset(c1);
    float4 params_OutputSize : packoffset(c2);
    float params_a_MSIZE : packoffset(c6.y);
};


static float4 gl_Position;
static float4 Position;
static float2 vTexCoord;
static float2 TexCoord;
static float2 ps;
static float maskpos;

struct SPIRV_Cross_Input
{
    float4 Position : TEXCOORD0;
    float2 TexCoord : TEXCOORD1;
};

struct SPIRV_Cross_Output
{
    float2 vTexCoord : TEXCOORD0;
    float2 ps : TEXCOORD1;
    float maskpos : TEXCOORD2;
    float4 gl_Position : SV_Position;
};

void vert_main()
{
    gl_Position = mul(Position, global_MVP);
    vTexCoord = TexCoord * 1.00010001659393310546875f;
    ps = 1.0f.xx / params_SourceSize.xy;
    maskpos = (((vTexCoord.x * params_OutputSize.x) / params_a_MSIZE) * (params_SourceSize.xy / params_OriginalSize.xy).x) * 3.1415920257568359375f;
}

SPIRV_Cross_Output main(SPIRV_Cross_Input stage_input)
{
    Position = stage_input.Position;
    TexCoord = stage_input.TexCoord;
    vert_main();
    SPIRV_Cross_Output stage_output;
    stage_output.gl_Position = gl_Position;
    stage_output.vTexCoord = vTexCoord;
    stage_output.ps = ps;
    stage_output.maskpos = maskpos;
    return stage_output;
}
