// Generated from interpolation/shaders/jinc2.slang. See slang/upstream for licence/source.
#version 120
#pragma parameter JINC2_WINDOW_SINC "Window Sinc Param" 0.44 0.0 1.0 0.01
#pragma parameter JINC2_SINC "Sinc Param" 0.82 0.0 1.0 0.01
#pragma parameter JINC2_AR_STRENGTH "Anti-ringing Strength" 0.5 0.0 1.0 0.1
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
    RA_VARYING_0 = TexCoord * vec2(1.00010001659393310546875);
}


#endif
#ifdef FRAGMENT

uniform float JINC2_AR_STRENGTH;
uniform float JINC2_SINC;
uniform float JINC2_WINDOW_SINC;
uniform vec2 TextureSize;
struct Push
{
    vec4 SourceSize;
    float JINC2_WINDOW_SINC;
    float JINC2_SINC;
    float JINC2_AR_STRENGTH;
};



uniform sampler2D Texture;

varying vec2 RA_VARYING_0;

void main()
{
    vec2 _245 = RA_VARYING_0 * (vec4(TextureSize, 1.0 / TextureSize)).xy;
    vec2 _251 = floor(_245 - vec2(0.5));
    vec2 _252 = _251 + vec2(0.5);
    vec2 _726 = (_251 + vec2(-0.5)) - _245;
    float _730 = sqrt(dot(_726, _726));
    vec2 _736 = (_251 + vec2(0.5, -0.5)) - _245;
    float _740 = sqrt(dot(_736, _736));
    vec2 _746 = (_251 + vec2(1.5, -0.5)) - _245;
    float _750 = sqrt(dot(_746, _746));
    vec2 _756 = (_251 + vec2(2.5, -0.5)) - _245;
    float _760 = sqrt(dot(_756, _756));
    float _1507;
    if (_730 == 0.0)
    {
        _1507 = 9.86960506439208984375 * ((JINC2_WINDOW_SINC) * (JINC2_SINC));
    }
    else
    {
        _1507 = (sin(_730 * ((JINC2_WINDOW_SINC) * 3.1415927410125732421875)) * sin(_730 * ((JINC2_SINC) * 3.1415927410125732421875))) / (_730 * _730);
    }
    float _1508;
    if (_740 == 0.0)
    {
        _1508 = 9.86960506439208984375 * ((JINC2_WINDOW_SINC) * (JINC2_SINC));
    }
    else
    {
        _1508 = (sin(_740 * ((JINC2_WINDOW_SINC) * 3.1415927410125732421875)) * sin(_740 * ((JINC2_SINC) * 3.1415927410125732421875))) / (_740 * _740);
    }
    float _1509;
    if (_750 == 0.0)
    {
        _1509 = 9.86960506439208984375 * ((JINC2_WINDOW_SINC) * (JINC2_SINC));
    }
    else
    {
        _1509 = (sin(_750 * ((JINC2_WINDOW_SINC) * 3.1415927410125732421875)) * sin(_750 * ((JINC2_SINC) * 3.1415927410125732421875))) / (_750 * _750);
    }
    float _1510;
    if (_760 == 0.0)
    {
        _1510 = 9.86960506439208984375 * ((JINC2_WINDOW_SINC) * (JINC2_SINC));
    }
    else
    {
        _1510 = (sin(_760 * ((JINC2_WINDOW_SINC) * 3.1415927410125732421875)) * sin(_760 * ((JINC2_SINC) * 3.1415927410125732421875))) / (_760 * _760);
    }
    vec4 _1805 = vec4(_1507, _1508, _1509, _1510);
    vec2 _918 = (_251 + vec2(-0.5, 0.5)) - _245;
    float _922 = sqrt(dot(_918, _918));
    vec2 _928 = _252 - _245;
    float _932 = sqrt(dot(_928, _928));
    vec2 _938 = (_251 + vec2(1.5, 0.5)) - _245;
    float _942 = sqrt(dot(_938, _938));
    vec2 _948 = (_251 + vec2(2.5, 0.5)) - _245;
    float _952 = sqrt(dot(_948, _948));
    float _1523;
    if (_922 == 0.0)
    {
        _1523 = 9.86960506439208984375 * ((JINC2_WINDOW_SINC) * (JINC2_SINC));
    }
    else
    {
        _1523 = (sin(_922 * ((JINC2_WINDOW_SINC) * 3.1415927410125732421875)) * sin(_922 * ((JINC2_SINC) * 3.1415927410125732421875))) / (_922 * _922);
    }
    float _1524;
    if (_932 == 0.0)
    {
        _1524 = 9.86960506439208984375 * ((JINC2_WINDOW_SINC) * (JINC2_SINC));
    }
    else
    {
        _1524 = (sin(_932 * ((JINC2_WINDOW_SINC) * 3.1415927410125732421875)) * sin(_932 * ((JINC2_SINC) * 3.1415927410125732421875))) / (_932 * _932);
    }
    float _1525;
    if (_942 == 0.0)
    {
        _1525 = 9.86960506439208984375 * ((JINC2_WINDOW_SINC) * (JINC2_SINC));
    }
    else
    {
        _1525 = (sin(_942 * ((JINC2_WINDOW_SINC) * 3.1415927410125732421875)) * sin(_942 * ((JINC2_SINC) * 3.1415927410125732421875))) / (_942 * _942);
    }
    float _1526;
    if (_952 == 0.0)
    {
        _1526 = 9.86960506439208984375 * ((JINC2_WINDOW_SINC) * (JINC2_SINC));
    }
    else
    {
        _1526 = (sin(_952 * ((JINC2_WINDOW_SINC) * 3.1415927410125732421875)) * sin(_952 * ((JINC2_SINC) * 3.1415927410125732421875))) / (_952 * _952);
    }
    vec4 _1806 = vec4(_1523, _1524, _1525, _1526);
    vec2 _1110 = (_251 + vec2(-0.5, 1.5)) - _245;
    float _1114 = sqrt(dot(_1110, _1110));
    vec2 _1120 = (_251 + vec2(0.5, 1.5)) - _245;
    float _1124 = sqrt(dot(_1120, _1120));
    vec2 _1130 = (_251 + vec2(1.5)) - _245;
    float _1134 = sqrt(dot(_1130, _1130));
    vec2 _1140 = (_251 + vec2(2.5, 1.5)) - _245;
    float _1144 = sqrt(dot(_1140, _1140));
    float _1547;
    if (_1114 == 0.0)
    {
        _1547 = 9.86960506439208984375 * ((JINC2_WINDOW_SINC) * (JINC2_SINC));
    }
    else
    {
        _1547 = (sin(_1114 * ((JINC2_WINDOW_SINC) * 3.1415927410125732421875)) * sin(_1114 * ((JINC2_SINC) * 3.1415927410125732421875))) / (_1114 * _1114);
    }
    float _1548;
    if (_1124 == 0.0)
    {
        _1548 = 9.86960506439208984375 * ((JINC2_WINDOW_SINC) * (JINC2_SINC));
    }
    else
    {
        _1548 = (sin(_1124 * ((JINC2_WINDOW_SINC) * 3.1415927410125732421875)) * sin(_1124 * ((JINC2_SINC) * 3.1415927410125732421875))) / (_1124 * _1124);
    }
    float _1549;
    if (_1134 == 0.0)
    {
        _1549 = 9.86960506439208984375 * ((JINC2_WINDOW_SINC) * (JINC2_SINC));
    }
    else
    {
        _1549 = (sin(_1134 * ((JINC2_WINDOW_SINC) * 3.1415927410125732421875)) * sin(_1134 * ((JINC2_SINC) * 3.1415927410125732421875))) / (_1134 * _1134);
    }
    float _1550;
    if (_1144 == 0.0)
    {
        _1550 = 9.86960506439208984375 * ((JINC2_WINDOW_SINC) * (JINC2_SINC));
    }
    else
    {
        _1550 = (sin(_1144 * ((JINC2_WINDOW_SINC) * 3.1415927410125732421875)) * sin(_1144 * ((JINC2_SINC) * 3.1415927410125732421875))) / (_1144 * _1144);
    }
    vec4 _1807 = vec4(_1547, _1548, _1549, _1550);
    vec2 _1302 = (_251 + vec2(-0.5, 2.5)) - _245;
    float _1306 = sqrt(dot(_1302, _1302));
    vec2 _1312 = (_251 + vec2(0.5, 2.5)) - _245;
    float _1316 = sqrt(dot(_1312, _1312));
    vec2 _1322 = (_251 + vec2(1.5, 2.5)) - _245;
    float _1326 = sqrt(dot(_1322, _1322));
    vec2 _1332 = (_251 + vec2(2.5)) - _245;
    float _1336 = sqrt(dot(_1332, _1332));
    float _1567;
    if (_1306 == 0.0)
    {
        _1567 = 9.86960506439208984375 * ((JINC2_WINDOW_SINC) * (JINC2_SINC));
    }
    else
    {
        _1567 = (sin(_1306 * ((JINC2_WINDOW_SINC) * 3.1415927410125732421875)) * sin(_1306 * ((JINC2_SINC) * 3.1415927410125732421875))) / (_1306 * _1306);
    }
    float _1568;
    if (_1316 == 0.0)
    {
        _1568 = 9.86960506439208984375 * ((JINC2_WINDOW_SINC) * (JINC2_SINC));
    }
    else
    {
        _1568 = (sin(_1316 * ((JINC2_WINDOW_SINC) * 3.1415927410125732421875)) * sin(_1316 * ((JINC2_SINC) * 3.1415927410125732421875))) / (_1316 * _1316);
    }
    float _1569;
    if (_1326 == 0.0)
    {
        _1569 = 9.86960506439208984375 * ((JINC2_WINDOW_SINC) * (JINC2_SINC));
    }
    else
    {
        _1569 = (sin(_1326 * ((JINC2_WINDOW_SINC) * 3.1415927410125732421875)) * sin(_1326 * ((JINC2_SINC) * 3.1415927410125732421875))) / (_1326 * _1326);
    }
    float _1570;
    if (_1336 == 0.0)
    {
        _1570 = 9.86960506439208984375 * ((JINC2_WINDOW_SINC) * (JINC2_SINC));
    }
    else
    {
        _1570 = (sin(_1336 * ((JINC2_WINDOW_SINC) * 3.1415927410125732421875)) * sin(_1336 * ((JINC2_SINC) * 3.1415927410125732421875))) / (_1336 * _1336);
    }
    vec4 _1808 = vec4(_1567, _1568, _1569, _1570);
    vec2 _416 = vec2(1.0, 0.0) * (vec4(TextureSize, 1.0 / TextureSize)).zw;
    vec2 _421 = vec2(0.0, 1.0) * (vec4(TextureSize, 1.0 / TextureSize)).zw;
    vec2 _426 = _252 * (vec4(TextureSize, 1.0 / TextureSize)).zw;
    vec2 _435 = _426 - _416;
    vec2 _451 = _426 + _416;
    vec2 _461 = _426 + (_416 * 2.0);
    vec4 _476 = texture2D(Texture, _426);
    vec3 _477 = _476.xyz;
    vec4 _483 = texture2D(Texture, _451);
    vec3 _484 = _483.xyz;
    vec4 _507 = texture2D(Texture, _426 + _421);
    vec3 _508 = _507.xyz;
    vec4 _516 = texture2D(Texture, _451 + _421);
    vec3 _517 = _516.xyz;
    vec2 _534 = _421 * 2.0;
    vec3 _690 = (((mat4x3(vec3(texture2D(Texture, _435 - _421).xyz), vec3(texture2D(Texture, _426 - _421).xyz), vec3(texture2D(Texture, _451 - _421).xyz), vec3(texture2D(Texture, _461 - _421).xyz)) * _1805) + (mat4x3(vec3(texture2D(Texture, _435).xyz), vec3(_476.xyz), vec3(_483.xyz), vec3(texture2D(Texture, _461).xyz)) * _1806)) + (mat4x3(vec3(texture2D(Texture, _435 + _421).xyz), vec3(_507.xyz), vec3(_516.xyz), vec3(texture2D(Texture, _461 + _421).xyz)) * _1807)) + (mat4x3(vec3(texture2D(Texture, _435 + _534).xyz), vec3(texture2D(Texture, _426 + _534).xyz), vec3(texture2D(Texture, _451 + _534).xyz), vec3(texture2D(Texture, _461 + _534).xyz)) * _1808);
    vec3 _697 = _690 / vec3(dot(mat4(_1805, _1806, _1807, _1808) * vec4(1.0), vec4(1.0)));
    gl_FragData[0] = vec4(mix(_697, clamp(_697, min(_477, min(_484, min(_508, _517))), max(_477, max(_484, max(_508, _517)))), vec3((JINC2_AR_STRENGTH))), 1.0);
}


#endif
