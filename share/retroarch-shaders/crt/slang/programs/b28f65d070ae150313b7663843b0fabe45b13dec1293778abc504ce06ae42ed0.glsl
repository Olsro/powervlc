// Generated from crt/shaders/tvout-tweaks.slang. See slang/upstream for licence/source.
#version 120
#pragma parameter TVOUT_RESOLUTION "TVOut Signal Resolution" 256.0 0.0 1024.0 32.0 // default, minimum, maximum, optional step
#pragma parameter TVOUT_COMPOSITE_CONNECTION "TVOut Composite Enable" 0.0 0.0 1.0 1.0
#pragma parameter TVOUT_TV_COLOR_LEVELS "TVOut TV Color Levels Enable" 0.0 0.0 1.0 1.0
#pragma parameter TVOUT_RESOLUTION_Y "TVOut Luma (Y) Resolution" 256.0 0.0 1024.0 32.0
#pragma parameter TVOUT_RESOLUTION_I "TVOut Chroma (I) Resolution" 83.2 0.0 256.0 8.0
#pragma parameter TVOUT_RESOLUTION_Q "TVOut Chroma (Q) Resolution" 25.6 0.0 256.0 8.0
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

uniform float TVOUT_COMPOSITE_CONNECTION;
uniform float TVOUT_RESOLUTION;
uniform float TVOUT_RESOLUTION_I;
uniform float TVOUT_RESOLUTION_Q;
uniform float TVOUT_RESOLUTION_Y;
uniform float TVOUT_TV_COLOR_LEVELS;
uniform vec2 TextureSize;
struct Push
{
    vec4 SourceSize;
    float TVOUT_RESOLUTION;
    float TVOUT_COMPOSITE_CONNECTION;
    float TVOUT_TV_COLOR_LEVELS;
    float TVOUT_RESOLUTION_Y;
    float TVOUT_RESOLUTION_I;
    float TVOUT_RESOLUTION_Q;
};



uniform sampler2D Texture;

varying vec2 RA_VARYING_0;

