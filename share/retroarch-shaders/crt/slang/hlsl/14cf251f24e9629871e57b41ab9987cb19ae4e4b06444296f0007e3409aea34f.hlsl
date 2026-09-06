// Generated from crt/shaders/crt-lottes-multipass/scanpass.slang. See slang/upstream for licence/source.
cbuffer UBO : register(b0)
{
    float4 global_OutputSize : packoffset(c4);
    float4 global_SourceSize : packoffset(c6);
};

cbuffer Push : register(b1)
{
    float param_hardScan : packoffset(c0);
    float param_hardPix : packoffset(c0.y);
    float param_warpX : packoffset(c0.z);
    float param_warpY : packoffset(c0.w);
    float param_maskDark : packoffset(c1);
    float param_maskLight : packoffset(c1.y);
    float param_scaleInLinearGamma : packoffset(c1.z);
    float param_shadowMask : packoffset(c1.w);
    float param_brightBoost : packoffset(c2);
    float param_bloomAmount : packoffset(c2.w);
    float param_shape : packoffset(c3);
};

Texture2D<float4> Reference : register(t4);
SamplerState _Reference_sampler : register(s4);
Texture2D<float4> BloomPass : register(t3);
SamplerState _BloomPass_sampler : register(s3);

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
    bool _949;
    float2 _776 = (vTexCoord * 2.0f) - 1.0f.xx;
    float _778 = _776.y;
    float _787 = _776.x;
    float2 _801 = ((_776 * float2(1.0f + ((_778 * _778) * param_warpX), 1.0f + ((_787 * _787) * param_warpY))) * 0.5f) + 0.5f.xx;
    float2 _922 = _801 * global_SourceSize.xy;
    float4 _935 = Reference.Sample(_Reference_sampler, (floor(_922 + (-1.0f).xx) + 0.5f.xx) / global_SourceSize.xy);
    float3 _937 = _935.xyz * param_brightBoost;
    float3 _3056;
    do
    {
        _949 = param_scaleInLinearGamma == 0.0f;
        if (_949)
        {
            _3056 = _937;
            break;
        }
        float _954 = _937.x;
        float _3051;
        do
        {
            if (_949)
            {
                _3051 = _954;
                break;
            }
            float _3050;
            if (_954 <= 0.040449999272823333740234375f)
            {
                _3050 = _954 * 0.077399380505084991455078125f;
            }
            else
            {
                _3050 = pow((_954 + 0.054999999701976776123046875f) * 0.947867333889007568359375f, 2.400000095367431640625f);
            }
            _3051 = _3050;
            break;
        } while(false);
        float _957 = _937.y;
        float _3053;
        do
        {
            if (_949)
            {
                _3053 = _957;
                break;
            }
            float _3052;
            if (_957 <= 0.040449999272823333740234375f)
            {
                _3052 = _957 * 0.077399380505084991455078125f;
            }
            else
            {
                _3052 = pow((_957 + 0.054999999701976776123046875f) * 0.947867333889007568359375f, 2.400000095367431640625f);
            }
            _3053 = _3052;
            break;
        } while(false);
        float _960 = _937.z;
        float _3055;
        do
        {
            if (_949)
            {
                _3055 = _960;
                break;
            }
            float _3054;
            if (_960 <= 0.040449999272823333740234375f)
            {
                _3054 = _960 * 0.077399380505084991455078125f;
            }
            else
            {
                _3054 = pow((_960 + 0.054999999701976776123046875f) * 0.947867333889007568359375f, 2.400000095367431640625f);
            }
            _3055 = _3054;
            break;
        } while(false);
        _3056 = float3(_3051, _3053, _3055);
        break;
    } while(false);
    float4 _1063 = Reference.Sample(_Reference_sampler, (floor(_922 + float2(0.0f, -1.0f)) + 0.5f.xx) / global_SourceSize.xy);
    float3 _1065 = _1063.xyz * param_brightBoost;
    float3 _3077;
    do
    {
        if (_949)
        {
            _3077 = _1065;
            break;
        }
        float _1082 = _1065.x;
        float _3072;
        do
        {
            if (_949)
            {
                _3072 = _1082;
                break;
            }
            float _3071;
            if (_1082 <= 0.040449999272823333740234375f)
            {
                _3071 = _1082 * 0.077399380505084991455078125f;
            }
            else
            {
                _3071 = pow((_1082 + 0.054999999701976776123046875f) * 0.947867333889007568359375f, 2.400000095367431640625f);
            }
            _3072 = _3071;
            break;
        } while(false);
        float _1085 = _1065.y;
        float _3074;
        do
        {
            if (_949)
            {
                _3074 = _1085;
                break;
            }
            float _3073;
            if (_1085 <= 0.040449999272823333740234375f)
            {
                _3073 = _1085 * 0.077399380505084991455078125f;
            }
            else
            {
                _3073 = pow((_1085 + 0.054999999701976776123046875f) * 0.947867333889007568359375f, 2.400000095367431640625f);
            }
            _3074 = _3073;
            break;
        } while(false);
        float _1088 = _1065.z;
        float _3076;
        do
        {
            if (_949)
            {
                _3076 = _1088;
                break;
            }
            float _3075;
            if (_1088 <= 0.040449999272823333740234375f)
            {
                _3075 = _1088 * 0.077399380505084991455078125f;
            }
            else
            {
                _3075 = pow((_1088 + 0.054999999701976776123046875f) * 0.947867333889007568359375f, 2.400000095367431640625f);
            }
            _3076 = _3075;
            break;
        } while(false);
        _3077 = float3(_3072, _3074, _3076);
        break;
    } while(false);
    float4 _1191 = Reference.Sample(_Reference_sampler, (floor(_922 + float2(1.0f, -1.0f)) + 0.5f.xx) / global_SourceSize.xy);
    float3 _1193 = _1191.xyz * param_brightBoost;
    float3 _3098;
    do
    {
        if (_949)
        {
            _3098 = _1193;
            break;
        }
        float _1210 = _1193.x;
        float _3093;
        do
        {
            if (_949)
            {
                _3093 = _1210;
                break;
            }
            float _3092;
            if (_1210 <= 0.040449999272823333740234375f)
            {
                _3092 = _1210 * 0.077399380505084991455078125f;
            }
            else
            {
                _3092 = pow((_1210 + 0.054999999701976776123046875f) * 0.947867333889007568359375f, 2.400000095367431640625f);
            }
            _3093 = _3092;
            break;
        } while(false);
        float _1213 = _1193.y;
        float _3095;
        do
        {
            if (_949)
            {
                _3095 = _1213;
                break;
            }
            float _3094;
            if (_1213 <= 0.040449999272823333740234375f)
            {
                _3094 = _1213 * 0.077399380505084991455078125f;
            }
            else
            {
                _3094 = pow((_1213 + 0.054999999701976776123046875f) * 0.947867333889007568359375f, 2.400000095367431640625f);
            }
            _3095 = _3094;
            break;
        } while(false);
        float _1216 = _1193.z;
        float _3097;
        do
        {
            if (_949)
            {
                _3097 = _1216;
                break;
            }
            float _3096;
            if (_1216 <= 0.040449999272823333740234375f)
            {
                _3096 = _1216 * 0.077399380505084991455078125f;
            }
            else
            {
                _3096 = pow((_1216 + 0.054999999701976776123046875f) * 0.947867333889007568359375f, 2.400000095367431640625f);
            }
            _3097 = _3096;
            break;
        } while(false);
        _3098 = float3(_3093, _3095, _3097);
        break;
    } while(false);
    float2 _1308 = floor(_922);
    float2 _1311 = 0.5f.xx - (_922 - _1308);
    float _882 = _1311.x;
    float _1321 = exp2(param_hardPix * pow(abs(_882 - 1.0f), param_shape));
    float _1331 = exp2(param_hardPix * pow(abs(_882), param_shape));
    float _1341 = exp2(param_hardPix * pow(abs(_882 + 1.0f), param_shape));
    float3 _913 = ((_1321 + _1331) + _1341).xxx;
    float4 _1472 = Reference.Sample(_Reference_sampler, (floor(_922 + float2(-2.0f, 0.0f)) + 0.5f.xx) / global_SourceSize.xy);
    float3 _1474 = _1472.xyz * param_brightBoost;
    float3 _3154;
    do
    {
        if (_949)
        {
            _3154 = _1474;
            break;
        }
        float _1491 = _1474.x;
        float _3149;
        do
        {
            if (_949)
            {
                _3149 = _1491;
                break;
            }
            float _3148;
            if (_1491 <= 0.040449999272823333740234375f)
            {
                _3148 = _1491 * 0.077399380505084991455078125f;
            }
            else
            {
                _3148 = pow((_1491 + 0.054999999701976776123046875f) * 0.947867333889007568359375f, 2.400000095367431640625f);
            }
            _3149 = _3148;
            break;
        } while(false);
        float _1494 = _1474.y;
        float _3151;
        do
        {
            if (_949)
            {
                _3151 = _1494;
                break;
            }
            float _3150;
            if (_1494 <= 0.040449999272823333740234375f)
            {
                _3150 = _1494 * 0.077399380505084991455078125f;
            }
            else
            {
                _3150 = pow((_1494 + 0.054999999701976776123046875f) * 0.947867333889007568359375f, 2.400000095367431640625f);
            }
            _3151 = _3150;
            break;
        } while(false);
        float _1497 = _1474.z;
        float _3153;
        do
        {
            if (_949)
            {
                _3153 = _1497;
                break;
            }
            float _3152;
            if (_1497 <= 0.040449999272823333740234375f)
            {
                _3152 = _1497 * 0.077399380505084991455078125f;
            }
            else
            {
                _3152 = pow((_1497 + 0.054999999701976776123046875f) * 0.947867333889007568359375f, 2.400000095367431640625f);
            }
            _3153 = _3152;
            break;
        } while(false);
        _3154 = float3(_3149, _3151, _3153);
        break;
    } while(false);
    float4 _1600 = Reference.Sample(_Reference_sampler, (floor(_922 + float2(-1.0f, 0.0f)) + 0.5f.xx) / global_SourceSize.xy);
    float3 _1602 = _1600.xyz * param_brightBoost;
    float3 _3175;
    do
    {
        if (_949)
        {
            _3175 = _1602;
            break;
        }
        float _1619 = _1602.x;
        float _3170;
        do
        {
            if (_949)
            {
                _3170 = _1619;
                break;
            }
            float _3169;
            if (_1619 <= 0.040449999272823333740234375f)
            {
                _3169 = _1619 * 0.077399380505084991455078125f;
            }
            else
            {
                _3169 = pow((_1619 + 0.054999999701976776123046875f) * 0.947867333889007568359375f, 2.400000095367431640625f);
            }
            _3170 = _3169;
            break;
        } while(false);
        float _1622 = _1602.y;
        float _3172;
        do
        {
            if (_949)
            {
                _3172 = _1622;
                break;
            }
            float _3171;
            if (_1622 <= 0.040449999272823333740234375f)
            {
                _3171 = _1622 * 0.077399380505084991455078125f;
            }
            else
            {
                _3171 = pow((_1622 + 0.054999999701976776123046875f) * 0.947867333889007568359375f, 2.400000095367431640625f);
            }
            _3172 = _3171;
            break;
        } while(false);
        float _1625 = _1602.z;
        float _3174;
        do
        {
            if (_949)
            {
                _3174 = _1625;
                break;
            }
            float _3173;
            if (_1625 <= 0.040449999272823333740234375f)
            {
                _3173 = _1625 * 0.077399380505084991455078125f;
            }
            else
            {
                _3173 = pow((_1625 + 0.054999999701976776123046875f) * 0.947867333889007568359375f, 2.400000095367431640625f);
            }
            _3174 = _3173;
            break;
        } while(false);
        _3175 = float3(_3170, _3172, _3174);
        break;
    } while(false);
    float4 _1728 = Reference.Sample(_Reference_sampler, (_1308 + 0.5f.xx) / global_SourceSize.xy);
    float3 _1730 = _1728.xyz * param_brightBoost;
    float3 _3196;
    do
    {
        if (_949)
        {
            _3196 = _1730;
            break;
        }
        float _1747 = _1730.x;
        float _3191;
        do
        {
            if (_949)
            {
                _3191 = _1747;
                break;
            }
            float _3190;
            if (_1747 <= 0.040449999272823333740234375f)
            {
                _3190 = _1747 * 0.077399380505084991455078125f;
            }
            else
            {
                _3190 = pow((_1747 + 0.054999999701976776123046875f) * 0.947867333889007568359375f, 2.400000095367431640625f);
            }
            _3191 = _3190;
            break;
        } while(false);
        float _1750 = _1730.y;
        float _3193;
        do
        {
            if (_949)
            {
                _3193 = _1750;
                break;
            }
            float _3192;
            if (_1750 <= 0.040449999272823333740234375f)
            {
                _3192 = _1750 * 0.077399380505084991455078125f;
            }
            else
            {
                _3192 = pow((_1750 + 0.054999999701976776123046875f) * 0.947867333889007568359375f, 2.400000095367431640625f);
            }
            _3193 = _3192;
            break;
        } while(false);
        float _1753 = _1730.z;
        float _3195;
        do
        {
            if (_949)
            {
                _3195 = _1753;
                break;
            }
            float _3194;
            if (_1753 <= 0.040449999272823333740234375f)
            {
                _3194 = _1753 * 0.077399380505084991455078125f;
            }
            else
            {
                _3194 = pow((_1753 + 0.054999999701976776123046875f) * 0.947867333889007568359375f, 2.400000095367431640625f);
            }
            _3195 = _3194;
            break;
        } while(false);
        _3196 = float3(_3191, _3193, _3195);
        break;
    } while(false);
    float4 _1856 = Reference.Sample(_Reference_sampler, (floor(_922 + float2(1.0f, 0.0f)) + 0.5f.xx) / global_SourceSize.xy);
    float3 _1858 = _1856.xyz * param_brightBoost;
    float3 _3217;
    do
    {
        if (_949)
        {
            _3217 = _1858;
            break;
        }
        float _1875 = _1858.x;
        float _3212;
        do
        {
            if (_949)
            {
                _3212 = _1875;
                break;
            }
            float _3211;
            if (_1875 <= 0.040449999272823333740234375f)
            {
                _3211 = _1875 * 0.077399380505084991455078125f;
            }
            else
            {
                _3211 = pow((_1875 + 0.054999999701976776123046875f) * 0.947867333889007568359375f, 2.400000095367431640625f);
            }
            _3212 = _3211;
            break;
        } while(false);
        float _1878 = _1858.y;
        float _3214;
        do
        {
            if (_949)
            {
                _3214 = _1878;
                break;
            }
            float _3213;
            if (_1878 <= 0.040449999272823333740234375f)
            {
                _3213 = _1878 * 0.077399380505084991455078125f;
            }
            else
            {
                _3213 = pow((_1878 + 0.054999999701976776123046875f) * 0.947867333889007568359375f, 2.400000095367431640625f);
            }
            _3214 = _3213;
            break;
        } while(false);
        float _1881 = _1858.z;
        float _3216;
        do
        {
            if (_949)
            {
                _3216 = _1881;
                break;
            }
            float _3215;
            if (_1881 <= 0.040449999272823333740234375f)
            {
                _3215 = _1881 * 0.077399380505084991455078125f;
            }
            else
            {
                _3215 = pow((_1881 + 0.054999999701976776123046875f) * 0.947867333889007568359375f, 2.400000095367431640625f);
            }
            _3216 = _3215;
            break;
        } while(false);
        _3217 = float3(_3212, _3214, _3216);
        break;
    } while(false);
    float4 _1984 = Reference.Sample(_Reference_sampler, (floor(_922 + float2(2.0f, 0.0f)) + 0.5f.xx) / global_SourceSize.xy);
    float3 _1986 = _1984.xyz * param_brightBoost;
    float3 _3238;
    do
    {
        if (_949)
        {
            _3238 = _1986;
            break;
        }
        float _2003 = _1986.x;
        float _3233;
        do
        {
            if (_949)
            {
                _3233 = _2003;
                break;
            }
            float _3232;
            if (_2003 <= 0.040449999272823333740234375f)
            {
                _3232 = _2003 * 0.077399380505084991455078125f;
            }
            else
            {
                _3232 = pow((_2003 + 0.054999999701976776123046875f) * 0.947867333889007568359375f, 2.400000095367431640625f);
            }
            _3233 = _3232;
            break;
        } while(false);
        float _2006 = _1986.y;
        float _3235;
        do
        {
            if (_949)
            {
                _3235 = _2006;
                break;
            }
            float _3234;
            if (_2006 <= 0.040449999272823333740234375f)
            {
                _3234 = _2006 * 0.077399380505084991455078125f;
            }
            else
            {
                _3234 = pow((_2006 + 0.054999999701976776123046875f) * 0.947867333889007568359375f, 2.400000095367431640625f);
            }
            _3235 = _3234;
            break;
        } while(false);
        float _2009 = _1986.z;
        float _3237;
        do
        {
            if (_949)
            {
                _3237 = _2009;
                break;
            }
            float _3236;
            if (_2009 <= 0.040449999272823333740234375f)
            {
                _3236 = _2009 * 0.077399380505084991455078125f;
            }
            else
            {
                _3236 = pow((_2009 + 0.054999999701976776123046875f) * 0.947867333889007568359375f, 2.400000095367431640625f);
            }
            _3237 = _3236;
            break;
        } while(false);
        _3238 = float3(_3233, _3235, _3237);
        break;
    } while(false);
    float _2114 = exp2(param_hardPix * pow(abs(_882 - 2.0f), param_shape));
    float _2154 = exp2(param_hardPix * pow(abs(_882 + 2.0f), param_shape));
    float4 _2245 = Reference.Sample(_Reference_sampler, (floor(_922 + float2(-1.0f, 1.0f)) + 0.5f.xx) / global_SourceSize.xy);
    float3 _2247 = _2245.xyz * param_brightBoost;
    float3 _3357;
    do
    {
        if (_949)
        {
            _3357 = _2247;
            break;
        }
        float _2264 = _2247.x;
        float _3352;
        do
        {
            if (_949)
            {
                _3352 = _2264;
                break;
            }
            float _3351;
            if (_2264 <= 0.040449999272823333740234375f)
            {
                _3351 = _2264 * 0.077399380505084991455078125f;
            }
            else
            {
                _3351 = pow((_2264 + 0.054999999701976776123046875f) * 0.947867333889007568359375f, 2.400000095367431640625f);
            }
            _3352 = _3351;
            break;
        } while(false);
        float _2267 = _2247.y;
        float _3354;
        do
        {
            if (_949)
            {
                _3354 = _2267;
                break;
            }
            float _3353;
            if (_2267 <= 0.040449999272823333740234375f)
            {
                _3353 = _2267 * 0.077399380505084991455078125f;
            }
            else
            {
                _3353 = pow((_2267 + 0.054999999701976776123046875f) * 0.947867333889007568359375f, 2.400000095367431640625f);
            }
            _3354 = _3353;
            break;
        } while(false);
        float _2270 = _2247.z;
        float _3356;
        do
        {
            if (_949)
            {
                _3356 = _2270;
                break;
            }
            float _3355;
            if (_2270 <= 0.040449999272823333740234375f)
            {
                _3355 = _2270 * 0.077399380505084991455078125f;
            }
            else
            {
                _3355 = pow((_2270 + 0.054999999701976776123046875f) * 0.947867333889007568359375f, 2.400000095367431640625f);
            }
            _3356 = _3355;
            break;
        } while(false);
        _3357 = float3(_3352, _3354, _3356);
        break;
    } while(false);
    float4 _2373 = Reference.Sample(_Reference_sampler, (floor(_922 + float2(0.0f, 1.0f)) + 0.5f.xx) / global_SourceSize.xy);
    float3 _2375 = _2373.xyz * param_brightBoost;
    float3 _3378;
    do
    {
        if (_949)
        {
            _3378 = _2375;
            break;
        }
        float _2392 = _2375.x;
        float _3373;
        do
        {
            if (_949)
            {
                _3373 = _2392;
                break;
            }
            float _3372;
            if (_2392 <= 0.040449999272823333740234375f)
            {
                _3372 = _2392 * 0.077399380505084991455078125f;
            }
            else
            {
                _3372 = pow((_2392 + 0.054999999701976776123046875f) * 0.947867333889007568359375f, 2.400000095367431640625f);
            }
            _3373 = _3372;
            break;
        } while(false);
        float _2395 = _2375.y;
        float _3375;
        do
        {
            if (_949)
            {
                _3375 = _2395;
                break;
            }
            float _3374;
            if (_2395 <= 0.040449999272823333740234375f)
            {
                _3374 = _2395 * 0.077399380505084991455078125f;
            }
            else
            {
                _3374 = pow((_2395 + 0.054999999701976776123046875f) * 0.947867333889007568359375f, 2.400000095367431640625f);
            }
            _3375 = _3374;
            break;
        } while(false);
        float _2398 = _2375.z;
        float _3377;
        do
        {
            if (_949)
            {
                _3377 = _2398;
                break;
            }
            float _3376;
            if (_2398 <= 0.040449999272823333740234375f)
            {
                _3376 = _2398 * 0.077399380505084991455078125f;
            }
            else
            {
                _3376 = pow((_2398 + 0.054999999701976776123046875f) * 0.947867333889007568359375f, 2.400000095367431640625f);
            }
            _3377 = _3376;
            break;
        } while(false);
        _3378 = float3(_3373, _3375, _3377);
        break;
    } while(false);
    float4 _2501 = Reference.Sample(_Reference_sampler, (floor(_922 + 1.0f.xx) + 0.5f.xx) / global_SourceSize.xy);
    float3 _2503 = _2501.xyz * param_brightBoost;
    float3 _3399;
    do
    {
        if (_949)
        {
            _3399 = _2503;
            break;
        }
        float _2520 = _2503.x;
        float _3394;
        do
        {
            if (_949)
            {
                _3394 = _2520;
                break;
            }
            float _3393;
            if (_2520 <= 0.040449999272823333740234375f)
            {
                _3393 = _2520 * 0.077399380505084991455078125f;
            }
            else
            {
                _3393 = pow((_2520 + 0.054999999701976776123046875f) * 0.947867333889007568359375f, 2.400000095367431640625f);
            }
            _3394 = _3393;
            break;
        } while(false);
        float _2523 = _2503.y;
        float _3396;
        do
        {
            if (_949)
            {
                _3396 = _2523;
                break;
            }
            float _3395;
            if (_2523 <= 0.040449999272823333740234375f)
            {
                _3395 = _2523 * 0.077399380505084991455078125f;
            }
            else
            {
                _3395 = pow((_2523 + 0.054999999701976776123046875f) * 0.947867333889007568359375f, 2.400000095367431640625f);
            }
            _3396 = _3395;
            break;
        } while(false);
        float _2526 = _2503.z;
        float _3398;
        do
        {
            if (_949)
            {
                _3398 = _2526;
                break;
            }
            float _3397;
            if (_2526 <= 0.040449999272823333740234375f)
            {
                _3397 = _2526 * 0.077399380505084991455078125f;
            }
            else
            {
                _3397 = pow((_2526 + 0.054999999701976776123046875f) * 0.947867333889007568359375f, 2.400000095367431640625f);
            }
            _3398 = _3397;
            break;
        } while(false);
        _3399 = float3(_3394, _3396, _3398);
        break;
    } while(false);
    float _2660 = _1311.y;
    float3 _844 = ((((((_3056 * _1321) + (_3077 * _1331)) + (_3098 * _1341)) / _913) * exp2(param_hardScan * pow(abs(_2660 + (-1.0f)), param_shape))) + (((((((_3154 * _2114) + (_3175 * _1321)) + (_3196 * _1331)) + (_3217 * _1341)) + (_3238 * _2154)) / ((((_2114 + _1321) + _1331) + _1341) + _2154).xxx) * exp2(param_hardScan * pow(abs(_2660), param_shape)))) + (((((_3357 * _1321) + (_3378 * _1331)) + (_3399 * _1341)) / _913) * exp2(param_hardScan * pow(abs(_2660 + 1.0f), param_shape)));
    float3 _3637;
    if (param_shadowMask > 0.0f)
    {
        float2 _720 = (vTexCoord / global_OutputSize.zw) * 1.00000095367431640625f;
        float3 _2777 = param_maskDark.xxx;
        float3 _3760;
        if (param_shadowMask == 1.0f)
        {
            float _2785 = _720.x;
            float _3528;
            if (frac((_720.y + float(frac(_2785 * 0.16666667163372039794921875f) < 0.5f)) * 0.5f) < 0.5f)
            {
                _3528 = param_maskDark;
            }
            else
            {
                _3528 = param_maskLight;
            }
            float _2805 = frac(_2785 * 0.3333333432674407958984375f);
            float3 _3758;
            if (_2805 < 0.333000004291534423828125f)
            {
                float3 _3703 = _2777;
                _3703.x = param_maskLight;
                _3758 = _3703;
            }
            else
            {
                float3 _3759;
                if (_2805 < 0.66600000858306884765625f)
                {
                    float3 _3706 = _2777;
                    _3706.y = param_maskLight;
                    _3759 = _3706;
                }
                else
                {
                    float3 _3708 = _2777;
                    _3708.z = param_maskLight;
                    _3759 = _3708;
                }
                _3758 = _3759;
            }
            _3760 = _3758 * _3528;
        }
        else
        {
            float3 _3761;
            if (param_shadowMask == 2.0f)
            {
                float _2839 = frac(_720.x * 0.3333333432674407958984375f);
                float3 _3762;
                if (_2839 < 0.333000004291534423828125f)
                {
                    float3 _3714 = _2777;
                    _3714.x = param_maskLight;
                    _3762 = _3714;
                }
                else
                {
                    float3 _3763;
                    if (_2839 < 0.66600000858306884765625f)
                    {
                        float3 _3717 = _2777;
                        _3717.y = param_maskLight;
                        _3763 = _3717;
                    }
                    else
                    {
                        float3 _3719 = _2777;
                        _3719.z = param_maskLight;
                        _3763 = _3719;
                    }
                    _3762 = _3763;
                }
                _3761 = _3762;
            }
            else
            {
                float3 _3764;
                if (param_shadowMask == 3.0f)
                {
                    float _2877 = frac((_720.x + (_720.y * 3.0f)) * 0.16666667163372039794921875f);
                    float3 _3765;
                    if (_2877 < 0.333000004291534423828125f)
                    {
                        float3 _3729 = _2777;
                        _3729.x = param_maskLight;
                        _3765 = _3729;
                    }
                    else
                    {
                        float3 _3766;
                        if (_2877 < 0.66600000858306884765625f)
                        {
                            float3 _3732 = _2777;
                            _3732.y = param_maskLight;
                            _3766 = _3732;
                        }
                        else
                        {
                            float3 _3734 = _2777;
                            _3734.z = param_maskLight;
                            _3766 = _3734;
                        }
                        _3765 = _3766;
                    }
                    _3764 = _3765;
                }
                else
                {
                    float3 _3767;
                    if (param_shadowMask == 4.0f)
                    {
                        float2 _2907 = floor(_720 * float2(1.0f, 0.5f));
                        float _2918 = frac((_2907.x + (_2907.y * 3.0f)) * 0.16666667163372039794921875f);
                        float3 _3768;
                        if (_2918 < 0.333000004291534423828125f)
                        {
                            float3 _3744 = _2777;
                            _3744.x = param_maskLight;
                            _3768 = _3744;
                        }
                        else
                        {
                            float3 _3769;
                            if (_2918 < 0.66600000858306884765625f)
                            {
                                float3 _3747 = _2777;
                                _3747.y = param_maskLight;
                                _3769 = _3747;
                            }
                            else
                            {
                                float3 _3749 = _2777;
                                _3749.z = param_maskLight;
                                _3769 = _3749;
                            }
                            _3768 = _3769;
                        }
                        _3767 = _3768;
                    }
                    else
                    {
                        _3767 = _2777;
                    }
                    _3764 = _3767;
                }
                _3761 = _3764;
            }
            _3760 = _3761;
        }
        _3637 = _844 * _3760;
    }
    else
    {
        _3637 = _844;
    }
    float4 _729 = BloomPass.Sample(_BloomPass_sampler, _801);
    float3 _737 = _3637 + lerp(0.0f.xxx, _729.xyz, param_bloomAmount.xxx);
    float3 _3644;
    do
    {
        if (_949)
        {
            _3644 = _737;
            break;
        }
        float _2961 = _737.x;
        float _3639;
        do
        {
            if (_949)
            {
                _3639 = _2961;
                break;
            }
            float _3638;
            if (_2961 < 0.003130800090730190277099609375f)
            {
                _3638 = _2961 * 12.9200000762939453125f;
            }
            else
            {
                _3638 = (1.05499994754791259765625f * pow(_2961, 0.416660010814666748046875f)) - 0.054999999701976776123046875f;
            }
            _3639 = _3638;
            break;
        } while(false);
        float _2964 = _737.y;
        float _3641;
        do
        {
            if (_949)
            {
                _3641 = _2964;
                break;
            }
            float _3640;
            if (_2964 < 0.003130800090730190277099609375f)
            {
                _3640 = _2964 * 12.9200000762939453125f;
            }
            else
            {
                _3640 = (1.05499994754791259765625f * pow(_2964, 0.416660010814666748046875f)) - 0.054999999701976776123046875f;
            }
            _3641 = _3640;
            break;
        } while(false);
        float _2967 = _737.z;
        float _3643;
        do
        {
            if (_949)
            {
                _3643 = _2967;
                break;
            }
            float _3642;
            if (_2967 < 0.003130800090730190277099609375f)
            {
                _3642 = _2967 * 12.9200000762939453125f;
            }
            else
            {
                _3642 = (1.05499994754791259765625f * pow(_2967, 0.416660010814666748046875f)) - 0.054999999701976776123046875f;
            }
            _3643 = _3642;
            break;
        } while(false);
        _3644 = float3(_3639, _3641, _3643);
        break;
    } while(false);
    FragColor = float4(_3644, 1.0f);
}

SPIRV_Cross_Output main(SPIRV_Cross_Input stage_input)
{
    vTexCoord = stage_input.vTexCoord;
    frag_main();
    SPIRV_Cross_Output stage_output;
    stage_output.FragColor = FragColor;
    return stage_output;
}
