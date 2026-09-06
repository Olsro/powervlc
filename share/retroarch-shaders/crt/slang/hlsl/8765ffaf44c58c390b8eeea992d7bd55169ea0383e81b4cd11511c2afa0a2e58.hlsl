// Generated from crt/shaders/crt-cgwg-fast.slang. See slang/upstream for licence/source.
cbuffer Push : register(b1)
{
    float param_CRTCGWG_GAMMA : packoffset(c0);
};

Texture2D<float4> Source : register(t2);
SamplerState _Source_sampler : register(s2);

static float2 ratio_scale;
static float2 c01;
static float2 c11;
static float2 c21;
static float2 c31;
static float2 c02;
static float2 c12;
static float2 c22;
static float2 c32;
static float mod_factor;
static float4 FragColor;

struct SPIRV_Cross_Input
{
    float2 c01 : TEXCOORD1;
    float2 c11 : TEXCOORD2;
    float2 c21 : TEXCOORD3;
    float2 c31 : TEXCOORD4;
    float2 c02 : TEXCOORD5;
    float2 c12 : TEXCOORD6;
    float2 c22 : TEXCOORD7;
    float2 c32 : TEXCOORD8;
    float mod_factor : TEXCOORD9;
    float2 ratio_scale : TEXCOORD10;
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
    float2 _13 = frac(ratio_scale);
    float _106 = _13.x;
    float4 _120 = float4(1.0f + _106, _106, 1.0f - _106, 2.0f - _106) + 0.004999999888241291046142578125f.xxxx;
    float4 _133 = (sin(_120 * 3.1415927410125732421875f) * sin(_120 * 1.57079637050628662109375f)) / (_120 * _120);
    float4 _139 = _133 / dot(_133, 1.0f.xxxx).xxxx;
    float _145 = _13.y;
    float3 _175 = clamp(mul(_139, float4x3(float3(Source.Sample(_Source_sampler, c01).xyz), float3(Source.Sample(_Source_sampler, c11).xyz), float3(Source.Sample(_Source_sampler, c21).xyz), float3(Source.Sample(_Source_sampler, c31).xyz))), 0.0f.xxx, 1.0f.xxx);
    float3 _182 = clamp(mul(_139, float4x3(float3(Source.Sample(_Source_sampler, c02).xyz), float3(Source.Sample(_Source_sampler, c12).xyz), float3(Source.Sample(_Source_sampler, c22).xyz), float3(Source.Sample(_Source_sampler, c32).xyz))), 0.0f.xxx, 1.0f.xxx);
    float3 _190 = (pow(_175, 4.0f.xxx) * 2.0f) + 2.0f.xxx;
    float3 _196 = (pow(_182, 4.0f.xxx) * 2.0f) + 2.0f.xxx;
    float3 _206 = param_CRTCGWG_GAMMA.xxx;
    FragColor = float4(pow(lerp(float3(1.0f, 0.699999988079071044921875f, 1.0f), float3(0.699999988079071044921875f, 1.0f, 0.699999988079071044921875f), floor(mod(mod_factor, 2.0f)).xxx) * ((pow(_175, _206) * (exp(-pow((3.3299999237060546875f * _145).xxx * rsqrt(_190 * 0.5f), _190)) / ((_190 * 0.1319999992847442626953125f) + 0.3919999897480010986328125f.xxx))) + (pow(_182, _206) * (exp(-pow((((-3.3299999237060546875f) * _145) + 3.3299999237060546875f).xxx * rsqrt(_196 * 0.5f), _196)) / ((_196 * 0.1319999992847442626953125f) + 0.3919999897480010986328125f.xxx)))), 0.4545449912548065185546875f.xxx), 1.0f);
}

SPIRV_Cross_Output main(SPIRV_Cross_Input stage_input)
{
    ratio_scale = stage_input.ratio_scale;
    c01 = stage_input.c01;
    c11 = stage_input.c11;
    c21 = stage_input.c21;
    c31 = stage_input.c31;
    c02 = stage_input.c02;
    c12 = stage_input.c12;
    c22 = stage_input.c22;
    c32 = stage_input.c32;
    mod_factor = stage_input.mod_factor;
    frag_main();
    SPIRV_Cross_Output stage_output;
    stage_output.FragColor = FragColor;
    return stage_output;
}
