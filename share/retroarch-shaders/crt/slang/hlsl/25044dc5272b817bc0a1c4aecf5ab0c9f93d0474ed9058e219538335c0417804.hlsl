// Generated from crt/shaders/cathode-retro/cathode-retro-crt-rgb-to-crt_no-signal.slang. See slang/upstream for licence/source.
cbuffer UBO : register(b0)
{
    float global_persistence : packoffset(c10.y);
    float global_scan_intens : packoffset(c10.z);
    float global_diffusion : packoffset(c10.w);
    float global_mask_intens : packoffset(c11);
    float global_mask_depth : packoffset(c11.y);
    float global_cat_mask_picker : packoffset(c11.z);
};

cbuffer Push : register(b1)
{
    float4 params_OriginalSize : packoffset(c1);
    float params_warpX : packoffset(c5);
    float params_warpY : packoffset(c5.y);
};

Texture2D<float4> g_screenMaskTexture : register(t4);
SamplerState _g_screenMaskTexture_sampler : register(s4);
Texture2D<float4> g_diffusionTexture : register(t5);
SamplerState _g_diffusionTexture_sampler : register(s5);
Texture2D<float4> g_sourceTexture : register(t2);
SamplerState _g_sourceTexture_sampler : register(s2);
Texture2D<float4> PassFeedback0 : register(t3);
SamplerState _PassFeedback0_sampler : register(s3);

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
    float _652;
    if (params_OriginalSize.y < 400.0f)
    {
        _652 = params_OriginalSize.y;
    }
    else
    {
        _652 = params_OriginalSize.y * 0.5f;
    }
    float4 _251 = g_screenMaskTexture.Sample(_g_screenMaskTexture_sampler, vTexCoord);
    float2 _256 = (vTexCoord * 2.0f) - 1.0f.xx;
    float2 _656;
    do
    {
        bool _519 = params_warpX == 0.0f;
        bool _525;
        if (_519)
        {
            _525 = params_warpY == 0.0f;
        }
        else
        {
            _525 = _519;
        }
        if (_525)
        {
            _656 = _256;
            break;
        }
        float2 _530 = max(9.9999997473787516355514526367188e-05f.xx, float2(params_warpX, params_warpY));
        float3 _536 = float3(_256 * _530, -2.0f);
        float _539 = dot(_536, _536);
        float _552 = (4.0f / _539) - sqrt(max(0.0f, (16.0f / (_539 * _539)) - (3.0f / _539)));
        float2 _615 = (_536.xy * _552) / (2.0f.xx + (_536.zz * _552));
        float2 _618 = _615 * _615;
        float3 _567 = float3(_530, -2.0f);
        float2 _569 = _567.xz;
        float2 _574 = _567.yz;
        float2 _578 = float2(dot(_569, _569), dot(_574, _574));
        float2 _593 = (4.0f.xx / _578) - sqrt(max(0.0f.xx, (16.0f.xx / (_578 * _578)) - (3.0f.xx / _578)));
        float2 _634 = (_567.xy * _593) / (2.0f.xx + (_567.zz * _593));
        float2 _637 = _634 * _634;
        _656 = (_615 * (1.0f.xx + (_618 * ((_618 * 0.20000000298023223876953125f) - 0.3333333432674407958984375f.xx)))) / (_634 * (1.0f.xx + (_637 * ((_637 * 0.20000000298023223876953125f) - 0.3333333432674407958984375f.xx))));
        break;
    } while(false);
    float _282 = _656.y + (0.5f / _652);
    float2 _709 = _656;
    _709.y = _282;
    float _290 = (_282 * _652) + _652;
    float _303 = ((_282 * 0.5f) + 0.5f) * _652;
    float _306 = frac(_303);
    float _311 = _306 - 0.5f;
    float2 _713 = _709;
    _713.y = ((((_303 - _306) + (((sign(_311) * clamp(abs(_311) - 0.100000001490116119384765625f, 0.0f, 1.0f)) * 1.25f) + 0.5f)) / _652) * 2.0f) - 1.0f;
    float2 _343 = (_713 * 0.5f) + 0.5f.xx;
    float _360 = lerp(global_scan_intens, 0.0f, smoothstep(1.0f, 1.39999997615814208984375f, (length(ddy(vTexCoord)) * _652) * 2.0f));
    float _365 = pow(abs(length(ddy(_709)) * _652), 2.599999904632568359375f);
    float _367 = _365 * 7.0f;
    float _371 = _290 - _367;
    float _375 = _290 + _367;
    float _394 = ((0.5f * (_375 - _371)) + (0.15915493667125701904296875f * (sin(3.1415927410125732421875f * _371) - sin(3.1415927410125732421875f * _375)))) / (_365 * 14.0f);
    float _396 = 1.0f - _360;
    float2 _716 = _343;
    _716.y = _343.y + ((-0.5f) / _652);
    float3 _453 = (_251.xyz * ((2.0f + global_cat_mask_picker) - global_mask_depth)) + global_mask_depth.xxx;
    float4 _718 = _251;
    _718.x = _453.x;
    _718.y = _453.y;
    _718.z = _453.z;
    float3 _474 = max(g_diffusionTexture.Sample(_g_diffusionTexture_sampler, (_656 * 0.5f) + 0.5f.xx).xyz * global_diffusion, (max((PassFeedback0.Sample(_PassFeedback0_sampler, _716).xyz * lerp(_396, 1.0f, 1.0f - _394)) * global_persistence, g_sourceTexture.Sample(_g_sourceTexture_sampler, _343).xyz * lerp(_396, 1.0f, _394)) / (1.0f - (_360 * 0.5f)).xxx) * lerp(1.0f.xxx, _718.xyz, global_mask_intens.xxx));
    FragColor = lerp(0.0f.xxxx, float4(_474, 1.0f), _251.w.xxxx);
}

SPIRV_Cross_Output main(SPIRV_Cross_Input stage_input)
{
    vTexCoord = stage_input.vTexCoord;
    frag_main();
    SPIRV_Cross_Output stage_output;
    stage_output.FragColor = FragColor;
    return stage_output;
}