void main()
{
    float _120 = fract((RA_VARYING_0.x * (vec4(TextureSize, 1.0 / TextureSize)).x) - 0.5);
    float _130 = _120 - (-1.0);
    bool _133 = (TVOUT_COMPOSITE_CONNECTION) > 0.5;
    vec3 _2198;
    if (_133)
    {
        vec4 _151 = texture2D(Texture, vec2(RA_VARYING_0.x - (_130 * (vec4(TextureSize, 1.0 / TextureSize)).z), RA_VARYING_0.y));
        vec3 _153 = _151.xyz;
        vec3 _2042;
        do
        {
            if ((TVOUT_TV_COLOR_LEVELS) > 0.5)
            {
                if (_133)
                {
                    _2042 = vec3(clamp((_151.x - 0.064453125) * 1.16363632678985595703125, 0.0, 1.0), clamp((_151.y - 0.064453125) * 1.14285719394683837890625, 0.0, 1.0), clamp((_151.z - 0.064453125) * 1.14285719394683837890625, 0.0, 1.0));
                    break;
                }
                else
                {
                    _2042 = clamp(((_153 - vec3(0.064453125)) * 256.0) * vec3(0.0045454544015228748321533203125), vec3(0.0), vec3(1.0));
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
        _2198 = _2042 * mat3(vec3(0.2989999949932098388671875, 0.58700001239776611328125, 0.114000000059604644775390625), vec3(0.595715999603271484375, -0.2744530141353607177734375, -0.3212629854679107666015625), vec3(0.211456000804901123046875, -0.52259099483489990234375, 0.311134994029998779296875));
    }
    else
    {
        vec4 _168 = texture2D(Texture, vec2(RA_VARYING_0.x - (_130 * (vec4(TextureSize, 1.0 / TextureSize)).z), RA_VARYING_0.y));
        vec3 _170 = _168.xyz;
        vec3 _2041;
        do
        {
            if ((TVOUT_TV_COLOR_LEVELS) > 0.5)
            {
                if (_133)
                {
                    _2041 = vec3(clamp((_168.x - 0.064453125) * 1.16363632678985595703125, 0.0, 1.0), clamp((_168.y - 0.064453125) * 1.14285719394683837890625, 0.0, 1.0), clamp((_168.z - 0.064453125) * 1.14285719394683837890625, 0.0, 1.0));
                    break;
                }
                else
                {
                    _2041 = clamp(((_170 - vec3(0.064453125)) * 256.0) * vec3(0.0045454544015228748321533203125), vec3(0.0), vec3(1.0));
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
    vec3 _2076;
    if (_133)
    {
        float _184 = (TVOUT_RESOLUTION_Y) * (vec4(TextureSize, 1.0 / TextureSize)).z;
        float _185 = 3.1415927410125732421875 * _184;
        float _187 = abs(_130);
        float _188 = _187 + 0.5;
        float _193 = 1.0 / _184;
        float _195 = _185 * min(_188, _193);
        float _220 = _187 - 0.5;
        float _233 = _185 * min(max(_220, (-1.0) / _184), _193);
        float _267 = (TVOUT_RESOLUTION_I) * (vec4(TextureSize, 1.0 / TextureSize)).z;
        float _268 = 3.1415927410125732421875 * _267;
        float _276 = 1.0 / _267;
        float _278 = _268 * min(_188, _276);
        float _316 = _268 * min(max(_220, (-1.0) / _267), _276);
        float _349 = (TVOUT_RESOLUTION_Q) * (vec4(TextureSize, 1.0 / TextureSize)).z;
        float _350 = 3.1415927410125732421875 * _349;
        float _358 = 1.0 / _349;
        float _360 = _350 * min(_188, _358);
        float _398 = _350 * min(max(_220, (-1.0) / _349), _358);
        _2076 = vec3(_2198.x * ((((_195 + sin(_195)) - _233) - sin(_233)) * 0.15915493667125701904296875), _2198.y * ((((_278 + sin(_278)) - _316) - sin(_316)) * 0.15915493667125701904296875), _2198.z * ((((_360 + sin(_360)) - _398) - sin(_398)) * 0.15915493667125701904296875));
    }
    else
    {
        float _434 = (TVOUT_RESOLUTION) * (vec4(TextureSize, 1.0 / TextureSize)).z;
        float _435 = 3.1415927410125732421875 * _434;
        float _437 = abs(_130);
        float _443 = 1.0 / _434;
        float _445 = _435 * min(_437 + 0.5, _443);
        float _483 = _435 * min(max(_437 - 0.5, (-1.0) / _434), _443);
        _2076 = _2198 * ((((_445 + sin(_445)) - _483) - sin(_483)) * 0.15915493667125701904296875);
    }
    vec3 _2199;
    if (_133)
    {
        vec4 _529 = texture2D(Texture, vec2(RA_VARYING_0.x - (_120 * (vec4(TextureSize, 1.0 / TextureSize)).z), RA_VARYING_0.y));
        vec3 _531 = _529.xyz;
        vec3 _2062;
        do
        {
            if ((TVOUT_TV_COLOR_LEVELS) > 0.5)
            {
                if (_133)
                {
                    _2062 = vec3(clamp((_529.x - 0.064453125) * 1.16363632678985595703125, 0.0, 1.0), clamp((_529.y - 0.064453125) * 1.14285719394683837890625, 0.0, 1.0), clamp((_529.z - 0.064453125) * 1.14285719394683837890625, 0.0, 1.0));
                    break;
                }
                else
                {
                    _2062 = clamp(((_531 - vec3(0.064453125)) * 256.0) * vec3(0.0045454544015228748321533203125), vec3(0.0), vec3(1.0));
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
        _2199 = _2062 * mat3(vec3(0.2989999949932098388671875, 0.58700001239776611328125, 0.114000000059604644775390625), vec3(0.595715999603271484375, -0.2744530141353607177734375, -0.3212629854679107666015625), vec3(0.211456000804901123046875, -0.52259099483489990234375, 0.311134994029998779296875));
    }
    else
    {
        vec4 _546 = texture2D(Texture, vec2(RA_VARYING_0.x - (_120 * (vec4(TextureSize, 1.0 / TextureSize)).z), RA_VARYING_0.y));
        vec3 _548 = _546.xyz;
        vec3 _2061;
        do
        {
            if ((TVOUT_TV_COLOR_LEVELS) > 0.5)
            {
                if (_133)
                {
                    _2061 = vec3(clamp((_546.x - 0.064453125) * 1.16363632678985595703125, 0.0, 1.0), clamp((_546.y - 0.064453125) * 1.14285719394683837890625, 0.0, 1.0), clamp((_546.z - 0.064453125) * 1.14285719394683837890625, 0.0, 1.0));
                    break;
                }
                else
                {
                    _2061 = clamp(((_548 - vec3(0.064453125)) * 256.0) * vec3(0.0045454544015228748321533203125), vec3(0.0), vec3(1.0));
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
    vec3 _2101;
    if (_133)
    {
        float _560 = (TVOUT_RESOLUTION_Y) * (vec4(TextureSize, 1.0 / TextureSize)).z;
        float _561 = 3.1415927410125732421875 * _560;
        float _563 = abs(_120);
        float _564 = _563 + 0.5;
        float _569 = 1.0 / _560;
        float _571 = _561 * min(_564, _569);
        float _596 = _563 - 0.5;
        float _609 = _561 * min(max(_596, (-1.0) / _560), _569);
        float _641 = (TVOUT_RESOLUTION_I) * (vec4(TextureSize, 1.0 / TextureSize)).z;
        float _642 = 3.1415927410125732421875 * _641;
        float _650 = 1.0 / _641;
        float _652 = _642 * min(_564, _650);
        float _690 = _642 * min(max(_596, (-1.0) / _641), _650);
        float _722 = (TVOUT_RESOLUTION_Q) * (vec4(TextureSize, 1.0 / TextureSize)).z;
        float _723 = 3.1415927410125732421875 * _722;
        float _731 = 1.0 / _722;
        float _733 = _723 * min(_564, _731);
        float _771 = _723 * min(max(_596, (-1.0) / _722), _731);
        _2101 = _2076 + vec3(_2199.x * ((((_571 + sin(_571)) - _609) - sin(_609)) * 0.15915493667125701904296875), _2199.y * ((((_652 + sin(_652)) - _690) - sin(_690)) * 0.15915493667125701904296875), _2199.z * ((((_733 + sin(_733)) - _771) - sin(_771)) * 0.15915493667125701904296875));
    }
    else
    {
        float _806 = (TVOUT_RESOLUTION) * (vec4(TextureSize, 1.0 / TextureSize)).z;
        float _807 = 3.1415927410125732421875 * _806;
        float _809 = abs(_120);
        float _815 = 1.0 / _806;
        float _817 = _807 * min(_809 + 0.5, _815);
        float _855 = _807 * min(max(_809 - 0.5, (-1.0) / _806), _815);
        _2101 = _2076 + (_2199 * ((((_817 + sin(_817)) - _855) - sin(_855)) * 0.15915493667125701904296875));
    }
    float _885 = _120 - 1.0;
    vec3 _2200;
    if (_133)
    {
        vec4 _901 = texture2D(Texture, vec2(RA_VARYING_0.x - (_885 * (vec4(TextureSize, 1.0 / TextureSize)).z), RA_VARYING_0.y));
        vec3 _903 = _901.xyz;
        vec3 _2087;
        do
        {
            if ((TVOUT_TV_COLOR_LEVELS) > 0.5)
            {
                if (_133)
                {
                    _2087 = vec3(clamp((_901.x - 0.064453125) * 1.16363632678985595703125, 0.0, 1.0), clamp((_901.y - 0.064453125) * 1.14285719394683837890625, 0.0, 1.0), clamp((_901.z - 0.064453125) * 1.14285719394683837890625, 0.0, 1.0));
                    break;
                }
                else
                {
                    _2087 = clamp(((_903 - vec3(0.064453125)) * 256.0) * vec3(0.0045454544015228748321533203125), vec3(0.0), vec3(1.0));
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
        _2200 = _2087 * mat3(vec3(0.2989999949932098388671875, 0.58700001239776611328125, 0.114000000059604644775390625), vec3(0.595715999603271484375, -0.2744530141353607177734375, -0.3212629854679107666015625), vec3(0.211456000804901123046875, -0.52259099483489990234375, 0.311134994029998779296875));
    }
    else
    {
        vec4 _918 = texture2D(Texture, vec2(RA_VARYING_0.x - (_885 * (vec4(TextureSize, 1.0 / TextureSize)).z), RA_VARYING_0.y));
        vec3 _920 = _918.xyz;
        vec3 _2086;
        do
        {
            if ((TVOUT_TV_COLOR_LEVELS) > 0.5)
            {
                if (_133)
                {
                    _2086 = vec3(clamp((_918.x - 0.064453125) * 1.16363632678985595703125, 0.0, 1.0), clamp((_918.y - 0.064453125) * 1.14285719394683837890625, 0.0, 1.0), clamp((_918.z - 0.064453125) * 1.14285719394683837890625, 0.0, 1.0));
                    break;
                }
                else
                {
                    _2086 = clamp(((_920 - vec3(0.064453125)) * 256.0) * vec3(0.0045454544015228748321533203125), vec3(0.0), vec3(1.0));
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
    vec3 _2126;
    if (_133)
    {
        float _932 = (TVOUT_RESOLUTION_Y) * (vec4(TextureSize, 1.0 / TextureSize)).z;
        float _933 = 3.1415927410125732421875 * _932;
        float _935 = abs(_885);
        float _936 = _935 + 0.5;
        float _941 = 1.0 / _932;
        float _943 = _933 * min(_936, _941);
        float _968 = _935 - 0.5;
        float _981 = _933 * min(max(_968, (-1.0) / _932), _941);
        float _1013 = (TVOUT_RESOLUTION_I) * (vec4(TextureSize, 1.0 / TextureSize)).z;
        float _1014 = 3.1415927410125732421875 * _1013;
        float _1022 = 1.0 / _1013;
        float _1024 = _1014 * min(_936, _1022);
        float _1062 = _1014 * min(max(_968, (-1.0) / _1013), _1022);
        float _1094 = (TVOUT_RESOLUTION_Q) * (vec4(TextureSize, 1.0 / TextureSize)).z;
        float _1095 = 3.1415927410125732421875 * _1094;
        float _1103 = 1.0 / _1094;
        float _1105 = _1095 * min(_936, _1103);
        float _1143 = _1095 * min(max(_968, (-1.0) / _1094), _1103);
        _2126 = _2101 + vec3(_2200.x * ((((_943 + sin(_943)) - _981) - sin(_981)) * 0.15915493667125701904296875), _2200.y * ((((_1024 + sin(_1024)) - _1062) - sin(_1062)) * 0.15915493667125701904296875), _2200.z * ((((_1105 + sin(_1105)) - _1143) - sin(_1143)) * 0.15915493667125701904296875));
    }
    else
    {
        float _1178 = (TVOUT_RESOLUTION) * (vec4(TextureSize, 1.0 / TextureSize)).z;
        float _1179 = 3.1415927410125732421875 * _1178;
        float _1181 = abs(_885);
        float _1187 = 1.0 / _1178;
        float _1189 = _1179 * min(_1181 + 0.5, _1187);
        float _1227 = _1179 * min(max(_1181 - 0.5, (-1.0) / _1178), _1187);
        _2126 = _2101 + (_2200 * ((((_1189 + sin(_1189)) - _1227) - sin(_1227)) * 0.15915493667125701904296875));
    }
    float _1258 = _120 - 2.0;
    vec3 _2201;
    if (_133)
    {
        vec4 _1274 = texture2D(Texture, vec2(RA_VARYING_0.x - (_1258 * (vec4(TextureSize, 1.0 / TextureSize)).z), RA_VARYING_0.y));
        vec3 _1276 = _1274.xyz;
        vec3 _2112;
        do
        {
            if ((TVOUT_TV_COLOR_LEVELS) > 0.5)
            {
                if (_133)
                {
                    _2112 = vec3(clamp((_1274.x - 0.064453125) * 1.16363632678985595703125, 0.0, 1.0), clamp((_1274.y - 0.064453125) * 1.14285719394683837890625, 0.0, 1.0), clamp((_1274.z - 0.064453125) * 1.14285719394683837890625, 0.0, 1.0));
                    break;
                }
                else
                {
                    _2112 = clamp(((_1276 - vec3(0.064453125)) * 256.0) * vec3(0.0045454544015228748321533203125), vec3(0.0), vec3(1.0));
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
        _2201 = _2112 * mat3(vec3(0.2989999949932098388671875, 0.58700001239776611328125, 0.114000000059604644775390625), vec3(0.595715999603271484375, -0.2744530141353607177734375, -0.3212629854679107666015625), vec3(0.211456000804901123046875, -0.52259099483489990234375, 0.311134994029998779296875));
    }
    else
    {
        vec4 _1291 = texture2D(Texture, vec2(RA_VARYING_0.x - (_1258 * (vec4(TextureSize, 1.0 / TextureSize)).z), RA_VARYING_0.y));
        vec3 _1293 = _1291.xyz;
        vec3 _2111;
        do
        {
            if ((TVOUT_TV_COLOR_LEVELS) > 0.5)
            {
                if (_133)
                {
                    _2111 = vec3(clamp((_1291.x - 0.064453125) * 1.16363632678985595703125, 0.0, 1.0), clamp((_1291.y - 0.064453125) * 1.14285719394683837890625, 0.0, 1.0), clamp((_1291.z - 0.064453125) * 1.14285719394683837890625, 0.0, 1.0));
                    break;
                }
                else
                {
                    _2111 = clamp(((_1293 - vec3(0.064453125)) * 256.0) * vec3(0.0045454544015228748321533203125), vec3(0.0), vec3(1.0));
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
    vec3 _2128;
    if (_133)
    {
        float _1305 = (TVOUT_RESOLUTION_Y) * (vec4(TextureSize, 1.0 / TextureSize)).z;
        float _1306 = 3.1415927410125732421875 * _1305;
        float _1308 = abs(_1258);
        float _1309 = _1308 + 0.5;
        float _1314 = 1.0 / _1305;
        float _1316 = _1306 * min(_1309, _1314);
        float _1341 = _1308 - 0.5;
        float _1354 = _1306 * min(max(_1341, (-1.0) / _1305), _1314);
        float _1386 = (TVOUT_RESOLUTION_I) * (vec4(TextureSize, 1.0 / TextureSize)).z;
        float _1387 = 3.1415927410125732421875 * _1386;
        float _1395 = 1.0 / _1386;
        float _1397 = _1387 * min(_1309, _1395);
        float _1435 = _1387 * min(max(_1341, (-1.0) / _1386), _1395);
        float _1467 = (TVOUT_RESOLUTION_Q) * (vec4(TextureSize, 1.0 / TextureSize)).z;
        float _1468 = 3.1415927410125732421875 * _1467;
        float _1476 = 1.0 / _1467;
        float _1478 = _1468 * min(_1309, _1476);
        float _1516 = _1468 * min(max(_1341, (-1.0) / _1467), _1476);
        _2128 = _2126 + vec3(_2201.x * ((((_1316 + sin(_1316)) - _1354) - sin(_1354)) * 0.15915493667125701904296875), _2201.y * ((((_1397 + sin(_1397)) - _1435) - sin(_1435)) * 0.15915493667125701904296875), _2201.z * ((((_1478 + sin(_1478)) - _1516) - sin(_1516)) * 0.15915493667125701904296875));
    }
    else
    {
        float _1551 = (TVOUT_RESOLUTION) * (vec4(TextureSize, 1.0 / TextureSize)).z;
        float _1552 = 3.1415927410125732421875 * _1551;
        float _1554 = abs(_1258);
        float _1560 = 1.0 / _1551;
        float _1562 = _1552 * min(_1554 + 0.5, _1560);
        float _1600 = _1552 * min(max(_1554 - 0.5, (-1.0) / _1551), _1560);
        _2128 = _2126 + (_2201 * ((((_1562 + sin(_1562)) - _1600) - sin(_1600)) * 0.15915493667125701904296875));
    }
    vec3 _2145;
    if (_133)
    {
        _2145 = _2128 * mat3(vec3(1.0, 0.9563000202178955078125, 0.620999991893768310546875), vec3(1.0, -0.2721000015735626220703125, -0.64740002155303955078125), vec3(1.0, -1.10699999332427978515625, 1.70459997653961181640625));
    }
    else
    {
        _2145 = _2128;
    }
    gl_FragData[0] = vec4(_2145, 1.0);
}


#endif
