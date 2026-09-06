// Generated from crt/shaders/crt-frutbunn.slang. See slang/upstream for licence/source.
cbuffer Push : register(b1)
{
    float4 params_SourceSize : packoffset(c0);
    float4 params_OutputSize : packoffset(c2);
    float params_CURVATURE : packoffset(c3.y);
    float params_SCANLINES : packoffset(c3.z);
    float params_CURVED_SCANLINES : packoffset(c3.w);
    float params_LIGHT : packoffset(c4);
    float params_light : packoffset(c4.y);
    float params_blur : packoffset(c4.z);
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
    float2 _210 = vTexCoord - 0.5f.xx;
    float _217 = length(((_210 * 0.5f) * _210) * 0.5f);
    bool _222 = params_CURVATURE > 0.5f;
    float2 _572;
    if (_222)
    {
        _572 = (_210 * _217) + (_210 * 0.935000002384185791015625f);
    }
    else
    {
        _572 = _210;
    }
    float2 _238 = _572 + 0.5f.xx;
    float2 _246 = params_SourceSize.xy * 2.0f;
    float _362 = _246.x;
    float _364 = _246.y;
    float _366 = params_blur / (_362 / _364);
    float _369 = _238.x;
    float _373 = _366 / _362;
    float _374 = _369 - _373;
    float _376 = _238.y;
    float _380 = _366 / _364;
    float _381 = _376 - _380;
    float4 _383 = Source.Sample(_Source_sampler, float2(_374, _381));
    float4 _397 = Source.Sample(_Source_sampler, float2(_374, _376));
    float _416 = _376 + _380;
    float4 _418 = Source.Sample(_Source_sampler, float2(_374, _416));
    float4 _434 = Source.Sample(_Source_sampler, float2(_369, _381));
    float4 _445 = Source.Sample(_Source_sampler, _238);
    float4 _461 = Source.Sample(_Source_sampler, float2(_369, _416));
    float _473 = _369 + _373;
    float4 _482 = Source.Sample(_Source_sampler, float2(_473, _381));
    float4 _498 = Source.Sample(_Source_sampler, float2(_473, _376));
    float4 _519 = Source.Sample(_Source_sampler, float2(_473, _416));
    float3 _523 = ((((((((_383.xyz * 0.077846996486186981201171875f) + (_397.xyz * 0.1233170032501220703125f)) + (_418.xyz * 0.077846996486186981201171875f)) + (_434.xyz * 0.1233170032501220703125f)) + (_445.xyz * 0.19534599781036376953125f)) + (_461.xyz * 0.1233170032501220703125f)) + (_482.xyz * 0.077846996486186981201171875f)) + (_498.xyz * 0.1233170032501220703125f)) + (_519.xyz * 0.077846996486186981201171875f);
    float3 _528;
    if (params_LIGHT > 0.5f)
    {
        _528 = _523 * (1.0f - min(1.0f, _217 * params_light));
    }
    else
    {
        _528 = _523;
    }
    float _526;
    if (params_CURVED_SCANLINES > 0.5f)
    {
        _526 = _572.y;
    }
    else
    {
        _526 = _210.y;
    }
    float3 _529;
    if (params_SCANLINES > 0.5f)
    {
        _529 = (_528 * abs(0.0f)) + ((_528 - (_528 * (cos((_526 * params_SourceSize.y) * (2.5f + (params_OutputSize.y * params_SourceSize.w))) * 0.25f))) * 1.0f);
    }
    else
    {
        _529 = _528;
    }
    float3 _530;
    if (_222)
    {
        _530 = _529 * min(max(0.0f, 1.0f - (2.0f * max(abs(_572.x), abs(_572.y)))) * 200.0f, 1.0f);
    }
    else
    {
        _530 = _529;
    }
    FragColor = float4(_530, 1.0f);
}

SPIRV_Cross_Output main(SPIRV_Cross_Input stage_input)
{
    vTexCoord = stage_input.vTexCoord;
    frag_main();
    SPIRV_Cross_Output stage_output;
    stage_output.FragColor = FragColor;
    return stage_output;
}
