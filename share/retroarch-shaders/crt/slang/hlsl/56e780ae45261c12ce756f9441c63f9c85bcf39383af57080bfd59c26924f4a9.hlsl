// Generated from crt/shaders/zfast_crt/zfast_crt_geo.slang. See slang/upstream for licence/source.
cbuffer Push : register(b1)
{
    float4 params_SourceSize : packoffset(c0);
    float4 params_OutputSize : packoffset(c2);
    float params_SCANLINE_WEIGHT : packoffset(c3.y);
    float params_MASK_DARK : packoffset(c3.z);
};

Texture2D<float4> Source : register(t2);
SamplerState _Source_sampler : register(s2);

static float2 vTexCoord;
static float2 invDims;
static float4 FragColor;

struct SPIRV_Cross_Input
{
    float2 vTexCoord : TEXCOORD0;
    float2 invDims : TEXCOORD1;
};

struct SPIRV_Cross_Output
{
    float4 FragColor : SV_Target0;
};

void frag_main()
{
    float2 _291 = (vTexCoord * 2.0f) - 1.0f.xx;
    float _293 = _291.y;
    float _300 = _291.x;
    float2 _310 = (_291 * float2(1.0f + ((_293 * _293) * 0.02759999968111515045166015625f), 1.0f + ((_300 * _300) * 0.04140000045299530029296875f))) * 0.5f;
    float2 _312 = _310 + 0.5f.xx;
    float2 _87 = min(_312, 0.5f.xx - _310);
    float _91 = 9.9999997473787516355514526367188e-05f / _87.x;
    float2 _97 = vTexCoord * (1.0f.xx - vTexCoord);
    float _121 = _312.y * params_SourceSize.y;
    float _125 = floor(_121 - 0.5f);
    float _130 = (-1.0f) + (_121 - _125);
    float _134 = _130 * _130;
    float _162 = (params_OutputSize.y > 1499.0f) ? 0.33329999446868896484375f : 0.5f;
    float4 _191 = Source.Sample(_Source_sampler, float2(_312.x, ((_125 + 0.5f) + ((4.0f * _134) * _130)) * invDims.y));
    float3 _192 = _191.xyz;
    bool _228 = _87.y <= _91;
    bool _235;
    if (!_228)
    {
        _235 = _91 < 9.9999997473787516355514526367188e-05f;
    }
    else
    {
        _235 = _228;
    }
    float3 _362;
    if (_235)
    {
        _362 = 0.0f.xxx;
    }
    else
    {
        _362 = max(mul(float3x3(float3(1.0f, 0.0f, -0.0617300011217594146728515625f), float3(0.071110002696514129638671875f, 0.968869984149932861328125f, -0.011359999887645244598388671875f), float3(0.0f, 0.081969998776912689208984375f, 1.07280004024505615234375f)) * min(sqrt((_97.x * _97.y) * 46.0f), 1.0f), _192 * _192), 0.0f.xxx);
    }
    float3 _259 = _362 * lerp((1.5f - (params_SCANLINE_WEIGHT * (_134 - (_134 * _134)))) * (1.0f + (float(frac(floor(vTexCoord.x * params_OutputSize.x) * (-_162)) < _162) * (-params_MASK_DARK))), 1.0f, 0.2666699886322021484375f * ((_362.x + _362.y) + _362.z));
    float3 _318 = _259 - 1.0f.xxx;
    float3 _329 = lerp(sqrt(_259), sqrt(1.0f.xxx - (_318 * _318)), ((1.0f / ((((-0.0324999988079071044921875f) * params_SCANLINE_WEIGHT) + 1.0f) * (((-0.31099998950958251953125f) * params_MASK_DARK) + 1.0f))) - 1.2000000476837158203125f).xxx);
    FragColor = float4(_329, 1.0f);
}

SPIRV_Cross_Output main(SPIRV_Cross_Input stage_input)
{
    vTexCoord = stage_input.vTexCoord;
    invDims = stage_input.invDims;
    frag_main();
    SPIRV_Cross_Output stage_output;
    stage_output.FragColor = FragColor;
    return stage_output;
}
