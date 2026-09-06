// Generated from crt/shaders/crt-slangtest/cubic.slang. See slang/upstream for licence/source.
cbuffer UBO
{
    float4 global_SourceSize : packoffset(c0);
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
    float _28 = (vTexCoord.x * global_SourceSize.x) - 0.5f;
    float _31 = frac(_28);
    float2 _44 = float2((floor(_28) + 0.5f) * global_SourceSize.z, vTexCoord.y);
    float3 _59 = Source.SampleLevel(_Source_sampler, _44, 0.0f, int2(-1, 0)).xyz;
    float3 _65 = Source.SampleLevel(_Source_sampler, _44, 0.0f, int2(0, 0)).xyz;
    float3 _72 = Source.SampleLevel(_Source_sampler, _44, 0.0f, int2(1, 0)).xyz;
    float3 _79 = Source.SampleLevel(_Source_sampler, _44, 0.0f, int2(2, 0)).xyz;
    float _83 = _31 * _31;
    FragColor = float4(((_65 + (((_72 - _59) * 0.5f) * _31)) + ((((_59 - (_65 * 2.5f)) + (_72 * 2.0f)) - (_79 * 0.5f)) * _83)) + ((((_79 - _59) + ((_65 - _72) * 3.0f)) * 0.5f) * (_83 * _31)), 1.0f);
}

SPIRV_Cross_Output main(SPIRV_Cross_Input stage_input)
{
    vTexCoord = stage_input.vTexCoord;
    frag_main();
    SPIRV_Cross_Output stage_output;
    stage_output.FragColor = FragColor;
    return stage_output;
}
