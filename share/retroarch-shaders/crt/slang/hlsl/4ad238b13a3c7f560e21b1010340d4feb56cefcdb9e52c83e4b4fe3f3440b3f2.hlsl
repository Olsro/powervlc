// Generated from crt/shaders/crt-super-xbr/custom-resolve.slang. See slang/upstream for licence/source.
cbuffer Push : register(b1)
{
    float params_BLOOM_STRENGTH : packoffset(c3.y);
    float params_SOURCE_BOOST : packoffset(c3.z);
    float params_OUTPUT_GAMMA : packoffset(c3.w);
};

Texture2D<float4> CRT_PASS : register(t3);
SamplerState _CRT_PASS_sampler : register(s3);
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
    FragColor = float4(pow(clamp((CRT_PASS.Sample(_CRT_PASS_sampler, vTexCoord).xyz * params_SOURCE_BOOST) + (Source.Sample(_Source_sampler, vTexCoord).xyz * params_BLOOM_STRENGTH), 0.0f.xxx, 1.0f.xxx), (1.0f / params_OUTPUT_GAMMA).xxx), 1.0f);
}

SPIRV_Cross_Output main(SPIRV_Cross_Input stage_input)
{
    vTexCoord = stage_input.vTexCoord;
    frag_main();
    SPIRV_Cross_Output stage_output;
    stage_output.FragColor = FragColor;
    return stage_output;
}
