// Generated from crt/shaders/crt-easymode-halation/blur_vert.slang. See slang/upstream for licence/source.
cbuffer Push : register(b1)
{
    float4 params_SourceSize : packoffset(c0);
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
    float3 _90;
    float _91;
    _91 = 0.0f;
    _90 = 0.0f.xxx;
    for (int _89 = -4; _89 <= 4; )
    {
        float _41 = float(_89);
        float _46 = exp(((-0.3499999940395355224609375f) * _41) * _41);
        _91 += _46;
        _90 += (Source.Sample(_Source_sampler, vTexCoord + float2(0.0f, _41 * params_SourceSize.w)).xyz * _46);
        _89++;
        continue;
    }
    FragColor = float4(_90 / _91.xxx, 1.0f);
}

SPIRV_Cross_Output main(SPIRV_Cross_Input stage_input)
{
    vTexCoord = stage_input.vTexCoord;
    frag_main();
    SPIRV_Cross_Output stage_output;
    stage_output.FragColor = FragColor;
    return stage_output;
}
