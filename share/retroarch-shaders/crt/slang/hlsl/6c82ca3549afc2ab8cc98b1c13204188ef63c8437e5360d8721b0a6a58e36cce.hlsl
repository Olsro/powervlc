// Generated from crt/shaders/crt-beans/calculate_widths.slang. See slang/upstream for licence/source.
cbuffer Push : register(b1)
{
    float4 params_SourceSize : packoffset(c0);
    float params_MaxSpotSize : packoffset(c1);
    float params_MinSpotSize : packoffset(c1.y);
};

Texture2D<float4> Source : register(t1);
SamplerState _Source_sampler : register(s1);

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
    float _48 = params_MinSpotSize * params_MaxSpotSize;
    float3 _63 = 1.0f.xxx / (_48.xxx - (sqrt(Source.Load(int3(int2(floor(vTexCoord * params_SourceSize.xy)), 0)).xyz) * (_48 - params_MaxSpotSize)));
    FragColor.x = _63.x;
    FragColor.y = _63.y;
    FragColor.z = _63.z;
}

SPIRV_Cross_Output main(SPIRV_Cross_Input stage_input)
{
    vTexCoord = stage_input.vTexCoord;
    frag_main();
    SPIRV_Cross_Output stage_output;
    stage_output.FragColor = FragColor;
    return stage_output;
}
