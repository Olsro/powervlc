// Generated from crt/shaders/zfast_crt/zfast_crt_curvature.slang. See slang/upstream for licence/source.
cbuffer Push : register(b1)
{
    float4 params_SourceSize : packoffset(c0);
    float4 params_OutputSize : packoffset(c2);
    float params_BLURSCALEX : packoffset(c3.y);
    float params_LOWLUMSCAN : packoffset(c3.z);
    float params_HILUMSCAN : packoffset(c3.w);
    float params_BRIGHTBOOST : packoffset(c4);
    float params_MASK_DARK : packoffset(c4.y);
    float params_CURVE : packoffset(c4.w);
};

Texture2D<float4> Source : register(t2);
SamplerState _Source_sampler : register(s2);

static float2 vTexCoord;
static float2 invDims;
static float cornerConst;
static float4 FragColor;
static float maskFade;

struct SPIRV_Cross_Input
{
    float2 vTexCoord : TEXCOORD0;
    float maskFade : TEXCOORD1;
    float2 invDims : TEXCOORD2;
    float cornerConst : TEXCOORD3;
};

struct SPIRV_Cross_Output
{
    float4 FragColor : SV_Target0;
};

void frag_main()
{
    float2 _230 = (-1.0f).xx + (vTexCoord * 2.0f);
    float2 _233 = _230 * _230;
    float2 _256 = clamp(((_230 * float2(1.0f + ((1.33329999446868896484375f * params_CURVE) * _233.y), 1.0f + (params_CURVE * _233.x))) * 0.5f) + 0.5f.xx, 0.0f.xx, 1.0f.xx);
    float2 _76 = _256 * params_SourceSize.xy;
    float2 _81 = floor(_76) + 0.5f.xx;
    float2 _85 = _76 - _81;
    float2 _97 = (_81 + (((_85 * 4.0f) * _85) * _85)) * invDims;
    _97.x = lerp(_97.x, _256.x, params_BLURSCALEX);
    float _109 = _85.y;
    float _112 = _109 * _109;
    float _116 = _112 * _112;
    float3 _150 = Source.Sample(_Source_sampler, _97).xyz;
    float2 _183 = min(_256, 1.0f.xx - _256);
    bool3 _265 = (_183.y <= (cornerConst / _183.x)).xxx;
    float3 _266 = float3(_265.x ? 0.0f.xxx.x : _150.x, _265.y ? 0.0f.xxx.y : _150.y, _265.z ? 0.0f.xxx.z : _150.z);
    float3 _211 = _266 * lerp((params_BRIGHTBOOST - (params_LOWLUMSCAN * (_112 - (2.0499999523162841796875f * _116)))) * (1.0f + (float(frac(floor((vTexCoord.x * params_OutputSize.x) * (-0.4999000132083892822265625f))) < 0.5f) * (-params_MASK_DARK))), 1.0f - (params_HILUMSCAN * (_116 - ((2.7999999523162841796875f * _116) * _112))), dot(_266, maskFade.xxx));
    FragColor.x = _211.x;
    FragColor.y = _211.y;
    FragColor.z = _211.z;
}

SPIRV_Cross_Output main(SPIRV_Cross_Input stage_input)
{
    vTexCoord = stage_input.vTexCoord;
    invDims = stage_input.invDims;
    cornerConst = stage_input.cornerConst;
    maskFade = stage_input.maskFade;
    frag_main();
    SPIRV_Cross_Output stage_output;
    stage_output.FragColor = FragColor;
    return stage_output;
}
