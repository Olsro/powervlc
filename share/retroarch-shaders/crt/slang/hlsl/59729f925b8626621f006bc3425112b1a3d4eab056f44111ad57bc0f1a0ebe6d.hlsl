// Generated from crt/shaders/crt-potato/shader-files/ultra_potato.slang. See slang/upstream for licence/source.
cbuffer Push : register(b1)
{
    float4 params_SourceSize : packoffset(c0);
    float4 params_OutputSize : packoffset(c2);
};

Texture2D<float4> Source : register(t2);
SamplerState _Source_sampler : register(s2);
Texture2D<float4> MASK : register(t3);
SamplerState _MASK_sampler : register(s3);

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
    float4 _19 = Source.Sample(_Source_sampler, vTexCoord);
    float _33 = lerp(1.0f, 0.300000011920928955078125f, max(_19.y, _19.z));
    FragColor = pow(MASK.Sample(_MASK_sampler, frac((vTexCoord * params_OutputSize.xy) / float2(2.0f, floor((params_OutputSize.y / params_SourceSize.y) + 9.9999999747524270787835121154785e-07f)))), _33.xxxx) * (_19 * lerp(1.0f, 1.2000000476837158203125f, _33));
}

SPIRV_Cross_Output main(SPIRV_Cross_Input stage_input)
{
    vTexCoord = stage_input.vTexCoord;
    frag_main();
    SPIRV_Cross_Output stage_output;
    stage_output.FragColor = FragColor;
    return stage_output;
}
