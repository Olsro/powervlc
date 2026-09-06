// Generated from crt/shaders/metacrt/Image.slang. See slang/upstream for licence/source.
cbuffer Push : register(b1)
{
    float4 params_OutputSize : packoffset(c2);
    uint params_FrameCount : packoffset(c3);
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
    float3 _617 = Source.Load(int3(int2(0, 0), 0)).xyz;
    float4 _648 = Source.Load(int3(int2(1, 0), 0));
    float4 _654 = Source.Load(int3(int2(2, 0), 0));
    float _635 = _654.z;
    float3 _666 = Source.Load(int3(int2(3, 0), 0)).xyz;
    float4 _697 = Source.Load(int3(int2(4, 0), 0));
    float4 _386 = Source.Load(int3(int2(vTexCoord * params_OutputSize.xy), 0));
    float _707 = max(0.0f, _386.w);
    float2 _730 = (vTexCoord * 2.0f) - 1.0f.xx;
    float3 _750 = normalize(_648.xyz - _617);
    float3 _753 = normalize(cross(float3(0.0f, 1.0f, 0.0f), _750));
    float3 _803 = normalize(_697.xyz - _666);
    float3 _806 = normalize(cross(float3(0.0f, 1.0f, 0.0f), _803));
    float3 _783 = mul(float3x3(_806, normalize(cross(_803, _806)), _803), (_617 + (normalize(mul(float3(_730.x * (params_OutputSize.x / params_OutputSize.y), _730.y, 1.0f / tan(radians(_648.w))), float3x3(_753, normalize(cross(_750, _753)), _750))) * _707)) - _666);
    float2 _793 = _783.xy / (_783.z * tan(radians(_697.w))).xx;
    _793.x = _793.x * (params_OutputSize.y / params_OutputSize.x);
    float2 _842 = (_793 * 0.5f) + 0.5f.xx;
    float _851 = min(1.0f, (_635 * _635) * 0.5f);
    float _862 = _635 - 0.02999999932944774627685546875f;
    float _865 = abs((_851 * (0.02999999932944774627685546875f * (_707 - _635))) / (_707 * _862));
    float _435 = max(0.001000000047497451305389404296875f, _865);
    float _1013;
    float3 _1014;
    _1014 = _386.xyz * _435;
    _1013 = _435;
    float _557;
    float _1026;
    float3 _1027;
    int _1012 = 1;
    float _1015 = 0.0f;
    for (; _1012 < 64; _1015 = _557, _1014 = _1027, _1013 = _1026, _1012++)
    {
        float2 _872 = frac(((((float(params_FrameCount) * 0.01666666753590106964111328125f) + _1015) + vTexCoord.x) + (vTexCoord.y * 12.34500026702880859375f)).xx * float2(4.438974857330322265625f, 3.9729731082916259765625f));
        float2 _881 = _872 + dot(_872.yx, _872 + 19.1900005340576171875f.xx).xx;
        float _500 = _1015 * 2.3999626636505126953125f;
        float4 _523 = Source.SampleLevel(_Source_sampler, lerp(vTexCoord, _842, ((frac(_881.x * _881.y) - 0.5f) * 0.5f).xx) + (float2(sin(_500), cos(_500)) * ((_865 * sqrt(_1015)) * 0.125f)), 0.0f);
        float _891 = max(0.0f, _523.w);
        if (_891 > 0.0f)
        {
            float _544 = max(0.001000000047497451305389404296875f, abs((_851 * (0.02999999932944774627685546875f * (_891 - _635))) / (_891 * _862)));
            _1027 = _1014 + (_523.xyz * _544);
            _1026 = _1013 + _544;
        }
        else
        {
            _1027 = _1014;
            _1026 = _1013;
        }
        _557 = _1015 + 1.0f;
    }
    FragColor = float4(_1014 / _1013.xxx, 1.0f);
    float4 _579 = FragColor;
    float3 _581 = _579.xyz * pow(max(0.0f, 1.0f - length(((vTexCoord - 0.5f.xx) * 1.41421353816986083984375f) * 0.699999988079071044921875f)), 2.0f);
    FragColor.x = _581.x;
    FragColor.y = _581.y;
    FragColor.z = _581.z;
    float4 _590 = FragColor;
    float3 _948 = _590.xyz * 0.00999999977648258209228515625f;
    float3 _964 = (_590.xyz * (_948 + 0.1319999992847442626953125f.xxx)) / ((_590.xyz * (_948 + 0.16300000250339508056640625f.xxx)) + 0.101000003516674041748046875f.xxx);
    FragColor.x = _964.x;
    FragColor.y = _964.y;
    FragColor.z = _964.z;
    FragColor.w = 1.0f;
}

SPIRV_Cross_Output main(SPIRV_Cross_Input stage_input)
{
    vTexCoord = stage_input.vTexCoord;
    frag_main();
    SPIRV_Cross_Output stage_output;
    stage_output.FragColor = FragColor;
    return stage_output;
}
