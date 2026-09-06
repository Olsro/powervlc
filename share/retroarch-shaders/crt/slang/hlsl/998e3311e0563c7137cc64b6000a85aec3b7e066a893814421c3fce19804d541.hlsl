// Generated from crt/shaders/hyllian/support/multiLUT-linear-fast.slang. See slang/upstream for licence/source.
cbuffer Push : register(b1)
{
    float params_LUT_selector_param : packoffset(c3.y);
    float params_H_InputGamma : packoffset(c3.z);
};

Texture2D<float4> Source : register(t2);
SamplerState _Source_sampler : register(s2);
Texture2D<float4> SamplerLUT1 : register(t3);
SamplerState _SamplerLUT1_sampler : register(s3);
Texture2D<float4> SamplerLUT2 : register(t4);
SamplerState _SamplerLUT2_sampler : register(s4);

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
    float4 _47 = Source.Sample(_Source_sampler, vTexCoord);
    float3 _193;
    if (params_LUT_selector_param < 0.5f)
    {
        _193 = _47.xyz;
    }
    else
    {
        float _77 = ((_47.x * 31.0f) + 0.4999000132083892822265625f) * 0.0009765625f;
        float _85 = ((_47.y * 31.0f) + 0.4999000132083892822265625f) * 0.03125f;
        float _88 = _47.z;
        float _89 = _88 * 31.0f;
        float _93 = (floor(_89) * 0.03125f) + _77;
        float _101 = (ceil(_89) * 0.03125f) + _77;
        float3 _189;
        float3 _190;
        if (params_LUT_selector_param < 1.5f)
        {
            _190 = SamplerLUT1.Sample(_SamplerLUT1_sampler, float2(_101, _85)).xyz;
            _189 = SamplerLUT1.Sample(_SamplerLUT1_sampler, float2(_93, _85)).xyz;
        }
        else
        {
            _190 = SamplerLUT2.Sample(_SamplerLUT2_sampler, float2(_101, _85)).xyz;
            _189 = SamplerLUT2.Sample(_SamplerLUT2_sampler, float2(_93, _85)).xyz;
        }
        float3 _192;
        if (_189.z < 1.0f)
        {
            _192 = lerp(_189, _190, clamp(max((_88 - _93) / (_101 - _93), 0.0f), 0.0f, 32.0f).xxx);
        }
        else
        {
            _192 = _189;
        }
        _193 = _192;
    }
    FragColor = float4(pow(_193, params_H_InputGamma.xxx), 1.0f);
}

SPIRV_Cross_Output main(SPIRV_Cross_Input stage_input)
{
    vTexCoord = stage_input.vTexCoord;
    frag_main();
    SPIRV_Cross_Output stage_output;
    stage_output.FragColor = FragColor;
    return stage_output;
}
