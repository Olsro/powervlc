// Generated from crt/shaders/glow/blur_horiz.slang. See slang/upstream for licence/source.
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
    float _27 = 4.0f * global_SourceSize.z;
    float3 _89;
    float _90;
    _90 = 0.0f;
    _89 = 0.0f.xxx;
    for (int _88 = -4; _88 <= 4; )
    {
        float _44 = float(_88);
        float _49 = exp(((-0.3499999940395355224609375f) * _44) * _44);
        _90 += _49;
        _89 += (Source.Sample(_Source_sampler, vTexCoord + float2(_44 * _27, 0.0f)).xyz * _49);
        _88++;
        continue;
    }
    FragColor = float4(_89 / _90.xxx, 1.0f);
}

SPIRV_Cross_Output main(SPIRV_Cross_Input stage_input)
{
    vTexCoord = stage_input.vTexCoord;
    frag_main();
    SPIRV_Cross_Output stage_output;
    stage_output.FragColor = FragColor;
    return stage_output;
}
