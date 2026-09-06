// Generated from crt/shaders/simple-crt/simple-fxaa.slang. See slang/upstream for licence/source.
cbuffer Push : register(b1)
{
    float4 params_SourceSize : packoffset(c0);
    float params_FXAA_EDGE_THRESHOLD : packoffset(c3.y);
    float params_FXAA_EDGE_THRESHOLD_MIN : packoffset(c3.z);
    float params_FXAA_SEARCH_STEPS : packoffset(c3.w);
    float params_FXAA_SEARCH_THRESHOLD : packoffset(c4);
    float params_FXAA_SUBPIX_TRIM : packoffset(c4.y);
    float params_FXAA_SUBPIX_CAP : packoffset(c4.z);
};

Texture2D<float4> Source : register(t2);
SamplerState _Source_sampler : register(s2);

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
    float3 _1770;
    do
    {
        float4 _1277 = Source.Sample(_Source_sampler, float2(vTexCoord.x, vTexCoord.y + ((-1.0f) * params_SourceSize.w)));
        float4 _1306 = Source.Sample(_Source_sampler, float2(vTexCoord.x + ((-1.0f) * params_SourceSize.z), vTexCoord.y));
        float4 _1335 = Source.Sample(_Source_sampler, vTexCoord);
        float3 _814 = _1335.xyz;
        float4 _1364 = Source.Sample(_Source_sampler, float2(vTexCoord.x + params_SourceSize.z, vTexCoord.y));
        float4 _1393 = Source.Sample(_Source_sampler, float2(vTexCoord.x, vTexCoord.y + params_SourceSize.w));
        float _1402 = (_1277.y * 1.96321070194244384765625f) + _1277.x;
        float _1410 = (_1306.y * 1.96321070194244384765625f) + _1306.x;
        float _1418 = (_1335.y * 1.96321070194244384765625f) + _1335.x;
        float _1426 = (_1364.y * 1.96321070194244384765625f) + _1364.x;
        float _1434 = (_1393.y * 1.96321070194244384765625f) + _1393.x;
        float _850 = max(_1418, max(max(_1402, _1410), max(_1434, _1426)));
        float _853 = _850 - min(_1418, min(min(_1402, _1410), min(_1434, _1426)));
        if (_853 < max(1.0f / params_FXAA_EDGE_THRESHOLD_MIN, _850 * (1.0f / params_FXAA_EDGE_THRESHOLD)))
        {
            _1770 = _814;
            break;
        }
        float _894 = 1.0f / params_FXAA_SUBPIX_TRIM;
        float _906 = min(params_FXAA_SUBPIX_CAP, max(0.0f, (abs(((((_1402 + _1410) + _1426) + _1434) * 0.25f) - _1418) / _853) - _894) * (1.0f / (1.0f - _894)));
        float4 _1462 = Source.Sample(_Source_sampler, float2(vTexCoord.x + ((-1.0f) * params_SourceSize.z), vTexCoord.y + ((-1.0f) * params_SourceSize.w)));
        float4 _1491 = Source.Sample(_Source_sampler, float2(vTexCoord.x + params_SourceSize.z, vTexCoord.y + ((-1.0f) * params_SourceSize.w)));
        float4 _1520 = Source.Sample(_Source_sampler, float2(vTexCoord.x + ((-1.0f) * params_SourceSize.z), vTexCoord.y + params_SourceSize.w));
        float4 _1549 = Source.Sample(_Source_sampler, float2(vTexCoord.x + params_SourceSize.z, vTexCoord.y + params_SourceSize.w));
        float _943 = 0.25f * ((_1462.y * 1.96321070194244384765625f) + _1462.x);
        float _948 = 0.25f * ((_1491.y * 1.96321070194244384765625f) + _1491.x);
        float _954 = (-1.0f) * _1418;
        float _962 = 0.25f * ((_1520.y * 1.96321070194244384765625f) + _1520.x);
        float _967 = 0.25f * ((_1549.y * 1.96321070194244384765625f) + _1549.x);
        bool _1002 = ((abs((_943 + ((-0.5f) * _1410)) + _962) + abs(((0.5f * _1402) + _954) + (0.5f * _1434))) + abs((_948 + ((-0.5f) * _1426)) + _967)) >= ((abs((_943 + ((-0.5f) * _1402)) + _948) + abs(((0.5f * _1410) + _954) + (0.5f * _1426))) + abs((_962 + ((-0.5f) * _1434)) + _967));
        float _1613;
        if (_1002)
        {
            _1613 = -params_SourceSize.w;
        }
        else
        {
            _1613 = -params_SourceSize.z;
        }
        bool _1015 = !_1002;
        float _1784 = _1015 ? _1426 : _1434;
        float _1785 = _1015 ? _1410 : _1402;
        float _1023 = abs(_1785 - _1418);
        float _1027 = abs(_1784 - _1418);
        bool _1038 = _1023 < _1027;
        float _1626;
        if (_1038)
        {
            _1626 = _1613 * (-1.0f);
        }
        else
        {
            _1626 = _1613;
        }
        float _1786 = _1038 ? ((_1784 + _1418) * 0.5f) : ((_1785 + _1418) * 0.5f);
        float _1627;
        if (_1002)
        {
            _1627 = 0.0f;
        }
        else
        {
            _1627 = _1626 * 0.5f;
        }
        float _1630;
        if (_1002)
        {
            _1630 = _1626 * 0.5f;
        }
        else
        {
            _1630 = 0.0f;
        }
        float2 _1913 = float2(vTexCoord.x + _1627, vTexCoord.y + _1630);
        float _1072 = (_1038 ? _1027 : _1023) * (1.0f / params_FXAA_SEARCH_THRESHOLD);
        float2 _1635;
        if (_1002)
        {
            _1635 = float2(params_SourceSize.z, 0.0f);
        }
        else
        {
            _1635 = float2(0.0f, params_SourceSize.w);
        }
        int _1640;
        bool _1641;
        bool _1643;
        float _1648;
        float _1661;
        float2 _1896;
        float2 _1898;
        _1898 = _1913 + _1635;
        _1896 = _1913 + (_1635 * (-1.0f).xx);
        _1661 = _1786;
        _1648 = _1786;
        _1643 = false;
        _1641 = false;
        _1640 = 0;
        bool _1131;
        bool _1142;
        float _1647;
        float _1659;
        float _1693;
        float _1698;
        float2 _1911;
        float2 _1912;
        for (;;)
        {
            if (_1640 < int(params_FXAA_SEARCH_STEPS))
            {
                bool _1104 = !_1641;
                if (_1104)
                {
                    float4 _1108 = Source.Sample(_Source_sampler, _1896);
                    _1647 = (_1108.y * 1.96321070194244384765625f) + _1108.x;
                }
                else
                {
                    _1647 = _1648;
                }
                bool _1113 = !_1643;
                if (_1113)
                {
                    float4 _1117 = Source.Sample(_Source_sampler, _1898);
                    _1659 = (_1117.y * 1.96321070194244384765625f) + _1117.x;
                }
                else
                {
                    _1659 = _1661;
                }
                if (_1104)
                {
                    _1131 = abs(_1647 - _1786) >= _1072;
                }
                else
                {
                    _1131 = _1641;
                }
                if (_1113)
                {
                    _1142 = abs(_1659 - _1786) >= _1072;
                }
                else
                {
                    _1142 = _1643;
                }
                if (_1131 && _1142)
                {
                    _1698 = _1659;
                    _1693 = _1647;
                    break;
                }
                if (!_1131)
                {
                    _1911 = _1896 - _1635;
                }
                else
                {
                    _1911 = _1896;
                }
                if (!_1142)
                {
                    _1912 = _1898 + _1635;
                }
                else
                {
                    _1912 = _1898;
                }
                _1898 = _1912;
                _1896 = _1911;
                _1661 = _1659;
                _1648 = _1647;
                _1643 = _1142;
                _1641 = _1131;
                _1640++;
                continue;
            }
            else
            {
                _1698 = _1661;
                _1693 = _1648;
                break;
            }
        }
        float _1687;
        if (_1002)
        {
            _1687 = vTexCoord.x - _1896.x;
        }
        else
        {
            _1687 = vTexCoord.y - _1896.y;
        }
        float _1689;
        if (_1002)
        {
            _1689 = _1898.x - vTexCoord.x;
        }
        else
        {
            _1689 = _1898.y - vTexCoord.y;
        }
        bool _1198 = _1687 < _1689;
        float _1227 = (0.5f + ((_1198 ? _1687 : _1689) * ((-1.0f) / (_1689 + _1687)))) * ((((_1418 - _1786) < 0.0f) == (((_1198 ? _1693 : _1698) - _1786) < 0.0f)) ? 0.0f : _1626);
        float3 _1243 = Source.Sample(_Source_sampler, float2(vTexCoord.x + (_1002 ? 0.0f : _1227), vTexCoord.y + (_1002 ? _1227 : 0.0f))).xyz;
        _1770 = ((-_906).xxx * _1243) + ((((((((_1277.xyz + _1306.xyz) + _814) + _1364.xyz) + _1393.xyz) + (((_1462.xyz + _1491.xyz) + _1520.xyz) + _1549.xyz)) * 0.111111111938953399658203125f.xxx) * _906.xxx) + _1243);
        break;
    } while(false);
    FragColor = float4(_1770, 1.0f) * 1.0f;
}

SPIRV_Cross_Output main(SPIRV_Cross_Input stage_input)
{
    vTexCoord = stage_input.vTexCoord;
    frag_main();
    SPIRV_Cross_Output stage_output;
    stage_output.FragColor = FragColor;
    return stage_output;
}
