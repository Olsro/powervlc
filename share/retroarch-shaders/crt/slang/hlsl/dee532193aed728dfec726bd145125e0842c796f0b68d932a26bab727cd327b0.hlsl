// Generated from crt/shaders/torridgristle/sunset-gaussian-vert.slang. See slang/upstream for licence/source.
cbuffer UBO : register(b0)
{
    row_major float4x4 global_MVP : packoffset(c0);
};

cbuffer Push : register(b1)
{
    float4 params_OutputSize : packoffset(c2);
};


static float4 gl_Position;
static float4 Position;
static float2 vTexCoord;
static float2 TexCoord;
static float2 blurCoordinates[5];

struct SPIRV_Cross_Input
{
    float4 Position : TEXCOORD0;
    float2 TexCoord : TEXCOORD1;
};

struct SPIRV_Cross_Output
{
    float2 vTexCoord : TEXCOORD0;
    float2 blurCoordinates[5] : TEXCOORD1;
    float4 gl_Position : SV_Position;
};

void vert_main()
{
    gl_Position = mul(Position, global_MVP);
    vTexCoord = TexCoord;
    blurCoordinates[0] = vTexCoord;
    float2 _54 = params_OutputSize.zw * float2(0.0f, 1.40733301639556884765625f);
    blurCoordinates[1] = vTexCoord + _54;
    blurCoordinates[2] = vTexCoord - _54;
    float2 _71 = params_OutputSize.zw * float2(0.0f, 3.2942149639129638671875f);
    blurCoordinates[3] = vTexCoord + _71;
    blurCoordinates[4] = vTexCoord - _71;
}

SPIRV_Cross_Output main(SPIRV_Cross_Input stage_input)
{
    Position = stage_input.Position;
    TexCoord = stage_input.TexCoord;
    vert_main();
    SPIRV_Cross_Output stage_output;
    stage_output.gl_Position = gl_Position;
    stage_output.vTexCoord = vTexCoord;
    stage_output.blurCoordinates = blurCoordinates;
    return stage_output;
}
