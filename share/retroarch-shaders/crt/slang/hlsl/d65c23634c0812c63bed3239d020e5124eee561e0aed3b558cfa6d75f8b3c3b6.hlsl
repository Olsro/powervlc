// Generated from crt/shaders/cathode-retro/cathode-retro-util-downsample-2x-horz.slang. See slang/upstream for licence/source.
static const float _64[4] = { -2.6764705181121826171875f, -0.712341248989105224609375f, 0.71234118938446044921875f, 2.6764705181121826171875f };
static const float _78[4] = { -0.05099999904632568359375f, 0.55099999904632568359375f, 0.55099999904632568359375f, -0.05099999904632568359375f };

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
    int2 _117 = int2(params_SourceSize.xy);
    float4 _148;
    _148 = 0.0f.xxxx;
    for (int _147 = 0; _147 < 4; )
    {
        _148 += (Source.Sample(_Source_sampler, vTexCoord + ((float2(1.0f, 0.0f) / float2(_117)) * _64[_147])) * _78[_147]);
        _147++;
        continue;
    }
    FragColor = _148;
}

SPIRV_Cross_Output main(SPIRV_Cross_Input stage_input)
{
    vTexCoord = stage_input.vTexCoord;
    frag_main();
    SPIRV_Cross_Output stage_output;
    stage_output.FragColor = FragColor;
    return stage_output;
}
