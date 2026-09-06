// Generated from crt/shaders/crt-sines.slang. See slang/upstream for licence/source.
static const float _44[5] = { 0.0625f, 0.25f, 0.375f, 0.25f, 0.0625f };

cbuffer UBO : register(b0)
{
    float4 global_SourceSize : packoffset(c4);
};

cbuffer Push : register(b1)
{
    float params_beam_max : packoffset(c0);
    float params_beam_min : packoffset(c0.y);
    float params_scan_max : packoffset(c0.z);
    float params_scan_min : packoffset(c0.w);
    float params_CURVATURE_X : packoffset(c1);
    float params_CURVATURE_Y : packoffset(c1.y);
    float params_CURVATURE_SCALE : packoffset(c1.z);
    float params_u_vignette : packoffset(c1.w);
    float params_MSK_BRI : packoffset(c2);
    float params_mask_type : packoffset(c2.y);
    float params_boost_bright : packoffset(c2.z);
    float params_boost_dark : packoffset(c2.w);
    float params_glow_str : packoffset(c3);
    float params_color_sat : packoffset(c3.y);
    float params_deconv : packoffset(c3.z);
    float params_glass_refl : packoffset(c3.w);
    float params_MSK_STAG : packoffset(c4.z);
    float params_glass_refl_pos : packoffset(c4.w);
    float params_profiler : packoffset(c5);
    float params_crt_colors : packoffset(c5.y);
    float params_filt : packoffset(c5.z);
    float params_corner_cut : packoffset(c5.w);
};

Texture2D<float4> Source : register(t2);
SamplerState _Source_sampler : register(s2);

static float2 invDims;
static float2 vTexCoord;
static float2 maskpos;
static float4 FragColor;

struct SPIRV_Cross_Input
{
    float2 vTexCoord : TEXCOORD0;
    float2 invDims : TEXCOORD1;
    float2 maskpos : TEXCOORD2;
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
    float2 _540 = (vTexCoord * 2.0f) - 1.0f.xx;
    float _543 = _540.y;
    float _548 = _540.x;
    float2 _584 = ((float2(_548 + (((_543 * _543) * _548) * params_CURVATURE_X), _540.y + (((_548 * _548) * _543) * params_CURVATURE_Y)) * (1.0f - (params_CURVATURE_SCALE * 0.100000001490116119384765625f))) * 0.5f) + 0.5f.xx;
    float2 _241 = _584 * global_SourceSize.xy;
    float2 _249 = floor(_241) + 0.5f.xx;
    float _254 = _249.y;
    float _255 = _241.y - _254;
    float _265 = frac(_241.x) - ((params_filt != 0.0f) ? 0.5f : 0.0f);
    float _677;
    if (params_filt == 0.0f)
    {
        _677 = (_249.x + ((_265 * _265) * (2.0f - _265))) * invDims.x;
    }
    else
    {
        float _676;
        if (params_filt == 1.0f)
        {
            _676 = (_249.x + (((sign(_265) * 2.0f) * _265) * _265)) * invDims.x;
        }
        else
        {
            _676 = (_249.x + (((4.0f * _265) * _265) * _265)) * invDims.x;
        }
        _677 = _676;
    }
    float2 _766 = float2(_677, (_254 + (((((16.0f * _255) * _255) * _255) * _255) * _255)) * invDims.y);
    float4 _345 = Source.Sample(_Source_sampler, _766);
    float3 _346 = _345.xyz;
    float3 _754;
    if (params_deconv == 1.0f)
    {
        float3 _738 = _346;
        _738.x = Source.Sample(_Source_sampler, _766 + float2(0.001000000047497451305389404296875f, 0.0f)).x;
        _738.z = Source.Sample(_Source_sampler, _766 - float2(0.001000000047497451305389404296875f, 0.0f)).z;
        _754 = _738;
    }
    else
    {
        _754 = _346;
    }
    float3 _370 = _754 * 0.949999988079071044921875f;
    float3 _755;
    if (params_crt_colors == 1.0f)
    {
        _755 = clamp(mul(float3x3(float3(1.0499999523162841796875f, 0.100000001490116119384765625f, -0.100000001490116119384765625f), float3(-0.0500000007450580596923828125f, 0.89999997615814208984375f, 0.0f), float3(0.0500000007450580596923828125f, 0.0f, 1.10000002384185791015625f)), _370), 0.0f.xxx, 1.0f.xxx);
    }
    else
    {
        _755 = _370;
    }
    float3 _401 = _755 + ((pow(1.0f - distance(_584, params_glass_refl_pos.xx), 6.0f) * params_glass_refl) * 0.100000001490116119384765625f).xxx;
    float _687;
    if (params_profiler == 0.0f)
    {
        _687 = max(max(_401.x, _401.y), _401.z);
    }
    else
    {
        _687 = dot(0.300000011920928955078125f.xxx, _401);
    }
    float3 _691;
    if (int(mod(floor(maskpos.x) + (mod(floor(maskpos.y), 2.0f) * params_MSK_STAG), (params_mask_type == 1.0f) ? 3.0f : 2.0f)) == 0)
    {
        _691 = params_MSK_BRI.xxx;
    }
    else
    {
        _691 = 1.0f.xxx;
    }
    int _693;
    float3 _694;
    _694 = 0.0f.xxx;
    _693 = -2;
    float3 _702;
    for (; _693 < 3; _694 = _702, _693++)
    {
        _702 = _694;
        for (int _698 = -1; _698 < 2; )
        {
            _702 += (Source.Sample(_Source_sampler, _766 + (invDims * float2(float(_693), float(_698) * 1.25f))).xyz * (_44[_693 + 2] + _44[_698 + 2]));
            _698++;
            continue;
        }
    }
    float _486 = distance(_584, 0.5f.xx);
    float3 _496 = (sqrt(((_401 * exp((((-lerp(params_beam_min, params_beam_max, _687)) * _255) * _255) * lerp(params_scan_min, params_scan_max, _687))) * lerp(_691, params_boost_bright.xxx, (_687 * 0.5f).xxx)) * lerp(params_boost_dark.xxx, 1.0f.xxx, _687.xxx)) + ((_694 * 0.533333361148834228515625f.xxx) * params_glow_str)) * (1.0f - (params_u_vignette * _486));
    float3 _763;
    if ((params_corner_cut == 1.0f) && (_486 > 0.699999988079071044921875f))
    {
        _763 = 0.0f.xxx;
    }
    else
    {
        _763 = lerp(dot(float3(0.300000011920928955078125f, 0.60000002384185791015625f, 0.100000001490116119384765625f), _496).xxx, _496, params_color_sat.xxx);
    }
    FragColor.x = _763.x;
    FragColor.y = _763.y;
    FragColor.z = _763.z;
}

SPIRV_Cross_Output main(SPIRV_Cross_Input stage_input)
{
    invDims = stage_input.invDims;
    vTexCoord = stage_input.vTexCoord;
    maskpos = stage_input.maskpos;
    frag_main();
    SPIRV_Cross_Output stage_output;
    stage_output.FragColor = FragColor;
    return stage_output;
}
