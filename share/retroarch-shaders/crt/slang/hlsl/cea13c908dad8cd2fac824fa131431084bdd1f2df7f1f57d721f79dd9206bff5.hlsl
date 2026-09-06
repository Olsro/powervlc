// Generated from crt/shaders/hyllian/support/glow/blur-glow-mask-geom.slang. See slang/upstream for licence/source.
static const float3 _281[3] = { float3(0.0f, 0.0f, 1.0f), float3(0.0f, 1.0f, 0.0f), float3(1.0f, 0.0f, 0.0f) };
static const float3 _299[3] = { 0.0f.xxx, 1.0f.xxx, 0.0f.xxx };
static const float3 _322[4] = { float3(0.0f, 0.0f, 1.0f), float3(0.0f, 1.0f, 1.0f), float3(1.0f, 1.0f, 0.0f), float3(1.0f, 0.0f, 0.0f) };
static const float3 _341[4] = { 0.0f.xxx, 0.0f.xxx, 1.0f.xxx, 1.0f.xxx };
static const float3 _359[4] = { float3(0.0f, 0.0f, 1.0f), float3(0.0f, 1.0f, 0.0f), float3(1.0f, 0.0f, 0.0f), 0.0f.xxx };
static const float3 _406[4] = { float3(1.0f, 1.0f, 0.0f), float3(1.0f, 0.0f, 0.0f), float3(0.0f, 0.0f, 1.0f), float3(0.0f, 1.0f, 1.0f) };
static const float3 _407[2][4] = { { float3(0.0f, 0.0f, 1.0f), float3(0.0f, 1.0f, 1.0f), float3(1.0f, 1.0f, 0.0f), float3(1.0f, 0.0f, 0.0f) }, { float3(1.0f, 1.0f, 0.0f), float3(1.0f, 0.0f, 0.0f), float3(0.0f, 0.0f, 1.0f), float3(0.0f, 1.0f, 1.0f) } };
static const float3 _432[4] = { float3(1.0f, 0.0f, 0.0f), 0.0f.xxx, float3(0.0f, 0.0f, 1.0f), float3(0.0f, 1.0f, 0.0f) };
static const float3 _433[2][4] = { { float3(0.0f, 0.0f, 1.0f), float3(0.0f, 1.0f, 0.0f), float3(1.0f, 0.0f, 0.0f), 0.0f.xxx }, { float3(1.0f, 0.0f, 0.0f), 0.0f.xxx, float3(0.0f, 0.0f, 1.0f), float3(0.0f, 1.0f, 0.0f) } };
static const float3 _458[4][4] = { { float3(0.0f, 0.0f, 1.0f), float3(0.0f, 1.0f, 1.0f), float3(1.0f, 1.0f, 0.0f), float3(1.0f, 0.0f, 0.0f) }, { float3(0.0f, 0.0f, 1.0f), float3(0.0f, 1.0f, 1.0f), float3(1.0f, 1.0f, 0.0f), float3(1.0f, 0.0f, 0.0f) }, { float3(1.0f, 1.0f, 0.0f), float3(1.0f, 0.0f, 0.0f), float3(0.0f, 0.0f, 1.0f), float3(0.0f, 1.0f, 1.0f) }, { float3(1.0f, 1.0f, 0.0f), float3(1.0f, 0.0f, 0.0f), float3(0.0f, 0.0f, 1.0f), float3(0.0f, 1.0f, 1.0f) } };
static const float3 _486[6] = { float3(0.0f, 0.0f, 1.0f), float3(0.0f, 1.0f, 0.0f), float3(1.0f, 0.0f, 0.0f), float3(0.0f, 0.0f, 1.0f), float3(0.0f, 1.0f, 0.0f), float3(1.0f, 0.0f, 0.0f) };
static const float3 _487[6] = { float3(0.0f, 0.0f, 1.0f), float3(0.0f, 1.0f, 0.0f), float3(1.0f, 0.0f, 0.0f), 0.0f.xxx, 0.0f.xxx, 0.0f.xxx };
static const float3 _488[6] = { 0.0f.xxx, 0.0f.xxx, 0.0f.xxx, float3(0.0f, 0.0f, 1.0f), float3(0.0f, 1.0f, 0.0f), float3(1.0f, 0.0f, 0.0f) };
static const float3 _489[4][6] = { { float3(0.0f, 0.0f, 1.0f), float3(0.0f, 1.0f, 0.0f), float3(1.0f, 0.0f, 0.0f), float3(0.0f, 0.0f, 1.0f), float3(0.0f, 1.0f, 0.0f), float3(1.0f, 0.0f, 0.0f) }, { float3(0.0f, 0.0f, 1.0f), float3(0.0f, 1.0f, 0.0f), float3(1.0f, 0.0f, 0.0f), 0.0f.xxx, 0.0f.xxx, 0.0f.xxx }, { float3(0.0f, 0.0f, 1.0f), float3(0.0f, 1.0f, 0.0f), float3(1.0f, 0.0f, 0.0f), float3(0.0f, 0.0f, 1.0f), float3(0.0f, 1.0f, 0.0f), float3(1.0f, 0.0f, 0.0f) }, { 0.0f.xxx, 0.0f.xxx, 0.0f.xxx, float3(0.0f, 0.0f, 1.0f), float3(0.0f, 1.0f, 0.0f), float3(1.0f, 0.0f, 0.0f) } };
static const float3 _514[6] = { 0.0f.xxx, 1.0f.xxx, 0.0f.xxx, 0.0f.xxx, 1.0f.xxx, 0.0f.xxx };
static const float3 _515[6] = { 0.0f.xxx, 1.0f.xxx, 0.0f.xxx, 0.0f.xxx, 0.0f.xxx, 0.0f.xxx };
static const float3 _516[6] = { 0.0f.xxx, 0.0f.xxx, 0.0f.xxx, 0.0f.xxx, 1.0f.xxx, 0.0f.xxx };
static const float3 _517[4][6] = { { 0.0f.xxx, 1.0f.xxx, 0.0f.xxx, 0.0f.xxx, 1.0f.xxx, 0.0f.xxx }, { 0.0f.xxx, 1.0f.xxx, 0.0f.xxx, 0.0f.xxx, 0.0f.xxx, 0.0f.xxx }, { 0.0f.xxx, 1.0f.xxx, 0.0f.xxx, 0.0f.xxx, 1.0f.xxx, 0.0f.xxx }, { 0.0f.xxx, 0.0f.xxx, 0.0f.xxx, 0.0f.xxx, 1.0f.xxx, 0.0f.xxx } };
static const float3 _544[8] = { float3(0.0f, 0.0f, 1.0f), float3(0.0f, 1.0f, 0.0f), float3(1.0f, 0.0f, 0.0f), 0.0f.xxx, float3(0.0f, 0.0f, 1.0f), float3(0.0f, 1.0f, 0.0f), float3(1.0f, 0.0f, 0.0f), 0.0f.xxx };
static const float3 _545[8] = { float3(0.0f, 0.0f, 1.0f), float3(0.0f, 1.0f, 0.0f), float3(1.0f, 0.0f, 0.0f), 0.0f.xxx, 0.0f.xxx, 0.0f.xxx, 0.0f.xxx, 0.0f.xxx };
static const float3 _546[8] = { 0.0f.xxx, 0.0f.xxx, 0.0f.xxx, 0.0f.xxx, float3(0.0f, 0.0f, 1.0f), float3(0.0f, 1.0f, 0.0f), float3(1.0f, 0.0f, 0.0f), 0.0f.xxx };
static const float3 _547[4][8] = { { float3(0.0f, 0.0f, 1.0f), float3(0.0f, 1.0f, 0.0f), float3(1.0f, 0.0f, 0.0f), 0.0f.xxx, float3(0.0f, 0.0f, 1.0f), float3(0.0f, 1.0f, 0.0f), float3(1.0f, 0.0f, 0.0f), 0.0f.xxx }, { float3(0.0f, 0.0f, 1.0f), float3(0.0f, 1.0f, 0.0f), float3(1.0f, 0.0f, 0.0f), 0.0f.xxx, 0.0f.xxx, 0.0f.xxx, 0.0f.xxx, 0.0f.xxx }, { float3(0.0f, 0.0f, 1.0f), float3(0.0f, 1.0f, 0.0f), float3(1.0f, 0.0f, 0.0f), 0.0f.xxx, float3(0.0f, 0.0f, 1.0f), float3(0.0f, 1.0f, 0.0f), float3(1.0f, 0.0f, 0.0f), 0.0f.xxx }, { 0.0f.xxx, 0.0f.xxx, 0.0f.xxx, 0.0f.xxx, float3(0.0f, 0.0f, 1.0f), float3(0.0f, 1.0f, 0.0f), float3(1.0f, 0.0f, 0.0f), 0.0f.xxx } };
static const float3 _574[10] = { float3(0.0f, 0.0f, 1.0f), float3(0.0f, 1.0f, 1.0f), float3(0.0f, 1.0f, 0.0f), float3(1.0f, 0.0f, 0.0f), float3(1.0f, 0.0f, 0.0f), float3(0.0f, 0.0f, 1.0f), float3(0.0f, 1.0f, 1.0f), float3(0.0f, 1.0f, 0.0f), float3(1.0f, 0.0f, 0.0f), float3(1.0f, 0.0f, 0.0f) };
static const float3 _575[10] = { 0.0f.xxx, float3(0.0f, 1.0f, 0.0f), float3(0.0f, 1.0f, 0.0f), float3(1.0f, 0.0f, 0.0f), float3(1.0f, 0.0f, 0.0f), float3(0.0f, 0.0f, 1.0f), float3(0.0f, 0.0f, 1.0f), 0.0f.xxx, 0.0f.xxx, 0.0f.xxx };
static const float3 _576[10] = { float3(0.0f, 0.0f, 1.0f), float3(0.0f, 0.0f, 1.0f), 0.0f.xxx, 0.0f.xxx, 0.0f.xxx, 0.0f.xxx, float3(0.0f, 1.0f, 0.0f), float3(0.0f, 1.0f, 0.0f), float3(1.0f, 0.0f, 0.0f), float3(1.0f, 0.0f, 0.0f) };
static const float3 _577[4][10] = { { float3(0.0f, 0.0f, 1.0f), float3(0.0f, 1.0f, 1.0f), float3(0.0f, 1.0f, 0.0f), float3(1.0f, 0.0f, 0.0f), float3(1.0f, 0.0f, 0.0f), float3(0.0f, 0.0f, 1.0f), float3(0.0f, 1.0f, 1.0f), float3(0.0f, 1.0f, 0.0f), float3(1.0f, 0.0f, 0.0f), float3(1.0f, 0.0f, 0.0f) }, { 0.0f.xxx, float3(0.0f, 1.0f, 0.0f), float3(0.0f, 1.0f, 0.0f), float3(1.0f, 0.0f, 0.0f), float3(1.0f, 0.0f, 0.0f), float3(0.0f, 0.0f, 1.0f), float3(0.0f, 0.0f, 1.0f), 0.0f.xxx, 0.0f.xxx, 0.0f.xxx }, { float3(0.0f, 0.0f, 1.0f), float3(0.0f, 1.0f, 1.0f), float3(0.0f, 1.0f, 0.0f), float3(1.0f, 0.0f, 0.0f), float3(1.0f, 0.0f, 0.0f), float3(0.0f, 0.0f, 1.0f), float3(0.0f, 1.0f, 1.0f), float3(0.0f, 1.0f, 0.0f), float3(1.0f, 0.0f, 0.0f), float3(1.0f, 0.0f, 0.0f) }, { float3(0.0f, 0.0f, 1.0f), float3(0.0f, 0.0f, 1.0f), 0.0f.xxx, 0.0f.xxx, 0.0f.xxx, 0.0f.xxx, float3(0.0f, 1.0f, 0.0f), float3(0.0f, 1.0f, 0.0f), float3(1.0f, 0.0f, 0.0f), float3(1.0f, 0.0f, 0.0f) } };

