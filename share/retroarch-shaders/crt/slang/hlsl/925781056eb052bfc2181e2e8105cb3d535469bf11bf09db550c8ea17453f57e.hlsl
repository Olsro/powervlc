// Generated from crt/shaders/crt-consumer/linear.slang. See slang/upstream for licence/source.
cbuffer Push : register(b1)
{
    float params_u_gamma : packoffset(c0);
};

Texture2D<float4> Source : register(t2);
SamplerState _Source_sampler : register(s2);

static float2 vTexCoord;
static float4 FragColor;

struct SPIRV_Cross_Input
{
    float2 vTexCoord : TEXCOORD0;
};

struct SPIRV_Cross_Output
{
    float4 FragColor : SV_Target0;
};

void frag_main()
{
    float3 _34 = pow(Source.Sample(_Source_sampler, vTexCoord).xyz, params_u_gamma.xxx);
    FragColor.x = _34.x;
    FragColor.y = _34.y;
    FragColor.z = _34.z;
}

SPIRV_Cross_Output main(SPIRV_Cross_Input stage_input)
{
    vTexCoord = stage_input.vTexCoord;
    frag_main();
    SPIRV_Cross_Output stage_output;
    stage_output.FragColor = FragColor;
    return stage_output;
}
