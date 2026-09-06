// Generated from crt/shaders/crt-mattias.slang. See slang/upstream for licence/source.
cbuffer Push : register(b1)
{
    float4 params_OutputSize : packoffset(c2);
    uint params_FrameCount : packoffset(c3);
    float params_CURVATURE : packoffset(c3.y);
    float params_SCANSPEED : packoffset(c3.z);
};

Texture2D<float4> Source : register(t2);
SamplerState _Source_sampler : register(s2);

static float2 vTexCoord;
static float4 FragColor;

struct SPIRV_Cross_Input
{
    float2 vTexCoord : TEXCOORD0;
};

struct SPIRV_Cross_Output
{
    float4 FragColor : SV_Target0;
};

float mod(float x, float y)
{
    return x - y * floor(x / y);
}

float2 mod(float2 x, float2 y)
{
    return x - y * floor(x / y);
}

float3 mod(float3 x, float3 y)
{
    return x - y * floor(x / y);
}

float4 mod(float4 x, float4 y)
{
    return x - y * floor(x / y);
}

void frag_main()
{
    float2 _444 = vTexCoord * params_OutputSize.xy;
    float2 _918 = ((vTexCoord - 0.5f.xx) * 2.0f) * 1.10000002384185791015625f;
    float _927 = _918.x * (1.0f + pow(abs(_918.y) * 0.20000000298023223876953125f, 2.0f));
    float2 _459 = lerp(vTexCoord, (((float2(_927, _918.y * (1.0f + pow(abs(_927) * 0.25f, 2.0f))) * 0.5f.xx) + 0.5f.xx) * 0.920000016689300537109375f) + 0.039999999105930328369140625f.xx, params_CURVATURE.xx);
    float _533 = _459.x;
    float _537 = _459.y;
    float2 _539 = float2(_533 + 0.000899999984540045261383056640625f, _537 + 0.000899999984540045261383056640625f);
    float4 _983 = params_OutputSize.x.xxxx;
    float4 _984 = float4(-2.400000095367431640625f, -1.2000000476837158203125f, 1.2000000476837158203125f, 2.400000095367431640625f) / _983;
    float4 _989 = params_OutputSize.y.xxxx;
    float4 _990 = float4(-2.400000095367431640625f, -1.2000000476837158203125f, 1.2000000476837158203125f, 2.400000095367431640625f) / _989;
    float _993 = _984.x;
    float _995 = _990.x;
    float2 _996 = float2(_993, _995);
    float _1004 = _984.y;
    float2 _1007 = float2(_1004, _995);
    float2 _1016 = float2(0.0f, _995);
    float _1024 = _984.z;
    float2 _1027 = float2(_1024, _995);
    float _1035 = _984.w;
    float2 _1038 = float2(_1035, _995);
    float _1048 = _990.y;
    float2 _1049 = float2(_993, _1048);
    float2 _1060 = float2(_1004, _1048);
    float2 _1069 = float2(0.0f, _1048);
    float2 _1080 = float2(_1024, _1048);
    float2 _1091 = float2(_1035, _1048);
    float2 _1100 = float2(_993, 0.0f);
    float3 _1105 = ((((((((((pow(Source.Sample(_Source_sampler, _539 + _996).xyz, 2.2000000476837158203125f.xxx) * 0.003659999929368495941162109375f) + (pow(Source.Sample(_Source_sampler, _539 + _1007).xyz, 2.2000000476837158203125f.xxx) * 0.01465000025928020477294921875f)) + (pow(Source.Sample(_Source_sampler, _539 + _1016).xyz, 2.2000000476837158203125f.xxx) * 0.0256399996578693389892578125f)) + (pow(Source.Sample(_Source_sampler, _539 + _1027).xyz, 2.2000000476837158203125f.xxx) * 0.01465000025928020477294921875f)) + (pow(Source.Sample(_Source_sampler, _539 + _1038).xyz, 2.2000000476837158203125f.xxx) * 0.003659999929368495941162109375f)) + (pow(Source.Sample(_Source_sampler, _539 + _1049).xyz, 2.2000000476837158203125f.xxx) * 0.01465000025928020477294921875f)) + (pow(Source.Sample(_Source_sampler, _539 + _1060).xyz, 2.2000000476837158203125f.xxx) * 0.058609999716281890869140625f)) + (pow(Source.Sample(_Source_sampler, _539 + _1069).xyz, 2.2000000476837158203125f.xxx) * 0.09523999691009521484375f)) + (pow(Source.Sample(_Source_sampler, _539 + _1080).xyz, 2.2000000476837158203125f.xxx) * 0.058609999716281890869140625f)) + (pow(Source.Sample(_Source_sampler, _539 + _1091).xyz, 2.2000000476837158203125f.xxx) * 0.01465000025928020477294921875f)) + (pow(Source.Sample(_Source_sampler, _539 + _1100).xyz, 2.2000000476837158203125f.xxx) * 0.0256399996578693389892578125f);
    float2 _1109 = float2(_1004, 0.0f);
    float2 _1124 = float2(_1024, 0.0f);
    float2 _1133 = float2(_1035, 0.0f);
    float _1143 = _990.z;
    float2 _1144 = float2(_993, _1143);
    float2 _1155 = float2(_1004, _1143);
    float2 _1164 = float2(0.0f, _1143);
    float2 _1175 = float2(_1024, _1143);
    float2 _1186 = float2(_1035, _1143);
    float _1196 = _990.w;
    float2 _1197 = float2(_993, _1196);
    float2 _1208 = float2(_1004, _1196);
    float3 _1213 = ((((((((((_1105 + (pow(Source.Sample(_Source_sampler, _539 + _1109).xyz, 2.2000000476837158203125f.xxx) * 0.09523999691009521484375f)) + (pow(Source.Sample(_Source_sampler, _539).xyz, 2.2000000476837158203125f.xxx) * 0.15017999708652496337890625f)) + (pow(Source.Sample(_Source_sampler, _539 + _1124).xyz, 2.2000000476837158203125f.xxx) * 0.09523999691009521484375f)) + (pow(Source.Sample(_Source_sampler, _539 + _1133).xyz, 2.2000000476837158203125f.xxx) * 0.0256399996578693389892578125f)) + (pow(Source.Sample(_Source_sampler, _539 + _1144).xyz, 2.2000000476837158203125f.xxx) * 0.01465000025928020477294921875f)) + (pow(Source.Sample(_Source_sampler, _539 + _1155).xyz, 2.2000000476837158203125f.xxx) * 0.058609999716281890869140625f)) + (pow(Source.Sample(_Source_sampler, _539 + _1164).xyz, 2.2000000476837158203125f.xxx) * 0.09523999691009521484375f)) + (pow(Source.Sample(_Source_sampler, _539 + _1175).xyz, 2.2000000476837158203125f.xxx) * 0.058609999716281890869140625f)) + (pow(Source.Sample(_Source_sampler, _539 + _1186).xyz, 2.2000000476837158203125f.xxx) * 0.01465000025928020477294921875f)) + (pow(Source.Sample(_Source_sampler, _539 + _1197).xyz, 2.2000000476837158203125f.xxx) * 0.003659999929368495941162109375f)) + (pow(Source.Sample(_Source_sampler, _539 + _1208).xyz, 2.2000000476837158203125f.xxx) * 0.01465000025928020477294921875f);
    float2 _1217 = float2(0.0f, _1196);
    float2 _1228 = float2(_1024, _1196);
    float2 _1239 = float2(_1035, _1196);
    float2 _556 = float2(_533, _537 - 0.00150000001303851604461669921875f);
    float3 _1627 = ((((((((((pow(Source.Sample(_Source_sampler, _556 + _996).xyz, 2.2000000476837158203125f.xxx) * 0.003659999929368495941162109375f) + (pow(Source.Sample(_Source_sampler, _556 + _1007).xyz, 2.2000000476837158203125f.xxx) * 0.01465000025928020477294921875f)) + (pow(Source.Sample(_Source_sampler, _556 + _1016).xyz, 2.2000000476837158203125f.xxx) * 0.0256399996578693389892578125f)) + (pow(Source.Sample(_Source_sampler, _556 + _1027).xyz, 2.2000000476837158203125f.xxx) * 0.01465000025928020477294921875f)) + (pow(Source.Sample(_Source_sampler, _556 + _1038).xyz, 2.2000000476837158203125f.xxx) * 0.003659999929368495941162109375f)) + (pow(Source.Sample(_Source_sampler, _556 + _1049).xyz, 2.2000000476837158203125f.xxx) * 0.01465000025928020477294921875f)) + (pow(Source.Sample(_Source_sampler, _556 + _1060).xyz, 2.2000000476837158203125f.xxx) * 0.058609999716281890869140625f)) + (pow(Source.Sample(_Source_sampler, _556 + _1069).xyz, 2.2000000476837158203125f.xxx) * 0.09523999691009521484375f)) + (pow(Source.Sample(_Source_sampler, _556 + _1080).xyz, 2.2000000476837158203125f.xxx) * 0.058609999716281890869140625f)) + (pow(Source.Sample(_Source_sampler, _556 + _1091).xyz, 2.2000000476837158203125f.xxx) * 0.01465000025928020477294921875f)) + (pow(Source.Sample(_Source_sampler, _556 + _1100).xyz, 2.2000000476837158203125f.xxx) * 0.0256399996578693389892578125f);
    float3 _1735 = ((((((((((_1627 + (pow(Source.Sample(_Source_sampler, _556 + _1109).xyz, 2.2000000476837158203125f.xxx) * 0.09523999691009521484375f)) + (pow(Source.Sample(_Source_sampler, _556).xyz, 2.2000000476837158203125f.xxx) * 0.15017999708652496337890625f)) + (pow(Source.Sample(_Source_sampler, _556 + _1124).xyz, 2.2000000476837158203125f.xxx) * 0.09523999691009521484375f)) + (pow(Source.Sample(_Source_sampler, _556 + _1133).xyz, 2.2000000476837158203125f.xxx) * 0.0256399996578693389892578125f)) + (pow(Source.Sample(_Source_sampler, _556 + _1144).xyz, 2.2000000476837158203125f.xxx) * 0.01465000025928020477294921875f)) + (pow(Source.Sample(_Source_sampler, _556 + _1155).xyz, 2.2000000476837158203125f.xxx) * 0.058609999716281890869140625f)) + (pow(Source.Sample(_Source_sampler, _556 + _1164).xyz, 2.2000000476837158203125f.xxx) * 0.09523999691009521484375f)) + (pow(Source.Sample(_Source_sampler, _556 + _1175).xyz, 2.2000000476837158203125f.xxx) * 0.058609999716281890869140625f)) + (pow(Source.Sample(_Source_sampler, _556 + _1186).xyz, 2.2000000476837158203125f.xxx) * 0.01465000025928020477294921875f)) + (pow(Source.Sample(_Source_sampler, _556 + _1197).xyz, 2.2000000476837158203125f.xxx) * 0.003659999929368495941162109375f)) + (pow(Source.Sample(_Source_sampler, _556 + _1208).xyz, 2.2000000476837158203125f.xxx) * 0.01465000025928020477294921875f);
    float2 _570 = float2(_533 - 0.00150000001303851604461669921875f, _537);
    float3 _2149 = ((((((((((pow(Source.Sample(_Source_sampler, _570 + _996).xyz, 2.2000000476837158203125f.xxx) * 0.003659999929368495941162109375f) + (pow(Source.Sample(_Source_sampler, _570 + _1007).xyz, 2.2000000476837158203125f.xxx) * 0.01465000025928020477294921875f)) + (pow(Source.Sample(_Source_sampler, _570 + _1016).xyz, 2.2000000476837158203125f.xxx) * 0.0256399996578693389892578125f)) + (pow(Source.Sample(_Source_sampler, _570 + _1027).xyz, 2.2000000476837158203125f.xxx) * 0.01465000025928020477294921875f)) + (pow(Source.Sample(_Source_sampler, _570 + _1038).xyz, 2.2000000476837158203125f.xxx) * 0.003659999929368495941162109375f)) + (pow(Source.Sample(_Source_sampler, _570 + _1049).xyz, 2.2000000476837158203125f.xxx) * 0.01465000025928020477294921875f)) + (pow(Source.Sample(_Source_sampler, _570 + _1060).xyz, 2.2000000476837158203125f.xxx) * 0.058609999716281890869140625f)) + (pow(Source.Sample(_Source_sampler, _570 + _1069).xyz, 2.2000000476837158203125f.xxx) * 0.09523999691009521484375f)) + (pow(Source.Sample(_Source_sampler, _570 + _1080).xyz, 2.2000000476837158203125f.xxx) * 0.058609999716281890869140625f)) + (pow(Source.Sample(_Source_sampler, _570 + _1091).xyz, 2.2000000476837158203125f.xxx) * 0.01465000025928020477294921875f)) + (pow(Source.Sample(_Source_sampler, _570 + _1100).xyz, 2.2000000476837158203125f.xxx) * 0.0256399996578693389892578125f);
    float3 _2257 = ((((((((((_2149 + (pow(Source.Sample(_Source_sampler, _570 + _1109).xyz, 2.2000000476837158203125f.xxx) * 0.09523999691009521484375f)) + (pow(Source.Sample(_Source_sampler, _570).xyz, 2.2000000476837158203125f.xxx) * 0.15017999708652496337890625f)) + (pow(Source.Sample(_Source_sampler, _570 + _1124).xyz, 2.2000000476837158203125f.xxx) * 0.09523999691009521484375f)) + (pow(Source.Sample(_Source_sampler, _570 + _1133).xyz, 2.2000000476837158203125f.xxx) * 0.0256399996578693389892578125f)) + (pow(Source.Sample(_Source_sampler, _570 + _1144).xyz, 2.2000000476837158203125f.xxx) * 0.01465000025928020477294921875f)) + (pow(Source.Sample(_Source_sampler, _570 + _1155).xyz, 2.2000000476837158203125f.xxx) * 0.058609999716281890869140625f)) + (pow(Source.Sample(_Source_sampler, _570 + _1164).xyz, 2.2000000476837158203125f.xxx) * 0.09523999691009521484375f)) + (pow(Source.Sample(_Source_sampler, _570 + _1175).xyz, 2.2000000476837158203125f.xxx) * 0.058609999716281890869140625f)) + (pow(Source.Sample(_Source_sampler, _570 + _1186).xyz, 2.2000000476837158203125f.xxx) * 0.01465000025928020477294921875f)) + (pow(Source.Sample(_Source_sampler, _570 + _1197).xyz, 2.2000000476837158203125f.xxx) * 0.003659999929368495941162109375f)) + (pow(Source.Sample(_Source_sampler, _570 + _1208).xyz, 2.2000000476837158203125f.xxx) * 0.01465000025928020477294921875f);
    float4 _2550 = float4(-4.5f, -2.25f, 2.25f, 4.5f) / _983;
    float4 _2556 = float4(-4.5f, -2.25f, 2.25f, 4.5f) / _989;
    float _2559 = _2550.x;
    float _2561 = _2556.x;
    float _2570 = _2550.y;
    float _2590 = _2550.z;
    float _2601 = _2550.w;
    float _2614 = _2556.y;
    float3 _2662 = (((((((((pow(Source.Sample(_Source_sampler, _539 + float2(_2559, _2561)).xyz, 2.2000000476837158203125f.xxx) * 0.003659999929368495941162109375f) + (pow(Source.Sample(_Source_sampler, _539 + float2(_2570, _2561)).xyz, 2.2000000476837158203125f.xxx) * 0.01465000025928020477294921875f)) + (pow(Source.Sample(_Source_sampler, _539 + float2(0.0f, _2561)).xyz, 2.2000000476837158203125f.xxx) * 0.0256399996578693389892578125f)) + (pow(Source.Sample(_Source_sampler, _539 + float2(_2590, _2561)).xyz, 2.2000000476837158203125f.xxx) * 0.01465000025928020477294921875f)) + (pow(Source.Sample(_Source_sampler, _539 + float2(_2601, _2561)).xyz, 2.2000000476837158203125f.xxx) * 0.003659999929368495941162109375f)) + (pow(Source.Sample(_Source_sampler, _539 + float2(_2559, _2614)).xyz, 2.2000000476837158203125f.xxx) * 0.01465000025928020477294921875f)) + (pow(Source.Sample(_Source_sampler, _539 + float2(_2570, _2614)).xyz, 2.2000000476837158203125f.xxx) * 0.058609999716281890869140625f)) + (pow(Source.Sample(_Source_sampler, _539 + float2(0.0f, _2614)).xyz, 2.2000000476837158203125f.xxx) * 0.09523999691009521484375f)) + (pow(Source.Sample(_Source_sampler, _539 + float2(_2590, _2614)).xyz, 2.2000000476837158203125f.xxx) * 0.058609999716281890869140625f)) + (pow(Source.Sample(_Source_sampler, _539 + float2(_2601, _2614)).xyz, 2.2000000476837158203125f.xxx) * 0.01465000025928020477294921875f);
    float _2709 = _2556.z;
    float3 _2757 = (((((((((_2662 + (pow(Source.Sample(_Source_sampler, _539 + float2(_2559, 0.0f)).xyz, 2.2000000476837158203125f.xxx) * 0.0256399996578693389892578125f)) + (pow(Source.Sample(_Source_sampler, _539 + float2(_2570, 0.0f)).xyz, 2.2000000476837158203125f.xxx) * 0.09523999691009521484375f)) + (pow(Source.Sample(_Source_sampler, _539).xyz, 2.2000000476837158203125f.xxx) * 0.15017999708652496337890625f)) + (pow(Source.Sample(_Source_sampler, _539 + float2(_2590, 0.0f)).xyz, 2.2000000476837158203125f.xxx) * 0.09523999691009521484375f)) + (pow(Source.Sample(_Source_sampler, _539 + float2(_2601, 0.0f)).xyz, 2.2000000476837158203125f.xxx) * 0.0256399996578693389892578125f)) + (pow(Source.Sample(_Source_sampler, _539 + float2(_2559, _2709)).xyz, 2.2000000476837158203125f.xxx) * 0.01465000025928020477294921875f)) + (pow(Source.Sample(_Source_sampler, _539 + float2(_2570, _2709)).xyz, 2.2000000476837158203125f.xxx) * 0.058609999716281890869140625f)) + (pow(Source.Sample(_Source_sampler, _539 + float2(0.0f, _2709)).xyz, 2.2000000476837158203125f.xxx) * 0.09523999691009521484375f)) + (pow(Source.Sample(_Source_sampler, _539 + float2(_2590, _2709)).xyz, 2.2000000476837158203125f.xxx) * 0.058609999716281890869140625f)) + (pow(Source.Sample(_Source_sampler, _539 + float2(_2601, _2709)).xyz, 2.2000000476837158203125f.xxx) * 0.01465000025928020477294921875f);
    float _2762 = _2556.w;
    float4 _3072 = float4(-3.5f, -1.75f, 1.75f, 3.5f) / _983;
    float4 _3078 = float4(-3.5f, -1.75f, 1.75f, 3.5f) / _989;
    float _3081 = _3072.x;
    float _3083 = _3078.x;
    float _3092 = _3072.y;
    float _3112 = _3072.z;
    float _3123 = _3072.w;
    float _3136 = _3078.y;
    float3 _3184 = (((((((((pow(Source.Sample(_Source_sampler, _556 + float2(_3081, _3083)).xyz, 2.2000000476837158203125f.xxx) * 0.003659999929368495941162109375f) + (pow(Source.Sample(_Source_sampler, _556 + float2(_3092, _3083)).xyz, 2.2000000476837158203125f.xxx) * 0.01465000025928020477294921875f)) + (pow(Source.Sample(_Source_sampler, _556 + float2(0.0f, _3083)).xyz, 2.2000000476837158203125f.xxx) * 0.0256399996578693389892578125f)) + (pow(Source.Sample(_Source_sampler, _556 + float2(_3112, _3083)).xyz, 2.2000000476837158203125f.xxx) * 0.01465000025928020477294921875f)) + (pow(Source.Sample(_Source_sampler, _556 + float2(_3123, _3083)).xyz, 2.2000000476837158203125f.xxx) * 0.003659999929368495941162109375f)) + (pow(Source.Sample(_Source_sampler, _556 + float2(_3081, _3136)).xyz, 2.2000000476837158203125f.xxx) * 0.01465000025928020477294921875f)) + (pow(Source.Sample(_Source_sampler, _556 + float2(_3092, _3136)).xyz, 2.2000000476837158203125f.xxx) * 0.058609999716281890869140625f)) + (pow(Source.Sample(_Source_sampler, _556 + float2(0.0f, _3136)).xyz, 2.2000000476837158203125f.xxx) * 0.09523999691009521484375f)) + (pow(Source.Sample(_Source_sampler, _556 + float2(_3112, _3136)).xyz, 2.2000000476837158203125f.xxx) * 0.058609999716281890869140625f)) + (pow(Source.Sample(_Source_sampler, _556 + float2(_3123, _3136)).xyz, 2.2000000476837158203125f.xxx) * 0.01465000025928020477294921875f);
    float _3231 = _3078.z;
    float3 _3279 = (((((((((_3184 + (pow(Source.Sample(_Source_sampler, _556 + float2(_3081, 0.0f)).xyz, 2.2000000476837158203125f.xxx) * 0.0256399996578693389892578125f)) + (pow(Source.Sample(_Source_sampler, _556 + float2(_3092, 0.0f)).xyz, 2.2000000476837158203125f.xxx) * 0.09523999691009521484375f)) + (pow(Source.Sample(_Source_sampler, _556).xyz, 2.2000000476837158203125f.xxx) * 0.15017999708652496337890625f)) + (pow(Source.Sample(_Source_sampler, _556 + float2(_3112, 0.0f)).xyz, 2.2000000476837158203125f.xxx) * 0.09523999691009521484375f)) + (pow(Source.Sample(_Source_sampler, _556 + float2(_3123, 0.0f)).xyz, 2.2000000476837158203125f.xxx) * 0.0256399996578693389892578125f)) + (pow(Source.Sample(_Source_sampler, _556 + float2(_3081, _3231)).xyz, 2.2000000476837158203125f.xxx) * 0.01465000025928020477294921875f)) + (pow(Source.Sample(_Source_sampler, _556 + float2(_3092, _3231)).xyz, 2.2000000476837158203125f.xxx) * 0.058609999716281890869140625f)) + (pow(Source.Sample(_Source_sampler, _556 + float2(0.0f, _3231)).xyz, 2.2000000476837158203125f.xxx) * 0.09523999691009521484375f)) + (pow(Source.Sample(_Source_sampler, _556 + float2(_3112, _3231)).xyz, 2.2000000476837158203125f.xxx) * 0.058609999716281890869140625f)) + (pow(Source.Sample(_Source_sampler, _556 + float2(_3123, _3231)).xyz, 2.2000000476837158203125f.xxx) * 0.01465000025928020477294921875f);
    float _3284 = _3078.w;
    float4 _3594 = float4(-2.5f, -1.25f, 1.25f, 2.5f) / _983;
    float4 _3600 = float4(-2.5f, -1.25f, 1.25f, 2.5f) / _989;
    float _3603 = _3594.x;
    float _3605 = _3600.x;
    float _3614 = _3594.y;
    float _3634 = _3594.z;
    float _3645 = _3594.w;
    float _3658 = _3600.y;
    float3 _3706 = (((((((((pow(Source.Sample(_Source_sampler, _570 + float2(_3603, _3605)).xyz, 2.2000000476837158203125f.xxx) * 0.003659999929368495941162109375f) + (pow(Source.Sample(_Source_sampler, _570 + float2(_3614, _3605)).xyz, 2.2000000476837158203125f.xxx) * 0.01465000025928020477294921875f)) + (pow(Source.Sample(_Source_sampler, _570 + float2(0.0f, _3605)).xyz, 2.2000000476837158203125f.xxx) * 0.0256399996578693389892578125f)) + (pow(Source.Sample(_Source_sampler, _570 + float2(_3634, _3605)).xyz, 2.2000000476837158203125f.xxx) * 0.01465000025928020477294921875f)) + (pow(Source.Sample(_Source_sampler, _570 + float2(_3645, _3605)).xyz, 2.2000000476837158203125f.xxx) * 0.003659999929368495941162109375f)) + (pow(Source.Sample(_Source_sampler, _570 + float2(_3603, _3658)).xyz, 2.2000000476837158203125f.xxx) * 0.01465000025928020477294921875f)) + (pow(Source.Sample(_Source_sampler, _570 + float2(_3614, _3658)).xyz, 2.2000000476837158203125f.xxx) * 0.058609999716281890869140625f)) + (pow(Source.Sample(_Source_sampler, _570 + float2(0.0f, _3658)).xyz, 2.2000000476837158203125f.xxx) * 0.09523999691009521484375f)) + (pow(Source.Sample(_Source_sampler, _570 + float2(_3634, _3658)).xyz, 2.2000000476837158203125f.xxx) * 0.058609999716281890869140625f)) + (pow(Source.Sample(_Source_sampler, _570 + float2(_3645, _3658)).xyz, 2.2000000476837158203125f.xxx) * 0.01465000025928020477294921875f);
    float _3753 = _3600.z;
    float3 _3801 = (((((((((_3706 + (pow(Source.Sample(_Source_sampler, _570 + float2(_3603, 0.0f)).xyz, 2.2000000476837158203125f.xxx) * 0.0256399996578693389892578125f)) + (pow(Source.Sample(_Source_sampler, _570 + float2(_3614, 0.0f)).xyz, 2.2000000476837158203125f.xxx) * 0.09523999691009521484375f)) + (pow(Source.Sample(_Source_sampler, _570).xyz, 2.2000000476837158203125f.xxx) * 0.15017999708652496337890625f)) + (pow(Source.Sample(_Source_sampler, _570 + float2(_3634, 0.0f)).xyz, 2.2000000476837158203125f.xxx) * 0.09523999691009521484375f)) + (pow(Source.Sample(_Source_sampler, _570 + float2(_3645, 0.0f)).xyz, 2.2000000476837158203125f.xxx) * 0.0256399996578693389892578125f)) + (pow(Source.Sample(_Source_sampler, _570 + float2(_3603, _3753)).xyz, 2.2000000476837158203125f.xxx) * 0.01465000025928020477294921875f)) + (pow(Source.Sample(_Source_sampler, _570 + float2(_3614, _3753)).xyz, 2.2000000476837158203125f.xxx) * 0.058609999716281890869140625f)) + (pow(Source.Sample(_Source_sampler, _570 + float2(0.0f, _3753)).xyz, 2.2000000476837158203125f.xxx) * 0.09523999691009521484375f)) + (pow(Source.Sample(_Source_sampler, _570 + float2(_3634, _3753)).xyz, 2.2000000476837158203125f.xxx) * 0.058609999716281890869140625f)) + (pow(Source.Sample(_Source_sampler, _570 + float2(_3645, _3753)).xyz, 2.2000000476837158203125f.xxx) * 0.01465000025928020477294921875f);
    float _3806 = _3600.w;
    float2 _649 = float2(0.0074999998323619365692138671875f, -0.020250000059604644775390625f) + float2(_533 + 0.001000000047497451305389404296875f, _537 + 0.001000000047497451305389404296875f);
    float4 _4116 = float4(-14.0f, -7.0f, 7.0f, 14.0f) / _983;
    float4 _4122 = float4(-14.0f, -7.0f, 7.0f, 14.0f) / _989;
    float _4125 = _4116.x;
    float _4127 = _4122.x;
    float _4136 = _4116.y;
    float _4156 = _4116.z;
    float _4167 = _4116.w;
    float _4180 = _4122.y;
    float3 _4228 = (((((((((pow(Source.Sample(_Source_sampler, _649 + float2(_4125, _4127)).xyz, 2.2000000476837158203125f.xxx) * 0.003659999929368495941162109375f) + (pow(Source.Sample(_Source_sampler, _649 + float2(_4136, _4127)).xyz, 2.2000000476837158203125f.xxx) * 0.01465000025928020477294921875f)) + (pow(Source.Sample(_Source_sampler, _649 + float2(0.0f, _4127)).xyz, 2.2000000476837158203125f.xxx) * 0.0256399996578693389892578125f)) + (pow(Source.Sample(_Source_sampler, _649 + float2(_4156, _4127)).xyz, 2.2000000476837158203125f.xxx) * 0.01465000025928020477294921875f)) + (pow(Source.Sample(_Source_sampler, _649 + float2(_4167, _4127)).xyz, 2.2000000476837158203125f.xxx) * 0.003659999929368495941162109375f)) + (pow(Source.Sample(_Source_sampler, _649 + float2(_4125, _4180)).xyz, 2.2000000476837158203125f.xxx) * 0.01465000025928020477294921875f)) + (pow(Source.Sample(_Source_sampler, _649 + float2(_4136, _4180)).xyz, 2.2000000476837158203125f.xxx) * 0.058609999716281890869140625f)) + (pow(Source.Sample(_Source_sampler, _649 + float2(0.0f, _4180)).xyz, 2.2000000476837158203125f.xxx) * 0.09523999691009521484375f)) + (pow(Source.Sample(_Source_sampler, _649 + float2(_4156, _4180)).xyz, 2.2000000476837158203125f.xxx) * 0.058609999716281890869140625f)) + (pow(Source.Sample(_Source_sampler, _649 + float2(_4167, _4180)).xyz, 2.2000000476837158203125f.xxx) * 0.01465000025928020477294921875f);
    float _4275 = _4122.z;
    float3 _4323 = (((((((((_4228 + (pow(Source.Sample(_Source_sampler, _649 + float2(_4125, 0.0f)).xyz, 2.2000000476837158203125f.xxx) * 0.0256399996578693389892578125f)) + (pow(Source.Sample(_Source_sampler, _649 + float2(_4136, 0.0f)).xyz, 2.2000000476837158203125f.xxx) * 0.09523999691009521484375f)) + (pow(Source.Sample(_Source_sampler, _649).xyz, 2.2000000476837158203125f.xxx) * 0.15017999708652496337890625f)) + (pow(Source.Sample(_Source_sampler, _649 + float2(_4156, 0.0f)).xyz, 2.2000000476837158203125f.xxx) * 0.09523999691009521484375f)) + (pow(Source.Sample(_Source_sampler, _649 + float2(_4167, 0.0f)).xyz, 2.2000000476837158203125f.xxx) * 0.0256399996578693389892578125f)) + (pow(Source.Sample(_Source_sampler, _649 + float2(_4125, _4275)).xyz, 2.2000000476837158203125f.xxx) * 0.01465000025928020477294921875f)) + (pow(Source.Sample(_Source_sampler, _649 + float2(_4136, _4275)).xyz, 2.2000000476837158203125f.xxx) * 0.058609999716281890869140625f)) + (pow(Source.Sample(_Source_sampler, _649 + float2(0.0f, _4275)).xyz, 2.2000000476837158203125f.xxx) * 0.09523999691009521484375f)) + (pow(Source.Sample(_Source_sampler, _649 + float2(_4156, _4275)).xyz, 2.2000000476837158203125f.xxx) * 0.058609999716281890869140625f)) + (pow(Source.Sample(_Source_sampler, _649 + float2(_4167, _4275)).xyz, 2.2000000476837158203125f.xxx) * 0.01465000025928020477294921875f);
    float _4328 = _4122.w;
    float _658 = ((((_1213 + (pow(Source.Sample(_Source_sampler, _539 + _1217).xyz, 2.2000000476837158203125f.xxx) * 0.0256399996578693389892578125f)) + (pow(Source.Sample(_Source_sampler, _539 + _1228).xyz, 2.2000000476837158203125f.xxx) * 0.01465000025928020477294921875f)) + (pow(Source.Sample(_Source_sampler, _539 + _1239).xyz, 2.2000000476837158203125f.xxx) * 0.003659999929368495941162109375f)).x + (0.20000000298023223876953125f * (((((_2757 + (pow(Source.Sample(_Source_sampler, _539 + float2(_2559, _2762)).xyz, 2.2000000476837158203125f.xxx) * 0.003659999929368495941162109375f)) + (pow(Source.Sample(_Source_sampler, _539 + float2(_2570, _2762)).xyz, 2.2000000476837158203125f.xxx) * 0.01465000025928020477294921875f)) + (pow(Source.Sample(_Source_sampler, _539 + float2(0.0f, _2762)).xyz, 2.2000000476837158203125f.xxx) * 0.0256399996578693389892578125f)) + (pow(Source.Sample(_Source_sampler, _539 + float2(_2590, _2762)).xyz, 2.2000000476837158203125f.xxx) * 0.01465000025928020477294921875f)) + (pow(Source.Sample(_Source_sampler, _539 + float2(_2601, _2762)).xyz, 2.2000000476837158203125f.xxx) * 0.003659999929368495941162109375f)).x)) + (0.0350500009953975677490234375f * (((((_4323 + (pow(Source.Sample(_Source_sampler, _649 + float2(_4125, _4328)).xyz, 2.2000000476837158203125f.xxx) * 0.003659999929368495941162109375f)) + (pow(Source.Sample(_Source_sampler, _649 + float2(_4136, _4328)).xyz, 2.2000000476837158203125f.xxx) * 0.01465000025928020477294921875f)) + (pow(Source.Sample(_Source_sampler, _649 + float2(0.0f, _4328)).xyz, 2.2000000476837158203125f.xxx) * 0.0256399996578693389892578125f)) + (pow(Source.Sample(_Source_sampler, _649 + float2(_4156, _4328)).xyz, 2.2000000476837158203125f.xxx) * 0.01465000025928020477294921875f)) + (pow(Source.Sample(_Source_sampler, _649 + float2(_4167, _4328)).xyz, 2.2000000476837158203125f.xxx) * 0.003659999929368495941162109375f)).x);
    float2 _674 = float2(-0.0164999999105930328369140625f, -0.014999999664723873138427734375f) + float2(_533, _537 - 0.00200000009499490261077880859375f);
    float4 _4638 = float4(-10.0f, -5.0f, 5.0f, 10.0f) / _983;
    float4 _4644 = float4(-10.0f, -5.0f, 5.0f, 10.0f) / _989;
    float _4647 = _4638.x;
    float _4649 = _4644.x;
    float _4658 = _4638.y;
    float _4678 = _4638.z;
    float _4689 = _4638.w;
    float _4702 = _4644.y;
    float3 _4750 = (((((((((pow(Source.Sample(_Source_sampler, _674 + float2(_4647, _4649)).xyz, 2.2000000476837158203125f.xxx) * 0.003659999929368495941162109375f) + (pow(Source.Sample(_Source_sampler, _674 + float2(_4658, _4649)).xyz, 2.2000000476837158203125f.xxx) * 0.01465000025928020477294921875f)) + (pow(Source.Sample(_Source_sampler, _674 + float2(0.0f, _4649)).xyz, 2.2000000476837158203125f.xxx) * 0.0256399996578693389892578125f)) + (pow(Source.Sample(_Source_sampler, _674 + float2(_4678, _4649)).xyz, 2.2000000476837158203125f.xxx) * 0.01465000025928020477294921875f)) + (pow(Source.Sample(_Source_sampler, _674 + float2(_4689, _4649)).xyz, 2.2000000476837158203125f.xxx) * 0.003659999929368495941162109375f)) + (pow(Source.Sample(_Source_sampler, _674 + float2(_4647, _4702)).xyz, 2.2000000476837158203125f.xxx) * 0.01465000025928020477294921875f)) + (pow(Source.Sample(_Source_sampler, _674 + float2(_4658, _4702)).xyz, 2.2000000476837158203125f.xxx) * 0.058609999716281890869140625f)) + (pow(Source.Sample(_Source_sampler, _674 + float2(0.0f, _4702)).xyz, 2.2000000476837158203125f.xxx) * 0.09523999691009521484375f)) + (pow(Source.Sample(_Source_sampler, _674 + float2(_4678, _4702)).xyz, 2.2000000476837158203125f.xxx) * 0.058609999716281890869140625f)) + (pow(Source.Sample(_Source_sampler, _674 + float2(_4689, _4702)).xyz, 2.2000000476837158203125f.xxx) * 0.01465000025928020477294921875f);
    float _4797 = _4644.z;
    float3 _4845 = (((((((((_4750 + (pow(Source.Sample(_Source_sampler, _674 + float2(_4647, 0.0f)).xyz, 2.2000000476837158203125f.xxx) * 0.0256399996578693389892578125f)) + (pow(Source.Sample(_Source_sampler, _674 + float2(_4658, 0.0f)).xyz, 2.2000000476837158203125f.xxx) * 0.09523999691009521484375f)) + (pow(Source.Sample(_Source_sampler, _674).xyz, 2.2000000476837158203125f.xxx) * 0.15017999708652496337890625f)) + (pow(Source.Sample(_Source_sampler, _674 + float2(_4678, 0.0f)).xyz, 2.2000000476837158203125f.xxx) * 0.09523999691009521484375f)) + (pow(Source.Sample(_Source_sampler, _674 + float2(_4689, 0.0f)).xyz, 2.2000000476837158203125f.xxx) * 0.0256399996578693389892578125f)) + (pow(Source.Sample(_Source_sampler, _674 + float2(_4647, _4797)).xyz, 2.2000000476837158203125f.xxx) * 0.01465000025928020477294921875f)) + (pow(Source.Sample(_Source_sampler, _674 + float2(_4658, _4797)).xyz, 2.2000000476837158203125f.xxx) * 0.058609999716281890869140625f)) + (pow(Source.Sample(_Source_sampler, _674 + float2(0.0f, _4797)).xyz, 2.2000000476837158203125f.xxx) * 0.09523999691009521484375f)) + (pow(Source.Sample(_Source_sampler, _674 + float2(_4678, _4797)).xyz, 2.2000000476837158203125f.xxx) * 0.058609999716281890869140625f)) + (pow(Source.Sample(_Source_sampler, _674 + float2(_4689, _4797)).xyz, 2.2000000476837158203125f.xxx) * 0.01465000025928020477294921875f);
    float _4850 = _4644.w;
    float _682 = ((((_1735 + (pow(Source.Sample(_Source_sampler, _556 + _1217).xyz, 2.2000000476837158203125f.xxx) * 0.0256399996578693389892578125f)) + (pow(Source.Sample(_Source_sampler, _556 + _1228).xyz, 2.2000000476837158203125f.xxx) * 0.01465000025928020477294921875f)) + (pow(Source.Sample(_Source_sampler, _556 + _1239).xyz, 2.2000000476837158203125f.xxx) * 0.003659999929368495941162109375f)).y + (0.20000000298023223876953125f * (((((_3279 + (pow(Source.Sample(_Source_sampler, _556 + float2(_3081, _3284)).xyz, 2.2000000476837158203125f.xxx) * 0.003659999929368495941162109375f)) + (pow(Source.Sample(_Source_sampler, _556 + float2(_3092, _3284)).xyz, 2.2000000476837158203125f.xxx) * 0.01465000025928020477294921875f)) + (pow(Source.Sample(_Source_sampler, _556 + float2(0.0f, _3284)).xyz, 2.2000000476837158203125f.xxx) * 0.0256399996578693389892578125f)) + (pow(Source.Sample(_Source_sampler, _556 + float2(_3112, _3284)).xyz, 2.2000000476837158203125f.xxx) * 0.01465000025928020477294921875f)) + (pow(Source.Sample(_Source_sampler, _556 + float2(_3123, _3284)).xyz, 2.2000000476837158203125f.xxx) * 0.003659999929368495941162109375f)).y)) + (0.0206499993801116943359375f * (((((_4845 + (pow(Source.Sample(_Source_sampler, _674 + float2(_4647, _4850)).xyz, 2.2000000476837158203125f.xxx) * 0.003659999929368495941162109375f)) + (pow(Source.Sample(_Source_sampler, _674 + float2(_4658, _4850)).xyz, 2.2000000476837158203125f.xxx) * 0.01465000025928020477294921875f)) + (pow(Source.Sample(_Source_sampler, _674 + float2(0.0f, _4850)).xyz, 2.2000000476837158203125f.xxx) * 0.0256399996578693389892578125f)) + (pow(Source.Sample(_Source_sampler, _674 + float2(_4678, _4850)).xyz, 2.2000000476837158203125f.xxx) * 0.01465000025928020477294921875f)) + (pow(Source.Sample(_Source_sampler, _674 + float2(_4689, _4850)).xyz, 2.2000000476837158203125f.xxx) * 0.003659999929368495941162109375f)).y);
    float2 _696 = float2(-0.014999999664723873138427734375f, -0.0f) + float2(_533 - 0.00200000009499490261077880859375f, _537);
    float4 _5160 = float4(-6.0f, -3.0f, 3.0f, 6.0f) / _983;
    float4 _5166 = float4(-6.0f, -3.0f, 3.0f, 6.0f) / _989;
    float _5169 = _5160.x;
    float _5171 = _5166.x;
    float _5180 = _5160.y;
    float _5200 = _5160.z;
    float _5211 = _5160.w;
    float _5224 = _5166.y;
    float3 _5272 = (((((((((pow(Source.Sample(_Source_sampler, _696 + float2(_5169, _5171)).xyz, 2.2000000476837158203125f.xxx) * 0.003659999929368495941162109375f) + (pow(Source.Sample(_Source_sampler, _696 + float2(_5180, _5171)).xyz, 2.2000000476837158203125f.xxx) * 0.01465000025928020477294921875f)) + (pow(Source.Sample(_Source_sampler, _696 + float2(0.0f, _5171)).xyz, 2.2000000476837158203125f.xxx) * 0.0256399996578693389892578125f)) + (pow(Source.Sample(_Source_sampler, _696 + float2(_5200, _5171)).xyz, 2.2000000476837158203125f.xxx) * 0.01465000025928020477294921875f)) + (pow(Source.Sample(_Source_sampler, _696 + float2(_5211, _5171)).xyz, 2.2000000476837158203125f.xxx) * 0.003659999929368495941162109375f)) + (pow(Source.Sample(_Source_sampler, _696 + float2(_5169, _5224)).xyz, 2.2000000476837158203125f.xxx) * 0.01465000025928020477294921875f)) + (pow(Source.Sample(_Source_sampler, _696 + float2(_5180, _5224)).xyz, 2.2000000476837158203125f.xxx) * 0.058609999716281890869140625f)) + (pow(Source.Sample(_Source_sampler, _696 + float2(0.0f, _5224)).xyz, 2.2000000476837158203125f.xxx) * 0.09523999691009521484375f)) + (pow(Source.Sample(_Source_sampler, _696 + float2(_5200, _5224)).xyz, 2.2000000476837158203125f.xxx) * 0.058609999716281890869140625f)) + (pow(Source.Sample(_Source_sampler, _696 + float2(_5211, _5224)).xyz, 2.2000000476837158203125f.xxx) * 0.01465000025928020477294921875f);
    float _5319 = _5166.z;
    float3 _5367 = (((((((((_5272 + (pow(Source.Sample(_Source_sampler, _696 + float2(_5169, 0.0f)).xyz, 2.2000000476837158203125f.xxx) * 0.0256399996578693389892578125f)) + (pow(Source.Sample(_Source_sampler, _696 + float2(_5180, 0.0f)).xyz, 2.2000000476837158203125f.xxx) * 0.09523999691009521484375f)) + (pow(Source.Sample(_Source_sampler, _696).xyz, 2.2000000476837158203125f.xxx) * 0.15017999708652496337890625f)) + (pow(Source.Sample(_Source_sampler, _696 + float2(_5200, 0.0f)).xyz, 2.2000000476837158203125f.xxx) * 0.09523999691009521484375f)) + (pow(Source.Sample(_Source_sampler, _696 + float2(_5211, 0.0f)).xyz, 2.2000000476837158203125f.xxx) * 0.0256399996578693389892578125f)) + (pow(Source.Sample(_Source_sampler, _696 + float2(_5169, _5319)).xyz, 2.2000000476837158203125f.xxx) * 0.01465000025928020477294921875f)) + (pow(Source.Sample(_Source_sampler, _696 + float2(_5180, _5319)).xyz, 2.2000000476837158203125f.xxx) * 0.058609999716281890869140625f)) + (pow(Source.Sample(_Source_sampler, _696 + float2(0.0f, _5319)).xyz, 2.2000000476837158203125f.xxx) * 0.09523999691009521484375f)) + (pow(Source.Sample(_Source_sampler, _696 + float2(_5200, _5319)).xyz, 2.2000000476837158203125f.xxx) * 0.058609999716281890869140625f)) + (pow(Source.Sample(_Source_sampler, _696 + float2(_5211, _5319)).xyz, 2.2000000476837158203125f.xxx) * 0.01465000025928020477294921875f);
    float _5372 = _5166.w;
    float _705 = ((((_2257 + (pow(Source.Sample(_Source_sampler, _570 + _1217).xyz, 2.2000000476837158203125f.xxx) * 0.0256399996578693389892578125f)) + (pow(Source.Sample(_Source_sampler, _570 + _1228).xyz, 2.2000000476837158203125f.xxx) * 0.01465000025928020477294921875f)) + (pow(Source.Sample(_Source_sampler, _570 + _1239).xyz, 2.2000000476837158203125f.xxx) * 0.003659999929368495941162109375f)).z + (0.20000000298023223876953125f * (((((_3801 + (pow(Source.Sample(_Source_sampler, _570 + float2(_3603, _3806)).xyz, 2.2000000476837158203125f.xxx) * 0.003659999929368495941162109375f)) + (pow(Source.Sample(_Source_sampler, _570 + float2(_3614, _3806)).xyz, 2.2000000476837158203125f.xxx) * 0.01465000025928020477294921875f)) + (pow(Source.Sample(_Source_sampler, _570 + float2(0.0f, _3806)).xyz, 2.2000000476837158203125f.xxx) * 0.0256399996578693389892578125f)) + (pow(Source.Sample(_Source_sampler, _570 + float2(_3634, _3806)).xyz, 2.2000000476837158203125f.xxx) * 0.01465000025928020477294921875f)) + (pow(Source.Sample(_Source_sampler, _570 + float2(_3645, _3806)).xyz, 2.2000000476837158203125f.xxx) * 0.003659999929368495941162109375f)).z)) + (0.0443000011146068572998046875f * (((((_5367 + (pow(Source.Sample(_Source_sampler, _696 + float2(_5169, _5372)).xyz, 2.2000000476837158203125f.xxx) * 0.003659999929368495941162109375f)) + (pow(Source.Sample(_Source_sampler, _696 + float2(_5180, _5372)).xyz, 2.2000000476837158203125f.xxx) * 0.01465000025928020477294921875f)) + (pow(Source.Sample(_Source_sampler, _696 + float2(0.0f, _5372)).xyz, 2.2000000476837158203125f.xxx) * 0.0256399996578693389892578125f)) + (pow(Source.Sample(_Source_sampler, _696 + float2(_5200, _5372)).xyz, 2.2000000476837158203125f.xxx) * 0.01465000025928020477294921875f)) + (pow(Source.Sample(_Source_sampler, _696 + float2(_5211, _5372)).xyz, 2.2000000476837158203125f.xxx) * 0.003659999929368495941162109375f)).z);
    float3 _6180 = float3(_658, _682, _705);
    float3 _742 = clamp((_6180 * 0.4000000059604644775390625f) + (((_6180 * 0.60000002384185791015625f) * _6180) * 1.0f), 0.0f.xxx, 1.0f.xxx) * pow((((16.0f * _533) * _537) * (1.0f - _533)) * (1.0f - _537), 0.300000011920928955078125f).xxx;
    float _762 = float(params_FrameCount);
    float2 _828 = _459 + (_762 * 1.6666666624587378464639186859131e-06f).xx;
    float3 _863 = pow(((((lerp(_742 * float3(0.949999988079071044921875f, 1.0499999523162841796875f, 0.949999988079071044921875f), float3(0.902499973773956298828125f, 1.10249984264373779296875f, 0.902499973773956298828125f) * (_742 * _742), 0.300000011920928955078125f.xxx) * 3.7999999523162841796875f) * pow(clamp(0.3499999940395355224609375f + (0.1500000059604644775390625f * sin((3.5f * ((_762 * 0.01666666753590106964111328125f) * params_SCANSPEED)) + ((_537 * params_OutputSize.y) * 1.5f))), 0.0f, 1.0f), 0.89999997615814208984375f).xxx) * (1.0f + (0.00150000001303851604461669921875f * sin(_762 * 5.000000476837158203125f)))) * (1.0f.xxx - (clamp((mod(_444.x + ((2.0f * mod(_444.y, 2.0f)) / params_OutputSize.x), 2.0f) - 1.0f) * 2.0f, 0.0f, 1.0f).xxx * 0.1500000059604644775390625f))) * (1.0f.xxx - (float3(frac(sin(mod(dot(_828, float2(12.98980045318603515625f, 78.233001708984375f)), 3.1400001049041748046875f)) * 43758.546875f), frac(sin(mod(dot(_828 + 0.300000011920928955078125f.xx, float2(12.98980045318603515625f, 78.233001708984375f)), 3.1400001049041748046875f)) * 43758.546875f), frac(sin(mod(dot(_828 + 0.5f.xx, float2(12.98980045318603515625f, 78.233001708984375f)), 3.1400001049041748046875f)) * 43758.546875f)) * 0.25f)), 0.449999988079071044921875f.xxx);
    bool _867 = _533 < 0.0f;
    bool _874;
    if (!_867)
    {
        _874 = _533 > 1.0f;
    }
    else
    {
        _874 = _867;
    }
    float3 _6171;
    if (_874)
    {
        _6171 = 0.0f.xxx;
    }
    else
    {
        _6171 = _863;
    }
    bool _881 = _537 < 0.0f;
    bool _888;
    if (!_881)
    {
        _888 = _537 > 1.0f;
    }
    else
    {
        _888 = _881;
    }
    float3 _6169;
    if (_888)
    {
        _6169 = 0.0f.xxx;
    }
    else
    {
        _6169 = _6171;
    }
    FragColor = float4(_6169, 1.0f);
}

SPIRV_Cross_Output main(SPIRV_Cross_Input stage_input)
{
    vTexCoord = stage_input.vTexCoord;
    frag_main();
    SPIRV_Cross_Output stage_output;
    stage_output.FragColor = FragColor;
    return stage_output;
}
