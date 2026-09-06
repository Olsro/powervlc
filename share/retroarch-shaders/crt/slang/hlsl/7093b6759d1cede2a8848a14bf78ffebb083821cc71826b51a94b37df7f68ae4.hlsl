// Generated from crt/shaders/gtu-v050/pass3.slang. See slang/upstream for licence/source.
cbuffer Push : register(b1)
{
    float4 params_OutputSize : packoffset(c0);
    float4 params_SourceSize : packoffset(c2);
    float params_noScanlines : packoffset(c3);
    float params_tvVerticalResolution : packoffset(c3.y);
    float params_blackLevel : packoffset(c3.z);
    float params_contrast : packoffset(c3.w);
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
    float2 _158 = frac((vTexCoord * params_SourceSize.xy) - 0.5f.xx);
    float _169 = ceil(0.5f + (params_SourceSize.y / params_tvVerticalResolution));
    float3 _676;
    if (params_noScanlines > 0.0f)
    {
        float _179 = -_169;
        float3 _677;
        _677 = 0.0f.xxx;
        for (float _674 = _179; _674 < (_169 + 2.0f); )
        {
            float _203 = _158.y - _674;
            float _216 = params_tvVerticalResolution * params_SourceSize.w;
            float _217 = 3.1415927410125732421875f * _216;
            float _222 = abs(_203);
            float _229 = 1.0f / _216;
            float _231 = _217 * min(_222 + 0.5f, _229);
            float _281 = _217 * min(max(_222 - 0.5f, (-1.0f) / _216), _229);
            _677 += (Source.Sample(_Source_sampler, float2(vTexCoord.x, vTexCoord.y - (_203 * params_SourceSize.w))).xyz * ((((_231 + sin(_231)) - _281) - sin(_281)) * 0.15915493667125701904296875f));
            _674 += 1.0f;
            continue;
        }
        _676 = _677;
    }
    else
    {
        float _321 = -_169;
        float3 _673;
        _673 = 0.0f.xxx;
        for (float _671 = _321; _671 < (_169 + 2.0f); )
        {
            float _334 = _158.y - _671;
            float4 _349 = Source.Sample(_Source_sampler, float2(vTexCoord.x, vTexCoord.y - (_334 * params_SourceSize.w)));
            float _403 = 2.5066282749176025390625f * (params_tvVerticalResolution * params_SourceSize.w);
            float _409 = 0.5f * (params_SourceSize.y * params_OutputSize.w);
            float _414 = (_334 + _409) * _403;
            float _419 = (_334 - _409) * _403;
            float _466 = 1.0f + (0.3326700031757354736328125f * abs(_414));
            float _467 = 1.0f / _466;
            float _502 = 1.0f + (0.3326700031757354736328125f * abs(_419));
            float _503 = 1.0f / _502;
            float _426 = ((0.5f - ((exp(((-_414) * _414) * 0.5f) * 0.398942291736602783203125f) * (_467 * (0.4361836016178131103515625f + (_467 * ((-0.12016759812831878662109375f) + (0.937297999858856201171875f / _466))))))) * sign(_414)) - ((0.5f - ((exp(((-_419) * _419) * 0.5f) * 0.398942291736602783203125f) * (_503 * (0.4361836016178131103515625f + (_503 * ((-0.12016759812831878662109375f) + (0.937297999858856201171875f / _502))))))) * sign(_419));
            _673 += (float3(_349.x * _426, _349.y * _426, _349.z * _426) * (params_OutputSize.y * params_SourceSize.w));
            _671 += 1.0f;
            continue;
        }
        _676 = _673;
    }
    FragColor = float4((_676 - params_blackLevel.xxx) * (params_contrast.xxx / (1.0f - params_blackLevel).xxx), 1.0f);
}

SPIRV_Cross_Output main(SPIRV_Cross_Input stage_input)
{
    vTexCoord = stage_input.vTexCoord;
    frag_main();
    SPIRV_Cross_Output stage_output;
    stage_output.FragColor = FragColor;
    return stage_output;
}
