// Generated from crt/shaders/hyllian/support/glow/threshold.slang. See slang/upstream for licence/source.
cbuffer Push : register(b1)
{
    float params_GLOW_WHITEPOINT : packoffset(c0);
    float params_GLOW_ROLLOFF : packoffset(c0.y);
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
    FragColor = float4(pow(clamp(Source.Sample(_Source_sampler, vTexCoord).xyz / params_GLOW_WHITEPOINT.xxx, 0.0f.xxx, 1.0f.xxx), params_GLOW_ROLLOFF.xxx), 1.0f);
}

SPIRV_Cross_Output main(SPIRV_Cross_Input stage_input)
{
    vTexCoord = stage_input.vTexCoord;
    frag_main();
    SPIRV_Cross_Output stage_output;
    stage_output.FragColor = FragColor;
    return stage_output;
}
