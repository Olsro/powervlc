// Generated from crt/shaders/crt-simple.slang. See slang/upstream for licence/source.
cbuffer Push : register(b1)
{
    float4 params_SourceSize : packoffset(c0);
    float4 params_OriginalSize : packoffset(c1);
    float4 params_OutputSize : packoffset(c2);
    float params_DISTORTION : packoffset(c3.y);
    float params_SCANLINE : packoffset(c3.z);
    float params_INPUTGAMMA : packoffset(c3.w);
    float params_OUTPUTGAMMA : packoffset(c4);
    float params_MASK : packoffset(c4.y);
    float params_SIZE : packoffset(c4.z);
    float params_DOWNSCALE : packoffset(c4.w);
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
    float2 _308 = float2(params_DISTORTION, params_DISTORTION * 1.5f);
    float2 _319 = params_SourceSize.xy / params_OriginalSize.xy;
    float2 _323 = (vTexCoord * _319) - 0.5f.xx;
    float _325 = _323.x;
    float _330 = _323.y;
    float2 _344 = (_323 + (_323 * (_308 * ((_325 * _325) + (_330 * _330))))) * (1.0f.xx - (_308 * 0.23000000417232513427734375f));
    bool _348 = abs(_344.x) >= 0.5f;
    bool _356;
    if (!_348)
    {
        _356 = abs(_344.y) >= 0.5f;
    }
    else
    {
        _356 = _348;
    }
    float2 _452;
    if (_356)
    {
        _452 = (-1.0f).xx;
    }
    else
    {
        _452 = (_344 + 0.5f.xx) / _319;
    }
    float2 _181 = (_452 * params_SourceSize.xy) - 0.5f.xx;
    float2 _189 = frac(_181 / params_DOWNSCALE.xx);
    float2 _197 = (floor(_181) + 0.5f.xx) / params_SourceSize.xy;
    _197.x = _452.x;
    float4 _212 = params_INPUTGAMMA.xxxx;
    float4 _213 = pow(Source.Sample(_Source_sampler, _197), _212);
    float4 _228 = pow(Source.Sample(_Source_sampler, _197 + float2(0.0f, params_SourceSize.w)), _212);
    float _232 = _189.y;
    float4 _380 = 2.0f.xxxx + (pow(_213, 4.0f.xxxx) * 2.0f);
    float4 _409 = 2.0f.xxxx + (pow(_228, 4.0f.xxxx) * 2.0f);
    FragColor = float4(pow(((_213 * ((exp(-pow((_232 / params_SCANLINE).xxxx * rsqrt(_380 * 0.5f), _380)) * 1.39999997615814208984375f) / (0.60000002384185791015625f.xxxx + (_380 * 0.20000000298023223876953125f)))) + (_228 * ((exp(-pow(((1.0f - _232) / params_SCANLINE).xxxx * rsqrt(_409 * 0.5f), _409)) * 1.39999997615814208984375f) / (0.60000002384185791015625f.xxxx + (_409 * 0.20000000298023223876953125f))))).xyz * lerp(params_MASK.xxx, 1.0f.xxx, frac(((vTexCoord * params_OutputSize.xy).x * 0.5f) / params_SIZE).xxx), (1.0f / params_OUTPUTGAMMA).xxx), 1.0f);
}

SPIRV_Cross_Output main(SPIRV_Cross_Input stage_input)
{
    vTexCoord = stage_input.vTexCoord;
    frag_main();
    SPIRV_Cross_Output stage_output;
    stage_output.FragColor = FragColor;
    return stage_output;
}
