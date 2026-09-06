// Generated from crt/shaders/crt-royale/src-fast/crt-royale-scanlines-horizontal-apply-mask.slang. See slang/upstream for licence/source.
cbuffer UBO : register(b0)
{
    float global_lcd_gamma : packoffset(c4.y);
    float global_beam_horiz_filter : packoffset(c6.w);
    float global_beam_horiz_sigma : packoffset(c7);
    float global_beam_horiz_linear_rgb_weight : packoffset(c7.y);
    float global_convergence_offset_x_r : packoffset(c7.z);
    float global_convergence_offset_x_g : packoffset(c7.w);
    float global_convergence_offset_x_b : packoffset(c8);
};

cbuffer Push : register(b1)
{
    float4 params_VERTICAL_SCANLINESSize : packoffset(c3);
    float params_geom_R : packoffset(c5.y);
    float params_geom_cornersize : packoffset(c5.z);
    float params_geom_cornersmooth : packoffset(c5.w);
    float params_geom_overscanx : packoffset(c6.z);
    float params_geom_overscany : packoffset(c6.w);
    float params_geom_curvature : packoffset(c7.z);
    float params_geom_invert_aspect : packoffset(c7.w);
};

Texture2D<float4> VERTICAL_SCANLINES : register(t3);
SamplerState _VERTICAL_SCANLINES_sampler : register(s3);
Texture2D<float4> MASK_RESIZE : register(t4);
SamplerState _MASK_RESIZE_sampler : register(s4);

static float2 sinangle;
static float2 cosangle;
static float3 stretch;
static float2 video_uv;
static float d2;
static float R_d_cx_cy;
static float2 scanline_texture_size_inv;
static float2 mask_tiles_per_screen;
static float4 mask_tile_start_uv_and_size;
static float4 FragColor;

struct SPIRV_Cross_Input
{
    float2 video_uv : TEXCOORD0;
    float2 scanline_texture_size_inv : TEXCOORD1;
    float4 mask_tile_start_uv_and_size : TEXCOORD2;
    float2 mask_tiles_per_screen : TEXCOORD3;
    float2 sinangle : TEXCOORD4;
    float2 cosangle : TEXCOORD5;
    float3 stretch : TEXCOORD6;
    float R_d_cx_cy : TEXCOORD7;
    float d2 : TEXCOORD8;
};

struct SPIRV_Cross_Output
{
    float4 FragColor : SV_Target0;
};

