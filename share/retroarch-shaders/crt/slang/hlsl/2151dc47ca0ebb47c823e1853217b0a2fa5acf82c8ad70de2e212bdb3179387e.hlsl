// Generated from crt/shaders/cathode-retro/cathode-retro-util-tonemap-and-downsample-horz.slang. See slang/upstream for licence/source.
cbuffer UBO : register(b0)
{
    row_major float4x4 global_MVP : packoffset(c0);
};


static float4 gl_Position;
static float4 Position;
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
    float4 gl_Position : SV_Position;
};

void vert_main()
{
    gl_Position = mul(Position, global_MVP);
    vTexCoord = float2(TexCoord.x, TexCoord.y) * 1.00010001659393310546875f;
}

SPIRV_Cross_Output main(SPIRV_Cross_Input stage_input)
{
    Position = stage_input.Position;
    TexCoord = stage_input.TexCoord;
    vert_main();
    SPIRV_Cross_Output stage_output;
    stage_output.gl_Position = gl_Position;
    stage_output.vTexCoord = vTexCoord;
    return stage_output;
}
