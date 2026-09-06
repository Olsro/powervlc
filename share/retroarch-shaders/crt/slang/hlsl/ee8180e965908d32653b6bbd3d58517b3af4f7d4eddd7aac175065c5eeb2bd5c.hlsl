// Generated from crt/shaders/crt-beans/scanlines_fast_horizontal.slang. See slang/upstream for licence/source.
cbuffer Push : register(b1)
{
    float4 params_SourceSize : packoffset(c0);
    float params_MaxSpotSize : packoffset(c3);
    float params_MinSpotSize : packoffset(c3.y);
};

Texture2D<float4> Source : register(t1);
SamplerState _Source_sampler : register(s1);

static float2 vTexCoord;
static float delta;
static float4 FragColor;

struct SPIRV_Cross_Input
{
    float2 vTexCoord : TEXCOORD0;
    nointerpolation float delta : TEXCOORD1;
};

struct SPIRV_Cross_Output
{
    float4 FragColor : SV_Target0;
};

void frag_main()
{
    float _102 = vTexCoord.x * params_SourceSize.x;
    float _107 = params_MaxSpotSize / delta;
    float _112 = params_SourceSize.z * (floor(_102 - _107) + 0.5f);
    float _128 = params_SourceSize.z * (floor(_102 + _107) + 1.0f);
    float _136 = _102 * delta;
    float3 _264;
    _264 = 0.0f.xxx;
    for (float _262 = _112; _262 < _128; )
    {
        float3 _160 = Source.SampleLevel(_Source_sampler, float2(_262, vTexCoord.y), 0.0f).xyz;
        float _168 = delta * ((params_SourceSize.x * _262) - 0.5f);
        float _215 = params_MinSpotSize * params_MaxSpotSize;
        float3 _230 = 1.0f.xxx / (_215.xxx - (sqrt(_160) * (_215 - params_MaxSpotSize)));
        float3 _249 = clamp(_230 * (_136 - _168), (-1.0f).xxx, 1.0f.xxx) * 3.1415927410125732421875f;
        float3 _255 = clamp(_230 * (_136 - (_168 + delta)), (-1.0f).xxx, 1.0f.xxx) * 3.1415927410125732421875f;
        _264 += (_160 * (((_249 + sin(_249)) - _255) - sin(_255)));
        _262 += params_SourceSize.z;
        continue;
    }
    float3 _191 = _264 * 0.15915493667125701904296875f.xxx;
    FragColor.x = _191.x;
    FragColor.y = _191.y;
    FragColor.z = _191.z;
}

SPIRV_Cross_Output main(SPIRV_Cross_Input stage_input)
{
    vTexCoord = stage_input.vTexCoord;
    delta = stage_input.delta;
    frag_main();
    SPIRV_Cross_Output stage_output;
    stage_output.FragColor = FragColor;
    return stage_output;
}
