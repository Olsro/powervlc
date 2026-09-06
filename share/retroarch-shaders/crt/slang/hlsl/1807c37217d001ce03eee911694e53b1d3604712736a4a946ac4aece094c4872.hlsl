// Generated from crt/shaders/hyllian/crt-hyllian-3d.slang. See slang/upstream for licence/source.
cbuffer Push : register(b1)
{
    float4 params_SourceSize : packoffset(c0);
    float4 params_OutputSize : packoffset(c2);
    float params_CRT_MULRES_X : packoffset(c3.y);
    float params_CRT_MULRES_Y : packoffset(c3.z);
    float params_PHOSPHOR : packoffset(c3.w);
    float params_InputGamma : packoffset(c4);
    float params_OutputGamma : packoffset(c4.y);
    float params_SHARPNESS : packoffset(c4.z);
    float params_COLOR_BOOST : packoffset(c4.w);
    float params_RED_BOOST : packoffset(c5);
    float params_GREEN_BOOST : packoffset(c5.y);
    float params_BLUE_BOOST : packoffset(c5.z);
    float params_SCANLINES_STRENGTH : packoffset(c5.w);
    float params_BEAM_MIN_WIDTH : packoffset(c6);
    float params_BEAM_MAX_WIDTH : packoffset(c6.y);
    float params_CRT_ANTI_RINGING : packoffset(c6.z);
};

Texture2D<float4> Source : register(t2);
SamplerState _Source_sampler : register(s2);

static float4 FragColor;
static float2 vTexCoord;

struct SPIRV_Cross_Input
{
    float2 vTexCoord : TEXCOORD0;
};

struct SPIRV_Cross_Output
{
    float4 FragColor : SV_Target0;
};

float mod(float x, float y)
{
    return x - y * floor(x / y);
}

float2 mod(float2 x, float2 y)
{
    return x - y * floor(x / y);
}

float3 mod(float3 x, float3 y)
{
    return x - y * floor(x / y);
}

float4 mod(float4 x, float4 y)
{
    return x - y * floor(x / y);
}

void frag_main()
{
    float2 _586 = float2(params_SHARPNESS * params_SourceSize.x, params_SourceSize.y) / float2(params_CRT_MULRES_X, params_CRT_MULRES_Y);
    float2 _590 = float2(1.0f / _586.x, 0.0f);
    float2 _594 = float2(0.0f, 1.0f / _586.y);
    float2 _598 = (vTexCoord * _586) + float2(-0.5f, 0.5f);
    float2 _603 = (floor(_598) + 0.5f.xx) / _586;
    float2 _605 = frac(_598);
    float2 _609 = _603 - _590;
    float4 _621 = params_InputGamma.xxxx;
    float4 _637 = pow(Source.Sample(_Source_sampler, _603 - _594), _621);
    float2 _641 = _603 + _590;
    float4 _654 = pow(Source.Sample(_Source_sampler, _641 - _594), _621);
    float2 _659 = _603 + (_590 * 2.0f);
    float4 _700 = pow(Source.Sample(_Source_sampler, _603), _621);
    float4 _715 = pow(Source.Sample(_Source_sampler, _641), _621);
    float4 _738 = min(min(_637, _700), min(_654, _715));
    float4 _745 = max(max(_637, _700), max(_654, _715));
    float _797 = _605.x;
    float _800 = _797 * _797;
    float4 _813 = mul(float4x4(float4(-0.5f, 1.0f, -0.5f, 0.0f), float4(1.5f, -2.5f, 0.0f, 1.0f), float4(-1.5f, 2.0f, 0.5f, 0.0f), float4(0.5f, -0.5f, 0.0f, 0.0f)), float4(_800 * _797, _800, _797, 1.0f));
    float4 _816 = mul(_813, float4x4(pow(Source.Sample(_Source_sampler, _609 - _594), _621), _637, _654, pow(Source.Sample(_Source_sampler, _659 - _594), _621)));
    float4 _819 = mul(_813, float4x4(pow(Source.Sample(_Source_sampler, _609), _621), _700, _715, pow(Source.Sample(_Source_sampler, _659), _621)));
    float4 _829 = params_CRT_ANTI_RINGING.xxxx;
    float _843 = _605.y;
    float3 _853 = params_BEAM_MIN_WIDTH.xxx;
    float3 _860 = params_BEAM_MAX_WIDTH.xxx;
    float3 _862 = lerp(_816, clamp(_816, _738, _745), _829).xyz;
    float3 _879 = lerp(_819, clamp(_819, _738, _745), _829).xyz;
    float3 _889 = clamp(_843.xxx / (lerp(_853, _860, _862) + 1.0000000116860974230803549289703e-07f.xxx), 0.0f.xxx, 1.0f.xxx);
    float3 _898 = clamp((1.0f - _843).xxx / (lerp(_853, _860, _879) + 1.0000000116860974230803549289703e-07f.xxx), 0.0f.xxx, 1.0f.xxx);
    float _901 = (-10.0f) * params_SCANLINES_STRENGTH;
    FragColor = float4(pow((clamp((_862 * exp((_889 * _901) * _889)) + (_879 * exp((_898 * _901) * _898)), 0.0f.xxx, 1.0f.xxx) * (float3(params_RED_BOOST, params_GREEN_BOOST, params_BLUE_BOOST) * params_COLOR_BOOST)) * lerp(1.0f.xxx, lerp(float3(1.0f, 0.699999988079071044921875f, 1.0f), float3(0.699999988079071044921875f, 1.0f, 0.699999988079071044921875f), floor(mod(vTexCoord.x * params_OutputSize.x, 2.0f)).xxx), params_PHOSPHOR.xxx), (1.0f / params_OutputGamma).xxx), 1.0f);
}

SPIRV_Cross_Output main(SPIRV_Cross_Input stage_input)
{
    vTexCoord = stage_input.vTexCoord;
    frag_main();
    SPIRV_Cross_Output stage_output;
    stage_output.FragColor = FragColor;
    return stage_output;
}
