// Generated from crt/shaders/crt-royale/src-fast/crt-royale-first-pass-linearize-crt-gamma-bob-fields.slang. See slang/upstream for licence/source.
cbuffer UBO : register(b0)
{
    float global_crt_gamma : packoffset(c4);
    float global_interlace_bff : packoffset(c11);
    float global_interlace_detect_toggle : packoffset(c11.z);
};

cbuffer Push : register(b1)
{
    float4 params_SourceSize : packoffset(c0);
    uint params_FrameCount : packoffset(c3);
};

Texture2D<float4> Source : register(t2);
SamplerState _Source_sampler : register(s2);

static float2 uv_step;
static float2 tex_uv;
static float interlaced;
static float4 FragColor;

struct SPIRV_Cross_Input
{
    float2 tex_uv : TEXCOORD0;
    float2 uv_step : TEXCOORD1;
    float interlaced : TEXCOORD2;
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
    if (global_interlace_detect_toggle != 0.0f)
    {
        float2 _183 = float2(0.0f, uv_step.y);
        float3 _199 = global_crt_gamma.xxx;
        float _232 = interlaced + 1.0f;
        FragColor = float4(lerp(pow(Source.Sample(_Source_sampler, tex_uv).xyz, _199), (pow(Source.Sample(_Source_sampler, tex_uv - _183).xyz, _199) + pow(Source.Sample(_Source_sampler, tex_uv + _183).xyz, _199)) * 0.5f, mod(floor((tex_uv.y * params_SourceSize.y) - 0.4995000064373016357421875f) + mod(float(params_FrameCount) + global_interlace_bff, _232), _232).xxx), 1.0f);
    }
    else
    {
        FragColor = float4(pow(Source.Sample(_Source_sampler, tex_uv).xyz, global_crt_gamma.xxx), 1.0f);
    }
}

SPIRV_Cross_Output main(SPIRV_Cross_Input stage_input)
{
    uv_step = stage_input.uv_step;
    tex_uv = stage_input.tex_uv;
    interlaced = stage_input.interlaced;
    frag_main();
    SPIRV_Cross_Output stage_output;
    stage_output.FragColor = FragColor;
    return stage_output;
}
