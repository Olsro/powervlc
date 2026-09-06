// Generated from crt/shaders/crt-super-xbr/super-xbr-pass0.slang. See slang/upstream for licence/source.
cbuffer Push : register(b1)
{
    float params_XBR_EDGE_STR_P0 : packoffset(c3.y);
    float params_XBR_WEIGHT : packoffset(c3.z);
    float params_MODE : packoffset(c4);
    float params_XBR_EDGE_SHP : packoffset(c4.y);
    float params_XBR_TEXTURE_SHP : packoffset(c4.z);
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
    float _302 = params_XBR_WEIGHT * 0.12963299453258514404296875f;
    float _309 = params_XBR_WEIGHT * 0.087534002959728240966796875f;
    float4 _321 = Source.Sample(_Source_sampler, t1.xy);
    float3 _322 = _321.xyz;
    float4 _327 = Source.Sample(_Source_sampler, t1.zy);
    float3 _328 = _327.xyz;
    float4 _333 = Source.Sample(_Source_sampler, t1.xw);
    float3 _334 = _333.xyz;
    float4 _339 = Source.Sample(_Source_sampler, t1.zw);
    float3 _340 = _339.xyz;
    float4 _346 = Source.Sample(_Source_sampler, t2.xy);
    float3 _347 = _346.xyz;
    float4 _352 = Source.Sample(_Source_sampler, t2.zy);
    float3 _353 = _352.xyz;
    float4 _358 = Source.Sample(_Source_sampler, t2.xw);
    float3 _359 = _358.xyz;
    float4 _364 = Source.Sample(_Source_sampler, t2.zw);
    float3 _365 = _364.xyz;
    float4 _371 = Source.Sample(_Source_sampler, t3.xy);
    float3 _372 = _371.xyz;
    float4 _377 = Source.Sample(_Source_sampler, t3.zy);
    float3 _378 = _377.xyz;
    float4 _383 = Source.Sample(_Source_sampler, t3.xw);
    float3 _384 = _383.xyz;
    float4 _389 = Source.Sample(_Source_sampler, t3.zw);
    float3 _390 = _389.xyz;
    float4 _396 = Source.Sample(_Source_sampler, t4.xy);
    float3 _397 = _396.xyz;
    float4 _402 = Source.Sample(_Source_sampler, t4.zy);
    float3 _403 = _402.xyz;
    float4 _408 = Source.Sample(_Source_sampler, t4.xw);
    float3 _409 = _408.xyz;
    float4 _414 = Source.Sample(_Source_sampler, t4.zw);
    float3 _415 = _414.xyz;
    float _1029 = dot(_347, float3(0.2125999927520751953125f, 0.715200006961822509765625f, 0.072200000286102294921875f));
    float _1033 = dot(_353, float3(0.2125999927520751953125f, 0.715200006961822509765625f, 0.072200000286102294921875f));
    float _1037 = dot(_372, float3(0.2125999927520751953125f, 0.715200006961822509765625f, 0.072200000286102294921875f));
    float _1041 = dot(_397, float3(0.2125999927520751953125f, 0.715200006961822509765625f, 0.072200000286102294921875f));
    float _1045 = dot(_403, float3(0.2125999927520751953125f, 0.715200006961822509765625f, 0.072200000286102294921875f));
    float _1049 = dot(_384, float3(0.2125999927520751953125f, 0.715200006961822509765625f, 0.072200000286102294921875f));
    float _1053 = dot(_409, float3(0.2125999927520751953125f, 0.715200006961822509765625f, 0.072200000286102294921875f));
    float _1057 = dot(_415, float3(0.2125999927520751953125f, 0.715200006961822509765625f, 0.072200000286102294921875f));
    float _1061 = dot(_390, float3(0.2125999927520751953125f, 0.715200006961822509765625f, 0.072200000286102294921875f));
    float _1065 = dot(_322, float3(0.2125999927520751953125f, 0.715200006961822509765625f, 0.072200000286102294921875f));
    float _1069 = dot(_365, float3(0.2125999927520751953125f, 0.715200006961822509765625f, 0.072200000286102294921875f));
    float _1073 = dot(_328, float3(0.2125999927520751953125f, 0.715200006961822509765625f, 0.072200000286102294921875f));
    float _1077 = dot(_359, float3(0.2125999927520751953125f, 0.715200006961822509765625f, 0.072200000286102294921875f));
    float _1081 = dot(_334, float3(0.2125999927520751953125f, 0.715200006961822509765625f, 0.072200000286102294921875f));
    float _1085 = dot(_378, float3(0.2125999927520751953125f, 0.715200006961822509765625f, 0.072200000286102294921875f));
    float _1089 = dot(_340, float3(0.2125999927520751953125f, 0.715200006961822509765625f, 0.072200000286102294921875f));
    float _1403 = abs(_1041 - _1057);
    float _563 = ((((((2.0f * (((abs(_1041 - _1033) + abs(_1041 - _1049)) + abs(_1057 - _1077)) + abs(_1057 - _1085))) + (abs(_1045 - _1073) + abs(_1081 - _1053))) + ((-1.0f) * (abs(_1053 - _1073) + abs(_1081 - _1045)))) + (4.0f * abs(_1053 - _1045))) + ((-1.0f) * (abs(_1049 - _1033) + abs(_1077 - _1085)))) + (abs(_1037 - _1029) + abs(_1069 - _1061))) - ((((((2.0f * (((abs(_1045 - _1061) + abs(_1045 - _1029)) + abs(_1053 - _1037)) + abs(_1053 - _1069))) + (abs(_1057 - _1089) + abs(_1065 - _1041))) + ((-1.0f) * (abs(_1041 - _1089) + abs(_1065 - _1057)))) + (4.0f * _1403)) + ((-1.0f) * (abs(_1029 - _1061) + abs(_1037 - _1069)))) + (abs(_1033 - _1085) + abs(_1049 - _1077)));
    float _1500 = abs(_1045 - _1057);
    float _1506 = abs(_1041 - _1053);
    float _1627 = abs(_1041 - _1045);
    float _1633 = abs(_1053 - _1057);
    float4 _1749;
    float3 _1755;
    float3 _1756;
    if (params_MODE == 2.0f)
    {
        float _697 = (smoothstep(0.0f, 0.60000002384185791015625f, max(max(_1627, max(_1403, max(_1506, abs(_1045 - _1053)))), max(_1500, _1633)) / (_1041 + 0.001000000047497451305389404296875f)) * params_XBR_EDGE_SHP) + params_XBR_TEXTURE_SHP;
        float _698 = _302 * _697;
        float _709 = _309 * _697;
        float _713 = -_698;
        float _716 = _698 + 0.5f;
        float _724 = -_709;
        float _727 = _709 + 0.25f;
        float4 _732 = float4(_724, _727, _727, _724);
        _1756 = mul(_732, float4x3((_322 + ((_353 + _347) * 2.0f)) + _328, (_372 + ((_403 + _397) * 2.0f)) + _378, (_384 + ((_415 + _409) * 2.0f)) + _390, (_334 + ((_365 + _359) * 2.0f)) + _340)) * 0.3333333432674407958984375f.xxx;
        _1755 = mul(_732, float4x3((_322 + ((_372 + _384) * 2.0f)) + _334, (_347 + ((_397 + _409) * 2.0f)) + _359, (_353 + ((_403 + _415) * 2.0f)) + _365, (_328 + ((_378 + _390) * 2.0f)) + _340)) * 0.3333333432674407958984375f.xxx;
        _1749 = float4(_713, _716, _716, _713);
    }
    else
    {
        float _845 = params_XBR_WEIGHT * (-0.12963299453258514404296875f);
        float _847 = _302 + 0.5f;
        float _854 = params_XBR_WEIGHT * (-0.087534002959728240966796875f);
        float _856 = _309 + 0.25f;
        float4 _861 = float4(_854, _856, _856, _854);
        _1756 = mul(_861, float4x3(_353 + _347, _403 + _397, _415 + _409, _365 + _359));
        _1755 = mul(_861, float4x3(_372 + _384, _397 + _409, _403 + _415, _378 + _390));
        _1749 = float4(_845, _847, _847, _845);
    }
    float _982 = step(0.0f, (((4.0f * (_1500 + _1506)) + (2.0f * (((abs(_1045 - _1033) + abs(_1057 - _1069)) + abs(_1041 - _1029)) + abs(_1053 - _1077)))) + ((-1.0f) * (((abs(_1045 - _1069) + abs(_1041 - _1077)) + abs(_1033 - _1057)) + abs(_1029 - _1053)))) - (((4.0f * (_1627 + _1633)) + (2.0f * (((abs(_1041 - _1037) + abs(_1045 - _1085)) + abs(_1053 - _1049)) + abs(_1057 - _1061)))) + ((-1.0f) * (((abs(_1041 - _1085) + abs(_1053 - _1061)) + abs(_1037 - _1045)) + abs(_1049 - _1057)))));
    float3 _1012 = clamp(lerp(lerp(mul(_1749, float4x3(float3(_333.xyz), float3(_408.xyz), float3(_402.xyz), float3(_327.xyz))), mul(_1749, float4x3(float3(_321.xyz), float3(_396.xyz), float3(_414.xyz), float3(_339.xyz))), step(0.0f, _563).xxx), lerp(_1755, _1756, _982.xxx), (1.0f - smoothstep(0.0f, params_XBR_EDGE_STR_P0 + 9.9999999747524270787835121154785e-07f, abs(_563))).xxx), min(_397, min(_403, min(_409, _415))), max(_397, max(_403, max(_409, _415))));
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
