// Generated from reshade/shaders/blendoverlay/blendoverlay.slang. See slang/upstream for licence/source.
cbuffer Push : register(b1)
{
    float4 params_OutputSize : packoffset(c2);
    float params_OverlayMix : packoffset(c3.y);
    float params_LUTWidth : packoffset(c3.z);
    float params_LUTHeight : packoffset(c3.w);
};

Texture2D<float4> Source : register(t2);
SamplerState _Source_sampler : register(s2);
Texture2D<float4> overlay : register(t3);
SamplerState _overlay_sampler : register(s3);

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
    float4 _50 = Source.Sample(_Source_sampler, vTexCoord);
    float4 _105 = overlay.Sample(_overlay_sampler, float2(frac((vTexCoord.x * params_OutputSize.x) / params_LUTWidth), frac((vTexCoord.y * params_OutputSize.y) / params_LUTHeight)));
    float _111 = _50.x;
    float _114 = _105.x;
    float _215;
    if (_111 < 0.5f)
    {
        _215 = (2.0f * _111) * _114;
    }
    else
    {
        _215 = 1.0f - ((2.0f * (1.0f - _111)) * (1.0f - _114));
    }
    float _119 = _50.y;
    float _122 = _105.y;
    float _216;
    if (_119 < 0.5f)
    {
        _216 = (2.0f * _119) * _122;
    }
    else
    {
        _216 = 1.0f - ((2.0f * (1.0f - _119)) * (1.0f - _122));
    }
    float _127 = _50.z;
    float _130 = _105.z;
    float _217;
    if (_127 < 0.5f)
    {
        _217 = (2.0f * _127) * _130;
    }
    else
    {
        _217 = 1.0f - ((2.0f * (1.0f - _127)) * (1.0f - _130));
    }
    FragColor = float4(lerp(_50.xyz, clamp(float3(_215, _216, _217), 0.0f.xxx, 1.0f.xxx), params_OverlayMix.xxx), 1.0f);
}

SPIRV_Cross_Output main(SPIRV_Cross_Input stage_input)
{
    vTexCoord = stage_input.vTexCoord;
    frag_main();
    SPIRV_Cross_Output stage_output;
    stage_output.FragColor = FragColor;
    return stage_output;
}
