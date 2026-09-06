// Generated from crt/shaders/crt-1tap.slang. See slang/upstream for licence/source.
struct ResType
{
    float _m0;
    float _m1;
};

cbuffer Push : register(b1)
{
    float4 param_SourceSize : packoffset(c1);
    float param_MIN_THICK : packoffset(c2);
    float param_MAX_THICK : packoffset(c2.y);
    float param_V_SHARP : packoffset(c2.z);
    float param_H_SHARP : packoffset(c2.w);
    float param_SUBPX_POS : packoffset(c3);
    float param_THICK_FALLOFF : packoffset(c3.y);
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
    ResType _31;
    _31._m0 = modf((vTexCoord.x * param_SourceSize.x) - 0.5f, _31._m1);
    ResType _46;
    _46._m0 = modf((vTexCoord.y * param_SourceSize.y) - param_SUBPX_POS, _46._m1);
    float _49 = _46._m0 - 0.5f;
    float _53 = sign(_31._m0 - 0.5f);
    float _58 = (1.0f + _53) * 0.5f;
    float3 _102 = Source.Sample(_Source_sampler, float2((((_31._m1 + _58) - ((0.5f * _53) * pow(2.0f * (_58 - (_53 * _31._m0)), lerp(1.0f, 6.0f, param_H_SHARP)))) + 0.5f) * param_SourceSize.z, (_46._m1 + 0.5f) * param_SourceSize.w)).xyz;
    float3 _130 = pow(lerp(param_MIN_THICK.xxx, param_MAX_THICK.xxx, _102), param_THICK_FALLOFF.xxx) * 0.5f;
    float3 _151 = _102 * clamp(0.25f.xxx - (((_49 * _49).xxx - (_130 * _130)) * (3.0f + ((50.0f * param_V_SHARP) * param_V_SHARP))), 0.0f.xxx, 1.0f.xxx);
    FragColor.x = _151.x;
    FragColor.y = _151.y;
    FragColor.z = _151.z;
}

SPIRV_Cross_Output main(SPIRV_Cross_Input stage_input)
{
    vTexCoord = stage_input.vTexCoord;
    frag_main();
    SPIRV_Cross_Output stage_output;
    stage_output.FragColor = FragColor;
    return stage_output;
}
