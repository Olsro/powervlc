// Generated from crt/shaders/cathode-retro/cathode-retro-util-tonemap-and-downsample-vert.slang. See slang/upstream for licence/source.
static const float _90[4] = { -2.6764705181121826171875f, -0.712341248989105224609375f, 0.71234118938446044921875f, 2.6764705181121826171875f };
static const float _103[4] = { -0.05099999904632568359375f, 0.55099999904632568359375f, 0.55099999904632568359375f, -0.05099999904632568359375f };

cbuffer UBO : register(b0)
{
    float global_minlum : packoffset(c6.y);
    float global_colorpower : packoffset(c6.z);
};

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
    int2 _176 = int2(params_SourceSize.xy);
    float4 _211;
    _211 = 0.0f.xxxx;
    for (int _210 = 0; _210 < 4; )
    {
        _211 += (Source.Sample(_Source_sampler, vTexCoord + ((float2(0.0f, 1.0f) / float2(_176)) * _90[_210])) * _103[_210]);
        _210++;
        continue;
    }
    float _134 = dot(_211.xyz, float3(0.300000011920928955078125f, 0.589999973773956298828125f, 0.10999999940395355224609375f));
    float3 _152 = _211.xyz * (pow(clamp((_134 - (1.0f - global_minlum)) / global_minlum, 0.0f, 1.0f), 2.0f - global_colorpower) / _134);
    float4 _219 = _211;
    _219.x = _152.x;
    _219.y = _152.y;
    _219.z = _152.z;
    FragColor = _219;
}

SPIRV_Cross_Output main(SPIRV_Cross_Input stage_input)
{
    vTexCoord = stage_input.vTexCoord;
    frag_main();
    SPIRV_Cross_Output stage_output;
    stage_output.FragColor = FragColor;
    return stage_output;
}
