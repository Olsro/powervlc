// Generated from crt/shaders/crt-royale/src/crt-royale-scanlines-horizontal-apply-mask-fake-bloom-intel.slang. See slang/upstream for licence/source.
cbuffer UBO : register(b0)
{
    float global_halation_weight : packoffset(c4.w);
    float global_diffusion_weight : packoffset(c5);
    float global_bloom_underestimate_levels : packoffset(c5.y);
    float global_bloom_excess : packoffset(c5.z);
    float global_beam_horiz_filter : packoffset(c7.y);
    float global_beam_horiz_sigma : packoffset(c7.z);
    float global_beam_horiz_linear_rgb_weight : packoffset(c7.w);
    float global_convergence_offset_x_r : packoffset(c8);
    float global_convergence_offset_x_g : packoffset(c8.y);
    float global_convergence_offset_x_b : packoffset(c8.z);
    float global_mask_type : packoffset(c9.z);
};

cbuffer Push : register(b1)
{
    float4 params_VERTICAL_SCANLINESSize : packoffset(c3);
};

Texture2D<float4> VERTICAL_SCANLINES : register(t6);
SamplerState _VERTICAL_SCANLINES_sampler : register(s6);
Texture2D<float4> mask_grille_texture_large : register(t3);
SamplerState _mask_grille_texture_large_sampler : register(s3);
Texture2D<float4> mask_slot_texture_large : register(t4);
SamplerState _mask_slot_texture_large_sampler : register(s4);
Texture2D<float4> mask_shadow_texture_large : register(t5);
SamplerState _mask_shadow_texture_large_sampler : register(s5);
Texture2D<float4> HALATION_BLUR : register(t8);
SamplerState _HALATION_BLUR_sampler : register(s8);
Texture2D<float4> BLOOM_APPROX : register(t7);
SamplerState _BLOOM_APPROX_sampler : register(s7);

static float2 scanline_tex_uv;
static float2 scanline_texture_size_inv;
static float2 video_uv;
static float2 mask_tiles_per_screen;
static float2 halation_tex_uv;
static float2 blur3x3_tex_uv;
static float4 FragColor;

struct SPIRV_Cross_Input
{
    float2 video_uv : TEXCOORD0;
    float2 scanline_tex_uv : TEXCOORD1;
    float2 blur3x3_tex_uv : TEXCOORD2;
    float2 halation_tex_uv : TEXCOORD3;
    float2 scanline_texture_size_inv : TEXCOORD4;
    float2 mask_tiles_per_screen : TEXCOORD6;
};

struct SPIRV_Cross_Output
{
    float4 FragColor : SV_Target0;
};

