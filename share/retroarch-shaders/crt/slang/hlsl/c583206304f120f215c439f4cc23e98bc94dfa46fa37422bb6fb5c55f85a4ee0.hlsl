// Generated from crt/shaders/yee64.slang. See slang/upstream for licence/source.
cbuffer UBO : register(b0)
{
    float4 global_FinalViewportSize : packoffset(c4);
};

cbuffer Push : register(b1)
{
    float params_viewSizeHD : packoffset(c0);
    float params_brightness : packoffset(c0.y);
    float params_intensityR : packoffset(c0.z);
    float params_intensityG : packoffset(c0.w);
    float params_intensityB : packoffset(c1);
    float4 params_SourceSize : packoffset(c2);
    float4 params_OriginalSize : packoffset(c3);
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
    float2 _50 = (params_SourceSize.xy / params_OriginalSize.xy) * vTexCoord;
    float4 _59 = (params_OriginalSize.xy / params_SourceSize.xy).xyxy * _50.xyxy;
    float2 _64 = _59.zw * params_SourceSize.xy;
    float2 _69 = floor(_64);
    float2 _74 = (_64 - _69) + (-0.5f).xx;
    float _83 = _74.x;
    float _88 = pow(2.0f, pow((-1.0f) - _83, 2.0f) * (-3.0f));
    float _96 = pow(2.0f, pow(1.0f - _83, 2.0f) * (-3.0f));
    float _105 = pow(2.0f, pow((-2.0f) - _83, 2.0f) * (-3.0f));
    float _113 = pow(2.0f, pow(2.0f - _83, 2.0f) * (-3.0f));
    float _121 = pow(2.0f, pow(_83, 2.0f) * (-3.0f));
    float _127 = _74.y;
    float2 _156 = floor(_50 * global_FinalViewportSize.xy) + 0.5f.xx;
    float _167 = frac(((_156.y * 3.0f) + _156.x) * 0.16666699945926666259765625f);
    float4 _622;
    if (_167 < 0.333000004291534423828125f)
    {
        float4 _576 = 0.0f.xxxx;
        _576.x = params_intensityR;
        _576.y = params_intensityG;
        _576.z = params_intensityB;
        _622 = _576;
    }
    else
    {
        float4 _623;
        if (_167 < 0.66600000858306884765625f)
        {
            float4 _582 = 0.0f.xxxx;
            _582.x = params_intensityB;
            _582.y = params_intensityR;
            _582.z = params_intensityG;
            _623 = _582;
        }
        else
        {
            float4 _588 = 0.0f.xxxx;
            _588.x = params_intensityG;
            _588.y = params_intensityB;
            _588.z = params_intensityR;
            _623 = _588;
        }
        _622 = _623;
    }
    float3 _491 = ((_96 + _88) + _121).xxx;
    float3 _493 = ((((((((Source.Sample(_Source_sampler, (floor(_64 + float2(-2.0f, 0.0f)) + 0.5f.xx) / params_SourceSize.xy).xyz * _105) * params_brightness) + ((Source.Sample(_Source_sampler, (floor(_64 + float2(-1.0f, 0.0f)) + 0.5f.xx) / params_SourceSize.xy).xyz * _88) * params_brightness)) + ((Source.Sample(_Source_sampler, (floor(_64 + float2(1.0f, 0.0f)) + 0.5f.xx) / params_SourceSize.xy).xyz * _96) * params_brightness)) + ((Source.Sample(_Source_sampler, (_69 + 0.5f.xx) / params_SourceSize.xy).xyz * _121) * params_brightness)) + ((Source.Sample(_Source_sampler, (floor(_64 + float2(2.0f, 0.0f)) + 0.5f.xx) / params_SourceSize.xy).xyz * _113) * params_brightness)) * pow(2.0f, pow(_127, 2.0f) * (-8.0f))) / ((((_105 + _88) + _96) + _121) + _113).xxx) + ((((((Source.Sample(_Source_sampler, (floor(_64 + float2(1.0f, -1.0f)) + 0.5f.xx) / params_SourceSize.xy).xyz * _96) * params_brightness) + ((Source.Sample(_Source_sampler, (floor(_64 + (-1.0f).xx) + 0.5f.xx) / params_SourceSize.xy).xyz * _88) * params_brightness)) + ((Source.Sample(_Source_sampler, (floor(_64 + float2(0.0f, -1.0f)) + 0.5f.xx) / params_SourceSize.xy).xyz * _121) * params_brightness)) * pow(2.0f, pow((-1.0f) - _127, 2.0f) * (-8.0f))) / _491);
    float3 _511 = _493 + ((((((Source.Sample(_Source_sampler, (floor(_64 + 1.0f.xx) + 0.5f.xx) / params_SourceSize.xy).xyz * _96) * params_brightness) + ((Source.Sample(_Source_sampler, (floor(_64 + float2(-1.0f, 1.0f)) + 0.5f.xx) / params_SourceSize.xy).xyz * _88) * params_brightness)) + ((Source.Sample(_Source_sampler, (floor((_59.xy * params_SourceSize.xy) + float2(0.0f, 1.0f)) + 0.5f.xx) / params_SourceSize.xy).xyz * _121) * params_brightness)) * pow(2.0f, pow(1.0f - _127, 2.0f) * (-8.0f))) / _491);
    float3 _545;
    if (params_viewSizeHD < global_FinalViewportSize.y)
    {
        _545 = _622.xyz * _511;
    }
    else
    {
        _545 = _511;
    }
    FragColor = float4(_545, 1.0f);
}

SPIRV_Cross_Output main(SPIRV_Cross_Input stage_input)
{
    vTexCoord = stage_input.vTexCoord;
    frag_main();
    SPIRV_Cross_Output stage_output;
    stage_output.FragColor = FragColor;
    return stage_output;
}
