// Generated from crt/shaders/hyllian/crt-hyllian-fast.slang. See slang/upstream for licence/source.
cbuffer UBO : register(b0)
{
    row_major float4x4 global_MVP : packoffset(c0);
    float4 global_SourceSize : packoffset(c4);
};


static float4 gl_Position;
static float4 Position;
static float2 ps;
static float2 vTexCoord;
static float2 TexCoord;

struct SPIRV_Cross_Input
{
    float4 Position : TEXCOORD0;
    float2 TexCoord : TEXCOORD1;
};

struct SPIRV_Cross_Output
{
    float2 vTexCoord : TEXCOORD0;
    float2 ps : TEXCOORD1;
    float4 gl_Position : SV_Position;
};

void vert_main()
{
    gl_Position = mul(Position, global_MVP);
    ps = 1.0f.xx / float2(global_SourceSize.x, global_SourceSize.y);
    vTexCoord = TexCoord + (ps * float2(-0.499989986419677734375f, 0.0f));
}

SPIRV_Cross_Output main(SPIRV_Cross_Input stage_input)
{
    Position = stage_input.Position;
    TexCoord = stage_input.TexCoord;
    vert_main();
    SPIRV_Cross_Output stage_output;
    stage_output.gl_Position = gl_Position;
    stage_output.ps = ps;
    stage_output.vTexCoord = vTexCoord;
    return stage_output;
}
