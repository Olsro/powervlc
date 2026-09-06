// Generated from crt/shaders/crt-beans/transform.slang. See slang/upstream for licence/source.
cbuffer Push : register(b1)
{
    float4 params_SourceSize : packoffset(c0);
    float params_YIQ : packoffset(c1);
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
    float3 _72 = Source.Load(int3(int2(int(floor(vTexCoord.x * params_SourceSize.x)), int(floor(vTexCoord.y * params_SourceSize.y))), 0)).xyz;
    float3 _103;
    if (params_YIQ > 0.5f)
    {
        _103 = mul(_72, float3x3(float3(0.300000011920928955078125f, 0.59899997711181640625f, 0.212999999523162841796875f), float3(0.589999973773956298828125f, -0.27730000019073486328125f, -0.5250999927520751953125f), float3(0.10999999940395355224609375f, -0.3217000067234039306640625f, 0.312099993228912353515625f)));
    }
    else
    {
        _103 = _72;
    }
    FragColor.x = _103.x;
    FragColor.y = _103.y;
    FragColor.z = _103.z;
}

SPIRV_Cross_Output main(SPIRV_Cross_Input stage_input)
{
    vTexCoord = stage_input.vTexCoord;
    frag_main();
    SPIRV_Cross_Output stage_output;
    stage_output.FragColor = FragColor;
    return stage_output;
}
