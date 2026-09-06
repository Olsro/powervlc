// Generated from crt/shaders/simple-crt/simple-fxaa.slang. See slang/upstream for licence/source.
#version 120
#pragma parameter FXAA_EDGE_THRESHOLD     "[FXAA] Edge threshold"          4.00    2.00   8.00   1.00  // 4.0 seems good
#pragma parameter FXAA_EDGE_THRESHOLD_MIN "[FXAA] Edge threshold min"     16.00    8.00  32.00   4.00  // no effect observed with my quick test I didn't notice any differences
#pragma parameter FXAA_SEARCH_STEPS       "[FXAA] Search steps"            8.00    8.00  32.00   4.00  // no effect observed with my quick test I didn't notice any differences
#pragma parameter FXAA_SEARCH_THRESHOLD   "[FXAA] Search threshold"        8.00    2.00   8.00   1.00  // higher values may be better for 2D
#pragma parameter FXAA_SUBPIX_TRIM        "[FXAA] Sub-pixel trim"          2.00    2.00   8.00   1.00  // sub-pixel blurs low-res 2D on higher values, bad for SNES, etc.
#pragma parameter FXAA_SUBPIX_CAP         "[FXAA] Sub-pixel cap"           0.10    0.10   0.90   0.10  // similar to trim, blurs 2D
#ifdef VERTEX

uniform mat4 MVPMatrix;
struct UBO
{
    mat4 MVP;
};



attribute vec4 VertexCoord;
varying vec2 RA_VARYING_0;
attribute vec2 TexCoord;

void main()
{
    gl_Position = (MVPMatrix) * VertexCoord;
    RA_VARYING_0 = TexCoord;
}


#endif
#ifdef FRAGMENT

uniform float FXAA_EDGE_THRESHOLD;
uniform float FXAA_EDGE_THRESHOLD_MIN;
uniform float FXAA_SEARCH_STEPS;
uniform float FXAA_SEARCH_THRESHOLD;
uniform float FXAA_SUBPIX_CAP;
uniform float FXAA_SUBPIX_TRIM;
uniform vec2 TextureSize;
struct Push
{
    vec4 SourceSize;
    float FXAA_EDGE_THRESHOLD;
    float FXAA_EDGE_THRESHOLD_MIN;
    float FXAA_SEARCH_STEPS;
    float FXAA_SEARCH_THRESHOLD;
    float FXAA_SUBPIX_TRIM;
    float FXAA_SUBPIX_CAP;
};



uniform sampler2D Texture;

varying vec2 RA_VARYING_0;