cbuffer UBO : register(b0)
{
    float4 global_SourceSize : packoffset(c4);
    float4 global_OutputSize : packoffset(c6);
};

cbuffer Push : register(b1)
{
    float params_GLOW_ENABLE : packoffset(c0);
    float params_GLOW_RADIUS : packoffset(c0.y);
    float params_GLOW_STRENGTH : packoffset(c0.z);
    float params_MASK_STRENGTH : packoffset(c1.z);
    float params_BRIGHTBOOST : packoffset(c1.w);
    float params_MONITOR_SUBPIXELS : packoffset(c2);
    float params_VSCANLINES : packoffset(c2.y);
    float params_H_OUTPUT_GAMMA : packoffset(c2.z);
    float params_H_MaskGamma : packoffset(c2.w);
    float params_h_curvature : packoffset(c3);
    float params_h_shape : packoffset(c3.y);
    float params_h_radius : packoffset(c3.z);
    float params_h_cornersize : packoffset(c3.w);
    float params_h_cornersmooth : packoffset(c4);
};

Texture2D<float4> Source : register(t2);
SamplerState _Source_sampler : register(s2);
Texture2D<float4> CRTPass : register(t3);
SamplerState _CRTPass_sampler : register(s3);

static float2 vTexCoord;
static float2 mask_profile;
static float4 FragColor;

