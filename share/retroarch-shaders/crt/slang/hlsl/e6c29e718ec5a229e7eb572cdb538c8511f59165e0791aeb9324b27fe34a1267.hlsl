// Generated from crt/shaders/hyllian/support/glow/blur_horiz.slang. See slang/upstream for licence/source.
cbuffer UBO : register(b0)
{
    float4 global_SourceSize : packoffset(c6);
};

cbuffer Push : register(b1)
{
    float params_GLOW_RADIUS : packoffset(c0);
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
    float2 _140 = float2(params_GLOW_RADIUS * global_SourceSize.z, 0.0f);
    float2 _164 = _140 * 4.0f;
    float2 _174 = _140 * 3.0f;
    float2 _184 = _140 * 2.0f;
    FragColor = float4(((((((((Source.Sample(_Source_sampler, vTexCoord - _164).xyz * 0.001234402996487915515899658203125f) + (Source.Sample(_Source_sampler, vTexCoord - _174).xyz * 0.01430468820035457611083984375f)) + (Source.Sample(_Source_sampler, vTexCoord - _184).xyz * 0.0823177993297576904296875f)) + (Source.Sample(_Source_sampler, vTexCoord - _140).xyz * 0.2352355420589447021484375f)) + (Source.Sample(_Source_sampler, vTexCoord).xyz * 0.3338151276111602783203125f)) + (Source.Sample(_Source_sampler, vTexCoord + _140).xyz * 0.2352355420589447021484375f)) + (Source.Sample(_Source_sampler, vTexCoord + _184).xyz * 0.0823177993297576904296875f)) + (Source.Sample(_Source_sampler, vTexCoord + _174).xyz * 0.01430468820035457611083984375f)) + (Source.Sample(_Source_sampler, vTexCoord + _164).xyz * 0.001234402996487915515899658203125f), 1.0f);
}

SPIRV_Cross_Output main(SPIRV_Cross_Input stage_input)
{
    vTexCoord = stage_input.vTexCoord;
    frag_main();
    SPIRV_Cross_Output stage_output;
    stage_output.FragColor = FragColor;
    return stage_output;
}
