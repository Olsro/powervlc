// Generated from crt/shaders/guest/advanced/ntsc/ntsc-pass3.slang. See slang/upstream for licence/source.
#version 130
#pragma parameter auto_res "          SNES/Amiga Hi-Res Auto Mode" 0.0 0.0 1.0 1.0
#pragma parameter speedup  "          Speedup w. higher Internal Res." 1.0 1.0 4.0 1.0
#pragma parameter ntsc_phase    "NTSC Phase: Auto | 2 phase | 3 phase | Mixed | PCE" 1.0 1.0 5.0 1.0
#pragma parameter ntsc_rainbow1 "NTSC Coloring/Rainbow Effect (2-phase)"  0.0 0.0 3.0 1.0
#pragma parameter ntsc_sharp  "NTSC Sharpness (Adaptive)" 0.0 -10.0 10.0 0.50
#pragma parameter ntsc_fonts  "NTSC Sharpness - Preserve Fonts (0.35 is a Good Spot)" 0.25 0.25 1.0 0.01
#pragma parameter ntsc_shape  "NTSC Sharpness Shape" 0.80 0.5 1.0 0.025
#pragma parameter ntsc_charp  "NTSC Preserve 'Edge' Colors 2-phase" 0.0 0.0 10.0 0.50
#pragma parameter ntsc_charp3 "NTSC Preserve 'Edge' Colors 3-phase" 0.0 0.0 10.0 0.50
#pragma parameter ntsc_gamma  "NTSC Filtering Gamma Correction" 1.0 0.25 2.5 0.025
#pragma parameter RFNOISE     "NTSC RF Noise Frequency  " 0.30 0.0 1.0 0.01
#pragma parameter RFNOISE1    "NTSC RF Noise Luma+      " 0.00 0.0 0.7 0.01
#pragma parameter RFNOISE2    "NTSC RF Noise Chroma+    " 0.00 0.0 0.7 0.01
#ifdef VERTEX

uniform mat4 MVPMatrix;
uniform vec2 OrigTextureSize;
uniform float auto_res;
uniform float speedup;
struct UBO
{
    mat4 MVP;
};



struct Push
{
    vec4 OriginalSize;
    float auto_res;
    float speedup;
};



in vec4 VertexCoord;
out vec2 RA_VARYING_1;
in vec2 TexCoord;
out vec2 RA_VARYING_2;
out vec2 RA_VARYING_0;

void main()
{
    gl_Position = (MVPMatrix) * VertexCoord;
    RA_VARYING_1 = TexCoord / vec2((speedup), 1.0);
    RA_VARYING_2 = (floor(RA_VARYING_1 * (vec4(OrigTextureSize, 1.0 / OrigTextureSize)).xy) + vec2(0.5)) * (vec4(OrigTextureSize, 1.0 / OrigTextureSize)).zw;
    RA_VARYING_0 = TexCoord + vec2(((vec4(OrigTextureSize, 1.0 / OrigTextureSize)).z / mix(1.0, 0.5, clamp(((auto_res) * round((vec4(OrigTextureSize, 1.0 / OrigTextureSize)).x * 0.0033333334140479564666748046875)) - 1.0, 0.0, 1.0))) * 0.125, 0.0);
}


#endif
#ifdef FRAGMENT

uniform int FrameCount;
uniform vec2 OrigTextureSize;
uniform float RFNOISE;
uniform float RFNOISE1;
uniform float RFNOISE2;
uniform vec2 TextureSize;
uniform float auto_res;
uniform float ntsc_charp;
uniform float ntsc_charp3;
uniform float ntsc_fonts;
uniform float ntsc_gamma;
uniform float ntsc_phase;
uniform float ntsc_rainbow1;
uniform float ntsc_shape;
uniform float ntsc_sharp;
uniform float speedup;
struct Push
{
    vec4 OriginalSize;
    vec4 SourceSize;
    uint FrameCount;
    float ntsc_phase;
    float auto_res;
    float ntsc_sharp;
    float ntsc_fonts;
    float ntsc_charp;
    float ntsc_charp3;
    float ntsc_shape;
    float ntsc_gamma;
    float ntsc_rainbow1;
    float speedup;
    float RFNOISE;
    float RFNOISE1;
    float RFNOISE2;
};



