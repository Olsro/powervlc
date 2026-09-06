// Generated from crt/shaders/zfast_crt/zfast_crt_finemask.slang. See slang/upstream for licence/source.
cbuffer Push : register(b1)
{
    float4 params_SourceSize : packoffset(c0);
    float4 params_OutputSize : packoffset(c2);
    float params_BLURSCALEX : packoffset(c3.y);
    float params_LOWLUMSCAN : packoffset(c3.z);
    float params_HILUMSCAN : packoffset(c3.w);
    float params_BRIGHTBOOST : packoffset(c4);
    float params_MASK_DARK : packoffset(c4.y);
};

Texture2D<float4> Source : register(t2);
SamplerState _Source_sampler : register(s2);

static float2 vTexCoord;
static float2 invDims;
static float4 FragColor;
static float maskFade;

struct SPIRV_Cross_Input
{
    float2 vTexCoord : TEXCOORD0;
    float maskFade : TEXCOORD1;
    float2 invDims : TEXCOORD2;
};

struct SPIRV_Cross_Output
{
    float4 FragColor : SV_Target0;
};

void frag_main()
{
    float2 _24 = vTexCoord * params_SourceSize.xy;
    float2 _30 = floor(_24) + 0.5f.xx;
    float2 _34 = _24 - _30;
    float2 _46 = (_30 + (((_34 * 4.0f) * _34) * _34)) * invDims;
    _46.x = lerp(_46.x, vTexCoord.x, params_BLURSCALEX);
    float _63 = _34.y;
    float _66 = _63 * _63;
    float _70 = _66 * _66;
    float3 _105 = Source.Sample(_Source_sampler, _46).xyz;
    float3 _146 = _105 * lerp((params_BRIGHTBOOST - (params_LOWLUMSCAN * (_66 - (2.0499999523162841796875f * _70)))) * (1.0f + (float(frac(floor(vTexCoord.x * params_OutputSize.x) * (-0.4999000132083892822265625f)) < 0.5f) * (-params_MASK_DARK))), 1.0f - (params_HILUMSCAN * (_70 - ((2.7999999523162841796875f * _70) * _66))), dot(_105, maskFade.xxx));
    FragColor.x = _146.x;
    FragColor.y = _146.y;
    FragColor.z = _146.z;
}

SPIRV_Cross_Output main(SPIRV_Cross_Input stage_input)
{
    vTexCoord = stage_input.vTexCoord;
    invDims = stage_input.invDims;
    maskFade = stage_input.maskFade;
    frag_main();
    SPIRV_Cross_Output stage_output;
    stage_output.FragColor = FragColor;
    return stage_output;
}
