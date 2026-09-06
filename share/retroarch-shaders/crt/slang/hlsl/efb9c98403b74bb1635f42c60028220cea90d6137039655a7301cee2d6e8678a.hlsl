// Generated from crt/shaders/crt-blurPi.slang. See slang/upstream for licence/source.
cbuffer Push : register(b1)
{
    float4 params_OutputSize : packoffset(c2);
    float params_scanlineGain : packoffset(c3.y);
    float params_rgbExtraGain : packoffset(c3.z);
    float params_blurGain : packoffset(c3.w);
    float params_blurRadius : packoffset(c4);
};

Texture2D<float4> Source : register(t2);
SamplerState _Source_sampler : register(s2);

static float2 dot_size;
static float2 vTexCoord;
static float4 FragColor;

struct SPIRV_Cross_Input
{
    float2 vTexCoord : TEXCOORD0;
    float2 dot_size : TEXCOORD1;
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
    float2 _23 = dot_size * params_blurRadius;
    float _53 = 0.25f * params_blurGain;
    float _58 = _23.x;
    float _102 = mod(float(int(vTexCoord.y * params_OutputSize.y)), 2.0f);
    FragColor = ((((Source.Sample(_Source_sampler, vTexCoord) * ((1.0f - (0.75f * params_blurGain)) * (1.0f + params_rgbExtraGain))) + (Source.Sample(_Source_sampler, vTexCoord + float2(-_58, 0.0f)) * _53)) + (Source.Sample(_Source_sampler, vTexCoord + float2(_58, 0.0f)) * _53)) + (Source.Sample(_Source_sampler, vTexCoord + float2(0.0f, _23.y)) * _53)) * lerp(1.0f, _102 * _102, params_scanlineGain);
}

SPIRV_Cross_Output main(SPIRV_Cross_Input stage_input)
{
    dot_size = stage_input.dot_size;
    vTexCoord = stage_input.vTexCoord;
    frag_main();
    SPIRV_Cross_Output stage_output;
    stage_output.FragColor = FragColor;
    return stage_output;
}
