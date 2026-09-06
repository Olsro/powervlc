// Generated from crt/shaders/crt-royale/src/crt-royale-bloom-vertical.slang. See slang/upstream for licence/source.
Texture2D<float4> Source : register(t2);
SamplerState _Source_sampler : register(s2);

static float bloom_sigma_runtime;
static float2 tex_uv;
static float2 bloom_dxdy;
static float4 FragColor;

struct SPIRV_Cross_Input
{
    float2 tex_uv : TEXCOORD0;
    float2 bloom_dxdy : TEXCOORD1;
    float bloom_sigma_runtime : TEXCOORD2;
};

struct SPIRV_Cross_Output
{
    float4 FragColor : SV_Target0;
};

void frag_main()
{
    float _742 = bloom_sigma_runtime * bloom_sigma_runtime;
    float _749 = exp((-2.0f) / _742);
    float _755 = exp((-8.0f) / _742);
    float _761 = exp((-18.0f) / _742);
    float _767 = exp((-32.0f) / _742);
    float _772 = exp((-0.5f) / _742) + _749;
    float _775 = exp((-4.5f) / _742) + _755;
    float _778 = exp((-12.5f) / _742) + _761;
    float _781 = exp((-24.5f) / _742) + _767;
    float2 _799 = bloom_dxdy * (7.0f + (_767 / _781));
    float2 _811 = bloom_dxdy * (5.0f + (_761 / _778));
    float2 _823 = bloom_dxdy * (3.0f + (_755 / _775));
    float2 _835 = bloom_dxdy * (1.0f + (_749 / _772));
    FragColor = float4((((((((((Source.Sample(_Source_sampler, tex_uv - _799).xyz * _781) + (Source.Sample(_Source_sampler, tex_uv - _811).xyz * _778)) + (Source.Sample(_Source_sampler, tex_uv - _823).xyz * _775)) + (Source.Sample(_Source_sampler, tex_uv - _835).xyz * _772)) + (Source.Sample(_Source_sampler, tex_uv).xyz * 1.0f)) + (Source.Sample(_Source_sampler, tex_uv + _835).xyz * _772)) + (Source.Sample(_Source_sampler, tex_uv + _823).xyz * _775)) + (Source.Sample(_Source_sampler, tex_uv + _811).xyz * _778)) + (Source.Sample(_Source_sampler, tex_uv + _799).xyz * _781)) * min(exp(exp(0.3483484089374542236328125f / (bloom_sigma_runtime - 0.086058728396892547607421875f))), 0.3993345797061920166015625f / bloom_sigma_runtime), 1.0f);
}

SPIRV_Cross_Output main(SPIRV_Cross_Input stage_input)
{
    bloom_sigma_runtime = stage_input.bloom_sigma_runtime;
    tex_uv = stage_input.tex_uv;
    bloom_dxdy = stage_input.bloom_dxdy;
    frag_main();
    SPIRV_Cross_Output stage_output;
    stage_output.FragColor = FragColor;
    return stage_output;
}
