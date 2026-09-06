// Generated from crt/shaders/GritsScanlines/GritsScanlines.slang. See slang/upstream for licence/source.
cbuffer Push : register(b1)
{
    float4 params_SourceSize : packoffset(c0);
    float params_ScanlinesOpacity : packoffset(c3.y);
};

Texture2D<float4> luminance_LUT : register(t3);
SamplerState _luminance_LUT_sampler : register(s3);
Texture2D<float4> Source : register(t2);
SamplerState _Source_sampler : register(s2);
Texture2D<float4> scanlines_LUT : register(t5);
SamplerState _scanlines_LUT_sampler : register(s5);

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
    float4 _96 = Source.Sample(_Source_sampler, vTexCoord);
    float _160 = ((_96.x * 15.0f) + 0.4999000132083892822265625f) * 0.00390625f;
    float _165 = ((_96.y * 15.0f) + 0.4999000132083892822265625f) * 0.0625f;
    float _167 = _96.z;
    float _168 = _167 * 15.0f;
    float _172 = (floor(_168) * 0.0625f) + _160;
    float _179 = (ceil(_168) * 0.0625f) + _160;
    FragColor = ((scanlines_LUT.Sample(_scanlines_LUT_sampler, float2(clamp(lerp(luminance_LUT.Sample(_luminance_LUT_sampler, float2(_172, _165)).x, luminance_LUT.Sample(_luminance_LUT_sampler, float2(_179, _165)).x, clamp(max((_167 - _172) / (_179 - _172), 0.0f), 0.0f, 32.0f)), 0.0f, 1.0f), frac(vTexCoord.y * params_SourceSize.y))) * params_ScanlinesOpacity) + (1.0f - params_ScanlinesOpacity).xxxx) * _96;
}

SPIRV_Cross_Output main(SPIRV_Cross_Input stage_input)
{
    vTexCoord = stage_input.vTexCoord;
    frag_main();
    SPIRV_Cross_Output stage_output;
    stage_output.FragColor = FragColor;
    return stage_output;
}
