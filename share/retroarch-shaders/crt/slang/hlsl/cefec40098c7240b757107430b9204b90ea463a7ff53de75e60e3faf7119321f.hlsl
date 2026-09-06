// Generated from crt/shaders/crt-super-xbr/custom-bicubic-y.slang. See slang/upstream for licence/source.
cbuffer Push : register(b1)
{
    float4 params_SourceSize : packoffset(c0);
};

Texture2D<float4> Source : register(t2);
SamplerState _Source_sampler : register(s2);

static float2 vTexCoord;
static float4 t1;
static float4 t2;
static float4 FragColor;

struct SPIRV_Cross_Input
{
    float2 vTexCoord : TEXCOORD0;
    float4 t1 : TEXCOORD1;
    float4 t2 : TEXCOORD2;
};

struct SPIRV_Cross_Output
{
    float4 FragColor : SV_Target0;
};

void frag_main()
{
    float2 _25 = frac(vTexCoord * params_SourceSize.xy);
    float _64 = _25.y;
    float _67 = _64 * _64;
    FragColor = float4(mul(mul(float4x4(float4(-1.0f, 2.0f, -1.0f, 0.0f), float4(1.0f, -2.0f, 0.0f, 1.0f), float4(-1.0f, 1.0f, 1.0f, 0.0f), float4(1.0f, -1.0f, 0.0f, 0.0f)), float4(_67 * _64, _67, _64, 1.0f)), float4x3(float3(Source.Sample(_Source_sampler, t1.xy).xyz), float3(Source.Sample(_Source_sampler, t1.zw).xyz), float3(Source.Sample(_Source_sampler, t2.xy).xyz), float3(Source.Sample(_Source_sampler, t2.zw).xyz))), 1.0f);
}

SPIRV_Cross_Output main(SPIRV_Cross_Input stage_input)
{
    vTexCoord = stage_input.vTexCoord;
    t1 = stage_input.t1;
    t2 = stage_input.t2;
    frag_main();
    SPIRV_Cross_Output stage_output;
    stage_output.FragColor = FragColor;
    return stage_output;
}
