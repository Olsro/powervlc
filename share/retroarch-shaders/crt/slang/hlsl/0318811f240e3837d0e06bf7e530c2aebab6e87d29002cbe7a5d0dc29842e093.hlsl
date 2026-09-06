// Generated from crt/shaders/torridgristle/Candy-Bloom.slang. See slang/upstream for licence/source.
cbuffer Push : register(b1)
{
    float params_GlowLevel : packoffset(c3.y);
    float params_GlowTightness : packoffset(c3.z);
};

Texture2D<float4> Source : register(t2);
SamplerState _Source_sampler : register(s2);
Texture2D<float4> candy_ref : register(t3);
SamplerState _candy_ref_sampler : register(s3);

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
    float4 _20 = Source.Sample(_Source_sampler, vTexCoord);
    float _27 = _20.x;
    float _30 = _20.y;
    float _33 = _20.z;
    float _59 = ((0.2989999949932098388671875f * _27) + (0.58700001239776611328125f * _30)) + (0.114000000059604644775390625f * _33);
    FragColor = float4(lerp(candy_ref.Sample(_candy_ref_sampler, vTexCoord).xyz, clamp(_20.xyz / max(_27, max(_30, _33)).xxx, 0.0f.xxx, 1.0f.xxx), (lerp(1.0f - pow(1.0f - _59, 2.0f), _59 * _59, params_GlowTightness) * params_GlowLevel).xxx), 1.0f);
}

SPIRV_Cross_Output main(SPIRV_Cross_Input stage_input)
{
    vTexCoord = stage_input.vTexCoord;
    frag_main();
    SPIRV_Cross_Output stage_output;
    stage_output.FragColor = FragColor;
    return stage_output;
}
