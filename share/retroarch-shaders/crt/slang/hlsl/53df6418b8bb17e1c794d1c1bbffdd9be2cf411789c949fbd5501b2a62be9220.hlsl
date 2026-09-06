// Generated from crt/shaders/cathode-retro/cathode-retro-crt-generate-masks.slang. See slang/upstream for licence/source.
cbuffer UBO : register(b0)
{
    float global_cat_mask_picker : packoffset(c11.z);
    float global_mask_scale : packoffset(c11.w);
};

cbuffer Push : register(b1)
{
    float4 params_FinalViewportSize : packoffset(c4);
};


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

void frag_main()
{
    float _38 = params_FinalViewportSize.y * 2.0f;
    int _418 = int(global_cat_mask_picker);
    if (_418 == 1)
    {
        float _514 = frac((float(uint((frac((vTexCoord * (params_FinalViewportSize.xy * 0.16666667163372039794921875f.xx)) / global_mask_scale.xx).x * _38) - 0.5f)) / _38) * 2.0f) * 3.0f;
        float3 _830;
        if (_514 >= 2.0f)
        {
            _830 = float3(0.0f, 0.0f, 1.0f);
        }
        else
        {
            bool3 _841 = (_514 >= 1.0f).xxx;
            _830 = float3(_841.x ? float3(0.0f, 1.0f, 0.0f).x : float3(1.0f, 0.0f, 0.0f).x, _841.y ? float3(0.0f, 1.0f, 0.0f).y : float3(1.0f, 0.0f, 0.0f).y, _841.z ? float3(0.0f, 1.0f, 0.0f).z : float3(1.0f, 0.0f, 0.0f).z);
        }
        float _553 = 9.0f / params_FinalViewportSize.y;
        FragColor = float4(_830 * clamp(1.0f - smoothstep(1.0f - _553, 1.0f + _553, max(0.0f, (abs((frac(_514) * 0.3333333432674407958984375f) - 0.16666667163372039794921875f) - 0.083333335816860198974609375f) * 36.0f)), 0.0f, 1.0f), 1.0f);
    }
    else
    {
        if (_418 == 2)
        {
            float2 _597 = (float2(uint2((frac((vTexCoord * (params_FinalViewportSize.xy * 0.16666667163372039794921875f.xx)) / global_mask_scale.xx) * float2(_38, params_FinalViewportSize.y)) - 0.5f.xx)) / _38.xx) * float2(1.0f, 2.0f);
            float _599 = _597.x;
            float2 _918;
            if (_599 > 0.5f)
            {
                _918 = float2((_597.x * 2.0f) - 1.0f, frac(_597.y + 0.5f));
            }
            else
            {
                _597.x = _599 * 2.0f;
                _918 = _597;
            }
            float _620 = _918.x * 3.0f;
            float2 _864 = _918;
            _864.x = _620;
            float3 _826;
            if (_620 >= 2.0f)
            {
                _826 = float3(0.0f, 0.0f, 1.0f);
            }
            else
            {
                bool3 _843 = (_620 >= 1.0f).xxx;
                _826 = float3(_843.x ? float3(0.0f, 1.0f, 0.0f).x : float3(1.0f, 0.0f, 0.0f).x, _843.y ? float3(0.0f, 1.0f, 0.0f).y : float3(1.0f, 0.0f, 0.0f).y, _843.z ? float3(0.0f, 1.0f, 0.0f).z : float3(1.0f, 0.0f, 0.0f).z);
            }
            float _635 = frac(_620);
            _864.x = _635;
            _864.x = _635 * 0.3333333432674407958984375f;
            float _673 = 8.99999904632568359375f / params_FinalViewportSize.y;
            FragColor = float4(_826 * clamp(1.0f - smoothstep(1.0f - _673, 1.0f + _673, length(max(0.0f.xx, (abs(_864 - float2(0.16666667163372039794921875f, 0.5f)) - float2(0.083333335816860198974609375f, 0.333333313465118408203125f)) * 35.999996185302734375f.xx))), 0.0f, 1.0f), 1.0f);
        }
        else
        {
            if (_418 == 3)
            {
                float2 _704 = frac((vTexCoord * (params_FinalViewportSize.xy * 0.16666667163372039794921875f.xx)) / global_mask_scale.xx) * 6.0f.xx;
                bool _709 = frac(_704.y * 0.5f) >= 0.5f;
                float2 _909;
                if (_709)
                {
                    float2 _878 = _704;
                    _878.x = _704.x + 0.5f;
                    _909 = _878;
                }
                else
                {
                    _909 = _704;
                }
                int2 _719 = int2(floor(_909));
                float2 _721 = frac(_909);
                float _723 = _721.y;
                float _725 = _721.x;
                int2 _910;
                float2 _912;
                if (_723 < (((-0.57735025882720947265625f) * _725) + 0.288675129413604736328125f))
                {
                    float2 _886 = _909;
                    _886.x = _909.x + (_709 ? (-0.5f) : 0.5f);
                    _912 = _886;
                    _910 = int2(_719.x - int(_709), _719.y - 1);
                }
                else
                {
                    int2 _911;
                    float2 _913;
                    if (_723 < ((0.57735025882720947265625f * _725) - 0.288675129413604736328125f))
                    {
                        float2 _897 = _909;
                        _897.x = _909.x + (_709 ? (-0.5f) : 0.5f);
                        _913 = _897;
                        _911 = int2(_719.x + int(!_709), _719.y - 1);
                    }
                    else
                    {
                        _913 = _909;
                        _911 = _719;
                    }
                    _912 = _913;
                    _910 = _911;
                }
                int2 _914;
                float2 _916;
                if (frac(float(_910.y) * 0.5f) >= 0.5f)
                {
                    float2 _904 = _912;
                    _904.x = _912.x + 1.0f;
                    int2 _907 = _910;
                    _907.x = _910.x + 1;
                    _916 = _904;
                    _914 = _907;
                }
                else
                {
                    _916 = _912;
                    _914 = _910;
                }
                uint _791 = uint(_914.x + 1) % 3u;
                float3 _824;
                if (_791 == 0u)
                {
                    _824 = float3(1.0f, 0.0f, 0.0f);
                }
                else
                {
                    bool3 _845 = (_791 == 1u).xxx;
                    _824 = float3(_845.x ? float3(0.0f, 1.0f, 0.0f).x : float3(0.0f, 0.0f, 1.0f).x, _845.y ? float3(0.0f, 1.0f, 0.0f).y : float3(0.0f, 0.0f, 1.0f).y, _845.z ? float3(0.0f, 1.0f, 0.0f).z : float3(0.0f, 0.0f, 1.0f).z);
                }
                FragColor = float4(_824 * (1.0f - smoothstep(0.75f, 0.800000011920928955078125f, length((((_916 - float2(_914)) * float2(1.0f, 0.775990784168243408203125f)) * 2.0f) - 1.0f.xx))), 1.0f);
            }
            else
            {
                FragColor = 0.5f.xxxx;
            }
        }
    }
}

SPIRV_Cross_Output main(SPIRV_Cross_Input stage_input)
{
    vTexCoord = stage_input.vTexCoord;
    frag_main();
    SPIRV_Cross_Output stage_output;
    stage_output.FragColor = FragColor;
    return stage_output;
}