void frag_main()
{
    float2 _295 = ((params_geom_invert_aspect > 0.5f) ? 1.0f : 0.75f).xx;
    float _2507;
    float2 _2566;
    if (params_geom_curvature > 0.5f)
    {
        float2 _978 = (((video_uv - 0.5f.xx) * _295) * stretch.z) + stretch.xy;
        float _1099 = dot(_978, _978) + d2;
        float _1109 = ((params_geom_R * dot(_978, sinangle)) - R_d_cx_cy) - d2;
        float2 _1032 = (((((_1109 * (-2.0f)) - sqrt((4.0f * (_1109 * _1109)) - ((4.0f * _1099) * (d2 + (2.0f * R_d_cx_cy))))) / (2.0f * _1099)).xx * _978) - ((-params_geom_R).xx * sinangle)) / params_geom_R.xx;
        float2 _1035 = _1032 / cosangle;
        float2 _1038 = sinangle / cosangle;
        float _1042 = dot(_1038, _1038) + 1.0f;
        float _1045 = dot(_1035, _1038);
        float _1065 = ((_1045 * 2.0f) + sqrt((4.0f * (_1045 * _1045)) - ((4.0f * _1042) * (dot(_1035, _1035) - 1.0f)))) / (2.0f * _1042);
        float _1079 = max(abs(params_geom_R * acos(_1065)), 9.9999997473787516355514526367188e-06f);
        float2 _989 = float2(params_geom_overscanx * 0.00999999977648258209228515625f, params_geom_overscany * 0.00999999977648258209228515625f);
        float2 _992 = (((((_1032 - (sinangle * _1065)) / cosangle) * _1079) / sin(_1079 / params_geom_R).xx) / _989) / _295;
        float2 _1143 = _992 * _989;
        float2 _1153 = params_geom_cornersize.xx;
        float2 _1158 = _1153 - min(min(_1143 + 0.5f.xx, 0.5f.xx - _1143) * _295, _1153);
        _2566 = _992 + 0.5f.xx;
        _2507 = clamp((params_geom_cornersize - sqrt(dot(_1158, _1158))) * params_geom_cornersmooth, 0.0f, 1.0f);
    }
    else
    {
        _2566 = video_uv;
        _2507 = 1.0f;
    }
    float3 _1202 = float3(global_convergence_offset_x_r, global_convergence_offset_x_g, global_convergence_offset_x_b) * scanline_texture_size_inv.xxx;
    float2 _1275 = (_2566 - float2(_1202.x, 0.0f)) * params_VERTICAL_SCANLINESSize.xy;
    float2 _1281 = floor(_1275 - 0.4995000064373016357421875f.xx) + 0.5f.xx;
    float _1283 = _1281.x;
    float2 _1289 = float2(_1283, _1275.y) * scanline_texture_size_inv;
    float _1294 = _1275.x - _1283;
    float4 _1302 = float4(1.0f + _1294, _1294, 1.0f - _1294, 2.0f - _1294);
    bool _1305 = global_beam_horiz_filter < 0.5f;
    float4 _2422;
    if (_1305)
    {
        float _1320 = ((_1294 * _1294) * _1294) * ((_1294 * ((_1294 * 6.0f) - 15.0f)) + 10.0f);
        _2422 = float4(0.0f, 1.0f - _1320, _1320, 0.0f);
    }
    else
    {
        float4 _2423;
        if (global_beam_horiz_filter < 1.5f)
        {
            _2423 = exp((-(_1302 * _1302)) * (1.0f / ((2.0f * global_beam_horiz_sigma) * global_beam_horiz_sigma)));
        }
        else
        {
            float4 _2424;
            if (global_beam_horiz_filter < 2.5f)
            {
                float4 _1354 = max(abs(_1302 * 3.1415927410125732421875f), 1.52587890625e-05f.xxxx);
                _2424 = ((sin(_1354) * 2.0f) * sin(_1354 * 0.5f)) / (_1354 * _1354);
            }
            else
            {
                _2424 = float4(0.0f, 1.0f - _1294, _1294, 0.0f);
            }
            _2423 = _2424;
        }
        _2422 = _2423;
    }
    float4 _1380 = _2422 / dot(_2422, 1.0f.xxxx).xxxx;
    float2 _1383 = float2(scanline_texture_size_inv.x, 0.0f);
    float4 _1401 = VERTICAL_SCANLINES.Sample(_VERTICAL_SCANLINES_sampler, _1289);
    float4 _1407 = VERTICAL_SCANLINES.Sample(_VERTICAL_SCANLINES_sampler, _1289 + _1383);
    bool _1411 = global_beam_horiz_filter > 0.5f;
    float3 _2428;
    float3 _2431;
    if (_1411)
    {
        _2431 = VERTICAL_SCANLINES.Sample(_VERTICAL_SCANLINES_sampler, _1289 + (_1383 * 2.0f)).xyz;
        _2428 = VERTICAL_SCANLINES.Sample(_VERTICAL_SCANLINES_sampler, _1289 - _1383).xyz;
    }
    else
    {
        _2431 = 0.0f.xxx;
        _2428 = 0.0f.xxx;
    }
    float3 _1459 = (1.0f / global_lcd_gamma).xxx;
    float3 _1482 = global_beam_horiz_linear_rgb_weight.xxx;
    float2 _1559 = (_2566 - float2(_1202.y, 0.0f)) * params_VERTICAL_SCANLINESSize.xy;
    float2 _1565 = floor(_1559 - 0.4995000064373016357421875f.xx) + 0.5f.xx;
    float _1567 = _1565.x;
    float2 _1573 = float2(_1567, _1559.y) * scanline_texture_size_inv;
    float _1578 = _1559.x - _1567;
    float4 _1586 = float4(1.0f + _1578, _1578, 1.0f - _1578, 2.0f - _1578);
    float4 _2453;
    if (_1305)
    {
        float _1604 = ((_1578 * _1578) * _1578) * ((_1578 * ((_1578 * 6.0f) - 15.0f)) + 10.0f);
        _2453 = float4(0.0f, 1.0f - _1604, _1604, 0.0f);
    }
    else
    {
        float4 _2454;
        if (global_beam_horiz_filter < 1.5f)
        {
            _2454 = exp((-(_1586 * _1586)) * (1.0f / ((2.0f * global_beam_horiz_sigma) * global_beam_horiz_sigma)));
        }
        else
        {
            float4 _2455;
            if (global_beam_horiz_filter < 2.5f)
            {
                float4 _1638 = max(abs(_1586 * 3.1415927410125732421875f), 1.52587890625e-05f.xxxx);
                _2455 = ((sin(_1638) * 2.0f) * sin(_1638 * 0.5f)) / (_1638 * _1638);
            }
            else
            {
                _2455 = float4(0.0f, 1.0f - _1578, _1578, 0.0f);
            }
            _2454 = _2455;
        }
        _2453 = _2454;
    }
    float4 _1664 = _2453 / dot(_2453, 1.0f.xxxx).xxxx;
    float4 _1685 = VERTICAL_SCANLINES.Sample(_VERTICAL_SCANLINES_sampler, _1573);
    float4 _1691 = VERTICAL_SCANLINES.Sample(_VERTICAL_SCANLINES_sampler, _1573 + _1383);
    float3 _2459;
    float3 _2462;
    if (_1411)
    {
        _2462 = VERTICAL_SCANLINES.Sample(_VERTICAL_SCANLINES_sampler, _1573 + (_1383 * 2.0f)).xyz;
        _2459 = VERTICAL_SCANLINES.Sample(_VERTICAL_SCANLINES_sampler, _1573 - _1383).xyz;
    }
    else
    {
        _2462 = 0.0f.xxx;
        _2459 = 0.0f.xxx;
    }
    float2 _1843 = (_2566 - float2(_1202.z, 0.0f)) * params_VERTICAL_SCANLINESSize.xy;
    float2 _1849 = floor(_1843 - 0.4995000064373016357421875f.xx) + 0.5f.xx;
    float _1851 = _1849.x;
    float2 _1857 = float2(_1851, _1843.y) * scanline_texture_size_inv;
    float _1862 = _1843.x - _1851;
    float4 _1870 = float4(1.0f + _1862, _1862, 1.0f - _1862, 2.0f - _1862);
    float4 _2488;
    if (_1305)
    {
        float _1888 = ((_1862 * _1862) * _1862) * ((_1862 * ((_1862 * 6.0f) - 15.0f)) + 10.0f);
        _2488 = float4(0.0f, 1.0f - _1888, _1888, 0.0f);
    }
    else
    {
        float4 _2489;
        if (global_beam_horiz_filter < 1.5f)
        {
            _2489 = exp((-(_1870 * _1870)) * (1.0f / ((2.0f * global_beam_horiz_sigma) * global_beam_horiz_sigma)));
        }
        else
        {
            float4 _2490;
            if (global_beam_horiz_filter < 2.5f)
            {
                float4 _1922 = max(abs(_1870 * 3.1415927410125732421875f), 1.52587890625e-05f.xxxx);
                _2490 = ((sin(_1922) * 2.0f) * sin(_1922 * 0.5f)) / (_1922 * _1922);
            }
            else
            {
                _2490 = float4(0.0f, 1.0f - _1862, _1862, 0.0f);
            }
            _2489 = _2490;
        }
        _2488 = _2489;
    }
    float4 _1948 = _2488 / dot(_2488, 1.0f.xxxx).xxxx;
    float4 _1969 = VERTICAL_SCANLINES.Sample(_VERTICAL_SCANLINES_sampler, _1857);
    float4 _1975 = VERTICAL_SCANLINES.Sample(_VERTICAL_SCANLINES_sampler, _1857 + _1383);
    float3 _2494;
    float3 _2497;
    if (_1411)
    {
        _2497 = VERTICAL_SCANLINES.Sample(_VERTICAL_SCANLINES_sampler, _1857 + (_1383 * 2.0f)).xyz;
        _2494 = VERTICAL_SCANLINES.Sample(_VERTICAL_SCANLINES_sampler, _1857 - _1383).xyz;
    }
    else
    {
        _2497 = 0.0f.xxx;
        _2494 = 0.0f.xxx;
    }
    float3 _940 = float3(lerp(max(mul(_1380, float4x3(pow(_2428, _1459), pow(_1401.xyz, _1459), pow(_1407.xyz, _1459), pow(_2431, _1459))), 0.0f.xxx), max(mul(_1380, float4x3(_2428, float3(_1401.xyz), float3(_1407.xyz), _2431)), 0.0f.xxx), _1482).x, lerp(max(mul(_1664, float4x3(pow(_2459, _1459), pow(_1685.xyz, _1459), pow(_1691.xyz, _1459), pow(_2462, _1459))), 0.0f.xxx), max(mul(_1664, float4x3(_2459, float3(_1685.xyz), float3(_1691.xyz), _2462)), 0.0f.xxx), _1482).y, lerp(max(mul(_1948, float4x3(pow(_2494, _1459), pow(_1969.xyz, _1459), pow(_1975.xyz, _1459), pow(_2497, _1459))), 0.0f.xxx), max(mul(_1948, float4x3(_2494, float3(_1969.xyz), float3(_1975.xyz), _2497)), 0.0f.xxx), _1482).z) * MASK_RESIZE.Sample(_MASK_RESIZE_sampler, mask_tile_start_uv_and_size.xy + (frac(video_uv * mask_tiles_per_screen) * mask_tile_start_uv_and_size.zw)).xyz;
    FragColor = float4((_940 * _2507.xxx) * step(0.0f, frac(_2566.y)), 1.0f);
}

SPIRV_Cross_Output main(SPIRV_Cross_Input stage_input)
{
    sinangle = stage_input.sinangle;
    cosangle = stage_input.cosangle;
    stretch = stage_input.stretch;
    video_uv = stage_input.video_uv;
    d2 = stage_input.d2;
    R_d_cx_cy = stage_input.R_d_cx_cy;
    scanline_texture_size_inv = stage_input.scanline_texture_size_inv;
    mask_tiles_per_screen = stage_input.mask_tiles_per_screen;
    mask_tile_start_uv_and_size = stage_input.mask_tile_start_uv_and_size;
    frag_main();
    SPIRV_Cross_Output stage_output;
    stage_output.FragColor = FragColor;
    return stage_output;
}