void frag_main()
{
    float3 _1053 = float3(global_convergence_offset_x_r, global_convergence_offset_x_g, global_convergence_offset_x_b) * scanline_texture_size_inv.xxx;
    float2 _1125 = (scanline_tex_uv - float2(_1053.x, 0.0f)) * params_VERTICAL_SCANLINESSize.xy;
    float2 _1131 = floor(_1125 - 0.4995000064373016357421875f.xx) + 0.5f.xx;
    float _1133 = _1131.x;
    float2 _1139 = float2(_1133, _1125.y) * scanline_texture_size_inv;
    float _1144 = _1125.x - _1133;
    float4 _1152 = float4(1.0f + _1144, _1144, 1.0f - _1144, 2.0f - _1144);
    bool _1155 = global_beam_horiz_filter < 0.5f;
    float4 _2596;
    if (_1155)
    {
        float _1170 = ((_1144 * _1144) * _1144) * ((_1144 * ((_1144 * 6.0f) - 15.0f)) + 10.0f);
        _2596 = float4(0.0f, 1.0f - _1170, _1170, 0.0f);
    }
    else
    {
        float4 _2597;
        if (global_beam_horiz_filter < 1.5f)
        {
            _2597 = exp((-(_1152 * _1152)) * (1.0f / ((2.0f * global_beam_horiz_sigma) * global_beam_horiz_sigma)));
        }
        else
        {
            float4 _1200 = max(abs(_1152 * 3.1415927410125732421875f), 1.52587890625e-05f.xxxx);
            _2597 = ((sin(_1200) * 2.0f) * sin(_1200 * 0.5f)) / (_1200 * _1200);
        }
        _2596 = _2597;
    }
    float4 _1218 = _2596 / dot(_2596, 1.0f.xxxx).xxxx;
    float2 _1221 = float2(scanline_texture_size_inv.x, 0.0f);
    float4 _1239 = VERTICAL_SCANLINES.Sample(_VERTICAL_SCANLINES_sampler, _1139);
    float4 _1245 = VERTICAL_SCANLINES.Sample(_VERTICAL_SCANLINES_sampler, _1139 + _1221);
    bool _1249 = global_beam_horiz_filter > 0.5f;
    float3 _2600;
    float3 _2603;
    if (_1249)
    {
        _2603 = VERTICAL_SCANLINES.Sample(_VERTICAL_SCANLINES_sampler, _1139 + (_1221 * 2.0f)).xyz;
        _2600 = VERTICAL_SCANLINES.Sample(_VERTICAL_SCANLINES_sampler, _1139 - _1221).xyz;
    }
    else
    {
        _2603 = 0.0f.xxx;
        _2600 = 0.0f.xxx;
    }
    float3 _1319 = global_beam_horiz_linear_rgb_weight.xxx;
    float2 _1398 = (scanline_tex_uv - float2(_1053.y, 0.0f)) * params_VERTICAL_SCANLINESSize.xy;
    float2 _1404 = floor(_1398 - 0.4995000064373016357421875f.xx) + 0.5f.xx;
    float _1406 = _1404.x;
    float2 _1412 = float2(_1406, _1398.y) * scanline_texture_size_inv;
    float _1417 = _1398.x - _1406;
    float4 _1425 = float4(1.0f + _1417, _1417, 1.0f - _1417, 2.0f - _1417);
    float4 _2623;
    if (_1155)
    {
        float _1443 = ((_1417 * _1417) * _1417) * ((_1417 * ((_1417 * 6.0f) - 15.0f)) + 10.0f);
        _2623 = float4(0.0f, 1.0f - _1443, _1443, 0.0f);
    }
    else
    {
        float4 _2624;
        if (global_beam_horiz_filter < 1.5f)
        {
            _2624 = exp((-(_1425 * _1425)) * (1.0f / ((2.0f * global_beam_horiz_sigma) * global_beam_horiz_sigma)));
        }
        else
        {
            float4 _1473 = max(abs(_1425 * 3.1415927410125732421875f), 1.52587890625e-05f.xxxx);
            _2624 = ((sin(_1473) * 2.0f) * sin(_1473 * 0.5f)) / (_1473 * _1473);
        }
        _2623 = _2624;
    }
    float4 _1491 = _2623 / dot(_2623, 1.0f.xxxx).xxxx;
    float4 _1512 = VERTICAL_SCANLINES.Sample(_VERTICAL_SCANLINES_sampler, _1412);
    float4 _1518 = VERTICAL_SCANLINES.Sample(_VERTICAL_SCANLINES_sampler, _1412 + _1221);
    float3 _2627;
    float3 _2630;
    if (_1249)
    {
        _2630 = VERTICAL_SCANLINES.Sample(_VERTICAL_SCANLINES_sampler, _1412 + (_1221 * 2.0f)).xyz;
        _2627 = VERTICAL_SCANLINES.Sample(_VERTICAL_SCANLINES_sampler, _1412 - _1221).xyz;
    }
    else
    {
        _2630 = 0.0f.xxx;
        _2627 = 0.0f.xxx;
    }
    float2 _1671 = (scanline_tex_uv - float2(_1053.z, 0.0f)) * params_VERTICAL_SCANLINESSize.xy;
    float2 _1677 = floor(_1671 - 0.4995000064373016357421875f.xx) + 0.5f.xx;
    float _1679 = _1677.x;
    float2 _1685 = float2(_1679, _1671.y) * scanline_texture_size_inv;
    float _1690 = _1671.x - _1679;
    float4 _1698 = float4(1.0f + _1690, _1690, 1.0f - _1690, 2.0f - _1690);
    float4 _2653;
    if (_1155)
    {
        float _1716 = ((_1690 * _1690) * _1690) * ((_1690 * ((_1690 * 6.0f) - 15.0f)) + 10.0f);
        _2653 = float4(0.0f, 1.0f - _1716, _1716, 0.0f);
    }
    else
    {
        float4 _2654;
        if (global_beam_horiz_filter < 1.5f)
        {
            _2654 = exp((-(_1698 * _1698)) * (1.0f / ((2.0f * global_beam_horiz_sigma) * global_beam_horiz_sigma)));
        }
        else
        {
            float4 _1746 = max(abs(_1698 * 3.1415927410125732421875f), 1.52587890625e-05f.xxxx);
            _2654 = ((sin(_1746) * 2.0f) * sin(_1746 * 0.5f)) / (_1746 * _1746);
        }
        _2653 = _2654;
    }
    float4 _1764 = _2653 / dot(_2653, 1.0f.xxxx).xxxx;
    float4 _1785 = VERTICAL_SCANLINES.Sample(_VERTICAL_SCANLINES_sampler, _1685);
    float4 _1791 = VERTICAL_SCANLINES.Sample(_VERTICAL_SCANLINES_sampler, _1685 + _1221);
    float3 _2657;
    float3 _2660;
    if (_1249)
    {
        _2660 = VERTICAL_SCANLINES.Sample(_VERTICAL_SCANLINES_sampler, _1685 + (_1221 * 2.0f)).xyz;
        _2657 = VERTICAL_SCANLINES.Sample(_VERTICAL_SCANLINES_sampler, _1685 - _1221).xyz;
    }
    else
    {
        _2660 = 0.0f.xxx;
        _2657 = 0.0f.xxx;
    }
    float2 _842 = video_uv * mask_tiles_per_screen;
    bool _858 = global_mask_type < 0.5f;
    float3 _2747;
    if (_858)
    {
        _2747 = mask_grille_texture_large.Sample(_mask_grille_texture_large_sampler, _842).xyz;
    }
    else
    {
        float3 _2748;
        if (global_mask_type < 1.5f)
        {
            _2748 = mask_slot_texture_large.Sample(_mask_slot_texture_large_sampler, _842).xyz;
        }
        else
        {
            _2748 = mask_shadow_texture_large.Sample(_mask_shadow_texture_large_sampler, _842).xyz;
        }
        _2747 = _2748;
    }
    float4 _2427 = HALATION_BLUR.Sample(_HALATION_BLUR_sampler, halation_tex_uv);
    float3 _896 = _2427.xyz;
    float3 _911 = lerp(float3(lerp(max(mul(_1218, float4x3(pow(_2600, 0.454545438289642333984375f.xxx), pow(_1239.xyz, 0.454545438289642333984375f.xxx), pow(_1245.xyz, 0.454545438289642333984375f.xxx), pow(_2603, 0.454545438289642333984375f.xxx))), 0.0f.xxx), max(mul(_1218, float4x3(_2600, float3(_1239.xyz), float3(_1245.xyz), _2603)), 0.0f.xxx), _1319).x, lerp(max(mul(_1491, float4x3(pow(_2627, 0.454545438289642333984375f.xxx), pow(_1512.xyz, 0.454545438289642333984375f.xxx), pow(_1518.xyz, 0.454545438289642333984375f.xxx), pow(_2630, 0.454545438289642333984375f.xxx))), 0.0f.xxx), max(mul(_1491, float4x3(_2627, float3(_1512.xyz), float3(_1518.xyz), _2630)), 0.0f.xxx), _1319).y, lerp(max(mul(_1764, float4x3(pow(_2657, 0.454545438289642333984375f.xxx), pow(_1785.xyz, 0.454545438289642333984375f.xxx), pow(_1791.xyz, 0.454545438289642333984375f.xxx), pow(_2660, 0.454545438289642333984375f.xxx))), 0.0f.xxx), max(mul(_1764, float4x3(_2657, float3(_1785.xyz), float3(_1791.xyz), _2660)), 0.0f.xxx), _1319).z), dot(_896, 0.16666667163372039794921875f.xxx).xxx, global_halation_weight.xxx);
    float _2815;
    if (_858)
    {
        _2815 = 4.811320781707763671875f;
    }
    else
    {
        _2815 = (global_mask_type < 1.5f) ? 5.5434780120849609375f : 6.21951198577880859375f;
    }
    float3 _946 = lerp(BLOOM_APPROX.Sample(_BLOOM_APPROX_sampler, blur3x3_tex_uv).xyz, _911 * 2.0f, 0.100000001490116119384765625f.xxx) * 1.0499999523162841796875f;
    float3 _952 = _946 * global_bloom_underestimate_levels;
    float3 _956 = _952 * _2815;
    FragColor = float4(lerp(lerp(((_911 * _2747) * 2.0f) * _2815, _946, lerp(max(clamp((_956 - 1.0f.xxx) / (_956 - _952), 0.0f.xxx, 1.0f.xxx), 0.0f.xxx), 1.0f.xxx, global_bloom_excess.xxx)), _896, global_diffusion_weight.xxx), 1.0f);
}

SPIRV_Cross_Output main(SPIRV_Cross_Input stage_input)
{
    scanline_tex_uv = stage_input.scanline_tex_uv;
    scanline_texture_size_inv = stage_input.scanline_texture_size_inv;
    video_uv = stage_input.video_uv;
    mask_tiles_per_screen = stage_input.mask_tiles_per_screen;
    halation_tex_uv = stage_input.halation_tex_uv;
    blur3x3_tex_uv = stage_input.blur3x3_tex_uv;
    frag_main();
    SPIRV_Cross_Output stage_output;
    stage_output.FragColor = FragColor;
    return stage_output;
}
