// Generated from crt/shaders/crt-super-xbr/super-xbr-pass2.slang. See slang/upstream for licence/source.
#version 120
#pragma parameter MODE "Mode - Normal, Details, Adaptive" 1.0 0.0 2.0 1.0
#pragma parameter XBR_EDGE_STR_P2 "Xbr - Edge Strength p2" 1.0 0.0 5.0 0.5
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
    float _55 = (-2.0) * (vec4(TextureSize, 1.0 / TextureSize)).z;
    float _57 = (-2.0) * (vec4(TextureSize, 1.0 / TextureSize)).w;
    RA_VARYING_1 = RA_VARYING_0.xyxy + vec4(_55, _57, (vec4(TextureSize, 1.0 / TextureSize)).z, (vec4(TextureSize, 1.0 / TextureSize)).w);
    float _66 = -(vec4(TextureSize, 1.0 / TextureSize)).z;
    RA_VARYING_2 = RA_VARYING_0.xyxy + vec4(_66, _57, 0.0, (vec4(TextureSize, 1.0 / TextureSize)).w);
    float _79 = -(vec4(TextureSize, 1.0 / TextureSize)).w;
    RA_VARYING_3 = RA_VARYING_0.xyxy + vec4(_55, _79, (vec4(TextureSize, 1.0 / TextureSize)).z, 0.0);
    RA_VARYING_4 = RA_VARYING_0.xyxy + vec4(_66, _79, 0.0, 0.0);
}


#endif
#ifdef FRAGMENT

uniform float MODE;
uniform float XBR_EDGE_SHP;
uniform float XBR_EDGE_STR_P2;
uniform float XBR_TEXTURE_SHP;
struct Push
{
    float MODE;
    float XBR_EDGE_SHP;
    float XBR_TEXTURE_SHP;
    float XBR_EDGE_STR_P2;
};



uniform sampler2D Texture;

varying vec4 RA_VARYING_1;
varying vec4 RA_VARYING_2;
varying vec4 RA_VARYING_3;
varying vec4 RA_VARYING_4;

