// Generated from crt/shaders/crt-yo6/crt-yo6-native-resolution.slang. See slang/upstream for licence/source.
cbuffer Push : register(b1)
{
    float4 params_SourceSize : packoffset(c0);
};

Texture2D<float4> Source : register(t2);
SamplerState _Source_sampler : register(s2);

static float vY;
static float vU;
static float4 FragColor;

struct SPIRV_Cross_Input
{
    float vU : TEXCOORD0;
    float vY : TEXCOORD1;
};

struct SPIRV_Cross_Output
{
    float4 FragColor : SV_Target0;
};

void frag_main()
{
    FragColor = float4(Source.Sample(_Source_sampler, float2(vU, vY / params_SourceSize.y)).xyz * (0.25f * ((sign(vY) + 1.0f) * (sign(params_SourceSize.y - vY) + 1.0f))), 1.0f);
}

SPIRV_Cross_Output main(SPIRV_Cross_Input stage_input)
{
    vY = stage_input.vY;
    vU = stage_input.vU;
    frag_main();
    SPIRV_Cross_Output stage_output;
    stage_output.FragColor = FragColor;
    return stage_output;
}
