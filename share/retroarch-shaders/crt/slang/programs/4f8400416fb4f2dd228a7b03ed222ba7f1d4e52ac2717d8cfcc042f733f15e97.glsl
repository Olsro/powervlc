// Generated from anti-aliasing/shaders/fxaa.slang. See slang/upstream for licence/source.
#version 120

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

uniform vec2 TextureSize;
struct Push
{
    vec4 SourceSize;
};



uniform sampler2D Texture;

varying vec2 RA_VARYING_0;

void main()
{
    vec3 _1705;
    do
    {
        vec4 _1229 = texture2D(Texture, vec2(RA_VARYING_0.x, RA_VARYING_0.y + ((-1.0) * (vec4(TextureSize, 1.0 / TextureSize)).w)));
        vec4 _1256 = texture2D(Texture, vec2(RA_VARYING_0.x + ((-1.0) * (vec4(TextureSize, 1.0 / TextureSize)).z), RA_VARYING_0.y));
        vec4 _1283 = texture2D(Texture, RA_VARYING_0);
        vec3 _788 = _1283.xyz;
        vec4 _1310 = texture2D(Texture, vec2(RA_VARYING_0.x + (vec4(TextureSize, 1.0 / TextureSize)).z, RA_VARYING_0.y));
        vec4 _1337 = texture2D(Texture, vec2(RA_VARYING_0.x, RA_VARYING_0.y + (vec4(TextureSize, 1.0 / TextureSize)).w));
        float _1345 = (_1229.y * 1.96321070194244384765625) + _1229.x;
        float _1353 = (_1256.y * 1.96321070194244384765625) + _1256.x;
        float _1361 = (_1283.y * 1.96321070194244384765625) + _1283.x;
        float _1369 = (_1310.y * 1.96321070194244384765625) + _1310.x;
        float _1377 = (_1337.y * 1.96321070194244384765625) + _1337.x;
        float _824 = max(_1361, max(max(_1345, _1353), max(_1377, _1369)));
        float _827 = _824 - min(_1361, min(min(_1345, _1353), min(_1377, _1369)));
        if (_827 < max(0.0416666679084300994873046875, _824 * 0.125))
        {
            _1705 = _788;
            break;
        }
        float _864 = min(0.75, max(0.0, (abs(((((_1345 + _1353) + _1369) + _1377) * 0.25) - _1361) / _827) - 0.25) * 1.33333337306976318359375);
        vec4 _1404 = texture2D(Texture, vec2(RA_VARYING_0.x + ((-1.0) * (vec4(TextureSize, 1.0 / TextureSize)).z), RA_VARYING_0.y + ((-1.0) * (vec4(TextureSize, 1.0 / TextureSize)).w)));
        vec4 _1431 = texture2D(Texture, vec2(RA_VARYING_0.x + (vec4(TextureSize, 1.0 / TextureSize)).z, RA_VARYING_0.y + ((-1.0) * (vec4(TextureSize, 1.0 / TextureSize)).w)));
        vec4 _1458 = texture2D(Texture, vec2(RA_VARYING_0.x + ((-1.0) * (vec4(TextureSize, 1.0 / TextureSize)).z), RA_VARYING_0.y + (vec4(TextureSize, 1.0 / TextureSize)).w));
        vec4 _1485 = texture2D(Texture, vec2(RA_VARYING_0.x + (vec4(TextureSize, 1.0 / TextureSize)).z, RA_VARYING_0.y + (vec4(TextureSize, 1.0 / TextureSize)).w));
        float _901 = 0.25 * ((_1404.y * 1.96321070194244384765625) + _1404.x);
        float _906 = 0.25 * ((_1431.y * 1.96321070194244384765625) + _1431.x);
        float _912 = (-1.0) * _1361;
        float _920 = 0.25 * ((_1458.y * 1.96321070194244384765625) + _1458.x);
        float _925 = 0.25 * ((_1485.y * 1.96321070194244384765625) + _1485.x);
        bool _960 = ((abs((_901 + ((-0.5) * _1353)) + _920) + abs(((0.5 * _1345) + _912) + (0.5 * _1377))) + abs((_906 + ((-0.5) * _1369)) + _925)) >= ((abs((_901 + ((-0.5) * _1345)) + _906) + abs(((0.5 * _1353) + _912) + (0.5 * _1369))) + abs((_920 + ((-0.5) * _1377)) + _925));
        float _1548;
        if (_960)
        {
            _1548 = -(vec4(TextureSize, 1.0 / TextureSize)).w;
        }
        else
        {
            _1548 = -(vec4(TextureSize, 1.0 / TextureSize)).z;
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
            _1561 = _1548 * (-1.0);
        }
        else
        {
            _1561 = _1548;
        }
        float _1721 = _996 ? ((_1719 + _1361) * 0.5) : ((_1720 + _1361) * 0.5);
        float _1562;
        if (_960)
        {
            _1562 = 0.0;
        }
        else
        {
            _1562 = _1561 * 0.5;
        }
        float _1565;
        if (_960)
        {
            _1565 = _1561 * 0.5;
        }
        else
        {
            _1565 = 0.0;
        }
        vec2 _1844 = vec2(RA_VARYING_0.x + _1562, RA_VARYING_0.y + _1565);
        float _1027 = (_996 ? _985 : _981) * 0.25;
        vec2 _1570;
        if (_960)
        {
            _1570 = vec2((vec4(TextureSize, 1.0 / TextureSize)).z, 0.0);
        }
        else
        {
            _1570 = vec2(0.0, (vec4(TextureSize, 1.0 / TextureSize)).w);
        }
        vec2 _1827;
        vec2 _1829;
        _1829 = _1844 + _1570;
        _1827 = _1844 + (_1570 * vec2(-1.0));
        bool _1083;
        bool _1094;
        float _1582;
        float _1594;
        float _1628;
        float _1633;
        vec2 _1842;
        vec2 _1843;
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
                    vec4 _1060 = texture2D(Texture, _1827);
                    _1582 = (_1060.y * 1.96321070194244384765625) + _1060.x;
                }
                else
                {
                    _1582 = _1583;
                }
                bool _1065 = !_1578;
                if (_1065)
                {
                    vec4 _1069 = texture2D(Texture, _1829);
                    _1594 = (_1069.y * 1.96321070194244384765625) + _1069.x;
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
            _1622 = RA_VARYING_0.x - _1827.x;
        }
        else
        {
            _1622 = RA_VARYING_0.y - _1827.y;
        }
        float _1624;
        if (_960)
        {
            _1624 = _1829.x - RA_VARYING_0.x;
        }
        else
        {
            _1624 = _1829.y - RA_VARYING_0.y;
        }
        bool _1150 = _1622 < _1624;
        float _1179 = (0.5 + ((_1150 ? _1622 : _1624) * ((-1.0) / (_1624 + _1622)))) * ((((_1361 - _1721) < 0.0) == (((_1150 ? _1628 : _1633) - _1721) < 0.0)) ? 0.0 : _1561);
        vec3 _1195 = texture2D(Texture, vec2(RA_VARYING_0.x + (_960 ? 0.0 : _1179), RA_VARYING_0.y + (_960 ? _1179 : 0.0))).xyz;
        _1705 = (vec3(-_864) * _1195) + ((((((((_1229.xyz + _1256.xyz) + _788) + _1310.xyz) + _1337.xyz) + (((_1404.xyz + _1431.xyz) + _1458.xyz) + _1485.xyz)) * vec3(0.111111111938953399658203125)) * vec3(_864)) + _1195);
        break;
    } while(false);
    gl_FragData[0] = vec4(_1705, 1.0) * 1.0;
}


#endif