void main()
{
    bool _290 = (MODE) == 1.0;
    float _1749;
    float _1755;
    if (_290)
    {
        _1755 = 0.0;
        _1749 = 0.0;
    }
    else
    {
        bool _308 = (MODE) == 2.0;
        _1755 = _308 ? 0.0 : 1.0;
        _1749 = _308 ? 1.0 : 2.0;
    }
    float _1786 = _290 ? 0.0 : (-2.0);
    float _1787 = _290 ? 1.0 : 3.0;
    float _1788 = _290 ? 0.0 : 1.0;
    vec4 _325 = texture2D(Texture, RA_VARYING_1.xy);
    vec3 _326 = _325.xyz;
    vec4 _331 = texture2D(Texture, RA_VARYING_1.zy);
    vec3 _332 = _331.xyz;
    vec4 _337 = texture2D(Texture, RA_VARYING_1.xw);
    vec3 _338 = _337.xyz;
    vec4 _343 = texture2D(Texture, RA_VARYING_1.zw);
    vec3 _344 = _343.xyz;
    vec4 _350 = texture2D(Texture, RA_VARYING_2.xy);
    vec3 _351 = _350.xyz;
    vec4 _356 = texture2D(Texture, RA_VARYING_2.zy);
    vec3 _357 = _356.xyz;
    vec4 _362 = texture2D(Texture, RA_VARYING_2.xw);
    vec3 _363 = _362.xyz;
    vec4 _368 = texture2D(Texture, RA_VARYING_2.zw);
    vec3 _369 = _368.xyz;
    vec4 _375 = texture2D(Texture, RA_VARYING_3.xy);
    vec3 _376 = _375.xyz;
    vec4 _381 = texture2D(Texture, RA_VARYING_3.zy);
    vec3 _382 = _381.xyz;
    vec4 _387 = texture2D(Texture, RA_VARYING_3.xw);
    vec3 _388 = _387.xyz;
    vec4 _393 = texture2D(Texture, RA_VARYING_3.zw);
    vec3 _394 = _393.xyz;
    vec4 _400 = texture2D(Texture, RA_VARYING_4.xy);
    vec3 _401 = _400.xyz;
    vec4 _406 = texture2D(Texture, RA_VARYING_4.zy);
    vec3 _407 = _406.xyz;
    vec4 _412 = texture2D(Texture, RA_VARYING_4.xw);
    vec3 _413 = _412.xyz;
    vec4 _418 = texture2D(Texture, RA_VARYING_4.zw);
    vec3 _419 = _418.xyz;
    float _1029 = dot(_351, vec3(0.2125999927520751953125, 0.715200006961822509765625, 0.072200000286102294921875));
    float _1033 = dot(_357, vec3(0.2125999927520751953125, 0.715200006961822509765625, 0.072200000286102294921875));
    float _1037 = dot(_376, vec3(0.2125999927520751953125, 0.715200006961822509765625, 0.072200000286102294921875));
    float _1041 = dot(_401, vec3(0.2125999927520751953125, 0.715200006961822509765625, 0.072200000286102294921875));
    float _1045 = dot(_407, vec3(0.2125999927520751953125, 0.715200006961822509765625, 0.072200000286102294921875));
    float _1049 = dot(_388, vec3(0.2125999927520751953125, 0.715200006961822509765625, 0.072200000286102294921875));
    float _1053 = dot(_413, vec3(0.2125999927520751953125, 0.715200006961822509765625, 0.072200000286102294921875));
    float _1057 = dot(_419, vec3(0.2125999927520751953125, 0.715200006961822509765625, 0.072200000286102294921875));
    float _1061 = dot(_394, vec3(0.2125999927520751953125, 0.715200006961822509765625, 0.072200000286102294921875));
    float _1069 = dot(_369, vec3(0.2125999927520751953125, 0.715200006961822509765625, 0.072200000286102294921875));
    float _1077 = dot(_363, vec3(0.2125999927520751953125, 0.715200006961822509765625, 0.072200000286102294921875));
    float _1085 = dot(_382, vec3(0.2125999927520751953125, 0.715200006961822509765625, 0.072200000286102294921875));
    float _1403 = abs(_1041 - _1057);
    float _567 = (((((_1788 * (((abs(_1041 - _1033) + abs(_1041 - _1049)) + abs(_1057 - _1077)) + abs(_1057 - _1085))) + (_1749 * (abs(_1053 - dot(_332, vec3(0.2125999927520751953125, 0.715200006961822509765625, 0.072200000286102294921875))) + abs(dot(_338, vec3(0.2125999927520751953125, 0.715200006961822509765625, 0.072200000286102294921875)) - _1045)))) + (_1787 * abs(_1053 - _1045))) + (_1786 * (abs(_1049 - _1033) + abs(_1077 - _1085)))) + (_1755 * (abs(_1037 - _1029) + abs(_1069 - _1061)))) - (((((_1788 * (((abs(_1045 - _1061) + abs(_1045 - _1029)) + abs(_1053 - _1037)) + abs(_1053 - _1069))) + (_1749 * (abs(_1041 - dot(_344, vec3(0.2125999927520751953125, 0.715200006961822509765625, 0.072200000286102294921875))) + abs(dot(_326, vec3(0.2125999927520751953125, 0.715200006961822509765625, 0.072200000286102294921875)) - _1057)))) + (_1787 * _1403)) + (_1786 * (abs(_1029 - _1061) + abs(_1037 - _1069)))) + (_1755 * (abs(_1033 - _1085) + abs(_1049 - _1077))));
    float _1500 = abs(_1045 - _1057);
    float _1506 = abs(_1041 - _1053);
    float _1627 = abs(_1041 - _1045);
    float _1633 = abs(_1053 - _1057);
    vec4 _1765;
    vec3 _1771;
    vec3 _1772;
    if ((MODE) == 2.0)
    {
        float _698 = (smoothstep(0.0, 0.60000002384185791015625, max(max(_1627, max(_1403, max(_1506, abs(_1045 - _1053)))), max(_1500, _1633)) / (_1041 + 0.001000000047497451305389404296875)) * (XBR_EDGE_SHP)) + (XBR_TEXTURE_SHP);
        float _714 = _698 * (-0.12963299453258514404296875);
        float _717 = (0.12963299453258514404296875 * _698) + 0.5;
        float _725 = _698 * (-0.087534002959728240966796875);
        float _728 = (0.087534002959728240966796875 * _698) + 0.25;
        vec4 _733 = vec4(_725, _728, _728, _725);
        _1772 = (mat4x3((_326 + ((_357 + _351) * 2.0)) + _332, (_376 + ((_407 + _401) * 2.0)) + _382, (_388 + ((_419 + _413) * 2.0)) + _394, (_338 + ((_369 + _363) * 2.0)) + _344) * _733) * vec3(0.3333333432674407958984375);
        _1771 = (mat4x3((_326 + ((_376 + _388) * 2.0)) + _338, (_351 + ((_401 + _413) * 2.0)) + _363, (_357 + ((_407 + _419) * 2.0)) + _369, (_332 + ((_382 + _394) * 2.0)) + _344) * _733) * vec3(0.3333333432674407958984375);
        _1765 = vec4(_714, _717, _717, _714);
    }
    else
    {
        _1772 = mat4x3(_357 + _351, _407 + _401, _419 + _413, _369 + _363) * vec4(-0.087534002959728240966796875, 0.337534010410308837890625, 0.337534010410308837890625, -0.087534002959728240966796875);
        _1771 = mat4x3(_376 + _388, _401 + _413, _407 + _419, _382 + _394) * vec4(-0.087534002959728240966796875, 0.337534010410308837890625, 0.337534010410308837890625, -0.087534002959728240966796875);
        _1765 = vec4(-0.12963299453258514404296875, 0.629633009433746337890625, 0.629633009433746337890625, -0.12963299453258514404296875);
    }
    float _982 = step(0.0, (((_1787 * (_1500 + _1506)) + (_1788 * (((abs(_1045 - _1033) + abs(_1057 - _1069)) + abs(_1041 - _1029)) + abs(_1053 - _1077)))) + (_1749 * (((abs(_1045 - _1069) + abs(_1041 - _1077)) + abs(_1033 - _1057)) + abs(_1029 - _1053)))) - (((_1787 * (_1627 + _1633)) + (_1788 * (((abs(_1041 - _1037) + abs(_1045 - _1085)) + abs(_1053 - _1049)) + abs(_1057 - _1061)))) + (_1749 * (((abs(_1041 - _1085) + abs(_1053 - _1061)) + abs(_1037 - _1045)) + abs(_1049 - _1057)))));
    vec3 _1012 = clamp(mix(mix(mat4x3(vec3(_337.xyz), vec3(_412.xyz), vec3(_406.xyz), vec3(_331.xyz)) * _1765, mat4x3(vec3(_325.xyz), vec3(_400.xyz), vec3(_418.xyz), vec3(_343.xyz)) * _1765, vec3(step(0.0, _567))), mix(_1771, _1772, vec3(_982)), vec3(1.0 - smoothstep(0.0, (XBR_EDGE_STR_P2) + 9.9999999747524270787835121154785e-07, abs(_567)))), min(_401, min(_407, min(_413, _419))), max(_401, max(_407, max(_413, _419))));
    gl_FragData[0] = vec4(_1012, 1.0);
}


#endif
