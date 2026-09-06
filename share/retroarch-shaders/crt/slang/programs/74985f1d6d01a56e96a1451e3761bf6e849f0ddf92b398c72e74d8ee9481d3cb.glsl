// Generated from crt/shaders/Advanced_CRT_shader_whkrmrgks0.slang. See slang/upstream for licence/source.
#version 120
#pragma parameter cus "CRT curvature" 0.15 0.0 1.0 0.01
#pragma parameter vstr "Vignette strength" 0.05 0.0 1.0 0.01
#pragma parameter marginv "Display margin" 0.02 0.0 0.1 0.005
#pragma parameter dts "Phosper size" 1.0 1.0 3.0 1.0
#pragma parameter AAz "De-moire conv iteration" 64.0 2.0 256.0 1.0
#pragma parameter vex "De-moire conv size" 2.0 0.0 4.0 0.1
#pragma parameter capa "Horizontal convolution size" 1.0 0.0 4.0 0.1
#pragma parameter capaiter "Horizontal convolution iterations" 5.0 1.0 20.0 1.0
#pragma parameter capashape "Horizontal convololution kernel shape" 3.0 1.0 40.0 0.1
#pragma parameter scl "Scnaline count, set 0 to match with input" 240.0 0.0 1080.0 1.0
#pragma parameter gma "Gamma correction" 1.0 0.1 4.0 0.1
#pragma parameter sling "line bleed" 2.0 1.0 2.0 0.1
#ifdef VERTEX

uniform mat4 MVPMatrix;
struct UBO
{
    mat4 MVP;
};



attribute vec4 VertexCoord;
varying vec2 RA_VARYING_2;
attribute vec2 TexCoord;

void main()
{
    gl_Position = (MVPMatrix) * VertexCoord;
    RA_VARYING_2 = TexCoord;
}


#endif
#ifdef FRAGMENT

uniform float AAz;
uniform vec2 OutputSize;
uniform vec2 TextureSize;
uniform float capa;
uniform float capaiter;
uniform float capashape;
uniform float cus;
uniform float dts;
uniform float gma;
uniform float marginv;
uniform float scl;
uniform float sling;
uniform float vex;
uniform float vstr;
struct UBO
{
    vec4 OutputSize;
    vec4 SourceSize;
};



struct Push
{
    float cus;
    float vstr;
    float marginv;
    float dts;
    float AAz;
    float vex;
    float capa;
    float capaiter;
    float capashape;
    float scl;
    float gma;
    float sling;
};



uniform sampler2D Texture;

varying vec2 RA_VARYING_2;

