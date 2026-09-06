// Generated from crt/shaders/crt-cgwg-fast.slang. See slang/upstream for licence/source.
cbuffer UBO : register(b0)
{
    row_major float4x4 global_MVP : packoffset(c0);
    float4 global_OutputSize : packoffset(c4);
    float4 global_SourceSize : packoffset(c6);
};


static float4 gl_Position;
static float4 Position;
static float2 vTexCoord;
static float2 TexCoord;
static float2 c01;
static float2 c11;
static float2 c21;
static float2 c31;
static float2 c02;
static float2 c12;
static float2 c22;
static float2 c32;
static float mod_factor;
static float2 ratio_scale;

struct SPIRV_Cross_Input
{
    float4 Position : TEXCOORD0;
    float2 TexCoord : TEXCOORD1;
};

struct SPIRV_Cross_Output
{
    float2 vTexCoord : TEXCOORD0;
    float2 c01 : TEXCOORD1;
    float2 c11 : TEXCOORD2;
    float2 c21 : TEXCOORD3;
    float2 c31 : TEXCOORD4;
    float2 c02 : TEXCOORD5;
    float2 c12 : TEXCOORD6;
    float2 c22 : TEXCOORD7;
    float2 c32 : TEXCOORD8;
    float mod_factor : TEXCOORD9;
    float2 ratio_scale : TEXCOORD10;
    float4 gl_Position : SV_Position;
};

void vert_main()
{
    gl_Position = mul(Position, global_MVP);
    vTexCoord = TexCoord;
    float _53 = -global_SourceSize.z;
    c01 = vTexCoord + float2(_53, 0.0f);
    c11 = vTexCoord;
    c21 = vTexCoord + float2(global_SourceSize.z, 0.0f);
    float _70 = 2.0f * global_SourceSize.z;
    c31 = vTexCoord + float2(_70, 0.0f);
    c02 = vTexCoord + float2(_53, global_SourceSize.w);
    c12 = vTexCoord + float2(0.0f, global_SourceSize.w);
    c22 = vTexCoord + float2(global_SourceSize.zw);
    c32 = vTexCoord + float2(_70, global_SourceSize.w);
    mod_factor = vTexCoord.x * global_OutputSize.x;
    ratio_scale = vTexCoord * global_SourceSize.xy;
}

SPIRV_Cross_Output main(SPIRV_Cross_Input stage_input)
{
    Position = stage_input.Position;
    TexCoord = stage_input.TexCoord;
    vert_main();
    SPIRV_Cross_Output stage_output;
    stage_output.gl_Position = gl_Position;
    stage_output.vTexCoord = vTexCoord;
    stage_output.c01 = c01;
    stage_output.c11 = c11;
    stage_output.c21 = c21;
    stage_output.c31 = c31;
    stage_output.c02 = c02;
    stage_output.c12 = c12;
    stage_output.c22 = c22;
    stage_output.c32 = c32;
    stage_output.mod_factor = mod_factor;
    stage_output.ratio_scale = ratio_scale;
    return stage_output;
}
