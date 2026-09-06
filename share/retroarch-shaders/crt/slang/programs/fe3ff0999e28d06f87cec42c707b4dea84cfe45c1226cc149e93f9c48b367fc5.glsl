// Generated from crt/shaders/crt-super-xbr/super-xbr-pass0.slang. See slang/upstream for licence/source.
#version 120
#pragma parameter MODE "Mode - Normal, Details, Adaptive" 1.0 0.0 2.0 1.0
#pragma parameter XBR_EDGE_STR_P0 "Xbr - Edge Strength p0" 1.0 0.0 5.0 0.5
#pragma parameter XBR_WEIGHT "Xbr - Filter Weight" 0.0 0.0 1.0 0.1
#pragma parameter XBR_EDGE_SHP "Adaptive Dynamic Edge Sharp" 0.4 0.0 3.0 0.1
#pragma parameter XBR_TEXTURE_SHP "Adaptive Static Edge Sharp" 1.0 0.0 2.0 0.1
#ifdef VERTEX

uniform mat4 MVPMatrix;
uniform vec2 TextureSize;
struct UBO
{
    mat4 MVP;
};



struct Push
{
    vec4 SourceSize;
};



attribute vec4 VertexCoord;
varying vec2 RA_VARYING_0;
attribute vec2 TexCoord;
varying vec4 RA_VARYING_1;
varying vec4 RA_VARYING_2;
varying vec4 RA_VARYING_3;
varying vec4 RA_VARYING_4;

void main()
{
    gl_Position = (MVPMatrix) * VertexCoord;
    RA_VARYING_0 = TexCoord * 1.00010001659393310546875;
    float _54 = -(vec4(TextureSize, 1.0 / TextureSize)).z;
    float _56 = -(vec4(TextureSize, 1.0 / TextureSize)).w;
    float _59 = 2.0 * (vec4(TextureSize, 1.0 / TextureSize)).z;
    float _61 = 2.0 * (vec4(TextureSize, 1.0 / TextureSize)).w;
    RA_VARYING_1 = RA_VARYING_0.xyxy + vec4(_54, _56, _59, _61);
    RA_VARYING_2 = RA_VARYING_0.xyxy + vec4(0.0, _56, (vec4(TextureSize, 1.0 / TextureSize)).z, _61);
    RA_VARYING_3 = RA_VARYING_0.xyxy + vec4(_54, 0.0, _59, (vec4(TextureSize, 1.0 / TextureSize)).w);
    RA_VARYING_4 = RA_VARYING_0.xyxy + vec4(0.0, 0.0, (vec4(TextureSize, 1.0 / TextureSize)).z, (vec4(TextureSize, 1.0 / TextureSize)).w);
}


#endif
#ifdef FRAGMENT

uniform float MODE;
uniform float XBR_EDGE_SHP;
uniform float XBR_EDGE_STR_P0;
uniform float XBR_TEXTURE_SHP;
uniform float XBR_WEIGHT;
struct Push
{
    float XBR_EDGE_STR_P0;
    float XBR_WEIGHT;
    float MODE;
    float XBR_EDGE_SHP;
    float XBR_TEXTURE_SHP;
};



uniform sampler2D Texture;

varying vec4 RA_VARYING_1;
varying vec4 RA_VARYING_2;
varying vec4 RA_VARYING_3;
varying vec4 RA_VARYING_4;

