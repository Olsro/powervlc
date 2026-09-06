// Generated from crt/shaders/crt-beans/blur_horizontal.slang. See slang/upstream for licence/source.
cbuffer Push : register(b1)
{
    float4 params_SourceSize : packoffset(c0);
    float params_GlowSigma : packoffset(c1);
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
    float _23 = params_GlowSigma * params_SourceSize.y;
    int _32 = 2 * int(ceil(_23 * 1.5f));
    float2 _43 = vTexCoord * params_SourceSize.xy;
    float _82 = exp((-1.0f) / ((2.0f * _23) * _23));
    float _86 = _82 * _82;
    float _90 = _82 * _86;
    float3 _186;
    float _187;
    _187 = 1.0f;
    _186 = Source.Load(int3(int2(int(floor(_43.x)), int(floor(_43.y))), 0)).xyz;
    int _184 = 1;
    float _188 = _82;
    float _189 = _90;
    for (; _184 <= _32; )
    {
        float _105 = _188 * _189;
        float _108 = _189 * _86;
        float _120 = _188 + _105;
        float _135 = (float(_184) + (_105 / _120)) * params_SourceSize.z;
        _189 = _108 * _86;
        _188 = _105 * _108;
        _187 = (2.0f * _120) + _187;
        _186 = (_186 + (Source.SampleLevel(_Source_sampler, float2(vTexCoord.x - _135, vTexCoord.y), 0.0f).xyz * _120)) + (Source.SampleLevel(_Source_sampler, float2(vTexCoord.x + _135, vTexCoord.y), 0.0f).xyz * _120);
        _184 += 2;
        continue;
    }
    float3 _172 = _186 / _187.xxx;
    FragColor.x = _172.x;
    FragColor.y = _172.y;
    FragColor.z = _172.z;
}

SPIRV_Cross_Output main(SPIRV_Cross_Input stage_input)
{
    vTexCoord = stage_input.vTexCoord;
    frag_main();
    SPIRV_Cross_Output stage_output;
    stage_output.FragColor = FragColor;
    return stage_output;
}
