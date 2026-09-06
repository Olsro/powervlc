// Generated from crt/shaders/newpixie-mini/newpixie-mini.slang. See slang/upstream for licence/source.
cbuffer Push : register(b1)
{
    float4 params_OutputSize : packoffset(c1);
    float params_curvature : packoffset(c2);
    float params_vignette : packoffset(c2.y);
};

Texture2D<float4> Source : register(t3);
SamplerState _Source_sampler : register(s3);

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
    float2 _377 = ((vTexCoord - 0.5f.xx) * float2(0.925000011920928955078125f, 1.0950000286102294921875f)) * params_curvature;
    float _386 = _377.x * (1.0f + pow(abs(_377.y) * 0.25f, 2.0f));
    float2 _160 = lerp((((float2(_386, _377.y * (1.0f + pow(abs(_386) * 0.3333333432674407958984375f, 2.0f))) / params_curvature.xx) + 0.5f.xx) * 0.920000016689300537109375f) + 0.039999999105930328369140625f.xx, vTexCoord, 0.4000000059604644775390625f.xx);
    float2 _175 = (_160 * 1.10099995136260986328125f) + float2(-0.0475000031292438507080078125f, -0.051500000059604644775390625f);
    float2 _184 = vTexCoord * params_OutputSize.xy;
    float _201 = ((sin(_184.y * 1.5f) / params_OutputSize.x) * 0.25f) + _175.x;
    float _205 = _175.y;
    float2 _416 = (float2(_201 + 0.000899999984540045261383056640625f, _205 + 0.000899999984540045261383056640625f) * float2(1.02499997615814208984375f, 0.920000016689300537109375f)) + float2(-0.012500000186264514923095703125f, 0.039999999105930328369140625f);
    float2 _435 = (float2(_201, _205 - 0.0010999999940395355224609375f) * float2(1.02499997615814208984375f, 0.920000016689300537109375f)) + float2(-0.012500000186264514923095703125f, 0.039999999105930328369140625f);
    float2 _454 = (float2(_201 - 0.00150000001303851604461669921875f, _205) * float2(1.02499997615814208984375f, 0.920000016689300537109375f)) + float2(-0.012500000186264514923095703125f, 0.039999999105930328369140625f);
    float3 _537 = float3((pow(abs(Source.Sample(_Source_sampler, float2(_416.x, 1.0f - _416.y)).xyz), 2.2000000476837158203125f.xxx) * 1.25f.xxx).x + 0.0199999995529651641845703125f, (pow(abs(Source.Sample(_Source_sampler, float2(_435.x, 1.0f - _435.y)).xyz), 2.2000000476837158203125f.xxx) * 1.25f.xxx).y + 0.0199999995529651641845703125f, (pow(abs(Source.Sample(_Source_sampler, float2(_454.x, 1.0f - _454.y)).xyz), 2.2000000476837158203125f.xxx) * 1.25f.xxx).z + 0.0199999995529651641845703125f);
    float3 _273 = _537 * _537;
    float _296 = _160.x;
    float _299 = _160.y;
    float3 _473 = max(0.0f.xxx, (((clamp((_537 + _273) + (((_273 * _537) * _537) * _537), 0.0f.xxx, 10.0f.xxx) * (1.2999999523162841796875f * pow((1.0f - (0.9900000095367431640625f * params_vignette)) + ((((4.0f * _296) * _299) * (1.0f - _296)) * (1.0f - _299)), 0.5f))) * pow(clamp(0.3499999940395355224609375f + (0.180000007152557373046875f * sin((_299 * params_OutputSize.y) * 1.5f)), 0.0f, 1.0f), 0.89999997615814208984375f).xxx) * (1.0f - (0.23000000417232513427734375f * clamp(mod(_184.x, 3.0f) * 0.5f, 0.0f, 1.0f)))) - 0.0040000001899898052215576171875f.xxx);
    float3 _476 = _473 * 6.19999980926513671875f;
    FragColor = float4((_473 * (_476 + 0.5f.xxx)) / ((_473 * (_476 + 1.7000000476837158203125f.xxx)) + 0.0599999986588954925537109375f.xxx), 1.0f);
}

SPIRV_Cross_Output main(SPIRV_Cross_Input stage_input)
{
    vTexCoord = stage_input.vTexCoord;
    frag_main();
    SPIRV_Cross_Output stage_output;
    stage_output.FragColor = FragColor;
    return stage_output;
}
