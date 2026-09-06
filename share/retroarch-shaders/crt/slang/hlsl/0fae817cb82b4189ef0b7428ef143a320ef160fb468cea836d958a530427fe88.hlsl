// Generated from crt/shaders/crt-beans/linearize.slang. See slang/upstream for licence/source.
cbuffer Push : register(b1)
{
    float4 params_SourceSize : packoffset(c0);
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
    float3 _89 = pow(clamp(Source.Load(int3(int2(int(floor(vTexCoord.x * params_SourceSize.x)), int(floor(vTexCoord.y * params_SourceSize.y))), 0)).xyz, 0.0f.xxx, 1.0f.xxx), 2.400000095367431640625f.xxx);
    FragColor.x = _89.x;
    FragColor.y = _89.y;
    FragColor.z = _89.z;
}

SPIRV_Cross_Output main(SPIRV_Cross_Input stage_input)
{
    vTexCoord = stage_input.vTexCoord;
    frag_main();
    SPIRV_Cross_Output stage_output;
    stage_output.FragColor = FragColor;
    return stage_output;
}
