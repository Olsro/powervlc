// Generated from crt/shaders/crt-beans/filter.slang. See slang/upstream for licence/source.
cbuffer Push : register(b1)
{
    float4 params_SourceSize : packoffset(c0);
    float params_Cutoff : packoffset(c1);
    float params_ICutoff : packoffset(c1.y);
    float params_QCutoff : packoffset(c1.z);
    float params_YIQ : packoffset(c1.w);
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
    bool _56 = params_YIQ > 0.5f;
    float3 _279;
    if (_56)
    {
        _279 = 1.0f.xxx / ((float3(params_Cutoff, params_ICutoff, params_QCutoff) * 53.3300018310546875f) * 2.0f);
    }
    else
    {
        _279 = 1.0f.xxx / ((params_Cutoff.xxx * 53.3300018310546875f) * 2.0f);
    }
    float _98 = max(_279.x, max(_279.y, _279.z));
    float3 _102 = 1.0f.xxx / _279;
    int _118 = int(floor(vTexCoord.y * params_SourceSize.y));
    int _132 = max(int(floor(params_SourceSize.x * (vTexCoord.x - _98))), 0);
    int _147 = min(int(floor(params_SourceSize.x * (vTexCoord.x + _98))), (int(params_SourceSize.x) - 1));
    float3 _167 = clamp(_102 * (vTexCoord.x - (float(_132) * params_SourceSize.z)), (-1.0f).xxx, 1.0f.xxx) * 3.1415927410125732421875f;
    float3 _282;
    float3 _287;
    _287 = _167 + sin(_167);
    _282 = 0.0f.xxx;
    for (int _280 = _132; _280 <= _147; )
    {
        int _197 = _280 + 1;
        float3 _213 = clamp(_102 * (vTexCoord.x - (float(_197) * params_SourceSize.z)), (-1.0f).xxx, 1.0f.xxx) * 3.1415927410125732421875f;
        float3 _217 = _213 + sin(_213);
        float3 _221 = _287 - _217;
        _287 = _217;
        _282 += (Source.Load(int3(int2(_280, _118), 0)).xyz * _221);
        _280 = _197;
        continue;
    }
    float3 _231 = _282 * 0.15915493667125701904296875f.xxx;
    float3 _283;
    if (_56)
    {
        _283 = pow(clamp(mul(_231, float3x3(1.0f.xxx, float3(0.946882188320159912109375f, -0.2747876346111297607421875f, -1.1085450649261474609375f), float3(0.623556554317474365234375f, -0.635691106319427490234375f, 1.70900690555572509765625f))), 0.0f.xxx, 1.0f.xxx), 2.400000095367431640625f.xxx);
    }
    else
    {
        _283 = pow(clamp(_231, 0.0f.xxx, 1.0f.xxx), 2.400000095367431640625f.xxx);
    }
    FragColor.x = _283.x;
    FragColor.y = _283.y;
    FragColor.z = _283.z;
}

SPIRV_Cross_Output main(SPIRV_Cross_Input stage_input)
{
    vTexCoord = stage_input.vTexCoord;
    frag_main();
    SPIRV_Cross_Output stage_output;
    stage_output.FragColor = FragColor;
    return stage_output;
}
