// Generated from crt/shaders/crt-royale/src/crt-royale-bloom-horizontal-reconstitute.slang. See slang/upstream for licence/source.
cbuffer UBO : register(b0)
{
    float global_levels_contrast : packoffset(c4.z);
    float global_diffusion_weight : packoffset(c5);
    float global_mask_type : packoffset(c9.z);
};

Texture2D<float4> Source : register(t2);
SamplerState _Source_sampler : register(s2);
Texture2D<float4> MASKED_SCANLINES : register(t5);
SamplerState _MASKED_SCANLINES_sampler : register(s5);
Texture2D<float4> BRIGHTPASS : register(t4);
SamplerState _BRIGHTPASS_sampler : register(s4);
Texture2D<float4> HALATION_BLUR : register(t3);
SamplerState _HALATION_BLUR_sampler : register(s3);

static float bloom_sigma_runtime;
static float2 bloom_tex_uv;
static float2 bloom_dxdy;
static float2 scanline_tex_uv;
static float2 brightpass_tex_uv;
static float2 halation_tex_uv;
static float4 FragColor;

struct SPIRV_Cross_Input
{
    float2 scanline_tex_uv : TEXCOORD1;
    float2 halation_tex_uv : TEXCOORD2;
    float2 brightpass_tex_uv : TEXCOORD3;
    float2 bloom_tex_uv : TEXCOORD4;
    float2 bloom_dxdy : TEXCOORD5;
    float bloom_sigma_runtime : TEXCOORD6;
};

struct SPIRV_Cross_Output
{
    float4 FragColor : SV_Target0;
};

void frag_main()
{
    float _826 = bloom_sigma_runtime * bloom_sigma_runtime;
    float _833 = exp((-2.0f) / _826);
    float _839 = exp((-8.0f) / _826);
    float _845 = exp((-18.0f) / _826);
    float _851 = exp((-32.0f) / _826);
    float _856 = exp((-0.5f) / _826) + _833;
    float _859 = exp((-4.5f) / _826) + _839;
    float _862 = exp((-12.5f) / _826) + _845;
    float _865 = exp((-24.5f) / _826) + _851;
    float2 _883 = bloom_dxdy * (7.0f + (_851 / _865));
    float4 _999 = Source.Sample(_Source_sampler, bloom_tex_uv - _883);
    float2 _895 = bloom_dxdy * (5.0f + (_845 / _862));
    float4 _1046 = Source.Sample(_Source_sampler, bloom_tex_uv - _895);
    float2 _907 = bloom_dxdy * (3.0f + (_839 / _859));
    float4 _1093 = Source.Sample(_Source_sampler, bloom_tex_uv - _907);
    float2 _919 = bloom_dxdy * (1.0f + (_833 / _856));
    float4 _1140 = Source.Sample(_Source_sampler, bloom_tex_uv - _919);
    float4 _1187 = Source.Sample(_Source_sampler, bloom_tex_uv);
    float4 _1234 = Source.Sample(_Source_sampler, bloom_tex_uv + _919);
    float4 _1281 = Source.Sample(_Source_sampler, bloom_tex_uv + _907);
    float4 _1328 = Source.Sample(_Source_sampler, bloom_tex_uv + _895);
    float4 _1375 = Source.Sample(_Source_sampler, bloom_tex_uv + _883);
    float4 _1422 = MASKED_SCANLINES.Sample(_MASKED_SCANLINES_sampler, scanline_tex_uv);
    float _1784;
    if (global_mask_type < 0.5f)
    {
        _1784 = 4.811320781707763671875f;
    }
    else
    {
        _1784 = (global_mask_type < 1.5f) ? 5.5434780120849609375f : 6.21951198577880859375f;
    }
    float3 _739 = lerp(((((_1422.xyz - BRIGHTPASS.Sample(_BRIGHTPASS_sampler, brightpass_tex_uv).xyz) + ((((((((((_999.xyz * _865) + (_1046.xyz * _862)) + (_1093.xyz * _859)) + (_1140.xyz * _856)) + (_1187.xyz * 1.0f)) + (_1234.xyz * _856)) + (_1281.xyz * _859)) + (_1328.xyz * _862)) + (_1375.xyz * _865)) * min(exp(exp(0.3483484089374542236328125f / (bloom_sigma_runtime - 0.086058728396892547607421875f))), 0.3993345797061920166015625f / bloom_sigma_runtime))) * _1784) * 2.0f) * global_levels_contrast, HALATION_BLUR.Sample(_HALATION_BLUR_sampler, halation_tex_uv).xyz * global_levels_contrast, global_diffusion_weight.xxx);
    FragColor = float4(_739, 1.0f);
}

SPIRV_Cross_Output main(SPIRV_Cross_Input stage_input)
{
    bloom_sigma_runtime = stage_input.bloom_sigma_runtime;
    bloom_tex_uv = stage_input.bloom_tex_uv;
    bloom_dxdy = stage_input.bloom_dxdy;
    scanline_tex_uv = stage_input.scanline_tex_uv;
    brightpass_tex_uv = stage_input.brightpass_tex_uv;
    halation_tex_uv = stage_input.halation_tex_uv;
    frag_main();
    SPIRV_Cross_Output stage_output;
    stage_output.FragColor = FragColor;
    return stage_output;
}
