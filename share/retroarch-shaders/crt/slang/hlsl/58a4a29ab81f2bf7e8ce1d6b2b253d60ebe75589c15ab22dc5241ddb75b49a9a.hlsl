// Generated from crt/shaders/yeetron.slang. See slang/upstream for licence/source.
cbuffer UBO : register(b0)
{
    float4 global_FinalViewportSize : packoffset(c4);
};

cbuffer Push : register(b1)
{
    float params_viewSizeHD : packoffset(c0);
    float params_intensityR : packoffset(c0.y);
    float params_intensityG : packoffset(c0.z);
    float params_intensityB : packoffset(c0.w);
    float4 params_SourceSize : packoffset(c1);
    float4 params_OriginalSize : packoffset(c2);
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
    float2 _59 = floor(((params_SourceSize.xy / params_OriginalSize.xy) * vTexCoord) * global_FinalViewportSize.xy) + 0.5f.xx;
    float _72 = frac(((_59.y * 3.0f) + _59.x) * 0.16666699945926666259765625f);
    float4 _344;
    if (_72 < 0.333000004291534423828125f)
    {
        float4 _285 = 0.0f.xxxx;
        _285.x = params_intensityR;
        _285.y = params_intensityG;
        _285.z = params_intensityB;
        _344 = _285;
    }
    else
    {
        float4 _345;
        if (_72 < 0.66600000858306884765625f)
        {
            float4 _291 = 0.0f.xxxx;
            _291.x = params_intensityB;
            _291.y = params_intensityR;
            _291.z = params_intensityG;
            _345 = _291;
        }
        else
        {
            float4 _297 = 0.0f.xxxx;
            _297.x = params_intensityG;
            _297.y = params_intensityB;
            _297.z = params_intensityR;
            _345 = _297;
        }
        _344 = _345;
    }
    float2 _129 = vTexCoord * params_SourceSize.xy;
    float2 _132 = floor(_129);
    float _142 = clamp(abs(sin(_129.y * 3.141590118408203125f)) + 0.25f, 0.5f, 1.0f);
    float4 _304 = _344;
    _304.w = _142;
    float2 _149 = frac(_129) + (-0.5f).xx;
    float2 _158 = ((-vTexCoord) * params_SourceSize.xy) + (_132 + 0.5f.xx);
    float _170 = clamp(1.5f - abs(_158.x * 0.5f), 0.800000011920928955078125f, 1.25f);
    float _179 = clamp(1.25f - abs(_158.y * 2.0f), 0.5f, 1.0f);
    float _202 = _142 * _170;
    _304.w = _202;
    float4 _227 = Source.Sample(_Source_sampler, ((((_149 - clamp(_149, (-0.25f).xx, 0.25f.xx)) * 2.0f) + _132) + 0.5f.xx) / params_SourceSize.xy);
    float3 _355 = float3(_202 * _227.x, float2(_170 * _179, _170 * ((_142 + _179) * 0.5f)) * _227.yz);
    float3 _277;
    if (global_FinalViewportSize.y >= params_viewSizeHD)
    {
        _277 = _304.xyz * _355;
    }
    else
    {
        _277 = _355;
    }
    FragColor = float4(_277, _227.w);
}

SPIRV_Cross_Output main(SPIRV_Cross_Input stage_input)
{
    vTexCoord = stage_input.vTexCoord;
    frag_main();
    SPIRV_Cross_Output stage_output;
    stage_output.FragColor = FragColor;
    return stage_output;
}
