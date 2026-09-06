// Generated from crt/shaders/tvout-tweaks.slang. See slang/upstream for licence/source.
cbuffer Push : register(b1)
{
    float4 params_SourceSize : packoffset(c0);
    float params_TVOUT_RESOLUTION : packoffset(c3.y);
    float params_TVOUT_COMPOSITE_CONNECTION : packoffset(c3.z);
    float params_TVOUT_TV_COLOR_LEVELS : packoffset(c3.w);
    float params_TVOUT_RESOLUTION_Y : packoffset(c4);
    float params_TVOUT_RESOLUTION_I : packoffset(c4.y);
    float params_TVOUT_RESOLUTION_Q : packoffset(c4.z);
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
    float _120 = frac((vTexCoord.x * params_SourceSize.x) - 0.5f);
    float _130 = _120 - (-1.0f);
    bool _133 = params_TVOUT_COMPOSITE_CONNECTION > 0.5f;
    float3 _2198;
    if (_133)
    {
        float4 _151 = Source.Sample(_Source_sampler, float2(vTexCoord.x - (_130 * params_SourceSize.z), vTexCoord.y));
        float3 _153 = _151.xyz;
        float3 _2042;
        do
        {
            if (params_TVOUT_TV_COLOR_LEVELS > 0.5f)
            {
                if (_133)
                {
                    _2042 = float3(clamp((_151.x - 0.064453125f) * 1.16363632678985595703125f, 0.0f, 1.0f), clamp((_151.y - 0.064453125f) * 1.14285719394683837890625f, 0.0f, 1.0f), clamp((_151.z - 0.064453125f) * 1.14285719394683837890625f, 0.0f, 1.0f));
                    break;
                }
                else
                {
                    _2042 = clamp(((_153 - 0.064453125f.xxx) * 256.0f) * 0.0045454544015228748321533203125f.xxx, 0.0f.xxx, 1.0f.xxx);
                    break;
                }
                break; // unreachable workaround
            }
            else
            {
                _2042 = _153;
                break;
            }
            break; // unreachable workaround
        } while(false);
        _2198 = mul(float3x3(float3(0.2989999949932098388671875f, 0.58700001239776611328125f, 0.114000000059604644775390625f), float3(0.595715999603271484375f, -0.2744530141353607177734375f, -0.3212629854679107666015625f), float3(0.211456000804901123046875f, -0.52259099483489990234375f, 0.311134994029998779296875f)), _2042);
    }
    else
    {
        float4 _168 = Source.Sample(_Source_sampler, float2(vTexCoord.x - (_130 * params_SourceSize.z), vTexCoord.y));
        float3 _170 = _168.xyz;
        float3 _2041;
        do
        {
            if (params_TVOUT_TV_COLOR_LEVELS > 0.5f)
            {
                if (_133)
                {
                    _2041 = float3(clamp((_168.x - 0.064453125f) * 1.16363632678985595703125f, 0.0f, 1.0f), clamp((_168.y - 0.064453125f) * 1.14285719394683837890625f, 0.0f, 1.0f), clamp((_168.z - 0.064453125f) * 1.14285719394683837890625f, 0.0f, 1.0f));
                    break;
                }
                else
                {
                    _2041 = clamp(((_170 - 0.064453125f.xxx) * 256.0f) * 0.0045454544015228748321533203125f.xxx, 0.0f.xxx, 1.0f.xxx);
                    break;
                }
                break; // unreachable workaround
            }
            else
            {
                _2041 = _170;
                break;
            }
            break; // unreachable workaround
        } while(false);
        _2198 = _2041;
    }
    float3 _2076;
    if (_133)
    {
        float _184 = params_TVOUT_RESOLUTION_Y * params_SourceSize.z;
        float _185 = 3.1415927410125732421875f * _184;
        float _187 = abs(_130);
        float _188 = _187 + 0.5f;
        float _193 = 1.0f / _184;
        float _195 = _185 * min(_188, _193);
        float _220 = _187 - 0.5f;
        float _233 = _185 * min(max(_220, (-1.0f) / _184), _193);
        float _267 = params_TVOUT_RESOLUTION_I * params_SourceSize.z;
        float _268 = 3.1415927410125732421875f * _267;
        float _276 = 1.0f / _267;
        float _278 = _268 * min(_188, _276);
        float _316 = _268 * min(max(_220, (-1.0f) / _267), _276);
        float _349 = params_TVOUT_RESOLUTION_Q * params_SourceSize.z;
        float _350 = 3.1415927410125732421875f * _349;
        float _358 = 1.0f / _349;
        float _360 = _350 * min(_188, _358);
        float _398 = _350 * min(max(_220, (-1.0f) / _349), _358);
        _2076 = float3(_2198.x * ((((_195 + sin(_195)) - _233) - sin(_233)) * 0.15915493667125701904296875f), _2198.y * ((((_278 + sin(_278)) - _316) - sin(_316)) * 0.15915493667125701904296875f), _2198.z * ((((_360 + sin(_360)) - _398) - sin(_398)) * 0.15915493667125701904296875f));
    }
    else
    {
        float _434 = params_TVOUT_RESOLUTION * params_SourceSize.z;
        float _435 = 3.1415927410125732421875f * _434;
        float _437 = abs(_130);
        float _443 = 1.0f / _434;
        float _445 = _435 * min(_437 + 0.5f, _443);
        float _483 = _435 * min(max(_437 - 0.5f, (-1.0f) / _434), _443);
        _2076 = _2198 * ((((_445 + sin(_445)) - _483) - sin(_483)) * 0.15915493667125701904296875f);
    }
    float3 _2199;
    if (_133)
    {
        float4 _529 = Source.Sample(_Source_sampler, float2(vTexCoord.x - (_120 * params_SourceSize.z), vTexCoord.y));
        float3 _531 = _529.xyz;
        float3 _2062;
        do
        {
            if (params_TVOUT_TV_COLOR_LEVELS > 0.5f)
            {
                if (_133)
                {
                    _2062 = float3(clamp((_529.x - 0.064453125f) * 1.16363632678985595703125f, 0.0f, 1.0f), clamp((_529.y - 0.064453125f) * 1.14285719394683837890625f, 0.0f, 1.0f), clamp((_529.z - 0.064453125f) * 1.14285719394683837890625f, 0.0f, 1.0f));
                    break;
                }
                else
                {
                    _2062 = clamp(((_531 - 0.064453125f.xxx) * 256.0f) * 0.0045454544015228748321533203125f.xxx, 0.0f.xxx, 1.0f.xxx);
                    break;
                }
                break; // unreachable workaround
            }
            else
            {
                _2062 = _531;
                break;
            }
            break; // unreachable workaround
        } while(false);
        _2199 = mul(float3x3(float3(0.2989999949932098388671875f, 0.58700001239776611328125f, 0.114000000059604644775390625f), float3(0.595715999603271484375f, -0.2744530141353607177734375f, -0.3212629854679107666015625f), float3(0.211456000804901123046875f, -0.52259099483489990234375f, 0.311134994029998779296875f)), _2062);
    }
    else
    {
        float4 _546 = Source.Sample(_Source_sampler, float2(vTexCoord.x - (_120 * params_SourceSize.z), vTexCoord.y));
        float3 _548 = _546.xyz;
        float3 _2061;
        do
        {
            if (params_TVOUT_TV_COLOR_LEVELS > 0.5f)
            {
                if (_133)
                {
                    _2061 = float3(clamp((_546.x - 0.064453125f) * 1.16363632678985595703125f, 0.0f, 1.0f), clamp((_546.y - 0.064453125f) * 1.14285719394683837890625f, 0.0f, 1.0f), clamp((_546.z - 0.064453125f) * 1.14285719394683837890625f, 0.0f, 1.0f));
                    break;
                }
                else
                {
                    _2061 = clamp(((_548 - 0.064453125f.xxx) * 256.0f) * 0.0045454544015228748321533203125f.xxx, 0.0f.xxx, 1.0f.xxx);
                    break;
                }
                break; // unreachable workaround
            }
            else
            {
                _2061 = _548;
                break;
            }
            break; // unreachable workaround
        } while(false);
        _2199 = _2061;
    }
    float3 _2101;
    if (_133)
    {
        float _560 = params_TVOUT_RESOLUTION_Y * params_SourceSize.z;
        float _561 = 3.1415927410125732421875f * _560;
        float _563 = abs(_120);
        float _564 = _563 + 0.5f;
        float _569 = 1.0f / _560;
        float _571 = _561 * min(_564, _569);
        float _596 = _563 - 0.5f;
        float _609 = _561 * min(max(_596, (-1.0f) / _560), _569);
        float _641 = params_TVOUT_RESOLUTION_I * params_SourceSize.z;
        float _642 = 3.1415927410125732421875f * _641;
        float _650 = 1.0f / _641;
        float _652 = _642 * min(_564, _650);
        float _690 = _642 * min(max(_596, (-1.0f) / _641), _650);
        float _722 = params_TVOUT_RESOLUTION_Q * params_SourceSize.z;
        float _723 = 3.1415927410125732421875f * _722;
        float _731 = 1.0f / _722;
        float _733 = _723 * min(_564, _731);
        float _771 = _723 * min(max(_596, (-1.0f) / _722), _731);
        _2101 = _2076 + float3(_2199.x * ((((_571 + sin(_571)) - _609) - sin(_609)) * 0.15915493667125701904296875f), _2199.y * ((((_652 + sin(_652)) - _690) - sin(_690)) * 0.15915493667125701904296875f), _2199.z * ((((_733 + sin(_733)) - _771) - sin(_771)) * 0.15915493667125701904296875f));
    }
    else
    {
        float _806 = params_TVOUT_RESOLUTION * params_SourceSize.z;
        float _807 = 3.1415927410125732421875f * _806;
        float _809 = abs(_120);
        float _815 = 1.0f / _806;
        float _817 = _807 * min(_809 + 0.5f, _815);
        float _855 = _807 * min(max(_809 - 0.5f, (-1.0f) / _806), _815);
        _2101 = _2076 + (_2199 * ((((_817 + sin(_817)) - _855) - sin(_855)) * 0.15915493667125701904296875f));
    }
    float _885 = _120 - 1.0f;
    float3 _2200;
    if (_133)
    {
        float4 _901 = Source.Sample(_Source_sampler, float2(vTexCoord.x - (_885 * params_SourceSize.z), vTexCoord.y));
        float3 _903 = _901.xyz;
        float3 _2087;
        do
        {
            if (params_TVOUT_TV_COLOR_LEVELS > 0.5f)
            {
                if (_133)
                {
                    _2087 = float3(clamp((_901.x - 0.064453125f) * 1.16363632678985595703125f, 0.0f, 1.0f), clamp((_901.y - 0.064453125f) * 1.14285719394683837890625f, 0.0f, 1.0f), clamp((_901.z - 0.064453125f) * 1.14285719394683837890625f, 0.0f, 1.0f));
                    break;
                }
                else
                {
                    _2087 = clamp(((_903 - 0.064453125f.xxx) * 256.0f) * 0.0045454544015228748321533203125f.xxx, 0.0f.xxx, 1.0f.xxx);
                    break;
                }
                break; // unreachable workaround
            }
            else
            {
                _2087 = _903;
                break;
            }
            break; // unreachable workaround
        } while(false);
        _2200 = mul(float3x3(float3(0.2989999949932098388671875f, 0.58700001239776611328125f, 0.114000000059604644775390625f), float3(0.595715999603271484375f, -0.2744530141353607177734375f, -0.3212629854679107666015625f), float3(0.211456000804901123046875f, -0.52259099483489990234375f, 0.311134994029998779296875f)), _2087);
    }
    else
    {
        float4 _918 = Source.Sample(_Source_sampler, float2(vTexCoord.x - (_885 * params_SourceSize.z), vTexCoord.y));
        float3 _920 = _918.xyz;
        float3 _2086;
        do
        {
            if (params_TVOUT_TV_COLOR_LEVELS > 0.5f)
            {
                if (_133)
                {
                    _2086 = float3(clamp((_918.x - 0.064453125f) * 1.16363632678985595703125f, 0.0f, 1.0f), clamp((_918.y - 0.064453125f) * 1.14285719394683837890625f, 0.0f, 1.0f), clamp((_918.z - 0.064453125f) * 1.14285719394683837890625f, 0.0f, 1.0f));
                    break;
                }
                else
                {
                    _2086 = clamp(((_920 - 0.064453125f.xxx) * 256.0f) * 0.0045454544015228748321533203125f.xxx, 0.0f.xxx, 1.0f.xxx);
                    break;
                }
                break; // unreachable workaround
            }
            else
            {
                _2086 = _920;
                break;
            }
            break; // unreachable workaround
        } while(false);
        _2200 = _2086;
    }
    float3 _2126;
    if (_133)
    {
        float _932 = params_TVOUT_RESOLUTION_Y * params_SourceSize.z;
        float _933 = 3.1415927410125732421875f * _932;
        float _935 = abs(_885);
        float _936 = _935 + 0.5f;
        float _941 = 1.0f / _932;
        float _943 = _933 * min(_936, _941);
        float _968 = _935 - 0.5f;
        float _981 = _933 * min(max(_968, (-1.0f) / _932), _941);
        float _1013 = params_TVOUT_RESOLUTION_I * params_SourceSize.z;
        float _1014 = 3.1415927410125732421875f * _1013;
        float _1022 = 1.0f / _1013;
        float _1024 = _1014 * min(_936, _1022);
        float _1062 = _1014 * min(max(_968, (-1.0f) / _1013), _1022);
        float _1094 = params_TVOUT_RESOLUTION_Q * params_SourceSize.z;
        float _1095 = 3.1415927410125732421875f * _1094;
        float _1103 = 1.0f / _1094;
        float _1105 = _1095 * min(_936, _1103);
        float _1143 = _1095 * min(max(_968, (-1.0f) / _1094), _1103);
        _2126 = _2101 + float3(_2200.x * ((((_943 + sin(_943)) - _981) - sin(_981)) * 0.15915493667125701904296875f), _2200.y * ((((_1024 + sin(_1024)) - _1062) - sin(_1062)) * 0.15915493667125701904296875f), _2200.z * ((((_1105 + sin(_1105)) - _1143) - sin(_1143)) * 0.15915493667125701904296875f));
    }
    else
    {
        float _1178 = params_TVOUT_RESOLUTION * params_SourceSize.z;
        float _1179 = 3.1415927410125732421875f * _1178;
        float _1181 = abs(_885);
        float _1187 = 1.0f / _1178;
        float _1189 = _1179 * min(_1181 + 0.5f, _1187);
        float _1227 = _1179 * min(max(_1181 - 0.5f, (-1.0f) / _1178), _1187);
        _2126 = _2101 + (_2200 * ((((_1189 + sin(_1189)) - _1227) - sin(_1227)) * 0.15915493667125701904296875f));
    }
    float _1258 = _120 - 2.0f;
    float3 _2201;
    if (_133)
    {
        float4 _1274 = Source.Sample(_Source_sampler, float2(vTexCoord.x - (_1258 * params_SourceSize.z), vTexCoord.y));
        float3 _1276 = _1274.xyz;
        float3 _2112;
        do
        {
            if (params_TVOUT_TV_COLOR_LEVELS > 0.5f)
            {
                if (_133)
                {
                    _2112 = float3(clamp((_1274.x - 0.064453125f) * 1.16363632678985595703125f, 0.0f, 1.0f), clamp((_1274.y - 0.064453125f) * 1.14285719394683837890625f, 0.0f, 1.0f), clamp((_1274.z - 0.064453125f) * 1.14285719394683837890625f, 0.0f, 1.0f));
                    break;
                }
                else
                {
                    _2112 = clamp(((_1276 - 0.064453125f.xxx) * 256.0f) * 0.0045454544015228748321533203125f.xxx, 0.0f.xxx, 1.0f.xxx);
                    break;
                }
                break; // unreachable workaround
            }
            else
            {
                _2112 = _1276;
                break;
            }
            break; // unreachable workaround
        } while(false);
        _2201 = mul(float3x3(float3(0.2989999949932098388671875f, 0.58700001239776611328125f, 0.114000000059604644775390625f), float3(0.595715999603271484375f, -0.2744530141353607177734375f, -0.3212629854679107666015625f), float3(0.211456000804901123046875f, -0.52259099483489990234375f, 0.311134994029998779296875f)), _2112);
    }
    else
    {
        float4 _1291 = Source.Sample(_Source_sampler, float2(vTexCoord.x - (_1258 * params_SourceSize.z), vTexCoord.y));
        float3 _1293 = _1291.xyz;
        float3 _2111;
        do
        {
            if (params_TVOUT_TV_COLOR_LEVELS > 0.5f)
            {
                if (_133)
                {
                    _2111 = float3(clamp((_1291.x - 0.064453125f) * 1.16363632678985595703125f, 0.0f, 1.0f), clamp((_1291.y - 0.064453125f) * 1.14285719394683837890625f, 0.0f, 1.0f), clamp((_1291.z - 0.064453125f) * 1.14285719394683837890625f, 0.0f, 1.0f));
                    break;
                }
                else
                {
                    _2111 = clamp(((_1293 - 0.064453125f.xxx) * 256.0f) * 0.0045454544015228748321533203125f.xxx, 0.0f.xxx, 1.0f.xxx);
                    break;
                }
                break; // unreachable workaround
            }
            else
            {
                _2111 = _1293;
                break;
            }
            break; // unreachable workaround
        } while(false);
        _2201 = _2111;
    }
    float3 _2128;
    if (_133)
    {
        float _1305 = params_TVOUT_RESOLUTION_Y * params_SourceSize.z;
        float _1306 = 3.1415927410125732421875f * _1305;
        float _1308 = abs(_1258);
        float _1309 = _1308 + 0.5f;
        float _1314 = 1.0f / _1305;
        float _1316 = _1306 * min(_1309, _1314);
        float _1341 = _1308 - 0.5f;
        float _1354 = _1306 * min(max(_1341, (-1.0f) / _1305), _1314);
        float _1386 = params_TVOUT_RESOLUTION_I * params_SourceSize.z;
        float _1387 = 3.1415927410125732421875f * _1386;
        float _1395 = 1.0f / _1386;
        float _1397 = _1387 * min(_1309, _1395);
        float _1435 = _1387 * min(max(_1341, (-1.0f) / _1386), _1395);
        float _1467 = params_TVOUT_RESOLUTION_Q * params_SourceSize.z;
        float _1468 = 3.1415927410125732421875f * _1467;
        float _1476 = 1.0f / _1467;
        float _1478 = _1468 * min(_1309, _1476);
        float _1516 = _1468 * min(max(_1341, (-1.0f) / _1467), _1476);
        _2128 = _2126 + float3(_2201.x * ((((_1316 + sin(_1316)) - _1354) - sin(_1354)) * 0.15915493667125701904296875f), _2201.y * ((((_1397 + sin(_1397)) - _1435) - sin(_1435)) * 0.15915493667125701904296875f), _2201.z * ((((_1478 + sin(_1478)) - _1516) - sin(_1516)) * 0.15915493667125701904296875f));
    }
    else
    {
        float _1551 = params_TVOUT_RESOLUTION * params_SourceSize.z;
        float _1552 = 3.1415927410125732421875f * _1551;
        float _1554 = abs(_1258);
        float _1560 = 1.0f / _1551;
        float _1562 = _1552 * min(_1554 + 0.5f, _1560);
        float _1600 = _1552 * min(max(_1554 - 0.5f, (-1.0f) / _1551), _1560);
        _2128 = _2126 + (_2201 * ((((_1562 + sin(_1562)) - _1600) - sin(_1600)) * 0.15915493667125701904296875f));
    }
    float3 _2145;
    if (_133)
    {
        _2145 = mul(float3x3(float3(1.0f, 0.9563000202178955078125f, 0.620999991893768310546875f), float3(1.0f, -0.2721000015735626220703125f, -0.64740002155303955078125f), float3(1.0f, -1.10699999332427978515625f, 1.70459997653961181640625f)), _2128);
    }
    else
    {
        _2145 = _2128;
    }
    FragColor = float4(_2145, 1.0f);
}

SPIRV_Cross_Output main(SPIRV_Cross_Input stage_input)
{
    vTexCoord = stage_input.vTexCoord;
    frag_main();
    SPIRV_Cross_Output stage_output;
    stage_output.FragColor = FragColor;
    return stage_output;
}
