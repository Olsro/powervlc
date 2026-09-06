// Generated from crt/shaders/crt-beans/composite_output.slang. See slang/upstream for licence/source.
cbuffer Push : register(b1)
{
    float params_OutputGamma : packoffset(c0);
    float4 params_ScanlinesSize : packoffset(c2);
    uint params_FrameCount : packoffset(c3);
    float params_GlowAmount : packoffset(c3.z);
};

Texture2D<float4> BlueNoiseTex : register(t3);
SamplerState _BlueNoiseTex_sampler : register(s3);
Texture2D<float4> Source : register(t1);
SamplerState _Source_sampler : register(s1);
Texture2D<float4> Scanlines : register(t2);
SamplerState _Scanlines_sampler : register(s2);

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
    int2 _246 = int2(floor(vTexCoord * params_ScanlinesSize.xy));
    float3 _262 = lerp(Scanlines.Load(int3(_246, 0)).xyz, Source.SampleLevel(_Source_sampler, vTexCoord, 0.0f).xyz, params_GlowAmount.xxx);
    float3 _476;
    if (params_OutputGamma < 0.5f)
    {
        float3 _345 = clamp(_262, 0.0f.xxx, 1.0f.xxx);
        bool3 _347 = bool3(_345.x < 0.003130800090730190277099609375f.xxx.x, _345.y < 0.003130800090730190277099609375f.xxx.y, _345.z < 0.003130800090730190277099609375f.xxx.z);
        float3 _349 = _345 * 12.9200000762939453125f.xxx;
        float3 _353 = (1.05499994754791259765625f.xxx * pow(_345, 0.4166666567325592041015625f.xxx)) - 0.054999999701976776123046875f.xxx;
        float3 _321 = floor(float3(_347.x ? _349.x : _353.x, _347.y ? _349.y : _353.y, _347.z ? _349.z : _353.z) * 254.9999847412109375f.xxx) * 0.0039215688593685626983642578125f;
        float3 _324 = _321 + 0.0039215688593685626983642578125f.xxx;
        float3 _366 = clamp(_321, 0.0f.xxx, 1.0f.xxx);
        bool3 _368 = bool3(_366.x < 0.040449999272823333740234375f.xxx.x, _366.y < 0.040449999272823333740234375f.xxx.y, _366.z < 0.040449999272823333740234375f.xxx.z);
        float3 _371 = _366 * 0.077399380505084991455078125f.xxx;
        float3 _377 = pow((_366 + 0.054999999701976776123046875f.xxx) * 0.947867333889007568359375f.xxx, 2.400000095367431640625f.xxx);
        float3 _390 = clamp(_324, 0.0f.xxx, 1.0f.xxx);
        bool3 _392 = bool3(_390.x < 0.040449999272823333740234375f.xxx.x, _390.y < 0.040449999272823333740234375f.xxx.y, _390.z < 0.040449999272823333740234375f.xxx.z);
        float3 _395 = _390 * 0.077399380505084991455078125f.xxx;
        float3 _401 = pow((_390 + 0.054999999701976776123046875f.xxx) * 0.947867333889007568359375f.xxx, 2.400000095367431640625f.xxx);
        float3 _330 = lerp(float3(_368.x ? _371.x : _377.x, _368.y ? _371.y : _377.y, _368.z ? _371.z : _377.z), float3(_392.x ? _395.x : _401.x, _392.y ? _395.y : _401.y, _392.z ? _395.z : _401.z), BlueNoiseTex.Load(int3((_246 + (int(params_FrameCount & 63u).xx * int2(17, 13))) & int2(63, 63), 0)).xyz);
        bool3 _335 = bool3(_330.x < _262.x, _330.y < _262.y, _330.z < _262.z);
        _476 = float3(_335.x ? _324.x : _321.x, _335.y ? _324.y : _321.y, _335.z ? _324.z : _321.z);
    }
    else
    {
        float3 _436 = floor(pow(clamp(_262, 0.0f.xxx, 1.0f.xxx), 0.4545454680919647216796875f.xxx) * 254.9999847412109375f.xxx) * 0.0039215688593685626983642578125f;
        float3 _439 = _436 + 0.0039215688593685626983642578125f.xxx;
        float3 _445 = lerp(pow(clamp(_436, 0.0f.xxx, 1.0f.xxx), 2.2000000476837158203125f.xxx), pow(clamp(_439, 0.0f.xxx, 1.0f.xxx), 2.2000000476837158203125f.xxx), BlueNoiseTex.Load(int3((_246 + (int(params_FrameCount & 63u).xx * int2(17, 13))) & int2(63, 63), 0)).xyz);
        bool3 _450 = bool3(_445.x < _262.x, _445.y < _262.y, _445.z < _262.z);
        _476 = float3(_450.x ? _439.x : _436.x, _450.y ? _439.y : _436.y, _450.z ? _439.z : _436.z);
    }
    FragColor = float4(_476, 1.0f);
}

SPIRV_Cross_Output main(SPIRV_Cross_Input stage_input)
{
    vTexCoord = stage_input.vTexCoord;
    frag_main();
    SPIRV_Cross_Output stage_output;
    stage_output.FragColor = FragColor;
    return stage_output;
}
