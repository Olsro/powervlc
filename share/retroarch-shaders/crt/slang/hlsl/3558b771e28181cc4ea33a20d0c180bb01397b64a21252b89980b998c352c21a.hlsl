// Generated from crt/shaders/guest/advanced/ntsc/ntsc-pass3.slang. See slang/upstream for licence/source.
cbuffer Push : register(b1)
{
    float4 params_OriginalSize : packoffset(c1);
    float4 params_SourceSize : packoffset(c2);
    uint params_FrameCount : packoffset(c3);
    float params_ntsc_phase : packoffset(c3.y);
    float params_auto_res : packoffset(c3.z);
    float params_ntsc_sharp : packoffset(c3.w);
    float params_ntsc_fonts : packoffset(c4);
    float params_ntsc_charp : packoffset(c4.y);
    float params_ntsc_charp3 : packoffset(c4.z);
    float params_ntsc_shape : packoffset(c4.w);
    float params_ntsc_gamma : packoffset(c5);
    float params_ntsc_rainbow1 : packoffset(c5.y);
    float params_speedup : packoffset(c5.z);
    float params_RFNOISE : packoffset(c5.w);
    float params_RFNOISE1 : packoffset(c6);
    float params_RFNOISE2 : packoffset(c6.y);
};

Texture2D<float4> Source : register(t2);
SamplerState _Source_sampler : register(s2);
Texture2D<float4> NPass1 : register(t3);
SamplerState _NPass1_sampler : register(s3);
Texture2D<float4> PrePass0 : register(t4);
SamplerState _PrePass0_sampler : register(s4);

static float2 vTexCoord0;
static float4 FragColor;
static float2 vTexCoord;
static float2 vTexCoord1;

