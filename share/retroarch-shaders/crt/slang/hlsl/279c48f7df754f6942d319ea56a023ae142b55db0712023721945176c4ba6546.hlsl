// Generated from anti-aliasing/shaders/fxaa.slang. See slang/upstream for licence/source.
cbuffer Push : register(b1)
{
    float4 params_SourceSize : packoffset(c0);
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
    float3 _1705;
    do
    {
        float4 _1229 = Source.Sample(_Source_sampler, float2(vTexCoord.x, vTexCoord.y + ((-1.0f) * params_SourceSize.w)));
        float4 _1256 = Source.Sample(_Source_sampler, float2(vTexCoord.x + ((-1.0f) * params_SourceSize.z), vTexCoord.y));
        float4 _1283 = Source.Sample(_Source_sampler, vTexCoord);
        float3 _788 = _1283.xyz;
        float4 _1310 = Source.Sample(_Source_sampler, float2(vTexCoord.x + params_SourceSize.z, vTexCoord.y));
        float4 _1337 = Source.Sample(_Source_sampler, float2(vTexCoord.x, vTexCoord.y + params_SourceSize.w));
        float _1345 = (_1229.y * 1.96321070194244384765625f) + _1229.x;
        float _1353 = (_1256.y * 1.96321070194244384765625f) + _1256.x;
        float _1361 = (_1283.y * 1.96321070194244384765625f) + _1283.x;
        float _1369 = (_1310.y * 1.96321070194244384765625f) + _1310.x;
        float _1377 = (_1337.y * 1.96321070194244384765625f) + _1337.x;
        float _824 = max(_1361, max(max(_1345, _1353), max(_1377, _1369)));
        float _827 = _824 - min(_1361, min(min(_1345, _1353), min(_1377, _1369)));
        if (_827 < max(0.0416666679084300994873046875f, _824 * 0.125f))
        {
            _1705 = _788;
            break;
        }
        float _864 = min(0.75f, max(0.0f, (abs(((((_1345 + _1353) + _1369) + _1377) * 0.25f) - _1361) / _827) - 0.25f) * 1.33333337306976318359375f);
        float4 _1404 = Source.Sample(_Source_sampler, float2(vTexCoord.x + ((-1.0f) * params_SourceSize.z), vTexCoord.y + ((-1.0f) * params_SourceSize.w)));
        float4 _1431 = Source.Sample(_Source_sampler, float2(vTexCoord.x + params_SourceSize.z, vTexCoord.y + ((-1.0f) * params_SourceSize.w)));
        float4 _1458 = Source.Sample(_Source_sampler, float2(vTexCoord.x + ((-1.0f) * params_SourceSize.z), vTexCoord.y + params_SourceSize.w));
        float4 _1485 = Source.Sample(_Source_sampler, float2(vTexCoord.x + params_SourceSize.z, vTexCoord.y + params_SourceSize.w));
        float _901 = 0.25f * ((_1404.y * 1.96321070194244384765625f) + _1404.x);
        float _906 = 0.25f * ((_1431.y * 1.96321070194244384765625f) + _1431.x);
        float _912 = (-1.0f) * _1361;
        float _920 = 0.25f * ((_1458.y * 1.96321070194244384765625f) + _1458.x);
        float _925 = 0.25f * ((_1485.y * 1.96321070194244384765625f) + _1485.x);
        bool _960 = ((abs((_901 + ((-0.5f) * _1353)) + _920) + abs(((0.5f * _1345) + _912) + (0.5f * _1377))) + abs((_906 + ((-0.5f) * _1369)) + _925)) >= ((abs((_901 + ((-0.5f) * _1345)) + _906) + abs(((0.5f * _1353) + _912) + (0.5f * _1369))) + abs((_920 + ((-0.5f) * _1377)) + _925));
        float _1548;
        if (_960)
        {
            _1548 = -params_SourceSize.w;
        }
        else
        {
            _1548 = -params_SourceSize.z;
        }
        bool _973 = !_960;
        float _1719 = _973 ? _1369 : _1377;
        float _1720 = _973 ? _1353 : _1345;
        float _981 = abs(_1720 - _1361);
        float _985 = abs(_1719 - _1361);
        bool _996 = _981 < _985;
        float _1561;
        if (_996)
        {
            _1561 = _1548 * (-1.0f);
        }
        else
        {
            _1561 = _1548;
        }
        float _1721 = _996 ? ((_1719 + _1361) * 0.5f) : ((_1720 + _1361) * 0.5f);
        float _1562;
        if (_960)
        {
            _1562 = 0.0f;
        }
        else
        {
            _1562 = _1561 * 0.5f;
        }
        float _1565;
        if (_960)
        {
            _1565 = _1561 * 0.5f;
        }
        else
        {
            _1565 = 0.0f;
        }
        float2 _1844 = float2(vTexCoord.x + _1562, vTexCoord.y + _1565);
        float _1027 = (_996 ? _985 : _981) * 0.25f;
        float2 _1570;
        if (_960)
        {
            _1570 = float2(params_SourceSize.z, 0.0f);
        }
        else
        {
            _1570 = float2(0.0f, params_SourceSize.w);
        }
        float2 _1827;
        float2 _1829;
        _1829 = _1844 + _1570;
        _1827 = _1844 + (_1570 * (-1.0f).xx);
        bool _1083;
        bool _1094;
        float _1582;
        float _1594;
        float _1628;
        float _1633;
        float2 _1842;
        float2 _1843;
        int _1575 = 0;
        bool _1576 = false;
        bool _1578 = false;
        float _1583 = _1721;
        float _1596 = _1721;
        for (;;)
        {
            if (_1575 < 32)
            {
                bool _1056 = !_1576;
                if (_1056)
                {
                    float4 _1060 = Source.Sample(_Source_sampler, _1827);
                    _1582 = (_1060.y * 1.96321070194244384765625f) + _1060.x;
                }
                else
                {
                    _1582 = _1583;
                }
                bool _1065 = !_1578;
                if (_1065)
                {
                    float4 _1069 = Source.Sample(_Source_sampler, _1829);
                    _1594 = (_1069.y * 1.96321070194244384765625f) + _1069.x;
                }
                else
                {
                    _1594 = _1596;
                }
                if (_1056)
                {
                    _1083 = abs(_1582 - _1721) >= _1027;
                }
                else
                {
                    _1083 = _1576;
                }
                if (_1065)
                {
                    _1094 = abs(_1594 - _1721) >= _1027;
                }
                else
                {
                    _1094 = _1578;
                }
                if (_1083 && _1094)
                {
                    _1633 = _1594;
                    _1628 = _1582;
                    break;
                }
                if (!_1083)
                {
                    _1842 = _1827 - _1570;
                }
                else
                {
                    _1842 = _1827;
                }
                if (!_1094)
                {
                    _1843 = _1829 + _1570;
                }
                else
                {
                    _1843 = _1829;
                }
                _1829 = _1843;
                _1827 = _1842;
                _1596 = _1594;
                _1583 = _1582;
                _1578 = _1094;
                _1576 = _1083;
                _1575++;
                continue;
            }
            else
            {
                _1633 = _1596;
                _1628 = _1583;
                break;
            }
        }
        float _1622;
        if (_960)
        {
            _1622 = vTexCoord.x - _1827.x;
        }
        else
        {
            _1622 = vTexCoord.y - _1827.y;
        }
        float _1624;
        if (_960)
        {
            _1624 = _1829.x - vTexCoord.x;
        }
        else
        {
            _1624 = _1829.y - vTexCoord.y;
        }
        bool _1150 = _1622 < _1624;
        float _1179 = (0.5f + ((_1150 ? _1622 : _1624) * ((-1.0f) / (_1624 + _1622)))) * ((((_1361 - _1721) < 0.0f) == (((_1150 ? _1628 : _1633) - _1721) < 0.0f)) ? 0.0f : _1561);
        float3 _1195 = Source.Sample(_Source_sampler, float2(vTexCoord.x + (_960 ? 0.0f : _1179), vTexCoord.y + (_960 ? _1179 : 0.0f))).xyz;
        _1705 = ((-_864).xxx * _1195) + ((((((((_1229.xyz + _1256.xyz) + _788) + _1310.xyz) + _1337.xyz) + (((_1404.xyz + _1431.xyz) + _1458.xyz) + _1485.xyz)) * 0.111111111938953399658203125f.xxx) * _864.xxx) + _1195);
        break;
    } while(false);
    FragColor = float4(_1705, 1.0f) * 1.0f;
}

SPIRV_Cross_Output main(SPIRV_Cross_Input stage_input)
{
    vTexCoord = stage_input.vTexCoord;
    frag_main();
    SPIRV_Cross_Output stage_output;
    stage_output.FragColor = FragColor;
    return stage_output;
}
