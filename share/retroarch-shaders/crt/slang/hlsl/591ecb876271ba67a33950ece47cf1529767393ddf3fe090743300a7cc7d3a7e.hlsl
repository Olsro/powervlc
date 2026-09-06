// Generated from crt/shaders/crt-royale/src/crt-royale-scanlines-horizontal-apply-mask.slang. See slang/upstream for licence/source.
cbuffer UBO : register(b0)
{
    float global_halation_weight : packoffset(c4.w);
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

static float2 scanline_tex_uv;
static float2 scanline_texture_size_inv;
static float2 video_uv;
static float2 mask_tiles_per_screen;
static float4 mask_tile_start_uv_and_size;
static float2 halation_tex_uv;
static float4 FragColor;

struct SPIRV_Cross_Input
{
    float2 video_uv : TEXCOORD0;
    float2 scanline_tex_uv : TEXCOORD1;
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
    float3 _952 = float3(global_convergence_offset_x_r, global_convergence_offset_x_g, global_convergence_offset_x_b) * scanline_texture_size_inv.xxx;
    float2 _1024 = (scanline_tex_uv - float2(_952.x, 0.0f)) * params_VERTICAL_SCANLINESSize.xy;
    float2 _1030 = floor(_1024 - 0.4995000064373016357421875f.xx) + 0.5f.xx;
    float _1032 = _1030.x;
    float2 _1038 = float2(_1032, _1024.y) * scanline_texture_size_inv;
    float _1043 = _1024.x - _1032;
    float4 _1051 = float4(1.0f + _1043, _1043, 1.0f - _1043, 2.0f - _1043);
    bool _1054 = global_beam_horiz_filter < 0.5f;
    float4 _2425;
    if (_1054)
    {
        float _1069 = ((_1043 * _1043) * _1043) * ((_1043 * ((_1043 * 6.0f) - 15.0f)) + 10.0f);
        _2425 = float4(0.0f, 1.0f - _1069, _1069, 0.0f);
    }
    else
    {
        float4 _2426;
        if (global_beam_horiz_filter < 1.5f)
        {
            _2426 = exp((-(_1051 * _1051)) * (1.0f / ((2.0f * global_beam_horiz_sigma) * global_beam_horiz_sigma)));
        }
        else
        {
            float4 _1099 = max(abs(_1051 * 3.1415927410125732421875f), 1.52587890625e-05f.xxxx);
            _2426 = ((sin(_1099) * 2.0f) * sin(_1099 * 0.5f)) / (_1099 * _1099);
        }
        _2425 = _2426;
    }
    float4 _1117 = _2425 / dot(_2425, 1.0f.xxxx).xxxx;
    float2 _1120 = float2(scanline_texture_size_inv.x, 0.0f);
    float4 _1138 = VERTICAL_SCANLINES.Sample(_VERTICAL_SCANLINES_sampler, _1038);
    float4 _1144 = VERTICAL_SCANLINES.Sample(_VERTICAL_SCANLINES_sampler, _1038 + _1120);
    bool _1148 = global_beam_horiz_filter > 0.5f;
    float3 _2429;
    float3 _2432;
    if (_1148)
    {
        _2432 = VERTICAL_SCANLINES.Sample(_VERTICAL_SCANLINES_sampler, _1038 + (_1120 * 2.0f)).xyz;
        _2429 = VERTICAL_SCANLINES.Sample(_VERTICAL_SCANLINES_sampler, _1038 - _1120).xyz;
    }
    else
    {
        _2432 = 0.0f.xxx;
        _2429 = 0.0f.xxx;
    }
    float3 _1218 = global_beam_horiz_linear_rgb_weight.xxx;
    float2 _1297 = (scanline_tex_uv - float2(_952.y, 0.0f)) * params_VERTICAL_SCANLINESSize.xy;
    float2 _1303 = floor(_1297 - 0.4995000064373016357421875f.xx) + 0.5f.xx;
    float _1305 = _1303.x;
    float2 _1311 = float2(_1305, _1297.y) * scanline_texture_size_inv;
    float _1316 = _1297.x - _1305;
    float4 _1324 = float4(1.0f + _1316, _1316, 1.0f - _1316, 2.0f - _1316);
    float4 _2452;
    if (_1054)
    {
        float _1342 = ((_1316 * _1316) * _1316) * ((_1316 * ((_1316 * 6.0f) - 15.0f)) + 10.0f);
        _2452 = float4(0.0f, 1.0f - _1342, _1342, 0.0f);
    }
    else
    {
        float4 _2453;
        if (global_beam_horiz_filter < 1.5f)
        {
            _2453 = exp((-(_1324 * _1324)) * (1.0f / ((2.0f * global_beam_horiz_sigma) * global_beam_horiz_sigma)));
        }
        else
        {
            float4 _1372 = max(abs(_1324 * 3.1415927410125732421875f), 1.52587890625e-05f.xxxx);
            _2453 = ((sin(_1372) * 2.0f) * sin(_1372 * 0.5f)) / (_1372 * _1372);
        }
        _2452 = _2453;
    }
    float4 _1390 = _2452 / dot(_2452, 1.0f.xxxx).xxxx;
    float4 _1411 = VERTICAL_SCANLINES.Sample(_VERTICAL_SCANLINES_sampler, _1311);
    float4 _1417 = VERTICAL_SCANLINES.Sample(_VERTICAL_SCANLINES_sampler, _1311 + _1120);
    float3 _2456;
    float3 _2459;
    if (_1148)
    {
        _2459 = VERTICAL_SCANLINES.Sample(_VERTICAL_SCANLINES_sampler, _1311 + (_1120 * 2.0f)).xyz;
        _2456 = VERTICAL_SCANLINES.Sample(_VERTICAL_SCANLINES_sampler, _1311 - _1120).xyz;
    }
    else
    {
        _2459 = 0.0f.xxx;
        _2456 = 0.0f.xxx;
    }
    float2 _1570 = (scanline_tex_uv - float2(_952.z, 0.0f)) * params_VERTICAL_SCANLINESSize.xy;
    float2 _1576 = floor(_1570 - 0.4995000064373016357421875f.xx) + 0.5f.xx;
    float _1578 = _1576.x;
    float2 _1584 = float2(_1578, _1570.y) * scanline_texture_size_inv;
    float _1589 = _1570.x - _1578;
    float4 _1597 = float4(1.0f + _1589, _1589, 1.0f - _1589, 2.0f - _1589);
    float4 _2482;
    if (_1054)
    {
        float _1615 = ((_1589 * _1589) * _1589) * ((_1589 * ((_1589 * 6.0f) - 15.0f)) + 10.0f);
        _2482 = float4(0.0f, 1.0f - _1615, _1615, 0.0f);
    }
    else
    {
        float4 _2483;
        if (global_beam_horiz_filter < 1.5f)
        {
            _2483 = exp((-(_1597 * _1597)) * (1.0f / ((2.0f * global_beam_horiz_sigma) * global_beam_horiz_sigma)));
        }
        else
        {
            float4 _1645 = max(abs(_1597 * 3.1415927410125732421875f), 1.52587890625e-05f.xxxx);
            _2483 = ((sin(_1645) * 2.0f) * sin(_1645 * 0.5f)) / (_1645 * _1645);
        }
        _2482 = _2483;
    }
    float4 _1663 = _2482 / dot(_2482, 1.0f.xxxx).xxxx;
    float4 _1684 = VERTICAL_SCANLINES.Sample(_VERTICAL_SCANLINES_sampler, _1584);
    float4 _1690 = VERTICAL_SCANLINES.Sample(_VERTICAL_SCANLINES_sampler, _1584 + _1120);
    float3 _2486;
    float3 _2489;
    if (_1148)
    {
        _2489 = VERTICAL_SCANLINES.Sample(_VERTICAL_SCANLINES_sampler, _1584 + (_1120 * 2.0f)).xyz;
        _2486 = VERTICAL_SCANLINES.Sample(_VERTICAL_SCANLINES_sampler, _1584 - _1120).xyz;
    }
    else
    {
        _2489 = 0.0f.xxx;
        _2486 = 0.0f.xxx;
    }
    float _2126;
    float2 _809 = video_uv * mask_tiles_per_screen;
    float2 _2508;
    do
    {
        _2126 = global_mask_sample_mode_desired;
        if (_2126 < 0.5f)
        {
            _2508 = mask_tile_start_uv_and_size.xy + ((frac(_809 * 0.5f) * 2.0f) * mask_tile_start_uv_and_size.zw);
            break;
        }
        else
        {
            _2508 = _809;
            break;
        }
        break; // unreachable workaround
    } while(false);
    float3 _2575;
    if (_2126 > 0.5f)
    {
        float3 _2576;
        if (global_mask_type < 0.5f)
        {
            _2576 = mask_grille_texture_large.Sample(_mask_grille_texture_large_sampler, _2508).xyz;
        }
        else
        {
            float3 _2577;
            if (global_mask_type < 1.5f)
            {
                _2577 = mask_slot_texture_large.Sample(_mask_slot_texture_large_sampler, _2508).xyz;
            }
            else
            {
                _2577 = mask_shadow_texture_large.Sample(_mask_shadow_texture_large_sampler, _2508).xyz;
            }
            _2576 = _2577;
        }
        _2575 = _2576;
    }
    else
    {
        _2575 = MASK_RESIZE.Sample(_MASK_RESIZE_sampler, _2508).xyz;
    }
    float3 _881 = lerp(float3(lerp(max(mul(_1117, float4x3(pow(_2429, 0.454545438289642333984375f.xxx), pow(_1138.xyz, 0.454545438289642333984375f.xxx), pow(_1144.xyz, 0.454545438289642333984375f.xxx), pow(_2432, 0.454545438289642333984375f.xxx))), 0.0f.xxx), max(mul(_1117, float4x3(_2429, float3(_1138.xyz), float3(_1144.xyz), _2432)), 0.0f.xxx), _1218).x, lerp(max(mul(_1390, float4x3(pow(_2456, 0.454545438289642333984375f.xxx), pow(_1411.xyz, 0.454545438289642333984375f.xxx), pow(_1417.xyz, 0.454545438289642333984375f.xxx), pow(_2459, 0.454545438289642333984375f.xxx))), 0.0f.xxx), max(mul(_1390, float4x3(_2456, float3(_1411.xyz), float3(_1417.xyz), _2459)), 0.0f.xxx), _1218).y, lerp(max(mul(_1663, float4x3(pow(_2486, 0.454545438289642333984375f.xxx), pow(_1684.xyz, 0.454545438289642333984375f.xxx), pow(_1690.xyz, 0.454545438289642333984375f.xxx), pow(_2489, 0.454545438289642333984375f.xxx))), 0.0f.xxx), max(mul(_1663, float4x3(_2486, float3(_1684.xyz), float3(_1690.xyz), _2489)), 0.0f.xxx), _1218).z), dot(HALATION_BLUR.Sample(_HALATION_BLUR_sampler, halation_tex_uv).xyz, 0.16666667163372039794921875f.xxx).xxx, global_halation_weight.xxx);
    FragColor = float4(_881 * _2575, 1.0f);
}

SPIRV_Cross_Output main(SPIRV_Cross_Input stage_input)
{
    scanline_tex_uv = stage_input.scanline_tex_uv;
    scanline_texture_size_inv = stage_input.scanline_texture_size_inv;
    video_uv = stage_input.video_uv;
    mask_tiles_per_screen = stage_input.mask_tiles_per_screen;
    mask_tile_start_uv_and_size = stage_input.mask_tile_start_uv_and_size;
    halation_tex_uv = stage_input.halation_tex_uv;
    frag_main();
    SPIRV_Cross_Output stage_output;
    stage_output.FragColor = FragColor;
    return stage_output;
}
