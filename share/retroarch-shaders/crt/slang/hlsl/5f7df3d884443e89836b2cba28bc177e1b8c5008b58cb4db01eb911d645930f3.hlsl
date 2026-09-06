// Generated from crt/shaders/geom-deluxe/phosphor_apply.slang. See slang/upstream for licence/source.
cbuffer Push : register(b1)
{
    float params_phosphor_power : packoffset(c0);
    float params_phosphor_amplitude : packoffset(c0.y);
};

Texture2D<float4> Source : register(t2);
SamplerState _Source_sampler : register(s2);
Texture2D<float4> PassFeedback1 : register(t3);
SamplerState _PassFeedback1_sampler : register(s3);

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
    float4 _66 = PassFeedback1.Sample(_PassFeedback1_sampler, vTexCoord);
    FragColor = float4(pow(pow(Source.Sample(_Source_sampler, vTexCoord).xyz, 2.2000000476837158203125f.xxx) + (pow(_66.xyz, 2.2000000476837158203125f.xxx) * (params_phosphor_amplitude * pow((255.0f * _66.w) + (frac(_66.z * 63.75f) * 1024.0f), -params_phosphor_power)).xxx), 0.4545454680919647216796875f.xxx), 1.0f);
}

SPIRV_Cross_Output main(SPIRV_Cross_Input stage_input)
{
    vTexCoord = stage_input.vTexCoord;
    frag_main();
    SPIRV_Cross_Output stage_output;
    stage_output.FragColor = FragColor;
    return stage_output;
}
