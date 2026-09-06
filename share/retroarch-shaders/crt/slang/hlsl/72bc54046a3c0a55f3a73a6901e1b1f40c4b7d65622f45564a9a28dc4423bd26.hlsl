// Generated from crt/shaders/torridgristle/Brighten.slang. See slang/upstream for licence/source.
cbuffer Push : register(b1)
{
    float params_BrightenLevel : packoffset(c3.y);
    float params_BrightenAmount : packoffset(c3.z);
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
    float3 _27 = clamp(Source.Sample(_Source_sampler, vTexCoord).xyz, 0.0f.xxx, 1.0f.xxx);
    FragColor = float4(lerp(_27, 1.0f.xxx - pow(1.0f.xxx - _27, params_BrightenLevel.xxx), params_BrightenAmount.xxx), 1.0f);
}

SPIRV_Cross_Output main(SPIRV_Cross_Input stage_input)
{
    vTexCoord = stage_input.vTexCoord;
    frag_main();
    SPIRV_Cross_Output stage_output;
    stage_output.FragColor = FragColor;
    return stage_output;
}
