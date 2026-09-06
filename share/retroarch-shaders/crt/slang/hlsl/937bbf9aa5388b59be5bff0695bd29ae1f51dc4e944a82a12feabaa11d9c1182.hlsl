// Generated from crt/shaders/newpixie/accumulate.slang. See slang/upstream for licence/source.
cbuffer Push : register(b1)
{
    float params_acc_modulate : packoffset(c3.y);
};

Texture2D<float4> PassFeedback1 : register(t3);
SamplerState _PassFeedback1_sampler : register(s3);
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
    FragColor = max(PassFeedback1.Sample(_PassFeedback1_sampler, vTexCoord) * params_acc_modulate.xxxx, Source.Sample(_Source_sampler, vTexCoord) * 0.959999978542327880859375f);
}

SPIRV_Cross_Output main(SPIRV_Cross_Input stage_input)
{
    vTexCoord = stage_input.vTexCoord;
    frag_main();
    SPIRV_Cross_Output stage_output;
    stage_output.FragColor = FragColor;
    return stage_output;
}
