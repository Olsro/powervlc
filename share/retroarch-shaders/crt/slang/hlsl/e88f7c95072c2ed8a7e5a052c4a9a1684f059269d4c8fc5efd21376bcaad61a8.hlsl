// Generated from crt/shaders/crt-interlaced-halation/crt-interlaced-halation-pass2.slang. See slang/upstream for licence/source.
cbuffer Push : register(b1)
{
    float4 params_SourceSize : packoffset(c0);
    uint params_FrameCount : packoffset(c3);
};

Texture2D<float4> crt_interlaced_halation_refpass : register(t3);
SamplerState _crt_interlaced_halation_refpass_sampler : register(s3);
Texture2D<float4> Source : register(t2);
SamplerState _Source_sampler : register(s2);

static float2 vTexCoord;
static float3 stretch;
static float2 sinangle;
static float2 cosangle;
static float2 ilfac;
static float2 one;
static float mod_factor;
static float4 FragColor;

struct SPIRV_Cross_Input
{
    float2 vTexCoord : TEXCOORD0;
    float2 one : TEXCOORD1;
    float mod_factor : TEXCOORD2;
    float2 ilfac : TEXCOORD3;
    float3 stretch : TEXCOORD4;
    float2 sinangle : TEXCOORD5;
    float2 cosangle : TEXCOORD6;
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
    float2 _248 = (((vTexCoord - 0.5f.xx) * float2(1.0f, 0.75f)) * stretch.z) + stretch.xy;
    float _705 = dot(_248, _248) + 4.0f;
    float _722 = (2.0f * (dot(_248, sinangle) - ((2.0f * cosangle.x) * cosangle.y))) - 4.0f;
    float2 _638 = (((((_722 * (-2.0f)) - sqrt((4.0f * (_722 * _722)) - ((4.0f * _705) * (4.0f + ((8.0f * cosangle.x) * cosangle.y))))) / (2.0f * _705)).xx * _248) - ((-2.0f).xx * sinangle)) * 0.5f.xx;
    float2 _641 = sinangle / cosangle;
    float2 _644 = _638 / cosangle;
    float _648 = dot(_641, _641) + 1.0f;
    float _651 = dot(_644, _641);
    float _671 = ((_651 * 2.0f) + sqrt((4.0f * (_651 * _651)) - ((4.0f * _648) * (dot(_644, _644) - 1.0f)))) / (2.0f * _648);
    float _684 = max(abs(2.0f * acos(_671)), 9.9999997473787516355514526367188e-06f);
    float2 _262 = ((((_638 - (sinangle * _671)) / cosangle) * _684) / sin(_684 * 0.5f).xx) * float2(1.0f, 1.33333337306976318359375f);
    float2 _263 = _262 + 0.5f.xx;
    float2 _284 = 0.00999999977648258209228515625f.xx - min(min(_263, 0.5f.xx - _262) * float2(1.0f, 0.75f), 0.00999999977648258209228515625f.xx);
    float _795;
    if (ilfac.y > 1.5f)
    {
        _795 = mod(float(params_FrameCount), 2.0f);
    }
    else
    {
        _795 = 0.0f;
    }
    float2 _331 = float2(0.0f, _795);
    float2 _344 = (((_263 * params_SourceSize.xy) - 0.5f.xx) + _331) / ilfac;
    float2 _347 = frac(_344);
    float2 _358 = (((floor(_344) * ilfac) + 0.5f.xx) - _331) / params_SourceSize.xy;
    float _362 = _347.x;
    float4 _377 = max(abs(float4(1.0f + _362, _362, 1.0f - _362, 2.0f - _362) * 3.1415927410125732421875f), 9.9999997473787516355514526367188e-06f.xxxx);
    float4 _389 = ((sin(_377) * 2.0f) * sin(_377 * 0.5f.xxxx)) / (_377 * _377);
    float4 _395 = _389 / dot(_389, 1.0f.xxxx).xxxx;
    float _406 = -one.x;
    float _433 = 2.0f * one.x;
    float4 _466 = clamp(mul(_395, float4x4(pow(crt_interlaced_halation_refpass.Sample(_crt_interlaced_halation_refpass_sampler, _358 + float2(_406, 0.0f)), 2.400000095367431640625f.xxxx), pow(crt_interlaced_halation_refpass.Sample(_crt_interlaced_halation_refpass_sampler, _358), 2.400000095367431640625f.xxxx), pow(crt_interlaced_halation_refpass.Sample(_crt_interlaced_halation_refpass_sampler, _358 + float2(one.x, 0.0f)), 2.400000095367431640625f.xxxx), pow(crt_interlaced_halation_refpass.Sample(_crt_interlaced_halation_refpass_sampler, _358 + float2(_433, 0.0f)), 2.400000095367431640625f.xxxx))), 0.0f.xxxx, 1.0f.xxxx);
    float4 _537 = clamp(mul(_395, float4x4(pow(crt_interlaced_halation_refpass.Sample(_crt_interlaced_halation_refpass_sampler, _358 + float2(_406, one.y)), 2.400000095367431640625f.xxxx), pow(crt_interlaced_halation_refpass.Sample(_crt_interlaced_halation_refpass_sampler, _358 + float2(0.0f, one.y)), 2.400000095367431640625f.xxxx), pow(crt_interlaced_halation_refpass.Sample(_crt_interlaced_halation_refpass_sampler, _358 + one), 2.400000095367431640625f.xxxx), pow(crt_interlaced_halation_refpass.Sample(_crt_interlaced_halation_refpass_sampler, _358 + float2(_433, one.y)), 2.400000095367431640625f.xxxx))), 0.0f.xxxx, 1.0f.xxxx);
    float _541 = _347.y;
    float4 _761 = 0.300000011920928955078125f.xxxx + (pow(_466, 3.0f.xxxx) * 0.100000001490116119384765625f);
    float4 _765 = _541.xxxx / _761;
    float4 _782 = 0.300000011920928955078125f.xxxx + (pow(_537, 3.0f.xxxx) * 0.100000001490116119384765625f);
    float4 _786 = (1.0f - _541).xxxx / _782;
    FragColor = float4(pow(((((_466 * ((exp((-_765) * _765) * 0.4000000059604644775390625f) / _761)) + (_537 * ((exp((-_786) * _786) * 0.4000000059604644775390625f) / _782))).xyz + (pow(Source.Sample(_Source_sampler, _263).xyz, 2.2000000476837158203125f.xxx) * 0.100000001490116119384765625f)) * clamp((0.00999999977648258209228515625f - sqrt(dot(_284, _284))) * 800.0f, 0.0f, 1.0f).xxx) * lerp(1.0f.xxx, 1.0f.xxx, floor(mod(mod_factor, 2.0f)).xxx), 0.454545438289642333984375f.xxx), 1.0f);
}

SPIRV_Cross_Output main(SPIRV_Cross_Input stage_input)
{
    vTexCoord = stage_input.vTexCoord;
    stretch = stage_input.stretch;
    sinangle = stage_input.sinangle;
    cosangle = stage_input.cosangle;
    ilfac = stage_input.ilfac;
    one = stage_input.one;
    mod_factor = stage_input.mod_factor;
    frag_main();
    SPIRV_Cross_Output stage_output;
    stage_output.FragColor = FragColor;
    return stage_output;
}
