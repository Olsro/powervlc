// Generated from interpolation/shaders/jinc2.slang. See slang/upstream for licence/source.
cbuffer Push : register(b1)
{
    float4 params_SourceSize : packoffset(c0);
    float params_JINC2_WINDOW_SINC : packoffset(c3.y);
    float params_JINC2_SINC : packoffset(c3.z);
    float params_JINC2_AR_STRENGTH : packoffset(c3.w);
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

void frag_main()
{
    float2 _245 = vTexCoord * params_SourceSize.xy;
    float2 _251 = floor(_245 - 0.5f.xx);
    float2 _252 = _251 + 0.5f.xx;
    float2 _726 = (_251 + (-0.5f).xx) - _245;
    float _730 = sqrt(dot(_726, _726));
    float2 _736 = (_251 + float2(0.5f, -0.5f)) - _245;
    float _740 = sqrt(dot(_736, _736));
    float2 _746 = (_251 + float2(1.5f, -0.5f)) - _245;
    float _750 = sqrt(dot(_746, _746));
    float2 _756 = (_251 + float2(2.5f, -0.5f)) - _245;
    float _760 = sqrt(dot(_756, _756));
    float _1507;
    if (_730 == 0.0f)
    {
        _1507 = 9.86960506439208984375f * (params_JINC2_WINDOW_SINC * params_JINC2_SINC);
    }
    else
    {
        _1507 = (sin(_730 * (params_JINC2_WINDOW_SINC * 3.1415927410125732421875f)) * sin(_730 * (params_JINC2_SINC * 3.1415927410125732421875f))) / (_730 * _730);
    }
    float _1508;
    if (_740 == 0.0f)
    {
        _1508 = 9.86960506439208984375f * (params_JINC2_WINDOW_SINC * params_JINC2_SINC);
    }
    else
    {
        _1508 = (sin(_740 * (params_JINC2_WINDOW_SINC * 3.1415927410125732421875f)) * sin(_740 * (params_JINC2_SINC * 3.1415927410125732421875f))) / (_740 * _740);
    }
    float _1509;
    if (_750 == 0.0f)
    {
        _1509 = 9.86960506439208984375f * (params_JINC2_WINDOW_SINC * params_JINC2_SINC);
    }
    else
    {
        _1509 = (sin(_750 * (params_JINC2_WINDOW_SINC * 3.1415927410125732421875f)) * sin(_750 * (params_JINC2_SINC * 3.1415927410125732421875f))) / (_750 * _750);
    }
    float _1510;
    if (_760 == 0.0f)
    {
        _1510 = 9.86960506439208984375f * (params_JINC2_WINDOW_SINC * params_JINC2_SINC);
    }
    else
    {
        _1510 = (sin(_760 * (params_JINC2_WINDOW_SINC * 3.1415927410125732421875f)) * sin(_760 * (params_JINC2_SINC * 3.1415927410125732421875f))) / (_760 * _760);
    }
    float4 _1805 = float4(_1507, _1508, _1509, _1510);
    float2 _918 = (_251 + float2(-0.5f, 0.5f)) - _245;
    float _922 = sqrt(dot(_918, _918));
    float2 _928 = _252 - _245;
    float _932 = sqrt(dot(_928, _928));
    float2 _938 = (_251 + float2(1.5f, 0.5f)) - _245;
    float _942 = sqrt(dot(_938, _938));
    float2 _948 = (_251 + float2(2.5f, 0.5f)) - _245;
    float _952 = sqrt(dot(_948, _948));
    float _1523;
    if (_922 == 0.0f)
    {
        _1523 = 9.86960506439208984375f * (params_JINC2_WINDOW_SINC * params_JINC2_SINC);
    }
    else
    {
        _1523 = (sin(_922 * (params_JINC2_WINDOW_SINC * 3.1415927410125732421875f)) * sin(_922 * (params_JINC2_SINC * 3.1415927410125732421875f))) / (_922 * _922);
    }
    float _1524;
    if (_932 == 0.0f)
    {
        _1524 = 9.86960506439208984375f * (params_JINC2_WINDOW_SINC * params_JINC2_SINC);
    }
    else
    {
        _1524 = (sin(_932 * (params_JINC2_WINDOW_SINC * 3.1415927410125732421875f)) * sin(_932 * (params_JINC2_SINC * 3.1415927410125732421875f))) / (_932 * _932);
    }
    float _1525;
    if (_942 == 0.0f)
    {
        _1525 = 9.86960506439208984375f * (params_JINC2_WINDOW_SINC * params_JINC2_SINC);
    }
    else
    {
        _1525 = (sin(_942 * (params_JINC2_WINDOW_SINC * 3.1415927410125732421875f)) * sin(_942 * (params_JINC2_SINC * 3.1415927410125732421875f))) / (_942 * _942);
    }
    float _1526;
    if (_952 == 0.0f)
    {
        _1526 = 9.86960506439208984375f * (params_JINC2_WINDOW_SINC * params_JINC2_SINC);
    }
    else
    {
        _1526 = (sin(_952 * (params_JINC2_WINDOW_SINC * 3.1415927410125732421875f)) * sin(_952 * (params_JINC2_SINC * 3.1415927410125732421875f))) / (_952 * _952);
    }
    float4 _1806 = float4(_1523, _1524, _1525, _1526);
    float2 _1110 = (_251 + float2(-0.5f, 1.5f)) - _245;
    float _1114 = sqrt(dot(_1110, _1110));
    float2 _1120 = (_251 + float2(0.5f, 1.5f)) - _245;
    float _1124 = sqrt(dot(_1120, _1120));
    float2 _1130 = (_251 + 1.5f.xx) - _245;
    float _1134 = sqrt(dot(_1130, _1130));
    float2 _1140 = (_251 + float2(2.5f, 1.5f)) - _245;
    float _1144 = sqrt(dot(_1140, _1140));
    float _1547;
    if (_1114 == 0.0f)
    {
        _1547 = 9.86960506439208984375f * (params_JINC2_WINDOW_SINC * params_JINC2_SINC);
    }
    else
    {
        _1547 = (sin(_1114 * (params_JINC2_WINDOW_SINC * 3.1415927410125732421875f)) * sin(_1114 * (params_JINC2_SINC * 3.1415927410125732421875f))) / (_1114 * _1114);
    }
    float _1548;
    if (_1124 == 0.0f)
    {
        _1548 = 9.86960506439208984375f * (params_JINC2_WINDOW_SINC * params_JINC2_SINC);
    }
    else
    {
        _1548 = (sin(_1124 * (params_JINC2_WINDOW_SINC * 3.1415927410125732421875f)) * sin(_1124 * (params_JINC2_SINC * 3.1415927410125732421875f))) / (_1124 * _1124);
    }
    float _1549;
    if (_1134 == 0.0f)
    {
        _1549 = 9.86960506439208984375f * (params_JINC2_WINDOW_SINC * params_JINC2_SINC);
    }
    else
    {
        _1549 = (sin(_1134 * (params_JINC2_WINDOW_SINC * 3.1415927410125732421875f)) * sin(_1134 * (params_JINC2_SINC * 3.1415927410125732421875f))) / (_1134 * _1134);
    }
    float _1550;
    if (_1144 == 0.0f)
    {
        _1550 = 9.86960506439208984375f * (params_JINC2_WINDOW_SINC * params_JINC2_SINC);
    }
    else
    {
        _1550 = (sin(_1144 * (params_JINC2_WINDOW_SINC * 3.1415927410125732421875f)) * sin(_1144 * (params_JINC2_SINC * 3.1415927410125732421875f))) / (_1144 * _1144);
    }
    float4 _1807 = float4(_1547, _1548, _1549, _1550);
    float2 _1302 = (_251 + float2(-0.5f, 2.5f)) - _245;
    float _1306 = sqrt(dot(_1302, _1302));
    float2 _1312 = (_251 + float2(0.5f, 2.5f)) - _245;
    float _1316 = sqrt(dot(_1312, _1312));
    float2 _1322 = (_251 + float2(1.5f, 2.5f)) - _245;
    float _1326 = sqrt(dot(_1322, _1322));
    float2 _1332 = (_251 + 2.5f.xx) - _245;
    float _1336 = sqrt(dot(_1332, _1332));
    float _1567;
    if (_1306 == 0.0f)
    {
        _1567 = 9.86960506439208984375f * (params_JINC2_WINDOW_SINC * params_JINC2_SINC);
    }
    else
    {
        _1567 = (sin(_1306 * (params_JINC2_WINDOW_SINC * 3.1415927410125732421875f)) * sin(_1306 * (params_JINC2_SINC * 3.1415927410125732421875f))) / (_1306 * _1306);
    }
    float _1568;
    if (_1316 == 0.0f)
    {
        _1568 = 9.86960506439208984375f * (params_JINC2_WINDOW_SINC * params_JINC2_SINC);
    }
    else
    {
        _1568 = (sin(_1316 * (params_JINC2_WINDOW_SINC * 3.1415927410125732421875f)) * sin(_1316 * (params_JINC2_SINC * 3.1415927410125732421875f))) / (_1316 * _1316);
    }
    float _1569;
    if (_1326 == 0.0f)
    {
        _1569 = 9.86960506439208984375f * (params_JINC2_WINDOW_SINC * params_JINC2_SINC);
    }
    else
    {
        _1569 = (sin(_1326 * (params_JINC2_WINDOW_SINC * 3.1415927410125732421875f)) * sin(_1326 * (params_JINC2_SINC * 3.1415927410125732421875f))) / (_1326 * _1326);
    }
    float _1570;
    if (_1336 == 0.0f)
    {
        _1570 = 9.86960506439208984375f * (params_JINC2_WINDOW_SINC * params_JINC2_SINC);
    }
    else
    {
        _1570 = (sin(_1336 * (params_JINC2_WINDOW_SINC * 3.1415927410125732421875f)) * sin(_1336 * (params_JINC2_SINC * 3.1415927410125732421875f))) / (_1336 * _1336);
    }
    float4 _1808 = float4(_1567, _1568, _1569, _1570);
    float2 _416 = float2(1.0f, 0.0f) * params_SourceSize.zw;
    float2 _421 = float2(0.0f, 1.0f) * params_SourceSize.zw;
    float2 _426 = _252 * params_SourceSize.zw;
    float2 _435 = _426 - _416;
    float2 _451 = _426 + _416;
    float2 _461 = _426 + (_416 * 2.0f);
    float4 _476 = Source.Sample(_Source_sampler, _426);
    float3 _477 = _476.xyz;
    float4 _483 = Source.Sample(_Source_sampler, _451);
    float3 _484 = _483.xyz;
    float4 _507 = Source.Sample(_Source_sampler, _426 + _421);
    float3 _508 = _507.xyz;
    float4 _516 = Source.Sample(_Source_sampler, _451 + _421);
    float3 _517 = _516.xyz;
    float2 _534 = _421 * 2.0f;
    float3 _690 = ((mul(_1805, float4x3(float3(Source.Sample(_Source_sampler, _435 - _421).xyz), float3(Source.Sample(_Source_sampler, _426 - _421).xyz), float3(Source.Sample(_Source_sampler, _451 - _421).xyz), float3(Source.Sample(_Source_sampler, _461 - _421).xyz))) + mul(_1806, float4x3(float3(Source.Sample(_Source_sampler, _435).xyz), float3(_476.xyz), float3(_483.xyz), float3(Source.Sample(_Source_sampler, _461).xyz)))) + mul(_1807, float4x3(float3(Source.Sample(_Source_sampler, _435 + _421).xyz), float3(_507.xyz), float3(_516.xyz), float3(Source.Sample(_Source_sampler, _461 + _421).xyz)))) + mul(_1808, float4x3(float3(Source.Sample(_Source_sampler, _435 + _534).xyz), float3(Source.Sample(_Source_sampler, _426 + _534).xyz), float3(Source.Sample(_Source_sampler, _451 + _534).xyz), float3(Source.Sample(_Source_sampler, _461 + _534).xyz)));
    float3 _697 = _690 / dot(mul(1.0f.xxxx, float4x4(_1805, _1806, _1807, _1808)), 1.0f.xxxx).xxx;
    FragColor = float4(lerp(_697, clamp(_697, min(_477, min(_484, min(_508, _517))), max(_477, max(_484, max(_508, _517)))), params_JINC2_AR_STRENGTH.xxx), 1.0f);
}

SPIRV_Cross_Output main(SPIRV_Cross_Input stage_input)
{
    vTexCoord = stage_input.vTexCoord;
    frag_main();
    SPIRV_Cross_Output stage_output;
    stage_output.FragColor = FragColor;
    return stage_output;
}
