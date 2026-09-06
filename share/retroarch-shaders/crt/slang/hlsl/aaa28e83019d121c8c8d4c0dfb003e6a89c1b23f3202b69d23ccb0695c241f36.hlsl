// Generated from crt/shaders/zfast_crt/zfast_crt_geo_svideo.slang. See slang/upstream for licence/source.
static float _438;

cbuffer Push : register(b1)
{
    float4 params_SourceSize : packoffset(c0);
    float4 params_OutputSize : packoffset(c2);
    float params_SCANLINE_WEIGHT : packoffset(c3.y);
    float params_MASK_DARK : packoffset(c3.z);
    float params_blurx : packoffset(c3.w);
    float params_blury : packoffset(c4);
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
    float2 _365 = (vTexCoord * 2.0f) - 1.0f.xx;
    float _367 = _365.y;
    float _374 = _365.x;
    float2 _384 = (_365 * float2(1.0f + ((_367 * _367) * 0.02759999968111515045166015625f), 1.0f + ((_374 * _374) * 0.04140000045299530029296875f))) * 0.5f;
    float2 _386 = _384 + 0.5f.xx;
    float2 _87 = min(_386, 0.5f.xx - _384);
    float _91 = 9.9999997473787516355514526367188e-05f / _87.x;
    float _100 = _386.x;
    float2 _119 = params_SourceSize.xy * 2.0f;
    float2 _120 = float2(params_blurx, _438) / _119;
    float _121 = _120.x;
    float _124 = _386.y;
    float2 _134 = float2(_438, params_blury) / _119;
    float _135 = _134.y;
    float4 _138 = Source.Sample(_Source_sampler, float2(_100 + _121, _124 - _135));
    float4 _143 = Source.Sample(_Source_sampler, _386);
    float4 _176 = Source.Sample(_Source_sampler, float2(_100 - _121, _124 + _135));
    float3 _196 = float3(_138.x * 0.5f, 0.25f * (_138.y + _176.y), _176.z * 0.5f) + (_143.xyz * 0.5f);
    float2 _201 = vTexCoord * (1.0f.xx - vTexCoord);
    float _219 = vTexCoord.y * params_SourceSize.y;
    float _225 = _219 - (floor(_219) + 0.5f);
    float _229 = _225 * _225;
    float _244 = (params_OutputSize.y > 1499.0f) ? 0.33329999446868896484375f : 0.5f;
    bool _301 = _87.y <= _91;
    bool _308;
    if (!_301)
    {
        _308 = _91 < 9.9999997473787516355514526367188e-05f;
    }
    else
    {
        _308 = _301;
    }
    float3 _443;
    if (_308)
    {
        _443 = 0.0f.xxx;
    }
    else
    {
        _443 = max(mul(float3x3(float3(0.92060387134552001953125f, 0.069309853017330169677734375f, -0.0516451187431812286376953125f), float3(0.087028317153453826904296875f, 0.9494526386260986328125f, -0.0078606642782688140869140625f), float3(0.013233962468802928924560546875f, 0.118294127285480499267578125f, 1.02324199676513671875f)) * min(sqrt((_201.x * _201.y) * 46.0f), 1.0f), _196 * _196), 0.0f.xxx);
    }
    float3 _332 = _443 * lerp((1.5f - (params_SCANLINE_WEIGHT * (_229 - (_229 * _229)))) * (1.0f + (float(frac(floor(vTexCoord.x * params_OutputSize.x) * (-_244)) < _244) * (-params_MASK_DARK))), 1.0f, 0.2666699886322021484375f * ((_443.x + _443.y) + _443.z));
    float3 _392 = _332 - 1.0f.xxx;
    FragColor = float4(lerp(sqrt(_332), sqrt(1.0f.xxx - (_392 * _392)), ((1.0f / ((((-0.0324999988079071044921875f) * params_SCANLINE_WEIGHT) + 1.0f) * (((-0.31099998950958251953125f) * params_MASK_DARK) + 1.0f))) - 1.2000000476837158203125f).xxx), 1.0f);
}

SPIRV_Cross_Output main(SPIRV_Cross_Input stage_input)
{
    vTexCoord = stage_input.vTexCoord;
    frag_main();
    SPIRV_Cross_Output stage_output;
    stage_output.FragColor = FragColor;
    return stage_output;
}