uniform sampler2D Texture;
uniform sampler2D Pass3Texture;
uniform sampler2D Pass2Texture;

in vec2 RA_VARYING_1;
out vec4 FragColor;
in vec2 RA_VARYING_0;
in vec2 RA_VARYING_2;

void main()
{
    float _60 = mix(1.0, 0.5, clamp(((auto_res) * round((vec4(OrigTextureSize, 1.0 / OrigTextureSize)).x * 0.0033333334140479564666748046875)) - 1.0, 0.0, 1.0));
    float _69 = ((RFNOISE) * (RFNOISE)) + 9.9999997473787516355514526367188e-06;
    bool _279 = (speedup) > 1.25;
    bool _302;
    if (_279)
    {
        bool _286 = (vec4(OrigTextureSize, 1.0 / OrigTextureSize)).y > 500.0;
        bool _294;
        if (_286)
        {
            _294 = (vec4(TextureSize, 1.0 / TextureSize)).y > 820.0;
        }
        else
        {
            _294 = _286;
        }
        bool _301;
        if (!_294)
        {
            _301 = (vec4(TextureSize, 1.0 / TextureSize)).y > 820.0;
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
        vec4 _314 = texture(Texture, RA_VARYING_1);
        vec3 _315 = _314.xyz;
        _315.x = pow(_314.x, 1.0 / (ntsc_gamma));
        FragColor = vec4(clamp(_315 * mat3(vec3(1.0, 0.95599997043609619140625, 0.620999991893768310546875), vec3(1.0, -0.272000014781951904296875, -0.64740002155303955078125), vec3(1.0, -1.10599994659423828125, 1.70459997653961181640625)), vec3(0.0), vec3(1.0)), 1.0);
    }
    else
    {
        vec2 _347 = vec2(((0.5 * (vec4(OrigTextureSize, 1.0 / OrigTextureSize)).z) / _60) / (speedup), 0.0);
        float _354 = (0.0625 * (vec4(OrigTextureSize, 1.0 / OrigTextureSize)).z) / _60;
        vec2 _358 = vec2(_354 / (speedup), 0.0);
        vec2 _1495;
        vec2 _1530;
        vec2 _1720;
        if (_279)
        {
            _1720 = RA_VARYING_1;
            _1530 = RA_VARYING_1;
            _1495 = RA_VARYING_2;
        }
        else
        {
            _1720 = RA_VARYING_0 - (_358 * 2.0);
            _1530 = RA_VARYING_0;
            _1495 = (floor((vec4(OrigTextureSize, 1.0 / OrigTextureSize)).xy * RA_VARYING_0) + vec2(0.5)) * (vec4(OrigTextureSize, 1.0 / OrigTextureSize)).zw;
        }
        vec4 _396 = texture(Texture, _1720 + _347);
        vec4 _403 = texture(Texture, _1720 - _347);
        vec2 _410 = vec2(0.0, (vec4(OrigTextureSize, 1.0 / OrigTextureSize)).w);
        vec2 _418 = vec2(((vec4(OrigTextureSize, 1.0 / OrigTextureSize)).z / _60) / (speedup), 0.0);
        float _1491;
        if ((ntsc_phase) < 1.5)
        {
            _1491 = (((vec4(OrigTextureSize, 1.0 / OrigTextureSize)).x * _60) > 300.0) ? 2.0 : 3.0;
        }
        else
        {
            _1491 = ((ntsc_phase) > 2.5) ? 3.0 : 2.0;
        }
        bool _445 = (ntsc_phase) > 3.5;
        float _1655 = _445 ? 3.0 : _1491;
        bool _450 = _1655 < 2.5;
        float _453 = _450 ? 0.02500000037252902984619140625 : 0.0074999998323619365692138671875;
        vec2 _459 = _1495 - _418;
        vec4 _462 = texture(Pass3Texture, _459 - _418);
        float _463 = _462.w;
        vec4 _469 = texture(Pass3Texture, _459);
        float _470 = _469.w;
        vec4 _474 = texture(Pass3Texture, _1495);
        float _475 = _474.w;
        vec2 _480 = _1495 + _418;
        vec4 _481 = texture(Pass3Texture, _480);
        float _482 = _481.w;
        vec4 _490 = texture(Pass3Texture, _480 + _418);
        float _491 = _490.w;
        float _1232 = _450 ? (-0.02500000037252902984619140625) : (-0.0074999998323619365692138671875);
        float _1234 = clamp((min(abs(_475 - _470), abs(_482 - _475)) - _453) / _1232, 0.0, 1.0);
        float _540 = max(clamp((min(abs(_463 - _482), abs(_470 - _491)) - _453) / _1232, 0.0, 1.0), max(clamp((min(abs(_463 - _470), abs(_482 - _491)) - _453) / _1232, 0.0, 1.0), _1234));
        float _1538;
        if ((ntsc_fonts) > 0.25499999523162841796875)
        {
            vec4 _554 = texture(Pass3Texture, _1495 - _410);
            vec4 _561 = texture(Pass3Texture, _1495 + _410);
            vec4 _570 = texture(Pass3Texture, _480 + _410);
            float _593 = abs(_475 - _554.w);
            bool _609 = _593 < 0.0500000007450580596923828125;
            bool _618;
            if (!_609)
            {
                _618 = abs(_482 - _570.w) < 0.0500000007450580596923828125;
            }
            else
            {
                _618 = _609;
            }
            float _1501;
            float _1502;
            _1502 = 0.0;
            _1501 = 0.0;
            for (float _1500 = 0.5; _1500 < 10.5; )
            {
                float _636 = _1500 + 1.0;
                vec2 _641 = _418 * _1500;
                vec2 _649 = _418 * _636;
                _1502 = max(abs(texture(Texture, _1720 + _649).x - texture(Texture, _1720 + _641).x) - 0.2150000035762786865234375, _1502);
                _1501 = max(abs(texture(Texture, _1720 - _641).x - texture(Texture, _1720 - _649).x) - 0.2150000035762786865234375, _1501);
                _1500 = _636;
                continue;
            }
            _1538 = min((clamp(min(_1501, _1502) * 8.0, 0.0, 1.0) * (clamp((max(_593, abs(_475 - _561.w)) - 0.100000001490116119384765625) * (-10.0), 0.0, 1.0) * float(_618))) * float((0.5 * (abs(_470 - _475) + abs(_475 - _482))) > (1.0 - (ntsc_fonts))), 0.625);
        }
        else
        {
            _1538 = 0.0;
        }
        vec4 _706 = texture(Texture, _1720);
        vec3 _707 = _706.xyz;
        vec2 _710 = _706.yz;
        bool _714 = (ntsc_rainbow1) > 0.5;
        bool _727;
        if (_714)
        {
            bool _726;
            if (!_450)
            {
                _726 = (ntsc_phase) == 5.0;
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
        vec3 _1740;
        if (_727)
        {
            float _1519;
            if (((ntsc_rainbow1) < 1.5) && (_1234 != 0.0))
            {
                _1519 = 0.0;
            }
            else
            {
                _1519 = (((ntsc_rainbow1) < 2.5) && (_540 != 0.0)) ? 0.0 : 1.0;
            }
            vec2 _780 = vec2(0.0, (abs(floor(mod((vec4(OrigTextureSize, 1.0 / OrigTextureSize)).y * RA_VARYING_0.y, 2.0)) - floor(mod(float((uint(FrameCount))), 2.0))) * (vec4(OrigTextureSize, 1.0 / OrigTextureSize)).w) * _1519);
            vec2 _783 = texture(Texture, _1720 - _780).yz;
            vec2 _791 = texture(Texture, _1720 + _780).yz;
            vec2 _796 = abs(_710 - _783);
            vec2 _813 = mix(_783, _791, _796 / max(_796 + abs(_710 - _791), vec2(1.0000000116860974230803549289703e-07)));
            vec3 _1663 = _707;
            _1663.y = _813.x;
            _1663.z = _813.y;
            _1740 = _1663;
        }
        else
        {
            _1740 = _707;
        }
        vec4 _823 = texture(Pass3Texture, _1530 - _358);
        vec4 _829 = texture(Pass3Texture, _1530 + _358);
        float _831 = min(_823.w, _829.w);
        vec3 _839 = abs(_396.xyz - _403.xyz);
        float _844 = _839.y;
        float _847 = _839.z;
        float _849 = _396.x;
        float _854 = _403.x;
        float _863 = max(max(max(_839.x, _844), max(_847, abs((_849 * _849) - (_854 * _854)))), _1538);
        float _877 = clamp((abs(_1740.x - _831) - 0.20000000298023223876953125) * (-10.0), 0.0, 1.0) * pow(_863, 0.125);
        float _881 = 0.02999999932944774627685546875 * _877;
        float _1294 = clamp((_863 - (0.0500000007450580596923828125 - _881)) / (0.375 + (_881 - (0.375 * _877))), 0.0, 1.0);
        float _899 = pow((_1294 + 0.100000001490116119384765625) * 0.90909087657928466796875, 0.25);
        float _904 = mix(_1294, _899, _1234);
        float _909 = mix(_1294, _899, _540);
        float _916 = abs((ntsc_sharp));
        vec3 _1747;
        if (_916 > 0.25)
        {
            float _932 = (((ntsc_sharp) > 0.25) ? _909 : _904) * (0.100000001490116119384765625 * _916);
            float _937 = mix(_1740.x, _831, _932);
            float _948 = sqrt(mix(_1740.x * _1740.x, _831 * _831, _932));
            float _955 = mix(sqrt(_1740.x), sqrt(_831), _932);
            float _958 = _955 * _955;
            float _963 = abs(_937 - _948);
            float _969 = abs(_937 - _958);
            float _982 = min((((_969 + 9.9999997473787516355514526367188e-06) * _948) + ((_963 + 9.9999997473787516355514526367188e-06) * _958)) / (1.9999999494757503271102905273438e-05 + (_963 + _969)), 1.0);
            vec3 _1675 = _1740;
            _1675.x = _982;
            _1675.x = min(_982, max((ntsc_shape) * _982, _1740.x));
            _1747 = _1675;
        }
        else
        {
            _1747 = _1740;
        }
        vec3 _1748;
        if (((ntsc_charp) + (ntsc_charp3)) > 0.25)
        {
            _358.x = _354;
            float _1021 = ((vec4(OrigTextureSize, 1.0 / OrigTextureSize)).x * (RA_VARYING_0.x + _354)) - 0.5;
            float _1583;
            if (_450)
            {
                _1583 = (ntsc_charp);
            }
            else
            {
                _1583 = (ntsc_charp3);
            }
            vec2 _1077 = vec2((floor(_1021) + 0.5) * (vec4(OrigTextureSize, 1.0 / OrigTextureSize)).z, _1720.y);
            vec2 _1106 = mix(_1747.yz, (mix(texture(Pass2Texture, _1077).xyz, texture(Pass2Texture, _1077 + (_358 * 16.0)).xyz, vec3(clamp((1.5 * fract(_1021)) - 0.25, 0.0, 1.0))) * mat3(vec3(0.29890000820159912109375, 0.58700001239776611328125, 0.114000000059604644775390625), vec3(0.595899999141693115234375, -0.2743999958038330078125, -0.3215999901294708251953125), vec3(0.21150000393390655517578125, -0.52289998531341552734375, 0.311399996280670166015625))).yz, vec2((mix(clamp((max(_844, _847) - 0.07500000298023223876953125) * 20.0000019073486328125, 0.0, 1.0), clamp((_863 - 0.014999999664723873138427734375) * 80.0, 0.0, 1.0), _540) * (((ntsc_sharp) > 0.25) ? _909 : _904)) * (0.100000001490116119384765625 * _1583)));
            vec3 _1687 = _1747;
            _1687.y = _1106.x;
            _1687.z = _1106.y;
            _1748 = _1687;
        }
        else
        {
            _1748 = _1747;
        }
        vec3 _1749;
        if (((RFNOISE1) + (RFNOISE2)) > 0.004999999888241291046142578125)
        {
            float _1125 = float((uint(FrameCount)));
            vec3 _1438 = vec3(RA_VARYING_0 * 16758.544921875, _1125);
            vec3 _1347 = vec3(vec2(fract(sin(dot(_1438, vec3(12.98980045318603515625, 78.233001708984375, 3.183000087738037109375))) * 43758.546875), fract(sin(dot(_1438, vec3(25.9796009063720703125, 14.11299991607666015625, 11.270999908447265625))) * 96321.9140625)) * 758.5452880859375, _1125);
            float _1352 = fract(sin(dot(_1347, vec3(12.98983478546142578125, 78.2334136962890625, 0.16452999413013458251953125))) * 43758.546875);
            float _1357 = fract(sin(dot(_1347, vec3(39.346790313720703125, 11.13523006439208984375, 83.155731201171875))) * 39459.32421875);
            float _1362 = fract(sin(dot(_1347, vec3(73.15691375732421875, 52.23503875732421875, 9.15196990966796875))) * 60493.84765625);
            float _1367 = 0.20000000298023223876953125 * _69;
            bool _1368 = abs(_1352 - 0.5) < _1367;
            float _1374 = 0.5 * _69;
            bool _1375 = abs(_1357 - 0.5) < _1374;
            bool _1382 = abs(_1362 - 0.5) < _1374;
            float _1401 = 0.5 - _1374;
            float _1649 = _1374 + _1374;
            float _1150 = mix(0.375, 1.0, pow(_1748.x, 0.20000000298023223876953125)) * (RFNOISE2);
            _1749 = vec3(clamp(_1748.x + ((RFNOISE1) * (((float(_1368) * clamp((_1352 - (0.5 - _1367)) / (_1367 + _1367), 0.0, 1.0)) * 0.660000026226043701171875) - (_1368 ? 0.3300000131130218505859375 : 0.0))), 0.0, 1.0), clamp(_1748.y + ((_1150 * (0.324999988079071044921875 + (1.3250000476837158203125 * abs(_1748.y)))) * ((float(_1375) * clamp((_1357 - _1401) / _1649, 0.0, 1.0)) - (_1375 ? 0.5 : 0.0))), -0.60000002384185791015625, 0.60000002384185791015625), clamp(_1748.z + ((_1150 * (0.324999988079071044921875 + (1.3250000476837158203125 * abs(_1748.z)))) * ((float(_1382) * clamp((_1362 - _1401) / _1649, 0.0, 1.0)) - (_1382 ? 0.5 : 0.0))), -0.5299999713897705078125, 0.5299999713897705078125));
        }
        else
        {
            _1749 = _1748;
        }
        vec3 _1707 = _1749;
        _1707.x = pow(_1749.x, 1.0 / (ntsc_gamma));
        bool _1201 = _1655 == 2.0;
        bool _1208;
        if (!_1201)
        {
            _1208 = _445;
        }
        else
        {
            _1208 = _1201;
        }
        FragColor = vec4(clamp(_1707 * mat3(vec3(1.0, 0.95599997043609619140625, 0.620999991893768310546875), vec3(1.0, -0.272000014781951904296875, -0.64740002155303955078125), vec3(1.0, -1.10599994659423828125, 1.70459997653961181640625)), vec3(0.0), vec3(1.0)), _1208 ? _909 : 1.0);
    }
}


#endif
