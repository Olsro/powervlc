// Generated from crt/shaders/crt-yo6/crt-yo6-warp.slang. See slang/upstream for licence/source.
cbuffer Push : register(b1)
{
    float4 params_SourceSize : packoffset(c0);
};

Texture2D<float4> TEX_CRT : register(t3);
SamplerState _TEX_CRT_sampler : register(s3);
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
    float4 _20 = TEX_CRT.Sample(_TEX_CRT_sampler, vTexCoord);
    FragColor = float4(Source.Sample(_Source_sampler, ((vTexCoord * params_SourceSize.xy) + (((_20.xy * 255.0f) * 0.0625f.xx) - 7.0f.xx)) / params_SourceSize.xy).xyz * _20.z, 1.0f);
}

SPIRV_Cross_Output main(SPIRV_Cross_Input stage_input)
{
    vTexCoord = stage_input.vTexCoord;
    frag_main();
    SPIRV_Cross_Output stage_output;
    stage_output.FragColor = FragColor;
    return stage_output;
}
