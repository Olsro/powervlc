// Generated from crt/shaders/fake-crt-geom-potato.slang. See slang/upstream for licence/source.
cbuffer Push : register(b1)
{
    float4 params_SourceSize : packoffset(c0);
    float params_size : packoffset(c3.y);
    float params_warp : packoffset(c3.z);
    float params_border : packoffset(c3.w);
    float params_hheld_mode : packoffset(c4);
};

Texture2D<float4> Source : register(t1);
SamplerState _Source_sampler : register(s1);

static float2 vTexCoord;
static float2 screenscale;
static float maskpos;
static float4 FragColor;

struct SPIRV_Cross_Input
{
    float2 vTexCoord : TEXCOORD0;
    float2 screenscale : TEXCOORD1;
    float maskpos : TEXCOORD2;
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
    float2 _15 = vTexCoord * screenscale;
    float _21 = _15.x;
    float _23 = _21 - 0.5f;
    float _28 = _15.y - 0.5f;
    float _46 = _21 + (((_28 * _28) * params_warp) * _23);
    float _58 = _15.y + (((_23 * _23) * params_warp) * _28);
    float2 _64 = float2(_46, _58) / screenscale;
    float2 _72 = _64 * params_SourceSize.xy;
    float2 _77 = floor(_72) + 0.5f.xx;
    float2 _81 = _72 - _77;
    float _86 = _81.y;
    float2 _243 = _64;
    _243.y = (_77.y + (((((16.0f * _86) * _86) * _86) * _86) * _86)) * params_SourceSize.w;
    float4 _115 = Source.Sample(_Source_sampler, _243);
    float3 _116 = _115.xyz;
    float _121 = dot(0.25f.xxx, _116);
    float3 _224;
    if (mod(floor(maskpos), params_size) == 0.0f)
    {
        _224 = _116 * 0.699999988079071044921875f;
    }
    else
    {
        _224 = _116;
    }
    float3 _226;
    if (params_hheld_mode == 0.0f)
    {
        float _151 = lerp(0.5f, 0.20000000298023223876953125f, _121);
        _226 = _224 * (((_151 * sin((_72.y - 0.25f) * 6.28318500518798828125f)) + 1.0f) - _151);
    }
    else
    {
        _226 = _224;
    }
    float3 _207 = sqrt(_226 * lerp(1.4500000476837158203125f, 1.25f, _121)) * ((smoothstep(0.0f, params_border, _46) * smoothstep(0.0f, params_border, 1.0f - _46)) * (smoothstep(0.0f, params_border, _58) * smoothstep(0.0f, params_border, 1.0f - _58)));
    FragColor.x = _207.x;
    FragColor.y = _207.y;
    FragColor.z = _207.z;
}

SPIRV_Cross_Output main(SPIRV_Cross_Input stage_input)
{
    vTexCoord = stage_input.vTexCoord;
    screenscale = stage_input.screenscale;
    maskpos = stage_input.maskpos;
    frag_main();
    SPIRV_Cross_Output stage_output;
    stage_output.FragColor = FragColor;
    return stage_output;
}
