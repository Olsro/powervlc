// Generated from crt/shaders/torridgristle/ScanlineSimple.slang. See slang/upstream for licence/source.
cbuffer Push : register(b1)
{
    float4 params_OutputSize : packoffset(c2);
    float params_ScanlineSize : packoffset(c3.y);
    float params_YIQAmount : packoffset(c3.z);
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
    float4 _20 = Source.Sample(_Source_sampler, vTexCoord);
    float3 _21 = _20.xyz;
    float _27 = _20.x;
    float _30 = _20.y;
    float _36 = _20.z;
    float _38 = max(max(_27, _30), max(_30, _36));
    float _58 = lerp(_38, ((0.2989999949932098388671875f * _27) + (0.58700001239776611328125f * _30)) + (0.114000000059604644775390625f * _36), _38);
    float _100 = clamp(sqrt(1.0f - pow(abs((mod(vTexCoord.y * params_OutputSize.y, params_ScanlineSize) / params_ScanlineSize) - 0.5f) * 2.0f, 2.0f)) - (1.0f - _58), 0.0f, 1.0f) / _58;
    float3 _114 = mul(float3x3(float3(0.2989999949932098388671875f, 0.595715999603271484375f, 0.211456000804901123046875f), float3(0.58700001239776611328125f, -0.2744530141353607177734375f, -0.52259099483489990234375f), float3(0.114000000059604644775390625f, -0.3212629854679107666015625f, 0.311134994029998779296875f)), _21);
    _114.x = _114.x * _100;
    FragColor = float4(lerp(_21 * _100, mul(float3x3(1.0f.xxx, float3(0.9563000202178955078125f, -0.2721000015735626220703125f, -1.10699999332427978515625f), float3(0.620999991893768310546875f, -0.64740002155303955078125f, 1.70459997653961181640625f)), _114) * lerp(_100, 1.0f, 0.75f), params_YIQAmount.xxx), 1.0f);
}

SPIRV_Cross_Output main(SPIRV_Cross_Input stage_input)
{
    vTexCoord = stage_input.vTexCoord;
    frag_main();
    SPIRV_Cross_Output stage_output;
    stage_output.FragColor = FragColor;
    return stage_output;
}
