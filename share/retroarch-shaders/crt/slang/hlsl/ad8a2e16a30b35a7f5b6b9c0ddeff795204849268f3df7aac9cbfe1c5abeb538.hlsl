// Generated from crt/shaders/geom-deluxe/gaussx.slang. See slang/upstream for licence/source.
cbuffer UBO : register(b0)
{
    float4 global_SourceSize : packoffset(c0);
};

Texture2D<float4> internal1 : register(t2);
SamplerState _internal1_sampler : register(s2);

static float2 v_texCoord;
static float4 v_coeffs;
static float4 FragColor;

struct SPIRV_Cross_Input
{
    float2 v_texCoord : TEXCOORD0;
    float4 v_coeffs : TEXCOORD1;
};

struct SPIRV_Cross_Output
{
    float4 FragColor : SV_Target0;
};

void frag_main()
{
    float3 _94 = v_coeffs.w.xxx;
    float3 _111 = v_coeffs.z.xxx;
    float3 _128 = v_coeffs.y.xxx;
    float3 _144 = v_coeffs.x.xxx;
    float3 _217 = ((((((((pow(internal1.Sample(_internal1_sampler, v_texCoord + float2((-4.0f) / global_SourceSize.x, 0.0f)).xyz, 2.2000000476837158203125f.xxx) * _94) + (pow(internal1.Sample(_internal1_sampler, v_texCoord + float2((-3.0f) / global_SourceSize.x, 0.0f)).xyz, 2.2000000476837158203125f.xxx) * _111)) + (pow(internal1.Sample(_internal1_sampler, v_texCoord + float2((-2.0f) / global_SourceSize.x, 0.0f)).xyz, 2.2000000476837158203125f.xxx) * _128)) + (pow(internal1.Sample(_internal1_sampler, v_texCoord + float2((-1.0f) / global_SourceSize.x, 0.0f)).xyz, 2.2000000476837158203125f.xxx) * _144)) + pow(internal1.Sample(_internal1_sampler, v_texCoord).xyz, 2.2000000476837158203125f.xxx)) + (pow(internal1.Sample(_internal1_sampler, v_texCoord + float2(1.0f / global_SourceSize.x, 0.0f)).xyz, 2.2000000476837158203125f.xxx) * _144)) + (pow(internal1.Sample(_internal1_sampler, v_texCoord + float2(2.0f / global_SourceSize.x, 0.0f)).xyz, 2.2000000476837158203125f.xxx) * _128)) + (pow(internal1.Sample(_internal1_sampler, v_texCoord + float2(3.0f / global_SourceSize.x, 0.0f)).xyz, 2.2000000476837158203125f.xxx) * _111)) + (pow(internal1.Sample(_internal1_sampler, v_texCoord + float2(4.0f / global_SourceSize.x, 0.0f)).xyz, 2.2000000476837158203125f.xxx) * _94);
    FragColor = float4(pow(_217 * (1.0f / (1.0f + (2.0f * (((v_coeffs.x + v_coeffs.y) + v_coeffs.z) + v_coeffs.w)))).xxx, 0.4545454680919647216796875f.xxx), 1.0f);
}

SPIRV_Cross_Output main(SPIRV_Cross_Input stage_input)
{
    v_texCoord = stage_input.v_texCoord;
    v_coeffs = stage_input.v_coeffs;
    frag_main();
    SPIRV_Cross_Output stage_output;
    stage_output.FragColor = FragColor;
    return stage_output;
}
