// Generated from crt/shaders/cathode-retro/cathode-retro-util-gaussian-blur-vert.slang. See slang/upstream for licence/source.
static const float _62[7] = { -5.308887004852294921875f, -3.37461185455322265625f, -1.44531095027923583984375f, 0.0f, 1.44531095027923583984375f, 3.37461185455322265625f, 5.308887004852294921875f };
static const float _82[7] = { 0.035864882171154022216796875f, 0.12787799537181854248046875f, 0.2589758336544036865234375f, 0.1545625627040863037109375f, 0.2589758336544036865234375f, 0.12787799537181854248046875f, 0.035864882171154022216796875f };

cbuffer Push : register(b1)
{
    float4 params_SourceSize : packoffset(c0);
};

Texture2D<float4> Source : register(t2);
SamplerState _Source_sampler : register(s2);

static float4 FragColor;
static float2 vTexCoord;

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
    int2 _120 = int2(params_SourceSize.xy);
    float4 _151;
    _151 = 0.0f.xxxx;
    for (int _150 = 0; _150 < 7; )
    {
        _151 += (Source.Sample(_Source_sampler, vTexCoord + ((float2(0.0f, 1.0f) / float2(_120)) * _62[_150])) * _82[_150]);
        _150++;
        continue;
    }
    FragColor = _151;
}

SPIRV_Cross_Output main(SPIRV_Cross_Input stage_input)
{
    vTexCoord = stage_input.vTexCoord;
    frag_main();
    SPIRV_Cross_Output stage_output;
    stage_output.FragColor = FragColor;
    return stage_output;
}
