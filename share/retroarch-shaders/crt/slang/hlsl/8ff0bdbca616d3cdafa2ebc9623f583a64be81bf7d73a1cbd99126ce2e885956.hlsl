// Generated from crt/shaders/crt-super-xbr/blur_vert.slang. See slang/upstream for licence/source.
cbuffer UBO : register(b0)
{
    float4 global_SourceSize : packoffset(c6);
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
    float3 _87;
    float _88;
    _88 = 0.0f;
    _87 = 0.0f.xxx;
    for (int _86 = -4; _86 <= 4; )
    {
        float _42 = float(_86);
        float _47 = exp(((-0.3499999940395355224609375f) * _42) * _42);
        _88 += _47;
        _87 += (Source.Sample(_Source_sampler, vTexCoord + float2(0.0f, _42 * global_SourceSize.w)).xyz * _47);
        _86++;
        continue;
    }
    FragColor = float4(_87 / _88.xxx, 1.0f);
}

SPIRV_Cross_Output main(SPIRV_Cross_Input stage_input)
{
    vTexCoord = stage_input.vTexCoord;
    frag_main();
    SPIRV_Cross_Output stage_output;
    stage_output.FragColor = FragColor;
    return stage_output;
}