void main()
{
    float _262 = ((1.0 - min((scl), 1.0)) * (vec4(TextureSize, 1.0 / TextureSize)).y) + (scl);
    vec2 _272 = RA_VARYING_2 * (vec4(OutputSize, 1.0 / OutputSize)).xy;
    float _282 = (vec4(OutputSize, 1.0 / OutputSize)).x / (vec4(OutputSize, 1.0 / OutputSize)).y;
    vec2 _628 = ((RA_VARYING_2 * vec2(2.0)) - vec2(1.0)) * vec2(1.0 + (marginv), 1.0 + ((marginv) * _282));
    float _630 = _628.x;
    float _632 = _628.y;
    vec2 _655 = vec2(_630 / cos(abs(_632 * (cus)) * 1.57079637050628662109375), _632 / cos(abs((_630 * (cus)) * _282) * 1.57079637050628662109375));
    vec2 _658 = abs(_655) - vec2(1.0);
    float _660 = _658.x;
    float _662 = _658.y;
    vec2 _672 = (_655 + vec2(1.0)) * vec2(0.5);
    float _302 = _672.y * _262;
    float _306 = floor(_302 - 1.0) / _262;
    float _314 = floor(_302 + 1.0) / _262;
    float _320 = floor(_302);
    float _322 = _320 / _262;
    float _333 = (capaiter) * (-0.5);
    float _1136;
    float _1137;
    vec3 _1138;
    vec3 _1139;
    vec3 _1140;
    _1140 = vec3(0.0);
    _1139 = vec3(0.0);
    _1138 = vec3(0.0);
    _1137 = 0.0;
    _1136 = _333;
    float _342;
    for (;;)
    {
        _342 = (capaiter) * 0.5;
        if (_1136 <= _342)
        {
            float _681 = sin(pow((_1136 + _342) / (capaiter), (capashape)) * 6.283185482025146484375) + 1.0;
            float _377 = _672.x - ((((capa) / _262) * _1136) / _342);
            float _687 = _377 - floor(_377);
            _1140 += (texture2D(Texture, vec2(_687, _314)).xyz * _681);
            _1139 += (texture2D(Texture, vec2(_687, _322)).xyz * _681);
            _1138 += (texture2D(Texture, vec2(_687, _306)).xyz * _681);
            _1137 += _681;
            _1136 += 1.0;
            continue;
        }
        else
        {
            break;
        }
    }
    vec3 _443 = vec3(_1137);
    vec3 _444 = _1138 / _443;
    vec3 _448 = _1139 / _443;
    vec3 _452 = _1140 / _443;
    float _460 = (AAz) * (-0.5);
    float _1141;
    float _1142;
    vec3 _1143;
    _1143 = vec3(0.0);
    _1142 = 0.0;
    _1141 = _460;
    float _469;
    for (;;)
    {
        _469 = (AAz) * 0.5;
        if (_1141 <= _469)
        {
            float _481 = ((_469 - abs(_1141)) / (AAz)) * 0.5;
            float _764 = ((_302 - _320) + (((((_1141 / (AAz)) * 2.0) * (vex)) / (vec4(OutputSize, 1.0 / OutputSize)).y) * _262)) + 0.5;
            _1143 += ((((max(vec3((abs((_764 - floor(_764)) - 0.5) * 2.0) - 1.0) + (_448 * (sling)), vec3(0.0)) + max(vec3(-1.0) + (_452 * (sling)), vec3(0.0))) + max(vec3(-1.0) + (_444 * (sling)), vec3(0.0))) / vec3((sling) * 0.5)) * _481);
            _1142 += _481;
            _1141 += 1.0;
            continue;
        }
        else
        {
            break;
        }
    }
    vec2 _792 = vec2((dts));
    vec2 _793 = (_272 + (vec2(4.0, 0.0) * (dts))) / _792;
    float _806 = _793.x * 0.16666667163372039794921875;
    float _823 = _793.y * 0.5;
    vec2 _853 = _272 / _792;
    float _866 = _853.x * 0.16666667163372039794921875;
    float _883 = _853.y * 0.5;
    vec2 _913 = (_272 + (vec2(2.0, 0.0) * (dts))) / _792;
    float _926 = _913.x * 0.16666667163372039794921875;
    float _943 = _913.y * 0.5;
    vec2 _973 = (_272 + (vec2(7.0, 1.0) * (dts))) / _792;
    float _986 = _973.x * 0.16666667163372039794921875;
    float _1003 = _973.y * 0.5;
    vec2 _1033 = (_272 + (vec2(3.0, 1.0) * (dts))) / _792;
    float _1046 = _1033.x * 0.16666667163372039794921875;
    float _1063 = _1033.y * 0.5;
    vec2 _1093 = (_272 + (vec2(5.0, 1.0) * (dts))) / _792;
    float _1106 = _1093.x * 0.16666667163372039794921875;
    float _1123 = _1093.y * 0.5;
    vec3 _592 = pow(pow(pow((_1143 / vec3(_1142)) / vec3((sling)), vec3(0.5)), vec3(1.33333337306976318359375)), vec3((gma)));
    vec3 _606 = min(mix((_592 * (vec3(step(_806 - floor(_806), 0.3333333432674407958984375) * step(_823 - floor(_823), 0.5), step(_866 - floor(_866), 0.3333333432674407958984375) * step(_883 - floor(_883), 0.5), step(_926 - floor(_926), 0.3333333432674407958984375) * step(_943 - floor(_943), 0.5)) + vec3(step(_986 - floor(_986), 0.3333333432674407958984375) * step(_1003 - floor(_1003), 0.5), step(_1046 - floor(_1046), 0.3333333432674407958984375) * step(_1063 - floor(_1063), 0.5), step(_1106 - floor(_1106), 0.3333333432674407958984375) * step(_1123 - floor(_1123), 0.5)))) * 3.0, _592, _592), vec3(1.0)) * (step(max(_660, _662), 0.0) * pow(max(_660 * _662, 0.0), (vstr)));
    gl_FragData[0] = vec4(_606, 1.0);
}


#endif
