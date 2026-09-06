// Generated from crt/shaders/crt-royale/src/crt-royale-bloom-approx-fake-bloom-intel.slang. See slang/upstream for licence/source.
cbuffer UBO : register(b0)
{
    float global_convergence_offset_x_r : packoffset(c8);
    float global_convergence_offset_x_g : packoffset(c8.y);
    float global_convergence_offset_x_b : packoffset(c8.z);
    float global_convergence_offset_y_r : packoffset(c8.w);
    float global_convergence_offset_y_g : packoffset(c9);
    float global_convergence_offset_y_b : packoffset(c9.y);
};

Texture2D<float4> ORIG_LINEARIZED : register(t3);
SamplerState _ORIG_LINEARIZED_sampler : register(s3);

static float2 uv_scanline_step;
static float2 tex_uv;
static float4 FragColor;

struct SPIRV_Cross_Input
{
    float2 tex_uv : TEXCOORD0;
    float2 uv_scanline_step : TEXCOORD2;
};

struct SPIRV_Cross_Output
{
    float4 FragColor : SV_Target0;
};

void frag_main()
{
    FragColor = float4(ORIG_LINEARIZED.Sample(_ORIG_LINEARIZED_sampler, tex_uv - (float2(global_convergence_offset_x_r, global_convergence_offset_y_r) * uv_scanline_step)).x, ORIG_LINEARIZED.Sample(_ORIG_LINEARIZED_sampler, tex_uv - (float2(global_convergence_offset_x_g, global_convergence_offset_y_g) * uv_scanline_step)).y, ORIG_LINEARIZED.Sample(_ORIG_LINEARIZED_sampler, tex_uv - (float2(global_convergence_offset_x_b, global_convergence_offset_y_b) * uv_scanline_step)).z, 1.0f);
}

SPIRV_Cross_Output main(SPIRV_Cross_Input stage_input)
{
    uv_scanline_step = stage_input.uv_scanline_step;
    tex_uv = stage_input.tex_uv;
    frag_main();
    SPIRV_Cross_Output stage_output;
    stage_output.FragColor = FragColor;
    return stage_output;
}
