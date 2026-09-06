// Generated from crt/shaders/metacrt/bufD.slang. See slang/upstream for licence/source.
cbuffer Push : register(b1)
{
    float4 params_OutputSize : packoffset(c2);
    uint params_FrameCount : packoffset(c3);
};

Texture2D<float4> Source : register(t2);
SamplerState _Source_sampler : register(s2);
Texture2D<float4> cubeMap : register(t3);
SamplerState _cubeMap_sampler : register(s3);

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
    float4 _679 = Source.Load(int3(int2(0, 0), 0));
    float3 _654 = _679.xyz;
    float4 _685 = Source.Load(int3(int2(1, 0), 0));
    float4 _691 = Source.Load(int3(int2(2, 0), 0));
    float4 _728 = cubeMap.Load(int3(int2(0, 0), 0));
    float3 _703 = _728.xyz;
    float4 _734 = cubeMap.Load(int3(int2(1, 0), 0));
    float2 _401 = vTexCoord * params_OutputSize.xy;
    FragColor = Source.SampleLevel(_Source_sampler, vTexCoord - (_691.xy / params_OutputSize.xy), 0.0f);
    float2 _763 = (vTexCoord * 2.0f) - 1.0f.xx;
    float3 _783 = normalize(_685.xyz - _654);
    float3 _786 = normalize(cross(float3(0.0f, 1.0f, 0.0f), _783));
    int2 _436 = int2(_401);
    float3 _840 = normalize(_734.xyz - _703);
    float3 _843 = normalize(cross(float3(0.0f, 1.0f, 0.0f), _840));
    float3 _820 = mul(float3x3(_843, normalize(cross(_840, _843)), _840), (_654 + (normalize(mul(float3(_763.x * (params_OutputSize.x / params_OutputSize.y), _763.y, 1.0f / tan(radians(_685.w))), float3x3(_786, normalize(cross(_783, _786)), _783))) * max(0.0f, Source.Load(int3(_436, 0)).w))) - _703);
    float2 _830 = _820.xy / (_820.z * tan(radians(_734.w))).xx;
    _830.x = _830.x * (params_OutputSize.y / params_OutputSize.x);
    float2 _879 = (_830 * 0.5f) + 0.5f.xx;
    bool _461 = all(bool2(_879.x >= 0.0f.xx.x, _879.y >= 0.0f.xx.y));
    bool _468;
    if (_461)
    {
        _468 = all(bool2(_879.x < 1.0f.xx.x, _879.y < 1.0f.xx.y));
    }
    else
    {
        _468 = _461;
    }
    if (_468)
    {
        int2 _484 = int2(floor(_401));
        int _1224;
        float3 _1226;
        float3 _1227;
        _1227 = (-10000.0f).xxx;
        _1226 = 10000.0f.xxx;
        _1224 = -1;
        float3 _1289;
        float3 _1290;
        for (; _1224 <= 1; _1227 = _1290, _1226 = _1289, _1224++)
        {
            _1290 = _1227;
            _1289 = _1226;
            for (int _1284 = -1; _1284 <= 1; )
            {
                float3 _520 = Source.Load(int3(_484 + int2(_1284, _1224), 0)).xyz;
                float3 _895 = _520 * 0.00999999977648258209228515625f;
                float3 _911 = (_520 * (_895 + 0.1319999992847442626953125f.xxx)) / ((_520 * (_895 + 0.16300000250339508056640625f.xxx)) + 0.101000003516674041748046875f.xxx);
                _1290 = max(_1290, _911);
                _1289 = min(_1289, _911);
                _1284++;
                continue;
            }
        }
        float3 _537 = _1226 - 0.001000000047497451305389404296875f.xxx;
        float3 _541 = _1227 + 0.001000000047497451305389404296875f.xxx;
        float3 _550 = cubeMap.SampleLevel(_cubeMap_sampler, _879, 0.0f).xyz;
        float3 _927 = _550 * 0.00999999977648258209228515625f;
        float3 _943 = (_550 * (_927 + 0.1319999992847442626953125f.xxx)) / ((_550 * (_927 + 0.16300000250339508056640625f.xxx)) + 0.101000003516674041748046875f.xxx);
        bool _556 = all(bool3(_943.x >= _537.x, _943.y >= _537.y, _943.z >= _537.z));
        bool _563;
        if (_556)
        {
            _563 = all(bool3(_943.x <= _541.x, _943.y <= _541.y, _943.z <= _541.z));
        }
        else
        {
            _563 = _556;
        }
        float4 _567 = FragColor;
        float3 _573 = lerp(_567.xyz, _550, (_563 ? 0.89999997615814208984375f : 0.0f).xxx);
        FragColor.x = _573.x;
        FragColor.y = _573.y;
        FragColor.z = _573.z;
    }
    float3 _948 = frac(float3(_401, float(params_FrameCount) * 0.01666666753590106964111328125f) * 443.897491455078125f);
    float3 _957 = _948 + dot(_948, _948.yzx + 19.1900005340576171875f.xxx).xxx;
    float4 _601 = FragColor;
    float3 _604 = _601.xyz + (((frac((_957.x + _957.y) * _957.z) * 2.0f) - 1.0f) * 0.02999999932944774627685546875f).xxx;
    FragColor.x = _604.x;
    FragColor.y = _604.y;
    FragColor.z = _604.z;
    float4 _986 = float4(_679.xyz, 0.0f);
    bool4 _1022 = all(bool2(_436.x == int2(0, 0).x, _436.y == int2(0, 0).y)).xxxx;
    float4 _1023 = float4(_1022.x ? _986.x : FragColor.x, _1022.y ? _986.y : FragColor.y, _1022.z ? _986.z : FragColor.z, _1022.w ? _986.w : FragColor.w);
    bool4 _1039 = all(bool2(_436.x == int2(1, 0).x, _436.y == int2(1, 0).y)).xxxx;
    float4 _1040 = float4(_1039.x ? _685.x : _1023.x, _1039.y ? _685.y : _1023.y, _1039.z ? _685.z : _1023.z, _1039.w ? _685.w : _1023.w);
    float4 _1009 = float4(_691.xyz, 0.0f);
    bool4 _1055 = all(bool2(_436.x == int2(2, 0).x, _436.y == int2(2, 0).y)).xxxx;
    FragColor = float4(_1055.x ? _1009.x : _1040.x, _1055.y ? _1009.y : _1040.y, _1055.z ? _1009.z : _1040.z, _1055.w ? _1009.w : _1040.w);
    float4 _1082 = float4(_728.xyz, 0.0f);
    bool4 _1118 = all(bool2(_436.x == int2(3, 0).x, _436.y == int2(3, 0).y)).xxxx;
    float4 _1119 = float4(_1118.x ? _1082.x : FragColor.x, _1118.y ? _1082.y : FragColor.y, _1118.z ? _1082.z : FragColor.z, _1118.w ? _1082.w : FragColor.w);
    bool4 _1134 = all(bool2(_436.x == int2(4, 0).x, _436.y == int2(4, 0).y)).xxxx;
    float4 _1135 = float4(_1134.x ? _734.x : _1119.x, _1134.y ? _734.y : _1119.y, _1134.z ? _734.z : _1119.z, _1134.w ? _734.w : _1119.w);
    float4 _1105 = float4(cubeMap.Load(int3(int2(2, 0), 0)).xyz, 0.0f);
    bool4 _1150 = all(bool2(_436.x == int2(5, 0).x, _436.y == int2(5, 0).y)).xxxx;
    FragColor = float4(_1150.x ? _1105.x : _1135.x, _1150.y ? _1105.y : _1135.y, _1150.z ? _1105.z : _1135.z, _1150.w ? _1105.w : _1135.w);
}

SPIRV_Cross_Output main(SPIRV_Cross_Input stage_input)
{
    vTexCoord = stage_input.vTexCoord;
    frag_main();
    SPIRV_Cross_Output stage_output;
    stage_output.FragColor = FragColor;
    return stage_output;
}
