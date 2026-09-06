// Generated from crt/shaders/glow/gauss_vert.slang. See slang/upstream for licence/source.
cbuffer UBO : register(b0)
{
    row_major float4x4 global_MVP : packoffset(c0);
    float4 global_SourceSize : packoffset(c6);
};


static float4 gl_Position;
static float4 Position;
static float2 vTexCoord;
static float2 TexCoord;
static float2 data_pix_no;
static float data_one;

struct SPIRV_Cross_Input
{
    float4 Position : TEXCOORD0;
    float2 TexCoord : TEXCOORD1;
};

struct SPIRV_Cross_Output
{
    float2 vTexCoord : TEXCOORD0;
    float2 data_pix_no : TEXCOORD1;
    float data_one : TEXCOORD2;
    float4 gl_Position : SV_Position;
};

void vert_main()
{
    gl_Position = mul(Position, global_MVP);
    vTexCoord = TexCoord;
    data_pix_no = (vTexCoord * global_SourceSize.xy) - float2(0.0f, 0.5f);
    data_one = global_SourceSize.w;
}

SPIRV_Cross_Output main(SPIRV_Cross_Input stage_input)
{
    Position = stage_input.Position;
    TexCoord = stage_input.TexCoord;
    vert_main();
    SPIRV_Cross_Output stage_output;
    stage_output.gl_Position = gl_Position;
    stage_output.vTexCoord = vTexCoord;
    stage_output.data_pix_no = data_pix_no;
    stage_output.data_one = data_one;
    return stage_output;
}
