// Generated from crt/shaders/crt-royale/src/crt-royale-scanlines-horizontal-apply-mask-fake-bloom.slang. See slang/upstream for licence/source.
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
    float global_mask_sample_mode_desired : packoffset(c9.w);
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
Texture2D<float4> MASK_RESIZE : register(t9);
SamplerState _MASK_RESIZE_sampler : register(s9);
Texture2D<float4> HALATION_BLUR : register(t8);
SamplerState _HALATION_BLUR_sampler : register(s8);
Texture2D<float4> BLOOM_APPROX : register(t7);
SamplerState _BLOOM_APPROX_sampler : register(s7);

static float2 scanline_tex_uv;
static float2 scanline_texture_size_inv;
static float2 video_uv;
static float2 mask_tiles_per_screen;
static float4 mask_tile_start_uv_and_size;
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
    float4 mask_tile_start_uv_and_size : TEXCOORD5;
    float2 mask_tiles_per_screen : TEXCOORD6;
};

struct SPIRV_Cross_Output
{
    float4 FragColor : SV_Target0;
};

void frag_main()
{
    float3 _1052 = float3(global_convergence_offset_x_r, global_convergence_offset_x_g, global_convergence_offset_x_b) * scanline_texture_size_inv.xxx;
    float2 _1124 = (scanline_tex_uv - float2(_1052.x, 0.0f)) * params_VERTICAL_SCANLINESSize.xy;
    float2 _1130 = floor(_1124 - 0.4995000064373016357421875f.xx) + 0.5f.xx;
    float _1132 = _1130.x;
    float2 _1138 = float2(_1132, _1124.y) * scanline_texture_size_inv;
    float _1143 = _1124.x - _1132;
    float4 _1151 = float4(1.0f + _1143, _1143, 1.0f - _1143, 2.0f - _1143);
    bool _1154 = global_beam_horiz_filter < 0.5f;
    float4 _2598;
    if (_1154)
    {
        float _1169 = ((_1143 * _1143) * _1143) * ((_1143 * ((_1143 * 6.0f) - 15.0f)) + 10.0f);
        _2598 = float4(0.0f, 1.0f - _1169, _1169, 0.0f);
    }
    else
    {
        float4 _2599;
        if (global_beam_horiz_filter < 1.5f)
        {
            _2599 = exp((-(_1151 * _1151)) * (1.0f / ((2.0f * global_beam_horiz_sigma) * global_beam_horiz_sigma)));
        }
        else
        {
            float4 _1199 = max(abs(_1151 * 3.1415927410125732421875f), 1.52587890625e-05f.xxxx);
            _2599 = ((sin(_1199) * 2.0f) * sin(_1199 * 0.5f)) / (_1199 * _1199);
        }
        _2598 = _2599;
    }
    float4 _1217 = _2598 / dot(_2598, 1.0f.xxxx).xxxx;
    float2 _1220 = float2(scanline_texture_size_inv.x, 0.0f);
    float4 _1238 = VERTICAL_SCANLINES.Sample(_VERTICAL_SCANLINES_sampler, _1138);
    float4 _1244 = VERTICAL_SCANLINES.Sample(_VERTICAL_SCANLINES_sampler, _1138 + _1220);
    bool _1248 = global_beam_horiz_filter > 0.5f;
    float3 _2602;
    float3 _2605;
    if (_1248)
    {
        _2605 = VERTICAL_SCANLINES.Sample(_VERTICAL_SCANLINES_sampler, _1138 + (_1220 * 2.0f)).xyz;
        _2602 = VERTICAL_SCANLINES.Sample(_VERTICAL_SCANLINES_sampler, _1138 - _1220).xyz;
    }
    else
    {
        _2605 = 0.0f.xxx;
        _2602 = 0.0f.xxx;
    }
    float3 _1318 = global_beam_horiz_linear_rgb_weight.xxx;
    float2 _1397 = (scanline_tex_uv - float2(_1052.y, 0.0f)) * params_VERTICAL_SCANLINESSize.xy;
    float2 _1403 = floor(_1397 - 0.4995000064373016357421875f.xx) + 0.5f.xx;
    float _1405 = _1403.x;
    float2 _1411 = float2(_1405, _1397.y) * scanline_texture_size_inv;
    float _1416 = _1397.x - _1405;
    float4 _1424 = float4(1.0f + _1416, _1416, 1.0f - _1416, 2.0f - _1416);
    float4 _2625;
    if (_1154)
    {
        float _1442 = ((_1416 * _1416) * _1416) * ((_1416 * ((_1416 * 6.0f) - 15.0f)) + 10.0f);
        _2625 = float4(0.0f, 1.0f - _1442, _1442, 0.0f);
    }
    else
    {
        float4 _2626;
        if (global_beam_horiz_filter < 1.5f)
        {
            _2626 = exp((-(_1424 * _1424)) * (1.0f / ((2.0f * global_beam_horiz_sigma) * global_beam_horiz_sigma)));
        }
        else
        {
            float4 _1472 = max(abs(_1424 * 3.1415927410125732421875f), 1.52587890625e-05f.xxxx);
            _2626 = ((sin(_1472) * 2.0f) * sin(_1472 * 0.5f)) / (_1472 * _1472);
        }
        _2625 = _2626;
    }
    float4 _1490 = _2625 / dot(_2625, 1.0f.xxxx).xxxx;
    float4 _1511 = VERTICAL_SCANLINES.Sample(_VERTICAL_SCANLINES_sampler, _1411);
    float4 _1517 = VERTICAL_SCANLINES.Sample(_VERTICAL_SCANLINES_sampler, _1411 + _1220);
    float3 _2629;
    float3 _2632;
    if (_1248)
    {
        _2632 = VERTICAL_SCANLINES.Sample(_VERTICAL_SCANLINES_sampler, _1411 + (_1220 * 2.0f)).xyz;
        _2629 = VERTICAL_SCANLINES.Sample(_VERTICAL_SCANLINES_sampler, _1411 - _1220).xyz;
    }
    else
    {
        _2632 = 0.0f.xxx;
        _2629 = 0.0f.xxx;
    }
    float2 _1670 = (scanline_tex_uv - float2(_1052.z, 0.0f)) * params_VERTICAL_SCANLINESSize.xy;
    float2 _1676 = floor(_1670 - 0.4995000064373016357421875f.xx) + 0.5f.xx;
    float _1678 = _1676.x;
    float2 _1684 = float2(_1678, _1670.y) * scanline_texture_size_inv;
    float _1689 = _1670.x - _1678;
    float4 _1697 = float4(1.0f + _1689, _1689, 1.0f - _1689, 2.0f - _1689);
    float4 _2655;
    if (_1154)
    {
        float _1715 = ((_1689 * _1689) * _1689) * ((_1689 * ((_1689 * 6.0f) - 15.0f)) + 10.0f);
        _2655 = float4(0.0f, 1.0f - _1715, _1715, 0.0f);
    }
    else
    {
        float4 _2656;
        if (global_beam_horiz_filter < 1.5f)
        {
            _2656 = exp((-(_1697 * _1697)) * (1.0f / ((2.0f * global_beam_horiz_sigma) * global_beam_horiz_sigma)));
        }
        else
        {
            float4 _1745 = max(abs(_1697 * 3.1415927410125732421875f), 1.52587890625e-05f.xxxx);
            _2656 = ((sin(_1745) * 2.0f) * sin(_1745 * 0.5f)) / (_1745 * _1745);
        }
        _2655 = _2656;
    }
    float4 _1763 = _2655 / dot(_2655, 1.0f.xxxx).xxxx;
    float4 _1784 = VERTICAL_SCANLINES.Sample(_VERTICAL_SCANLINES_sampler, _1684);
    float4 _1790 = VERTICAL_SCANLINES.Sample(_VERTICAL_SCANLINES_sampler, _1684 + _1220);
    float3 _2659;
    float3 _2662;
    if (_1248)
    {
        _2662 = VERTICAL_SCANLINES.Sample(_VERTICAL_SCANLINES_sampler, _1684 + (_1220 * 2.0f)).xyz;
        _2659 = VERTICAL_SCANLINES.Sample(_VERTICAL_SCANLINES_sampler, _1684 - _1220).xyz;
    }
    else
    {
        _2662 = 0.0f.xxx;
        _2659 = 0.0f.xxx;
    }
    float _2226;
    float2 _838 = video_uv * mask_tiles_per_screen;
    float2 _2681;
    do
    {
        _2226 = global_mask_sample_mode_desired;
        if (_2226 < 0.5f)
        {
            _2681 = mask_tile_start_uv_and_size.xy + ((frac(_838 * 0.5f) * 2.0f) * mask_tile_start_uv_and_size.zw);
            break;
        }
        else
        {
            _2681 = _838;
            break;
        }
        break; // unreachable workaround
    } while(false);
    float3 _2748;
    if (_2226 > 0.5f)
    {
        float3 _2749;
        if (global_mask_type < 0.5f)
        {
            _2749 = mask_grille_texture_large.Sample(_mask_grille_texture_large_sampler, _2681).xyz;
        }
        else
        {
            float3 _2750;
            if (global_mask_type < 1.5f)
            {
                _2750 = mask_slot_texture_large.Sample(_mask_slot_texture_large_sampler, _2681).xyz;
            }
            else
            {
                _2750 = mask_shadow_texture_large.Sample(_mask_shadow_texture_large_sampler, _2681).xyz;
            }
            _2749 = _2750;
        }
        _2748 = _2749;
    }
    else
    {
        _2748 = MASK_RESIZE.Sample(_MASK_RESIZE_sampler, _2681).xyz;
    }
    float4 _2429 = HALATION_BLUR.Sample(_HALATION_BLUR_sampler, halation_tex_uv);
    float3 _894 = _2429.xyz;
    float3 _909 = lerp(float3(lerp(max(mul(_1217, float4x3(pow(_2602, 0.454545438289642333984375f.xxx), pow(_1238.xyz, 0.454545438289642333984375f.xxx), pow(_1244.xyz, 0.454545438289642333984375f.xxx), pow(_2605, 0.454545438289642333984375f.xxx))), 0.0f.xxx), max(mul(_1217, float4x3(_2602, float3(_1238.xyz), float3(_1244.xyz), _2605)), 0.0f.xxx), _1318).x, lerp(max(mul(_1490, float4x3(pow(_2629, 0.454545438289642333984375f.xxx), pow(_1511.xyz, 0.454545438289642333984375f.xxx), pow(_1517.xyz, 0.454545438289642333984375f.xxx), pow(_2632, 0.454545438289642333984375f.xxx))), 0.0f.xxx), max(mul(_1490, float4x3(_2629, float3(_1511.xyz), float3(_1517.xyz), _2632)), 0.0f.xxx), _1318).y, lerp(max(mul(_1763, float4x3(pow(_2659, 0.454545438289642333984375f.xxx), pow(_1784.xyz, 0.454545438289642333984375f.xxx), pow(_1790.xyz, 0.454545438289642333984375f.xxx), pow(_2662, 0.454545438289642333984375f.xxx))), 0.0f.xxx), max(mul(_1763, float4x3(_2659, float3(_1784.xyz), float3(_1790.xyz), _2662)), 0.0f.xxx), _1318).z), dot(_894, 0.16666667163372039794921875f.xxx).xxx, global_halation_weight.xxx);
    float _2817;
    if (global_mask_type < 0.5f)
    {
        _2817 = 4.811320781707763671875f;
    }
    else
    {
        _2817 = (global_mask_type < 1.5f) ? 5.5434780120849609375f : 6.21951198577880859375f;
    }
    float3 _944 = lerp(BLOOM_APPROX.Sample(_BLOOM_APPROX_sampler, blur3x3_tex_uv).xyz, _909 * 2.0f, 0.100000001490116119384765625f.xxx) * 1.0499999523162841796875f;
    float3 _950 = _944 * global_bloom_underestimate_levels;
    float3 _954 = _950 * _2817;
    FragColor = float4(lerp(lerp(((_909 * _2748) * 2.0f) * _2817, _944, lerp(max(clamp((_954 - 1.0f.xxx) / (_954 - _950), 0.0f.xxx, 1.0f.xxx), 0.0f.xxx), 1.0f.xxx, global_bloom_excess.xxx)), _894, global_diffusion_weight.xxx), 1.0f);
}

SPIRV_Cross_Output main(SPIRV_Cross_Input stage_input)
{
    scanline_tex_uv = stage_input.scanline_tex_uv;
    scanline_texture_size_inv = stage_input.scanline_texture_size_inv;
    video_uv = stage_input.video_uv;
    mask_tiles_per_screen = stage_input.mask_tiles_per_screen;
    mask_tile_start_uv_and_size = stage_input.mask_tile_start_uv_and_size;
    halation_tex_uv = stage_input.halation_tex_uv;
    blur3x3_tex_uv = stage_input.blur3x3_tex_uv;
    frag_main();
    SPIRV_Cross_Output stage_output;
    stage_output.FragColor = FragColor;
    return stage_output;
}