void main()
{
    vec3 _1770;
    do
    {
        vec4 _1277 = texture2D(Texture, vec2(RA_VARYING_0.x, RA_VARYING_0.y + ((-1.0) * (vec4(TextureSize, 1.0 / TextureSize)).w)));
        vec4 _1306 = texture2D(Texture, vec2(RA_VARYING_0.x + ((-1.0) * (vec4(TextureSize, 1.0 / TextureSize)).z), RA_VARYING_0.y));
        vec4 _1335 = texture2D(Texture, RA_VARYING_0);
        vec3 _814 = _1335.xyz;
        vec4 _1364 = texture2D(Texture, vec2(RA_VARYING_0.x + (vec4(TextureSize, 1.0 / TextureSize)).z, RA_VARYING_0.y));
        vec4 _1393 = texture2D(Texture, vec2(RA_VARYING_0.x, RA_VARYING_0.y + (vec4(TextureSize, 1.0 / TextureSize)).w));
        float _1402 = (_1277.y * 1.96321070194244384765625) + _1277.x;
        float _1410 = (_1306.y * 1.96321070194244384765625) + _1306.x;
        float _1418 = (_1335.y * 1.96321070194244384765625) + _1335.x;
        float _1426 = (_1364.y * 1.96321070194244384765625) + _1364.x;
        float _1434 = (_1393.y * 1.96321070194244384765625) + _1393.x;
        float _850 = max(_1418, max(max(_1402, _1410), max(_1434, _1426)));
        float _853 = _850 - min(_1418, min(min(_1402, _1410), min(_1434, _1426)));
        if (_853 < max(1.0 / (FXAA_EDGE_THRESHOLD_MIN), _850 * (1.0 / (FXAA_EDGE_THRESHOLD))))
        {
            _1770 = _814;
            break;
        }
        float _894 = 1.0 / (FXAA_SUBPIX_TRIM);
        float _906 = min((FXAA_SUBPIX_CAP), max(0.0, (abs(((((_1402 + _1410) + _1426) + _1434) * 0.25) - _1418) / _853) - _894) * (1.0 / (1.0 - _894)));
        vec4 _1462 = texture2D(Texture, vec2(RA_VARYING_0.x + ((-1.0) * (vec4(TextureSize, 1.0 / TextureSize)).z), RA_VARYING_0.y + ((-1.0) * (vec4(TextureSize, 1.0 / TextureSize)).w)));
        vec4 _1491 = texture2D(Texture, vec2(RA_VARYING_0.x + (vec4(TextureSize, 1.0 / TextureSize)).z, RA_VARYING_0.y + ((-1.0) * (vec4(TextureSize, 1.0 / TextureSize)).w)));
        vec4 _1520 = texture2D(Texture, vec2(RA_VARYING_0.x + ((-1.0) * (vec4(TextureSize, 1.0 / TextureSize)).z), RA_VARYING_0.y + (vec4(TextureSize, 1.0 / TextureSize)).w));
        vec4 _1549 = texture2D(Texture, vec2(RA_VARYING_0.x + (vec4(TextureSize, 1.0 / TextureSize)).z, RA_VARYING_0.y + (vec4(TextureSize, 1.0 / TextureSize)).w));
        float _943 = 0.25 * ((_1462.y * 1.96321070194244384765625) + _1462.x);
        float _948 = 0.25 * ((_1491.y * 1.96321070194244384765625) + _1491.x);
        float _954 = (-1.0) * _1418;
        float _962 = 0.25 * ((_1520.y * 1.96321070194244384765625) + _1520.x);
        float _967 = 0.25 * ((_1549.y * 1.96321070194244384765625) + _1549.x);
        bool _1002 = ((abs((_943 + ((-0.5) * _1410)) + _962) + abs(((0.5 * _1402) + _954) + (0.5 * _1434))) + abs((_948 + ((-0.5) * _1426)) + _967)) >= ((abs((_943 + ((-0.5) * _1402)) + _948) + abs(((0.5 * _1410) + _954) + (0.5 * _1426))) + abs((_962 + ((-0.5) * _1434)) + _967));
        float _1613;
        if (_1002)
        {
            _1613 = -(vec4(TextureSize, 1.0 / TextureSize)).w;
        }
        else
        {
            _1613 = -(vec4(TextureSize, 1.0 / TextureSize)).z;
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
            _1626 = _1613 * (-1.0);
        }
        else
        {
            _1626 = _1613;
        }
        float _1786 = _1038 ? ((_1784 + _1418) * 0.5) : ((_1785 + _1418) * 0.5);
        float _1627;
        if (_1002)
        {
            _1627 = 0.0;
        }
        else
        {
            _1627 = _1626 * 0.5;
        }
        float _1630;
        if (_1002)
        {
            _1630 = _1626 * 0.5;
        }
        else
        {
            _1630 = 0.0;
        }
        vec2 _1913 = vec2(RA_VARYING_0.x + _1627, RA_VARYING_0.y + _1630);
        float _1072 = (_1038 ? _1027 : _1023) * (1.0 / (FXAA_SEARCH_THRESHOLD));
        vec2 _1635;
        if (_1002)
        {
            _1635 = vec2((vec4(TextureSize, 1.0 / TextureSize)).z, 0.0);
        }
        else
        {
            _1635 = vec2(0.0, (vec4(TextureSize, 1.0 / TextureSize)).w);
        }
        int _1640;
        bool _1641;
        bool _1643;
        float _1648;
        float _1661;
        vec2 _1896;
        vec2 _1898;
        _1898 = _1913 + _1635;
        _1896 = _1913 + (_1635 * vec2(-1.0));
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
        vec2 _1911;
        vec2 _1912;
        for (;;)
        {
            if (_1640 < int((FXAA_SEARCH_STEPS)))
            {
                bool _1104 = !_1641;
                if (_1104)
                {
                    vec4 _1108 = texture2D(Texture, _1896);
                    _1647 = (_1108.y * 1.96321070194244384765625) + _1108.x;
                }
                else
                {
                    _1647 = _1648;
                }
                bool _1113 = !_1643;
                if (_1113)
                {
                    vec4 _1117 = texture2D(Texture, _1898);
                    _1659 = (_1117.y * 1.96321070194244384765625) + _1117.x;
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
            _1687 = RA_VARYING_0.x - _1896.x;
        }
        else
        {
            _1687 = RA_VARYING_0.y - _1896.y;
        }
        float _1689;
        if (_1002)
        {
            _1689 = _1898.x - RA_VARYING_0.x;
        }
        else
        {
            _1689 = _1898.y - RA_VARYING_0.y;
        }
        bool _1198 = _1687 < _1689;
        float _1227 = (0.5 + ((_1198 ? _1687 : _1689) * ((-1.0) / (_1689 + _1687)))) * ((((_1418 - _1786) < 0.0) == (((_1198 ? _1693 : _1698) - _1786) < 0.0)) ? 0.0 : _1626);
        vec3 _1243 = texture2D(Texture, vec2(RA_VARYING_0.x + (_1002 ? 0.0 : _1227), RA_VARYING_0.y + (_1002 ? _1227 : 0.0))).xyz;
        _1770 = (vec3(-_906) * _1243) + ((((((((_1277.xyz + _1306.xyz) + _814) + _1364.xyz) + _1393.xyz) + (((_1462.xyz + _1491.xyz) + _1520.xyz) + _1549.xyz)) * vec3(0.111111111938953399658203125)) * vec3(_906)) + _1243);
        break;
    } while(false);
    gl_FragData[0] = vec4(_1770, 1.0) * 1.0;
}


#endif