struct SPIRV_Cross_Input
{
    float2 vTexCoord : TEXCOORD0;
    float2 mask_profile : TEXCOORD1;
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
    float _49 = params_h_radius * params_h_radius;
    float _57 = _49 - 1.0f;
    float _76 = global_OutputSize.y / global_OutputSize.x;
    float2 _77 = float2(1.0f, _76);
    float _87 = params_h_cornersize * min(1.0f, _76);
    bool _772 = params_h_curvature > 0.5f;
    float2 _1495;
    if (_772)
    {
        float2 _932 = (vTexCoord * 2.0f) - 1.0f.xx;
        float _935 = _932.x;
        _1495 = ((_932 * lerp(sqrt(_57 / (_49 - dot(_932, _932))).xx, float2(sqrt((_49 - 2.0f) / _57), 1.0f) * sqrt((_49 - (_935 * _935)) / (_49 - ((2.0f * _935) * _935))), params_h_shape.xx)) * 0.5f) + 0.5f.xx;
    }
    else
    {
        _1495 = vTexCoord;
    }
    float _1498;
    if (_772)
    {
        float2 _989 = abs(((_1495 * 2.0f) - 1.0f.xx) * _77) - (_77 - _87.xx);
        _1498 = smoothstep(params_h_cornersmooth * 0.00999999977648258209228515625f, params_h_cornersmooth * (-0.00999999977648258209228515625f), (length(max(_989, 0.0f.xx)) + min(max(_989.x, _989.y), 0.0f)) - _87);
    }
    else
    {
        _1498 = 1.0f;
    }
    float2 _803 = float2(0.0f, params_GLOW_RADIUS * global_SourceSize.w);
    float3 _1500;
    if (params_GLOW_ENABLE > 0.5f)
    {
        float2 _1013 = _803 * 4.0f;
        float2 _1023 = _803 * 3.0f;
        float2 _1033 = _803 * 2.0f;
        _1500 = ((((((((Source.Sample(_Source_sampler, _1495 - _1013).xyz * 0.001234402996487915515899658203125f) + (Source.Sample(_Source_sampler, _1495 - _1023).xyz * 0.01430468820035457611083984375f)) + (Source.Sample(_Source_sampler, _1495 - _1033).xyz * 0.0823177993297576904296875f)) + (Source.Sample(_Source_sampler, _1495 - _803).xyz * 0.2352355420589447021484375f)) + (Source.Sample(_Source_sampler, _1495).xyz * 0.3338151276111602783203125f)) + (Source.Sample(_Source_sampler, _1495 + _803).xyz * 0.2352355420589447021484375f)) + (Source.Sample(_Source_sampler, _1495 + _1033).xyz * 0.0823177993297576904296875f)) + (Source.Sample(_Source_sampler, _1495 + _1023).xyz * 0.01430468820035457611083984375f)) + (Source.Sample(_Source_sampler, _1495 + _1013).xyz * 0.001234402996487915515899658203125f);
    }
    else
    {
        _1500 = 0.0f.xxx;
    }
    float2 _825 = vTexCoord * global_OutputSize.xy;
    float2 _833 = lerp(_825, _825.yx, params_VSCANLINES.xx);
    float3 _1506;
    do
    {
        if (mask_profile.x > 14.0f)
        {
            float3 _1639;
            if (mask_profile.x == 15.0f)
            {
                float _1388 = _833.x;
                float _1406 = frac(_1388 * 0.3333333432674407958984375f);
                float3 _1637;
                if (_1406 < 0.333000004291534423828125f)
                {
                    _1637 = float3(0.0f, 0.0f, 1.0f);
                }
                else
                {
                    float3 _1638;
                    if (_1406 < 0.66600000858306884765625f)
                    {
                        _1638 = float3(0.0f, 1.0f, 0.0f);
                    }
                    else
                    {
                        _1638 = float3(1.0f, 0.0f, 0.0f);
                    }
                    _1637 = _1638;
                }
                _1639 = _1637 * ((frac((_833.y + float(frac(_1388 * 0.16666667163372039794921875f) < 0.5f)) * 0.5f) < 0.5f) ? 0.0f : 1.0f);
            }
            else
            {
                float3 _1640;
                if (mask_profile.x == 16.0f)
                {
                    float _1440 = frac((_833.x + (_833.y * 3.0f)) * 0.16666667163372039794921875f);
                    float3 _1644;
                    if (_1440 < 0.333000004291534423828125f)
                    {
                        _1644 = float3(0.0f, 0.0f, 1.0f);
                    }
                    else
                    {
                        float3 _1645;
                        if (_1440 < 0.66600000858306884765625f)
                        {
                            _1645 = float3(0.0f, 1.0f, 0.0f);
                        }
                        else
                        {
                            _1645 = float3(1.0f, 0.0f, 0.0f);
                        }
                        _1644 = _1645;
                    }
                    _1640 = _1644;
                }
                else
                {
                    float3 _1641;
                    if (mask_profile.x == 17.0f)
                    {
                        float2 _1463 = floor(_833 * float2(1.0f, 0.5f));
                        float _1474 = frac((_1463.x + (_1463.y * 3.0f)) * 0.16666667163372039794921875f);
                        float3 _1642;
                        if (_1474 < 0.333000004291534423828125f)
                        {
                            _1642 = float3(0.0f, 0.0f, 1.0f);
                        }
                        else
                        {
                            float3 _1643;
                            if (_1474 < 0.66600000858306884765625f)
                            {
                                _1643 = float3(0.0f, 1.0f, 0.0f);
                            }
                            else
                            {
                                _1643 = float3(1.0f, 0.0f, 0.0f);
                            }
                            _1642 = _1643;
                        }
                        _1641 = _1642;
                    }
                    else
                    {
                        _1641 = 0.0f.xxx;
                    }
                    _1640 = _1641;
                }
                _1639 = _1640;
            }
            _1506 = _1639;
            break;
        }
        float _1128 = _833.x;
        float3 _1131 = floor(mod(_1128, 2.0f)).xxx;
        float3 _1132 = lerp(float3(1.0f, 0.0f, 1.0f), float3(0.0f, 1.0f, 0.0f), _1131);
        if (mask_profile.x == 0.0f)
        {
            _1506 = 1.0f.xxx;
            break;
        }
        else
        {
            if (mask_profile.x == 1.0f)
            {
                _1506 = _1132;
                break;
            }
            else
            {
                if (mask_profile.x == 2.0f)
                {
                    _1506 = _281[int(floor(mod(_1128, 3.0f)))];
                    break;
                }
                else
                {
                    if (mask_profile.x == 3.0f)
                    {
                        _1506 = _299[int(floor(mod(_1128, 3.0f)))];
                        break;
                    }
                    else
                    {
                        if (mask_profile.x == 4.0f)
                        {
                            _1506 = _322[int(floor(mod(_1128, 4.0f)))];
                            break;
                        }
                        else
                        {
                            if (mask_profile.x == 5.0f)
                            {
                                _1506 = _341[int(floor(mod(_1128, 4.0f)))];
                                break;
                            }
                            else
                            {
                                if (mask_profile.x == 6.0f)
                                {
                                    _1506 = _359[int(floor(mod(_1128, 4.0f)))];
                                    break;
                                }
                                else
                                {
                                    if (mask_profile.x == 7.0f)
                                    {
                                        _1506 = lerp(_1132, lerp(float3(0.0f, 1.0f, 0.0f), float3(1.0f, 0.0f, 1.0f), _1131), floor(mod(_833.y, 2.0f)).xxx);
                                        break;
                                    }
                                    else
                                    {
                                        if (mask_profile.x == 8.0f)
                                        {
                                            _1506 = _407[int(floor(mod(_833.y, 2.0f)))][int(floor(mod(_1128, 4.0f)))];
                                            break;
                                        }
                                        else
                                        {
                                            if (mask_profile.x == 9.0f)
                                            {
                                                _1506 = _433[int(floor(mod(_833.y, 2.0f)))][int(floor(mod(_1128, 4.0f)))];
                                                break;
                                            }
                                            else
                                            {
                                                if (mask_profile.x == 10.0f)
                                                {
                                                    _1506 = _458[int(floor(mod(_833.y, 4.0f)))][int(floor(mod(_1128, 4.0f)))];
                                                    break;
                                                }
                                                else
                                                {
                                                    if (mask_profile.x == 11.0f)
                                                    {
                                                        _1506 = _489[int(floor(mod(_833.y, 4.0f)))][int(floor(mod(_1128, 6.0f)))];
                                                        break;
                                                    }
                                                    else
                                                    {
                                                        if (mask_profile.x == 12.0f)
                                                        {
                                                            _1506 = _517[int(floor(mod(_833.y, 4.0f)))][int(floor(mod(_1128, 6.0f)))];
                                                            break;
                                                        }
                                                        else
                                                        {
                                                            if (mask_profile.x == 13.0f)
                                                            {
                                                                _1506 = _547[int(floor(mod(_833.y, 4.0f)))][int(floor(mod(_1128, 8.0f)))];
                                                                break;
                                                            }
                                                            else
                                                            {
                                                                if (mask_profile.x == 14.0f)
                                                                {
                                                                    _1506 = _577[int(floor(mod(_833.y, 4.0f)))][int(floor(mod(_1128, 10.0f)))];
                                                                    break;
                                                                }
                                                                else
                                                                {
                                                                    _1506 = 1.0f.xxx;
                                                                    break;
                                                                }
                                                                break; // unreachable workaround
                                                            }
                                                            break; // unreachable workaround
                                                        }
                                                        break; // unreachable workaround
                                                    }
                                                    break; // unreachable workaround
                                                }
                                                break; // unreachable workaround
                                            }
                                            break; // unreachable workaround
                                        }
                                        break; // unreachable workaround
                                    }
                                    break; // unreachable workaround
                                }
                                break; // unreachable workaround
                            }
                            break; // unreachable workaround
                        }
                        break; // unreachable workaround
                    }
                    break; // unreachable workaround
                }
                break; // unreachable workaround
            }
            break; // unreachable workaround
        }
        break; // unreachable workaround
    } while(false);
    float3 _1507;
    if (params_MONITOR_SUBPIXELS > 0.5f)
    {
        _1507 = _1506.zyx;
    }
    else
    {
        _1507 = _1506;
    }
    FragColor = float4((_1507 + ((1.0f.xxx - (_1507 * 2.0f)) * pow(abs(_1507 - pow(clamp((CRTPass.Sample(_CRTPass_sampler, _1495).xyz * params_BRIGHTBOOST) + (_1500 * params_GLOW_STRENGTH), 0.0f.xxx, 1.0f.xxx), (1.0f / params_H_OUTPUT_GAMMA).xxx)), ((_1507 * params_MASK_STRENGTH) * (params_H_MaskGamma - 1.0f)) + 1.0f.xxx))) * _1498, 1.0f);
}

SPIRV_Cross_Output main(SPIRV_Cross_Input stage_input)
{
    vTexCoord = stage_input.vTexCoord;
    mask_profile = stage_input.mask_profile;
    frag_main();
    SPIRV_Cross_Output stage_output;
    stage_output.FragColor = FragColor;
    return stage_output;
}
