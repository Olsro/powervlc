// Generated from crt/shaders/torridgristle/Scanline-Interpolation.slang. See slang/upstream for licence/source.
cbuffer Push : register(b1)
{
    float4 params_SourceSize : packoffset(c0);
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
    FragColor = float4(Source.Sample(_Source_sampler, float2(vTexCoord.x, (floor(vTexCoord.y * params_SourceSize.y) + 0.5f) / params_SourceSize.y)).xyz, 1.0f);
}

SPIRV_Cross_Output main(SPIRV_Cross_Input stage_input)
{
    vTexCoord = stage_input.vTexCoord;
    frag_main();
    SPIRV_Cross_Output stage_output;
    stage_output.FragColor = FragColor;
    return stage_output;
}