struct SPIRV_Cross_Input
{
    float2 vTexCoord : TEXCOORD0;
    float2 vTexCoord0 : TEXCOORD1;
    float2 vTexCoord1 : TEXCOORD2;
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
    float _60 = lerp(1.0f, 0.5f, clamp((params_auto_res * round(params_OriginalSize.x * 0.0033333334140479564666748046875f)) - 1.0f, 0.0f, 1.0f));
    float _69 = (params_RFNOISE * params_RFNOISE) + 9.9999997473787516355514526367188e-06f;
    bool _279 = params_speedup > 1.25f;
    bool _302;
    if (_279)
    {
        bool _286 = params_OriginalSize.y > 500.0f;
        bool _294;
        if (_286)
        {
            _294 = params_SourceSize.y > 820.0f;
        }
        else
        {
            _294 = _286;
        }
        bool _301;
        if (!_294)
        {
            _301 = params_SourceSize.y > 820.0f;
        }
        else
        {
            _301 = _294;
        }
        _302 = _301;
    }
    else
    {
        _302 = _279;
    }
    if (_302)
    {
        float4 _314 = Source.Sample(_Source_sampler, vTexCoord0);
        float3 _315 = _314.xyz;
        _315.x = pow(_314.x, 1.0f / params_ntsc_gamma);
        FragColor = float4(clamp(mul(float3x3(float3(1.0f, 0.95599997043609619140625f, 0.620999991893768310546875f), float3(1.0f, -0.272000014781951904296875f, -0.64740002155303955078125f), float3(1.0f, -1.10599994659423828125f, 1.70459997653961181640625f)), _315), 0.0f.xxx, 1.0f.xxx), 1.0f);
    }
    else
    {
        float2 _347 = float2(((0.5f * params_OriginalSize.z) / _60) / params_speedup, 0.0f);
        float _354 = (0.0625f * params_OriginalSize.z) / _60;
        float2 _358 = float2(_354 / params_speedup, 0.0f);
        float2 _1495;
        float2 _1530;
        float2 _1720;
        if (_279)
        {
            _1720 = vTexCoord0;
            _1530 = vTexCoord0;
            _1495 = vTexCoord1;
        }
        else
        {
            _1720 = vTexCoord - (_358 * 2.0f);
            _1530 = vTexCoord;
            _1495 = (floor(params_OriginalSize.xy * vTexCoord) + 0.5f.xx) * params_OriginalSize.zw;
        }
        float4 _396 = Source.Sample(_Source_sampler, _1720 + _347);
        float4 _403 = Source.Sample(_Source_sampler, _1720 - _347);
        float2 _410 = float2(0.0f, params_OriginalSize.w);
        float2 _418 = float2((params_OriginalSize.z / _60) / params_speedup, 0.0f);
        float _1491;
        if (params_ntsc_phase < 1.5f)
        {
            _1491 = ((params_OriginalSize.x * _60) > 300.0f) ? 2.0f : 3.0f;
        }
        else
        {
            _1491 = (params_ntsc_phase > 2.5f) ? 3.0f : 2.0f;
        }
        bool _445 = params_ntsc_phase > 3.5f;
        float _1655 = _445 ? 3.0f : _1491;
        bool _450 = _1655 < 2.5f;
        float _453 = _450 ? 0.02500000037252902984619140625f : 0.0074999998323619365692138671875f;
        float2 _459 = _1495 - _418;
        float4 _462 = NPass1.Sample(_NPass1_sampler, _459 - _418);
        float _463 = _462.w;
        float4 _469 = NPass1.Sample(_NPass1_sampler, _459);
        float _470 = _469.w;
        float4 _474 = NPass1.Sample(_NPass1_sampler, _1495);
        float _475 = _474.w;
        float2 _480 = _1495 + _418;
        float4 _481 = NPass1.Sample(_NPass1_sampler, _480);
        float _482 = _481.w;
        float4 _490 = NPass1.Sample(_NPass1_sampler, _480 + _418);
        float _491 = _490.w;
        float _1232 = _450 ? (-0.02500000037252902984619140625f) : (-0.0074999998323619365692138671875f);
        float _1234 = clamp((min(abs(_475 - _470), abs(_482 - _475)) - _453) / _1232, 0.0f, 1.0f);
        float _540 = max(clamp((min(abs(_463 - _482), abs(_470 - _491)) - _453) / _1232, 0.0f, 1.0f), max(clamp((min(abs(_463 - _470), abs(_482 - _491)) - _453) / _1232, 0.0f, 1.0f), _1234));
        float _1538;
        if (params_ntsc_fonts > 0.25499999523162841796875f)
        {
            float4 _554 = NPass1.Sample(_NPass1_sampler, _1495 - _410);
            float4 _561 = NPass1.Sample(_NPass1_sampler, _1495 + _410);
            float4 _570 = NPass1.Sample(_NPass1_sampler, _480 + _410);
            float _593 = abs(_475 - _554.w);
            bool _609 = _593 < 0.0500000007450580596923828125f;
            bool _618;
            if (!_609)
            {
                _618 = abs(_482 - _570.w) < 0.0500000007450580596923828125f;
            }
            else
            {
                _618 = _609;
            }
            float _1501;
            float _1502;
            _1502 = 0.0f;
            _1501 = 0.0f;
            for (float _1500 = 0.5f; _1500 < 10.5f; )
            {
                float _636 = _1500 + 1.0f;
                float2 _641 = _418 * _1500;
                float2 _649 = _418 * _636;
                _1502 = max(abs(Source.Sample(_Source_sampler, _1720 + _649).x - Source.Sample(_Source_sampler, _1720 + _641).x) - 0.2150000035762786865234375f, _1502);
                _1501 = max(abs(Source.Sample(_Source_sampler, _1720 - _641).x - Source.Sample(_Source_sampler, _1720 - _649).x) - 0.2150000035762786865234375f, _1501);
                _1500 = _636;
                continue;
            }
            _1538 = min((clamp(min(_1501, _1502) * 8.0f, 0.0f, 1.0f) * (clamp((max(_593, abs(_475 - _561.w)) - 0.100000001490116119384765625f) * (-10.0f), 0.0f, 1.0f) * float(_618))) * float((0.5f * (abs(_470 - _475) + abs(_475 - _482))) > (1.0f - params_ntsc_fonts)), 0.625f);
        }
        else
        {
            _1538 = 0.0f;
        }
        float4 _706 = Source.Sample(_Source_sampler, _1720);
        float3 _707 = _706.xyz;
        float2 _710 = _706.yz;
        bool _714 = params_ntsc_rainbow1 > 0.5f;
        bool _727;
        if (_714)
        {
            bool _726;
            if (!_450)
            {
                _726 = params_ntsc_phase == 5.0f;
            }
            else
            {
                _726 = _450;
            }
            _727 = _726;
        }
        else
        {
            _727 = _714;
        }
        float3 _1740;
        if (_727)
        {
            float _1519;
            if ((params_ntsc_rainbow1 < 1.5f) && (_1234 != 0.0f))
            {
                _1519 = 0.0f;
            }
            else
            {
                _1519 = ((params_ntsc_rainbow1 < 2.5f) && (_540 != 0.0f)) ? 0.0f : 1.0f;
            }
            float2 _780 = float2(0.0f, (abs(floor(mod(params_OriginalSize.y * vTexCoord.y, 2.0f)) - floor(mod(float(params_FrameCount), 2.0f))) * params_OriginalSize.w) * _1519);
            float2 _783 = Source.Sample(_Source_sampler, _1720 - _780).yz;
            float2 _791 = Source.Sample(_Source_sampler, _1720 + _780).yz;
            float2 _796 = abs(_710 - _783);
            float2 _813 = lerp(_783, _791, _796 / max(_796 + abs(_710 - _791), 1.0000000116860974230803549289703e-07f.xx));
            float3 _1663 = _707;
            _1663.y = _813.x;
            _1663.z = _813.y;
            _1740 = _1663;
        }
        else
        {
            _1740 = _707;
        }
        float4 _823 = NPass1.Sample(_NPass1_sampler, _1530 - _358);
        float4 _829 = NPass1.Sample(_NPass1_sampler, _1530 + _358);
        float _831 = min(_823.w, _829.w);
        float3 _839 = abs(_396.xyz - _403.xyz);
        float _844 = _839.y;
        float _847 = _839.z;
        float _849 = _396.x;
        float _854 = _403.x;
        float _863 = max(max(max(_839.x, _844), max(_847, abs((_849 * _849) - (_854 * _854)))), _1538);
        float _877 = clamp((abs(_1740.x - _831) - 0.20000000298023223876953125f) * (-10.0f), 0.0f, 1.0f) * pow(_863, 0.125f);
        float _881 = 0.02999999932944774627685546875f * _877;
        float _1294 = clamp((_863 - (0.0500000007450580596923828125f - _881)) / (0.375f + (_881 - (0.375f * _877))), 0.0f, 1.0f);
        float _899 = pow((_1294 + 0.100000001490116119384765625f) * 0.90909087657928466796875f, 0.25f);
        float _904 = lerp(_1294, _899, _1234);
        float _909 = lerp(_1294, _899, _540);
        float _916 = abs(params_ntsc_sharp);
        float3 _1747;
        if (_916 > 0.25f)
        {
            float _932 = ((params_ntsc_sharp > 0.25f) ? _909 : _904) * (0.100000001490116119384765625f * _916);
            float _937 = lerp(_1740.x, _831, _932);
            float _948 = sqrt(lerp(_1740.x * _1740.x, _831 * _831, _932));
            float _955 = lerp(sqrt(_1740.x), sqrt(_831), _932);
            float _958 = _955 * _955;
            float _963 = abs(_937 - _948);
            float _969 = abs(_937 - _958);
            float _982 = min((((_969 + 9.9999997473787516355514526367188e-06f) * _948) + ((_963 + 9.9999997473787516355514526367188e-06f) * _958)) / (1.9999999494757503271102905273438e-05f + (_963 + _969)), 1.0f);
            float3 _1675 = _1740;
            _1675.x = _982;
            _1675.x = min(_982, max(params_ntsc_shape * _982, _1740.x));
            _1747 = _1675;
        }
        else
        {
            _1747 = _1740;
        }
        float3 _1748;
        if ((params_ntsc_charp + params_ntsc_charp3) > 0.25f)
        {
            _358.x = _354;
            float _1021 = (params_OriginalSize.x * (vTexCoord.x + _354)) - 0.5f;
            float _1583;
            if (_450)
            {
                _1583 = params_ntsc_charp;
            }
            else
            {
                _1583 = params_ntsc_charp3;
            }
            float2 _1077 = float2((floor(_1021) + 0.5f) * params_OriginalSize.z, _1720.y);
            float2 _1106 = lerp(_1747.yz, mul(float3x3(float3(0.29890000820159912109375f, 0.58700001239776611328125f, 0.114000000059604644775390625f), float3(0.595899999141693115234375f, -0.2743999958038330078125f, -0.3215999901294708251953125f), float3(0.21150000393390655517578125f, -0.52289998531341552734375f, 0.311399996280670166015625f)), lerp(PrePass0.Sample(_PrePass0_sampler, _1077).xyz, PrePass0.Sample(_PrePass0_sampler, _1077 + (_358 * 16.0f)).xyz, clamp((1.5f * frac(_1021)) - 0.25f, 0.0f, 1.0f).xxx)).yz, ((lerp(clamp((max(_844, _847) - 0.07500000298023223876953125f) * 20.0000019073486328125f, 0.0f, 1.0f), clamp((_863 - 0.014999999664723873138427734375f) * 80.0f, 0.0f, 1.0f), _540) * ((params_ntsc_sharp > 0.25f) ? _909 : _904)) * (0.100000001490116119384765625f * _1583)).xx);
            float3 _1687 = _1747;
            _1687.y = _1106.x;
            _1687.z = _1106.y;
            _1748 = _1687;
        }
        else
        {
            _1748 = _1747;
        }
        float3 _1749;
        if ((params_RFNOISE1 + params_RFNOISE2) > 0.004999999888241291046142578125f)
        {
            float _1125 = float(params_FrameCount);
            float3 _1438 = float3(vTexCoord * 16758.544921875f, _1125);
            float3 _1347 = float3(float2(frac(sin(dot(_1438, float3(12.98980045318603515625f, 78.233001708984375f, 3.183000087738037109375f))) * 43758.546875f), frac(sin(dot(_1438, float3(25.9796009063720703125f, 14.11299991607666015625f, 11.270999908447265625f))) * 96321.9140625f)) * 758.5452880859375f, _1125);
            float _1352 = frac(sin(dot(_1347, float3(12.98983478546142578125f, 78.2334136962890625f, 0.16452999413013458251953125f))) * 43758.546875f);
            float _1357 = frac(sin(dot(_1347, float3(39.346790313720703125f, 11.13523006439208984375f, 83.155731201171875f))) * 39459.32421875f);
            float _1362 = frac(sin(dot(_1347, float3(73.15691375732421875f, 52.23503875732421875f, 9.15196990966796875f))) * 60493.84765625f);
            float _1367 = 0.20000000298023223876953125f * _69;
            bool _1368 = abs(_1352 - 0.5f) < _1367;
            float _1374 = 0.5f * _69;
            bool _1375 = abs(_1357 - 0.5f) < _1374;
            bool _1382 = abs(_1362 - 0.5f) < _1374;
            float _1401 = 0.5f - _1374;
            float _1649 = _1374 + _1374;
            float _1150 = lerp(0.375f, 1.0f, pow(_1748.x, 0.20000000298023223876953125f)) * params_RFNOISE2;
            _1749 = float3(clamp(_1748.x + (params_RFNOISE1 * (((float(_1368) * clamp((_1352 - (0.5f - _1367)) / (_1367 + _1367), 0.0f, 1.0f)) * 0.660000026226043701171875f) - (_1368 ? 0.3300000131130218505859375f : 0.0f))), 0.0f, 1.0f), clamp(_1748.y + ((_1150 * (0.324999988079071044921875f + (1.3250000476837158203125f * abs(_1748.y)))) * ((float(_1375) * clamp((_1357 - _1401) / _1649, 0.0f, 1.0f)) - (_1375 ? 0.5f : 0.0f))), -0.60000002384185791015625f, 0.60000002384185791015625f), clamp(_1748.z + ((_1150 * (0.324999988079071044921875f + (1.3250000476837158203125f * abs(_1748.z)))) * ((float(_1382) * clamp((_1362 - _1401) / _1649, 0.0f, 1.0f)) - (_1382 ? 0.5f : 0.0f))), -0.5299999713897705078125f, 0.5299999713897705078125f));
        }
        else
        {
            _1749 = _1748;
        }
        float3 _1707 = _1749;
        _1707.x = pow(_1749.x, 1.0f / params_ntsc_gamma);
        bool _1201 = _1655 == 2.0f;
        bool _1208;
        if (!_1201)
        {
            _1208 = _445;
        }
        else
        {
            _1208 = _1201;
        }
        FragColor = float4(clamp(mul(float3x3(float3(1.0f, 0.95599997043609619140625f, 0.620999991893768310546875f), float3(1.0f, -0.272000014781951904296875f, -0.64740002155303955078125f), float3(1.0f, -1.10599994659423828125f, 1.70459997653961181640625f)), _1707), 0.0f.xxx, 1.0f.xxx), _1208 ? _909 : 1.0f);
    }
}

SPIRV_Cross_Output main(SPIRV_Cross_Input stage_input)
{
    vTexCoord0 = stage_input.vTexCoord0;
    vTexCoord = stage_input.vTexCoord;
    vTexCoord1 = stage_input.vTexCoord1;
    frag_main();
    SPIRV_Cross_Output stage_output;
    stage_output.FragColor = FragColor;
    return stage_output;
}
