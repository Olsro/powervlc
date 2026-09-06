// Generated from crt/shaders/crt-nes-mini.slang. See slang/upstream for licence/source.
cbuffer Push : register(b1)
{
    float4 params_SourceSize : packoffset(c0);
    float params_BRIGHTBOOST : packoffset(c3.y);
    float params_INTENSITY : packoffset(c3.z);
    float params_SCANTHICK : packoffset(c3.w);
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

float mod(float x, float y)
{
    return x - y * floor(x / y);
}

float2 mod(float2 x, float2 y)
{
    return x - y * floor(x / y);
}

float3 mod(float3 x, float3 y)
{
    return x - y * floor(x / y);
}

float4 mod(float4 x, float4 y)
{
    return x - y * floor(x / y);
}

void frag_main()
{
    float3 _21 = Source.Sample(_Source_sampler, vTexCoord).xyz;
    float _71 = step(1.0f, mod((vTexCoord.y * params_SCANTHICK) * params_SourceSize.y, 2.0f));
    FragColor = float4(((((1.0f - params_INTENSITY).xxx + (_21 * 0.100000001490116119384765625f)) * _21) * (1.0f - _71)) + ((((1.0f + params_BRIGHTBOOST).xxx - (_21 * 0.20000000298023223876953125f)) * _21) * _71), 1.0f);
}

SPIRV_Cross_Output main(SPIRV_Cross_Input stage_input)
{
    vTexCoord = stage_input.vTexCoord;
    frag_main();
    SPIRV_Cross_Output stage_output;
    stage_output.FragColor = FragColor;
    return stage_output;
}
