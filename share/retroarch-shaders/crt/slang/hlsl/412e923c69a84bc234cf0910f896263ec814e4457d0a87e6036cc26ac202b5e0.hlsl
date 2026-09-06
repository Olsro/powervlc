// Generated from crt/shaders/guest/advanced/ntsc/ntsc-pass3.slang. See slang/upstream for licence/source.
cbuffer UBO : register(b0)
{
    row_major float4x4 global_MVP : packoffset(c0);
};

cbuffer Push : register(b1)
{
    float4 params_OriginalSize : packoffset(c1);
    float params_auto_res : packoffset(c3.z);
    float params_speedup : packoffset(c5.z);
};


static float4 gl_Position;
static float4 Position;
static float2 vTexCoord0;
static float2 TexCoord;
static float2 vTexCoord1;
static float2 vTexCoord;

struct SPIRV_Cross_Input
{
    float4 Position : TEXCOORD0;
    float2 TexCoord : TEXCOORD1;
};

struct SPIRV_Cross_Output
{
    float2 vTexCoord : TEXCOORD0;
    float2 vTexCoord0 : TEXCOORD1;
    float2 vTexCoord1 : TEXCOORD2;
    float4 gl_Position : SV_Position;
};

void vert_main()
{
    gl_Position = mul(Position, global_MVP);
    vTexCoord0 = TexCoord / float2(params_speedup, 1.0f);
    vTexCoord1 = (floor(vTexCoord0 * params_OriginalSize.xy) + 0.5f.xx) * params_OriginalSize.zw;
    vTexCoord = TexCoord + float2((params_OriginalSize.z / lerp(1.0f, 0.5f, clamp((params_auto_res * round(params_OriginalSize.x * 0.0033333334140479564666748046875f)) - 1.0f, 0.0f, 1.0f))) * 0.125f, 0.0f);
}

SPIRV_Cross_Output main(SPIRV_Cross_Input stage_input)
{
    Position = stage_input.Position;
    TexCoord = stage_input.TexCoord;
    vert_main();
    SPIRV_Cross_Output stage_output;
    stage_output.gl_Position = gl_Position;
    stage_output.vTexCoord0 = vTexCoord0;
    stage_output.vTexCoord1 = vTexCoord1;
    stage_output.vTexCoord = vTexCoord;
    return stage_output;
}
