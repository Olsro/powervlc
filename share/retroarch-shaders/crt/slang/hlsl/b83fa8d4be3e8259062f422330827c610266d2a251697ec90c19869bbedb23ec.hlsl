// Generated from crt/shaders/zfast_crt/zfast_crt_composite.slang. See slang/upstream for licence/source.
cbuffer UBO : register(b0)
{
    row_major float4x4 global_MVP : packoffset(c0);
};

cbuffer Push : register(b1)
{
    float4 params_SourceSize : packoffset(c0);
    float4 params_OutputSize : packoffset(c2);
    float params_MASK_FADE : packoffset(c4.z);
};


static float4 gl_Position;
static float4 Position;
static float2 vTexCoord;
static float2 TexCoord;
static float maskFade;
static float2 invDims;
static float2 maskpos;

struct SPIRV_Cross_Input
{
    float4 Position : TEXCOORD0;
    float2 TexCoord : TEXCOORD1;
};

struct SPIRV_Cross_Output
{
    float2 vTexCoord : TEXCOORD0;
    float maskFade : TEXCOORD1;
    float2 invDims : TEXCOORD2;
    float2 maskpos : TEXCOORD3;
    float4 gl_Position : SV_Position;
};

void vert_main()
{
    gl_Position = mul(Position, global_MVP);
    vTexCoord = TexCoord;
    maskFade = 0.33329999446868896484375f * params_MASK_FADE;
    invDims = 1.0f.xx / params_SourceSize.xy;
    maskpos = vTexCoord * params_OutputSize.xy;
}

SPIRV_Cross_Output main(SPIRV_Cross_Input stage_input)
{
    Position = stage_input.Position;
    TexCoord = stage_input.TexCoord;
    vert_main();
    SPIRV_Cross_Output stage_output;
    stage_output.gl_Position = gl_Position;
    stage_output.vTexCoord = vTexCoord;
    stage_output.maskFade = maskFade;
    stage_output.invDims = invDims;
    stage_output.maskpos = maskpos;
    return stage_output;
}
