// Generated from blurs/shaders/royale/blur9fast-vertical.slang. See slang/upstream for licence/source.
Texture2D<float4> Source : register(t2);
SamplerState _Source_sampler : register(s2);

static float2 tex_uv;
static float2 blur_dxdy;
static float4 FragColor;

struct SPIRV_Cross_Input
{
    float2 tex_uv : TEXCOORD0;
    float2 blur_dxdy : TEXCOORD1;
};

struct SPIRV_Cross_Output
{
    float4 FragColor : SV_Target0;
};

void frag_main()
{
    float2 _424 = blur_dxdy * 3.2425899505615234375f;
    float2 _436 = blur_dxdy * 1.38037836551666259765625f;
    FragColor = float4((((((Source.Sample(_Source_sampler, tex_uv - _424).xyz * 0.3054474890232086181640625f) + (Source.Sample(_Source_sampler, tex_uv - _436).xyz * 1.3716285228729248046875f)) + (Source.Sample(_Source_sampler, tex_uv).xyz * 1.0f)) + (Source.Sample(_Source_sampler, tex_uv + _436).xyz * 1.3716285228729248046875f)) + (Source.Sample(_Source_sampler, tex_uv + _424).xyz * 0.3054474890232086181640625f)) * 0.22966586053371429443359375f, 1.0f);
}

SPIRV_Cross_Output main(SPIRV_Cross_Input stage_input)
{
    tex_uv = stage_input.tex_uv;
    blur_dxdy = stage_input.blur_dxdy;
    frag_main();
    SPIRV_Cross_Output stage_output;
    stage_output.FragColor = FragColor;
    return stage_output;
}
