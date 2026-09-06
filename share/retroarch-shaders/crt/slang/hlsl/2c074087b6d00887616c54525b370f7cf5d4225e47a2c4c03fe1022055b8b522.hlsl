// Generated from crt/shaders/crt-super-xbr/super-xbr-pass2.slang. See slang/upstream for licence/source.
cbuffer Push : register(b1)
{
    float params_MODE : packoffset(c3.y);
    float params_XBR_EDGE_SHP : packoffset(c3.z);
    float params_XBR_TEXTURE_SHP : packoffset(c3.w);
    float params_XBR_EDGE_STR_P2 : packoffset(c4);
};

Texture2D<float4> Source : register(t2);
SamplerState _Source_sampler : register(s2);

static float4 t1;
static float4 t2;
static float4 t3;
static float4 t4;
static float4 FragColor;

struct SPIRV_Cross_Input
{
    float4 t1 : TEXCOORD1;
    float4 t2 : TEXCOORD2;
    float4 t3 : TEXCOORD3;
    float4 t4 : TEXCOORD4;
};

struct SPIRV_Cross_Output
{
    float4 FragColor : SV_Target0;
};

void frag_main()
{
    bool _290 = params_MODE == 1.0f;
    float _1749;
    float _1755;
    if (_290)
    {
        _1755 = 0.0f;
        _1749 = 0.0f;
    }
    else
    {
        bool _308 = params_MODE == 2.0f;
        _1755 = _308 ? 0.0f : 1.0f;
        _1749 = _308 ? 1.0f : 2.0f;
    }
    float _1786 = _290 ? 0.0f : (-2.0f);
    float _1787 = _290 ? 1.0f : 3.0f;
    float _1788 = _290 ? 0.0f : 1.0f;
    float4 _325 = Source.Sample(_Source_sampler, t1.xy);
    float3 _326 = _325.xyz;
    float4 _331 = Source.Sample(_Source_sampler, t1.zy);
    float3 _332 = _331.xyz;
    float4 _337 = Source.Sample(_Source_sampler, t1.xw);
    float3 _338 = _337.xyz;
    float4 _343 = Source.Sample(_Source_sampler, t1.zw);
    float3 _344 = _343.xyz;
    float4 _350 = Source.Sample(_Source_sampler, t2.xy);
    float3 _351 = _350.xyz;
    float4 _356 = Source.Sample(_Source_sampler, t2.zy);
    float3 _357 = _356.xyz;
    float4 _362 = Source.Sample(_Source_sampler, t2.xw);
    float3 _363 = _362.xyz;
    float4 _368 = Source.Sample(_Source_sampler, t2.zw);
    float3 _369 = _368.xyz;
    float4 _375 = Source.Sample(_Source_sampler, t3.xy);
    float3 _376 = _375.xyz;
    float4 _381 = Source.Sample(_Source_sampler, t3.zy);
    float3 _382 = _381.xyz;
    float4 _387 = Source.Sample(_Source_sampler, t3.xw);
    float3 _388 = _387.xyz;
    float4 _393 = Source.Sample(_Source_sampler, t3.zw);
    float3 _394 = _393.xyz;
    float4 _400 = Source.Sample(_Source_sampler, t4.xy);
    float3 _401 = _400.xyz;
    float4 _406 = Source.Sample(_Source_sampler, t4.zy);
    float3 _407 = _406.xyz;
    float4 _412 = Source.Sample(_Source_sampler, t4.xw);
    float3 _413 = _412.xyz;
    float4 _418 = Source.Sample(_Source_sampler, t4.zw);
    float3 _419 = _418.xyz;
    float _1029 = dot(_351, float3(0.2125999927520751953125f, 0.715200006961822509765625f, 0.072200000286102294921875f));
    float _1033 = dot(_357, float3(0.2125999927520751953125f, 0.715200006961822509765625f, 0.072200000286102294921875f));
    float _1037 = dot(_376, float3(0.2125999927520751953125f, 0.715200006961822509765625f, 0.072200000286102294921875f));
    float _1041 = dot(_401, float3(0.2125999927520751953125f, 0.715200006961822509765625f, 0.072200000286102294921875f));
    float _1045 = dot(_407, float3(0.2125999927520751953125f, 0.715200006961822509765625f, 0.072200000286102294921875f));
    float _1049 = dot(_388, float3(0.2125999927520751953125f, 0.715200006961822509765625f, 0.072200000286102294921875f));
    float _1053 = dot(_413, float3(0.2125999927520751953125f, 0.715200006961822509765625f, 0.072200000286102294921875f));
    float _1057 = dot(_419, float3(0.2125999927520751953125f, 0.715200006961822509765625f, 0.072200000286102294921875f));
    float _1061 = dot(_394, float3(0.2125999927520751953125f, 0.715200006961822509765625f, 0.072200000286102294921875f));
    float _1069 = dot(_369, float3(0.2125999927520751953125f, 0.715200006961822509765625f, 0.072200000286102294921875f));
    float _1077 = dot(_363, float3(0.2125999927520751953125f, 0.715200006961822509765625f, 0.072200000286102294921875f));
    float _1085 = dot(_382, float3(0.2125999927520751953125f, 0.715200006961822509765625f, 0.072200000286102294921875f));
    float _1403 = abs(_1041 - _1057);
    float _567 = (((((_1788 * (((abs(_1041 - _1033) + abs(_1041 - _1049)) + abs(_1057 - _1077)) + abs(_1057 - _1085))) + (_1749 * (abs(_1053 - dot(_332, float3(0.2125999927520751953125f, 0.715200006961822509765625f, 0.072200000286102294921875f))) + abs(dot(_338, float3(0.2125999927520751953125f, 0.715200006961822509765625f, 0.072200000286102294921875f)) - _1045)))) + (_1787 * abs(_1053 - _1045))) + (_1786 * (abs(_1049 - _1033) + abs(_1077 - _1085)))) + (_1755 * (abs(_1037 - _1029) + abs(_1069 - _1061)))) - (((((_1788 * (((abs(_1045 - _1061) + abs(_1045 - _1029)) + abs(_1053 - _1037)) + abs(_1053 - _1069))) + (_1749 * (abs(_1041 - dot(_344, float3(0.2125999927520751953125f, 0.715200006961822509765625f, 0.072200000286102294921875f))) + abs(dot(_326, float3(0.2125999927520751953125f, 0.715200006961822509765625f, 0.072200000286102294921875f)) - _1057)))) + (_1787 * _1403)) + (_1786 * (abs(_1029 - _1061) + abs(_1037 - _1069)))) + (_1755 * (abs(_1033 - _1085) + abs(_1049 - _1077))));
    float _1500 = abs(_1045 - _1057);
    float _1506 = abs(_1041 - _1053);
    float _1627 = abs(_1041 - _1045);
    float _1633 = abs(_1053 - _1057);
    float4 _1765;
    float3 _1771;
    float3 _1772;
    if (params_MODE == 2.0f)
    {
        float _698 = (smoothstep(0.0f, 0.60000002384185791015625f, max(max(_1627, max(_1403, max(_1506, abs(_1045 - _1053)))), max(_1500, _1633)) / (_1041 + 0.001000000047497451305389404296875f)) * params_XBR_EDGE_SHP) + params_XBR_TEXTURE_SHP;
        float _714 = _698 * (-0.12963299453258514404296875f);
        float _717 = (0.12963299453258514404296875f * _698) + 0.5f;
        float _725 = _698 * (-0.087534002959728240966796875f);
        float _728 = (0.087534002959728240966796875f * _698) + 0.25f;
        float4 _733 = float4(_725, _728, _728, _725);
        _1772 = mul(_733, float4x3((_326 + ((_357 + _351) * 2.0f)) + _332, (_376 + ((_407 + _401) * 2.0f)) + _382, (_388 + ((_419 + _413) * 2.0f)) + _394, (_338 + ((_369 + _363) * 2.0f)) + _344)) * 0.3333333432674407958984375f.xxx;
        _1771 = mul(_733, float4x3((_326 + ((_376 + _388) * 2.0f)) + _338, (_351 + ((_401 + _413) * 2.0f)) + _363, (_357 + ((_407 + _419) * 2.0f)) + _369, (_332 + ((_382 + _394) * 2.0f)) + _344)) * 0.3333333432674407958984375f.xxx;
        _1765 = float4(_714, _717, _717, _714);
    }
    else
    {
        _1772 = mul(float4(-0.087534002959728240966796875f, 0.337534010410308837890625f, 0.337534010410308837890625f, -0.087534002959728240966796875f), float4x3(_357 + _351, _407 + _401, _419 + _413, _369 + _363));
        _1771 = mul(float4(-0.087534002959728240966796875f, 0.337534010410308837890625f, 0.337534010410308837890625f, -0.087534002959728240966796875f), float4x3(_376 + _388, _401 + _413, _407 + _419, _382 + _394));
        _1765 = float4(-0.12963299453258514404296875f, 0.629633009433746337890625f, 0.629633009433746337890625f, -0.12963299453258514404296875f);
    }
    float _982 = step(0.0f, (((_1787 * (_1500 + _1506)) + (_1788 * (((abs(_1045 - _1033) + abs(_1057 - _1069)) + abs(_1041 - _1029)) + abs(_1053 - _1077)))) + (_1749 * (((abs(_1045 - _1069) + abs(_1041 - _1077)) + abs(_1033 - _1057)) + abs(_1029 - _1053)))) - (((_1787 * (_1627 + _1633)) + (_1788 * (((abs(_1041 - _1037) + abs(_1045 - _1085)) + abs(_1053 - _1049)) + abs(_1057 - _1061)))) + (_1749 * (((abs(_1041 - _1085) + abs(_1053 - _1061)) + abs(_1037 - _1045)) + abs(_1049 - _1057)))));
    float3 _1012 = clamp(lerp(lerp(mul(_1765, float4x3(float3(_337.xyz), float3(_412.xyz), float3(_406.xyz), float3(_331.xyz))), mul(_1765, float4x3(float3(_325.xyz), float3(_400.xyz), float3(_418.xyz), float3(_343.xyz))), step(0.0f, _567).xxx), lerp(_1771, _1772, _982.xxx), (1.0f - smoothstep(0.0f, params_XBR_EDGE_STR_P2 + 9.9999999747524270787835121154785e-07f, abs(_567))).xxx), min(_401, min(_407, min(_413, _419))), max(_401, max(_407, max(_413, _419))));
    FragColor = float4(_1012, 1.0f);
}

SPIRV_Cross_Output main(SPIRV_Cross_Input stage_input)
{
    t1 = stage_input.t1;
    t2 = stage_input.t2;
    t3 = stage_input.t3;
    t4 = stage_input.t4;
    frag_main();
    SPIRV_Cross_Output stage_output;
    stage_output.FragColor = FragColor;
    return stage_output;
}
