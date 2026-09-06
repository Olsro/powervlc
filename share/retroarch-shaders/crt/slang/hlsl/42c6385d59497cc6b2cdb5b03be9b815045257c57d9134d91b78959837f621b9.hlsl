// Generated from crt/shaders/crt-caligari.slang. See slang/upstream for licence/source.
cbuffer Push : register(b1)
{
    float4 params_SourceSize : packoffset(c0);
    float params_SPOT_WIDTH : packoffset(c3.y);
    float params_SPOT_HEIGHT : packoffset(c3.z);
    float params_COLOR_BOOST : packoffset(c3.w);
    float params_InputGamma : packoffset(c4);
    float params_OutputGamma : packoffset(c4.y);
};

Texture2D<float4> Source : register(t2);
SamplerState _Source_sampler : register(s2);

static float2 vTexCoord;
static float2 onex;
static float2 oney;
static float4 FragColor;

struct SPIRV_Cross_Input
{
    float2 vTexCoord : TEXCOORD0;
    float2 onex : TEXCOORD1;
    float2 oney : TEXCOORD2;
};

struct SPIRV_Cross_Output
{
    float4 FragColor : SV_Target0;
};

void frag_main()
{
    float2 _24 = vTexCoord * params_SourceSize.xy;
    float2 _30 = floor(_24) + 0.5f.xx;
    float2 _36 = _30 * params_SourceSize.zw;
    float4 _45 = Source.Sample(_Source_sampler, _36);
    float4 _50 = params_InputGamma.xxxx;
    float _59 = _24.x - _30.x;
    float _65 = _59 / params_SPOT_WIDTH;
    float _303 = (_65 > 1.0f) ? 1.0f : _65;
    float _75 = 1.0f - (_303 * _303);
    float _78 = _75 * _75;
    float2 _269;
    float _270;
    if (_59 > 0.0f)
    {
        _270 = 1.0f - _59;
        _269 = onex;
    }
    else
    {
        _270 = 1.0f + _59;
        _269 = -onex;
    }
    float2 _102 = _36 + _269;
    float4 _103 = Source.Sample(_Source_sampler, _102);
    float _112 = _270 / params_SPOT_WIDTH;
    float _304 = (_112 > 1.0f) ? 1.0f : _112;
    float _120 = 1.0f - (_304 * _304);
    float _123 = _120 * _120;
    float _136 = _24.y - _30.y;
    float _142 = _136 / params_SPOT_HEIGHT;
    float _305 = (_142 > 1.0f) ? 1.0f : _142;
    float _150 = 1.0f - (_305 * _305);
    float2 _281;
    float _282;
    if (_136 > 0.0f)
    {
        _282 = 1.0f - _136;
        _281 = oney;
    }
    else
    {
        _282 = 1.0f + _136;
        _281 = -oney;
    }
    float _185 = _282 / params_SPOT_HEIGHT;
    float _306 = (_185 > 1.0f) ? 1.0f : _185;
    float _193 = 1.0f - (_306 * _306);
    float _196 = _193 * _193;
    FragColor = clamp(pow((((((pow(_45, _50) * _78.xxxx) + (pow(_103, _50) * _123.xxxx)) * (_150 * _150).xxxx) + (pow(Source.Sample(_Source_sampler, _36 + _281), _50) * (_196 * _78).xxxx)) + (pow(Source.Sample(_Source_sampler, _102 + _281), _50) * (_196 * _123).xxxx)) * params_COLOR_BOOST.xxxx, (1.0f / params_OutputGamma).xxxx), 0.0f.xxxx, 1.0f.xxxx);
}

SPIRV_Cross_Output main(SPIRV_Cross_Input stage_input)
{
    vTexCoord = stage_input.vTexCoord;
    onex = stage_input.onex;
    oney = stage_input.oney;
    frag_main();
    SPIRV_Cross_Output stage_output;
    stage_output.FragColor = FragColor;
    return stage_output;
}
