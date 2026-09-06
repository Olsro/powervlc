// Generated from crt/shaders/crt-easymode-halation/threshold.slang. See slang/upstream for licence/source.
Texture2D<float4> Source : register(t2);
SamplerState _Source_sampler : register(s2);
Texture2D<float4> ORIG_LINEARIZED : register(t3);
SamplerState _ORIG_LINEARIZED_sampler : register(s3);

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
    FragColor = float4(clamp(Source.Sample(_Source_sampler, vTexCoord).xyz - ORIG_LINEARIZED.Sample(_ORIG_LINEARIZED_sampler, vTexCoord).xyz, 0.0f.xxx, 1.0f.xxx), 1.0f);
}

SPIRV_Cross_Output main(SPIRV_Cross_Input stage_input)
{
    vTexCoord = stage_input.vTexCoord;
    frag_main();
    SPIRV_Cross_Output stage_output;
    stage_output.FragColor = FragColor;
    return stage_output;
}
