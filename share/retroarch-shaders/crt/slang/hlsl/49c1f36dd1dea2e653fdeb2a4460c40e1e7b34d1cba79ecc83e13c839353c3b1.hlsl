// Generated from crt/shaders/crt-slangtest/scanline.slang. See slang/upstream for licence/source.
cbuffer UBO
{
    float4 global_SourceSize : packoffset(c0);
    float global_OUT_GAMMA : packoffset(c1);
    float global_BOOST : packoffset(c1.y);
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
    float2 _56 = vTexCoord * global_SourceSize.xy;
    float _62 = _56.y;
    float2 _185 = _56;
    _185.y = floor(_62) + 0.5f;
    float2 _75 = _185 * global_SourceSize.zw;
    float3 _87 = Source.SampleLevel(_Source_sampler, _75, 0.0f, int2(0, -1)).xyz;
    float3 _93 = Source.SampleLevel(_Source_sampler, _75, 0.0f, int2(0, 0)).xyz;
    float3 _99 = Source.SampleLevel(_Source_sampler, _75, 0.0f, int2(0, 1)).xyz;
    float3 _120 = (3.5f.xxx - (float3(dot(_87, float3(0.2899999916553497314453125f, 0.60000002384185791015625f, 0.10999999940395355224609375f)), dot(_93, float3(0.2899999916553497314453125f, 0.60000002384185791015625f, 0.10999999940395355224609375f)), dot(_99, float3(0.2899999916553497314453125f, 0.60000002384185791015625f, 0.10999999940395355224609375f))) * 1.0f)) * ((frac(_62) - 0.5f).xxx + float3(1.0f, 0.0f, -1.0f));
    float3 _125 = exp2((-_120) * _120);
    FragColor = float4(pow(clamp((((_87 * _125.x) + (_93 * _125.y)) + (_99 * _125.z)) * global_BOOST, 0.0f.xxx, 1.0f.xxx), (1.0f / global_OUT_GAMMA).xxx), 1.0f);
}

SPIRV_Cross_Output main(SPIRV_Cross_Input stage_input)
{
    vTexCoord = stage_input.vTexCoord;
    frag_main();
    SPIRV_Cross_Output stage_output;
    stage_output.FragColor = FragColor;
    return stage_output;
}
