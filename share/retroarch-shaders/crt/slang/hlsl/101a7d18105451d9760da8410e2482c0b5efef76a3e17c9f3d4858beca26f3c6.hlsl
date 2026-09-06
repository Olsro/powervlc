// Generated from crt/shaders/crt-royale/src-fast/crt-royale-bloom-vertical.slang. See slang/upstream for licence/source.
Texture2D<float4> Source : register(t2);
SamplerState _Source_sampler : register(s2);

static float4 FragColor;
static float2 tex_uv;
static float2 bloom_dxdy;
static float weight_sum_inv;
static float4 w1_8;
static float4 w1_8_ratio;

struct SPIRV_Cross_Input
{
    float2 tex_uv : TEXCOORD0;
    float2 bloom_dxdy : TEXCOORD1;
    float4 w1_8 : TEXCOORD3;
    float4 w1_8_ratio : TEXCOORD4;
    float weight_sum_inv : TEXCOORD5;
};

struct SPIRV_Cross_Output
{
    float4 FragColor : SV_Target0;
};

void frag_main()
{
    float2 _391 = bloom_dxdy * (7.0f + w1_8_ratio.w);
    float2 _406 = bloom_dxdy * (5.0f + w1_8_ratio.z);
    float2 _421 = bloom_dxdy * (3.0f + w1_8_ratio.y);
    float2 _436 = bloom_dxdy * (1.0f + w1_8_ratio.x);
    float3 _513 = (((((((((Source.Sample(_Source_sampler, tex_uv - _391).xyz * w1_8.w) + (Source.Sample(_Source_sampler, tex_uv - _406).xyz * w1_8.z)) + (Source.Sample(_Source_sampler, tex_uv - _421).xyz * w1_8.y)) + (Source.Sample(_Source_sampler, tex_uv - _436).xyz * w1_8.x)) + (Source.Sample(_Source_sampler, tex_uv).xyz * 1.0f)) + (Source.Sample(_Source_sampler, tex_uv + _436).xyz * w1_8.x)) + (Source.Sample(_Source_sampler, tex_uv + _421).xyz * w1_8.y)) + (Source.Sample(_Source_sampler, tex_uv + _406).xyz * w1_8.z)) + (Source.Sample(_Source_sampler, tex_uv + _391).xyz * w1_8.w)) * weight_sum_inv;
    FragColor = float4(_513, 1.0f);
}

SPIRV_Cross_Output main(SPIRV_Cross_Input stage_input)
{
    tex_uv = stage_input.tex_uv;
    bloom_dxdy = stage_input.bloom_dxdy;
    weight_sum_inv = stage_input.weight_sum_inv;
    w1_8 = stage_input.w1_8;
    w1_8_ratio = stage_input.w1_8_ratio;
    frag_main();
    SPIRV_Cross_Output stage_output;
    stage_output.FragColor = FragColor;
    return stage_output;
}
