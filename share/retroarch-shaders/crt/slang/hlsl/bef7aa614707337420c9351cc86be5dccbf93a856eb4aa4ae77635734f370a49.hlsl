// Generated from crt/shaders/crt-super-xbr/super-xbr-pass2.slang. See slang/upstream for licence/source.
cbuffer UBO : register(b0)
{
    row_major float4x4 global_MVP : packoffset(c0);
};

cbuffer Push : register(b1)
{
    float4 params_SourceSize : packoffset(c0);
};


static float4 gl_Position;
static float4 Position;
static float2 vTexCoord;
static float2 TexCoord;
static float4 t1;
static float4 t2;
static float4 t3;
static float4 t4;

struct SPIRV_Cross_Input
{
    float4 Position : TEXCOORD0;
    float2 TexCoord : TEXCOORD1;
};

struct SPIRV_Cross_Output
{
    float2 vTexCoord : TEXCOORD0;
    float4 t1 : TEXCOORD1;
    float4 t2 : TEXCOORD2;
    float4 t3 : TEXCOORD3;
    float4 t4 : TEXCOORD4;
    float4 gl_Position : SV_Position;
};

void vert_main()
{
    gl_Position = mul(Position, global_MVP);
    vTexCoord = TexCoord * 1.00010001659393310546875f;
    float _55 = (-2.0f) * params_SourceSize.z;
    float _57 = (-2.0f) * params_SourceSize.w;
    t1 = vTexCoord.xyxy + float4(_55, _57, params_SourceSize.z, params_SourceSize.w);
    float _66 = -params_SourceSize.z;
    t2 = vTexCoord.xyxy + float4(_66, _57, 0.0f, params_SourceSize.w);
    float _79 = -params_SourceSize.w;
    t3 = vTexCoord.xyxy + float4(_55, _79, params_SourceSize.z, 0.0f);
    t4 = vTexCoord.xyxy + float4(_66, _79, 0.0f, 0.0f);
}

SPIRV_Cross_Output main(SPIRV_Cross_Input stage_input)
{
    Position = stage_input.Position;
    TexCoord = stage_input.TexCoord;
    vert_main();
    SPIRV_Cross_Output stage_output;
    stage_output.gl_Position = gl_Position;
    stage_output.vTexCoord = vTexCoord;
    stage_output.t1 = t1;
    stage_output.t2 = t2;
    stage_output.t3 = t3;
    stage_output.t4 = t4;
    return stage_output;
}
