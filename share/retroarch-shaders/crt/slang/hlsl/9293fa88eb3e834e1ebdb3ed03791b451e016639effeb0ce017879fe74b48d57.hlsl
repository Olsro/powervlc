// Generated from crt/shaders/torridgristle/sunset-gaussian-horiz.slang. See slang/upstream for licence/source.
Texture2D<float4> Source : register(t2);
SamplerState _Source_sampler : register(s2);

static float2 blurCoordinates[5];
static float4 FragColor;

struct SPIRV_Cross_Input
{
    float2 blurCoordinates[5] : TEXCOORD1;
};

struct SPIRV_Cross_Output
{
    float4 FragColor : SV_Target0;
};

void frag_main()
{
    FragColor = ((((Source.Sample(_Source_sampler, blurCoordinates[0]) * 0.2041639983654022216796875f) + (Source.Sample(_Source_sampler, blurCoordinates[1]) * 0.3040049970149993896484375f)) + (Source.Sample(_Source_sampler, blurCoordinates[2]) * 0.3040049970149993896484375f)) + (Source.Sample(_Source_sampler, blurCoordinates[3]) * 0.093912996351718902587890625f)) + (Source.Sample(_Source_sampler, blurCoordinates[4]) * 0.093912996351718902587890625f);
}

SPIRV_Cross_Output main(SPIRV_Cross_Input stage_input)
{
    blurCoordinates = stage_input.blurCoordinates;
    frag_main();
    SPIRV_Cross_Output stage_output;
    stage_output.FragColor = FragColor;
    return stage_output;
}
