// Generated from crt/shaders/crtsim/post-upsample.slang. See slang/upstream for licence/source.
cbuffer Push : register(b1)
{
    float params_bloom_scale_up : packoffset(c3.y);
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
    float2 _24 = params_bloom_scale_up.xx;
    FragColor = ((((((Source.Sample(_Source_sampler, vTexCoord) + Source.Sample(_Source_sampler, vTexCoord + (float2(1.0f, 0.0f) * _24))) + Source.Sample(_Source_sampler, vTexCoord + (float2(-1.0f, 0.0f) * _24))) + Source.Sample(_Source_sampler, vTexCoord + (float2(0.5f, -0.86602497100830078125f) * _24))) + Source.Sample(_Source_sampler, vTexCoord + (float2(-0.5f, -0.86602497100830078125f) * _24))) + Source.Sample(_Source_sampler, vTexCoord + (float2(0.5f, 0.86602497100830078125f) * _24))) + Source.Sample(_Source_sampler, vTexCoord + (float2(-0.5f, 0.86602497100830078125f) * _24))) * 0.14285714924335479736328125f;
}

SPIRV_Cross_Output main(SPIRV_Cross_Input stage_input)
{
    vTexCoord = stage_input.vTexCoord;
    frag_main();
    SPIRV_Cross_Output stage_output;
    stage_output.FragColor = FragColor;
    return stage_output;
}
