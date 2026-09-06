// Generated from crt/shaders/gtu-v050/pass2.slang. See slang/upstream for licence/source.
cbuffer Push : register(b1)
{
    float4 params_SourceSize : packoffset(c2);
    float params_signalResolution : packoffset(c3);
    float params_signalResolutionI : packoffset(c3.y);
    float params_signalResolutionQ : packoffset(c3.z);
    float params_compositeConnection : packoffset(c3.w);
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
    float _29 = frac((vTexCoord.x * params_SourceSize.x) - 0.5f);
    bool _39 = params_compositeConnection > 0.0f;
    float _550;
    if (_39)
    {
        _550 = ceil(0.5f + (params_SourceSize.x / min(min(params_signalResolution, params_signalResolutionI), params_signalResolutionQ)));
    }
    else
    {
        _550 = ceil(0.5f + (params_SourceSize.x / params_signalResolution));
    }
    float3 _559;
    if (_39)
    {
        float _74 = -_550;
        float3 _560;
        _560 = 0.0f.xxx;
        for (float _557 = _74; _557 < (_550 + 2.0f); )
        {
            float _88 = _29 - _557;
            float4 _107 = Source.Sample(_Source_sampler, float2(vTexCoord.x - (_88 * params_SourceSize.z), vTexCoord.y));
            float _116 = params_signalResolution / params_SourceSize.x;
            float _117 = 3.1415927410125732421875f * _116;
            float _119 = abs(_88);
            float _120 = _119 + 0.5f;
            float _127 = 1.0f / _116;
            float _129 = _117 * min(_120, _127);
            float _157 = _119 - 0.5f;
            float _173 = _117 * min(max(_157, (-1.0f) / _116), _127);
            float _210 = params_signalResolutionI / params_SourceSize.x;
            float _211 = 3.1415927410125732421875f * _210;
            float _220 = 1.0f / _210;
            float _222 = _211 * min(_120, _220);
            float _265 = _211 * min(max(_157, (-1.0f) / _210), _220);
            float _301 = params_signalResolutionQ / params_SourceSize.x;
            float _302 = 3.1415927410125732421875f * _301;
            float _311 = 1.0f / _301;
            float _313 = _302 * min(_120, _311);
            float _356 = _302 * min(max(_157, (-1.0f) / _301), _311);
            _560 += float3(_107.x * ((((_129 + sin(_129)) - _173) - sin(_173)) * 0.15915493667125701904296875f), _107.y * ((((_222 + sin(_222)) - _265) - sin(_265)) * 0.15915493667125701904296875f), _107.z * ((((_313 + sin(_313)) - _356) - sin(_356)) * 0.15915493667125701904296875f));
            _557 += 1.0f;
            continue;
        }
        _559 = _560;
    }
    else
    {
        float _393 = -_550;
        float3 _555;
        _555 = 0.0f.xxx;
        for (float _551 = _393; _551 < (_550 + 2.0f); )
        {
            float _405 = _29 - _551;
            float _424 = params_signalResolution / params_SourceSize.x;
            float _425 = 3.1415927410125732421875f * _424;
            float _427 = abs(_405);
            float _434 = 1.0f / _424;
            float _436 = _425 * min(_427 + 0.5f, _434);
            float _479 = _425 * min(max(_427 - 0.5f, (-1.0f) / _424), _434);
            _555 += (Source.Sample(_Source_sampler, float2(vTexCoord.x - (_405 * params_SourceSize.z), vTexCoord.y)).xyz * ((((_436 + sin(_436)) - _479) - sin(_479)) * 0.15915493667125701904296875f));
            _551 += 1.0f;
            continue;
        }
        _559 = _555;
    }
    float3 _561;
    if (_39)
    {
        _561 = clamp(mul(float3x3(1.0f.xxx, float3(0.9563000202178955078125f, -0.2721000015735626220703125f, -1.10699999332427978515625f), float3(0.620999991893768310546875f, -0.64740002155303955078125f, 1.70459997653961181640625f)), _559), 0.0f.xxx, 1.0f.xxx);
    }
    else
    {
        _561 = clamp(_559, 0.0f.xxx, 1.0f.xxx);
    }
    FragColor = float4(_561, 1.0f);
}

SPIRV_Cross_Output main(SPIRV_Cross_Input stage_input)
{
    vTexCoord = stage_input.vTexCoord;
    frag_main();
    SPIRV_Cross_Output stage_output;
    stage_output.FragColor = FragColor;
    return stage_output;
}