void main()
{
    float _302 = (XBR_WEIGHT) * 0.12963299453258514404296875;
    float _309 = (XBR_WEIGHT) * 0.087534002959728240966796875;
    vec4 _321 = texture2D(Texture, RA_VARYING_1.xy);
    vec3 _322 = _321.xyz;
    vec4 _327 = texture2D(Texture, RA_VARYING_1.zy);
    vec3 _328 = _327.xyz;
    vec4 _333 = texture2D(Texture, RA_VARYING_1.xw);
    vec3 _334 = _333.xyz;
    vec4 _339 = texture2D(Texture, RA_VARYING_1.zw);
    vec3 _340 = _339.xyz;
    vec4 _346 = texture2D(Texture, RA_VARYING_2.xy);
    vec3 _347 = _346.xyz;
    vec4 _352 = texture2D(Texture, RA_VARYING_2.zy);
    vec3 _353 = _352.xyz;
    vec4 _358 = texture2D(Texture, RA_VARYING_2.xw);
    vec3 _359 = _358.xyz;
    vec4 _364 = texture2D(Texture, RA_VARYING_2.zw);
    vec3 _365 = _364.xyz;
    vec4 _371 = texture2D(Texture, RA_VARYING_3.xy);
    vec3 _372 = _371.xyz;
    vec4 _377 = texture2D(Texture, RA_VARYING_3.zy);
    vec3 _378 = _377.xyz;
    vec4 _383 = texture2D(Texture, RA_VARYING_3.xw);
    vec3 _384 = _383.xyz;
    vec4 _389 = texture2D(Texture, RA_VARYING_3.zw);
    vec3 _390 = _389.xyz;
    vec4 _396 = texture2D(Texture, RA_VARYING_4.xy);
    vec3 _397 = _396.xyz;
    vec4 _402 = texture2D(Texture, RA_VARYING_4.zy);
    vec3 _403 = _402.xyz;
    vec4 _408 = texture2D(Texture, RA_VARYING_4.xw);
    vec3 _409 = _408.xyz;
    vec4 _414 = texture2D(Texture, RA_VARYING_4.zw);
    vec3 _415 = _414.xyz;
    float _1029 = dot(_347, vec3(0.2125999927520751953125, 0.715200006961822509765625, 0.072200000286102294921875));
    float _1033 = dot(_353, vec3(0.2125999927520751953125, 0.715200006961822509765625, 0.072200000286102294921875));
    float _1037 = dot(_372, vec3(0.2125999927520751953125, 0.715200006961822509765625, 0.072200000286102294921875));
    float _1041 = dot(_397, vec3(0.2125999927520751953125, 0.715200006961822509765625, 0.072200000286102294921875));
    float _1045 = dot(_403, vec3(0.2125999927520751953125, 0.715200006961822509765625, 0.072200000286102294921875));
    float _1049 = dot(_384, vec3(0.2125999927520751953125, 0.715200006961822509765625, 0.072200000286102294921875));
    float _1053 = dot(_409, vec3(0.2125999927520751953125, 0.715200006961822509765625, 0.072200000286102294921875));
    float _1057 = dot(_415, vec3(0.2125999927520751953125, 0.715200006961822509765625, 0.072200000286102294921875));
    float _1061 = dot(_390, vec3(0.2125999927520751953125, 0.715200006961822509765625, 0.072200000286102294921875));
    float _1065 = dot(_322, vec3(0.2125999927520751953125, 0.715200006961822509765625, 0.072200000286102294921875));
    float _1069 = dot(_365, vec3(0.2125999927520751953125, 0.715200006961822509765625, 0.072200000286102294921875));
    float _1073 = dot(_328, vec3(0.2125999927520751953125, 0.715200006961822509765625, 0.072200000286102294921875));
    float _1077 = dot(_359, vec3(0.2125999927520751953125, 0.715200006961822509765625, 0.072200000286102294921875));
    float _1081 = dot(_334, vec3(0.2125999927520751953125, 0.715200006961822509765625, 0.072200000286102294921875));
    float _1085 = dot(_378, vec3(0.2125999927520751953125, 0.715200006961822509765625, 0.072200000286102294921875));
    float _1089 = dot(_340, vec3(0.2125999927520751953125, 0.715200006961822509765625, 0.072200000286102294921875));
    float _1403 = abs(_1041 - _1057);
    float _563 = ((((((2.0 * (((abs(_1041 - _1033) + abs(_1041 - _1049)) + abs(_1057 - _1077)) + abs(_1057 - _1085))) + (abs(_1045 - _1073) + abs(_1081 - _1053))) + ((-1.0) * (abs(_1053 - _1073) + abs(_1081 - _1045)))) + (4.0 * abs(_1053 - _1045))) + ((-1.0) * (abs(_1049 - _1033) + abs(_1077 - _1085)))) + (abs(_1037 - _1029) + abs(_1069 - _1061))) - ((((((2.0 * (((abs(_1045 - _1061) + abs(_1045 - _1029)) + abs(_1053 - _1037)) + abs(_1053 - _1069))) + (abs(_1057 - _1089) + abs(_1065 - _1041))) + ((-1.0) * (abs(_1041 - _1089) + abs(_1065 - _1057)))) + (4.0 * _1403)) + ((-1.0) * (abs(_1029 - _1061) + abs(_1037 - _1069)))) + (abs(_1033 - _1085) + abs(_1049 - _1077)));
    float _1500 = abs(_1045 - _1057);
    float _1506 = abs(_1041 - _1053);
    float _1627 = abs(_1041 - _1045);
    float _1633 = abs(_1053 - _1057);
    vec4 _1749;
    vec3 _1755;
    vec3 _1756;
    if ((MODE) == 2.0)
    {
        float _697 = (smoothstep(0.0, 0.60000002384185791015625, max(max(_1627, max(_1403, max(_1506, abs(_1045 - _1053)))), max(_1500, _1633)) / (_1041 + 0.001000000047497451305389404296875)) * (XBR_EDGE_SHP)) + (XBR_TEXTURE_SHP);
        float _698 = _302 * _697;
        float _709 = _309 * _697;
        float _713 = -_698;
        float _716 = _698 + 0.5;
        float _724 = -_709;
        float _727 = _709 + 0.25;
        vec4 _732 = vec4(_724, _727, _727, _724);
        _1756 = (mat4x3((_322 + ((_353 + _347) * 2.0)) + _328, (_372 + ((_403 + _397) * 2.0)) + _378, (_384 + ((_415 + _409) * 2.0)) + _390, (_334 + ((_365 + _359) * 2.0)) + _340) * _732) * vec3(0.3333333432674407958984375);
        _1755 = (mat4x3((_322 + ((_372 + _384) * 2.0)) + _334, (_347 + ((_397 + _409) * 2.0)) + _359, (_353 + ((_403 + _415) * 2.0)) + _365, (_328 + ((_378 + _390) * 2.0)) + _340) * _732) * vec3(0.3333333432674407958984375);
        _1749 = vec4(_713, _716, _716, _713);
    }
    else
    {
        float _845 = (XBR_WEIGHT) * (-0.12963299453258514404296875);
        float _847 = _302 + 0.5;
        float _854 = (XBR_WEIGHT) * (-0.087534002959728240966796875);
        float _856 = _309 + 0.25;
        vec4 _861 = vec4(_854, _856, _856, _854);
        _1756 = mat4x3(_353 + _347, _403 + _397, _415 + _409, _365 + _359) * _861;
        _1755 = mat4x3(_372 + _384, _397 + _409, _403 + _415, _378 + _390) * _861;
        _1749 = vec4(_845, _847, _847, _845);
    }
    float _982 = step(0.0, (((4.0 * (_1500 + _1506)) + (2.0 * (((abs(_1045 - _1033) + abs(_1057 - _1069)) + abs(_1041 - _1029)) + abs(_1053 - _1077)))) + ((-1.0) * (((abs(_1045 - _1069) + abs(_1041 - _1077)) + abs(_1033 - _1057)) + abs(_1029 - _1053)))) - (((4.0 * (_1627 + _1633)) + (2.0 * (((abs(_1041 - _1037) + abs(_1045 - _1085)) + abs(_1053 - _1049)) + abs(_1057 - _1061)))) + ((-1.0) * (((abs(_1041 - _1085) + abs(_1053 - _1061)) + abs(_1037 - _1045)) + abs(_1049 - _1057)))));
    vec3 _1012 = clamp(mix(mix(mat4x3(vec3(_333.xyz), vec3(_408.xyz), vec3(_402.xyz), vec3(_327.xyz)) * _1749, mat4x3(vec3(_321.xyz), vec3(_396.xyz), vec3(_414.xyz), vec3(_339.xyz)) * _1749, vec3(step(0.0, _563))), mix(_1755, _1756, vec3(_982)), vec3(1.0 - smoothstep(0.0, (XBR_EDGE_STR_P0) + 9.9999999747524270787835121154785e-07, abs(_563)))), min(_397, min(_403, min(_409, _415))), max(_397, max(_403, max(_409, _415))));
    gl_FragData[0] = vec4(_1012, 1.0);
}


#endif
