// Generated from crt/shaders/crt-royale/src/crt-royale-scanlines-horizontal-apply-mask-intel.slang. See slang/upstream for licence/source.
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

static float2 scanline_tex_uv;
static float2 scanline_texture_size_inv;
static float2 video_uv;
static float2 mask_tiles_per_screen;
static float2 halation_tex_uv;
static float4 FragColor;

struct SPIRV_Cross_Input
{
    float2 video_uv : TEXCOORD0;
    float2 scanline_tex_uv : TEXCOORD1;
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
    float3 _953 = float3(global_convergence_offset_x_r, global_convergence_offset_x_g, global_convergence_offset_x_b) * scanline_texture_size_inv.xxx;
    float2 _1025 = (scanline_tex_uv - float2(_953.x, 0.0f)) * params_VERTICAL_SCANLINESSize.xy;
    float2 _1031 = floor(_1025 - 0.4995000064373016357421875f.xx) + 0.5f.xx;
    float _1033 = _1031.x;
    float2 _1039 = float2(_1033, _1025.y) * scanline_texture_size_inv;
    float _1044 = _1025.x - _1033;
    float4 _1052 = float4(1.0f + _1044, _1044, 1.0f - _1044, 2.0f - _1044);
    bool _1055 = global_beam_horiz_filter < 0.5f;
    float4 _2423;
    if (_1055)
    {
        float _1070 = ((_1044 * _1044) * _1044) * ((_1044 * ((_1044 * 6.0f) - 15.0f)) + 10.0f);
        _2423 = float4(0.0f, 1.0f - _1070, _1070, 0.0f);
    }
    else
    {
        float4 _2424;
        if (global_beam_horiz_filter < 1.5f)
        {
            _2424 = exp((-(_1052 * _1052)) * (1.0f / ((2.0f * global_beam_horiz_sigma) * global_beam_horiz_sigma)));
        }
        else
        {
            float4 _1100 = max(abs(_1052 * 3.1415927410125732421875f), 1.52587890625e-05f.xxxx);
            _2424 = ((sin(_1100) * 2.0f) * sin(_1100 * 0.5f)) / (_1100 * _1100);
        }
        _2423 = _2424;
    }
    float4 _1118 = _2423 / dot(_2423, 1.0f.xxxx).xxxx;
    float2 _1121 = float2(scanline_texture_size_inv.x, 0.0f);
    float4 _1139 = VERTICAL_SCANLINES.Sample(_VERTICAL_SCANLINES_sampler, _1039);
    float4 _1145 = VERTICAL_SCANLINES.Sample(_VERTICAL_SCANLINES_sampler, _1039 + _1121);
    bool _1149 = global_beam_horiz_filter > 0.5f;
    float3 _2427;
    float3 _2430;
    if (_1149)
    {
        _2430 = VERTICAL_SCANLINES.Sample(_VERTICAL_SCANLINES_sampler, _1039 + (_1121 * 2.0f)).xyz;
        _2427 = VERTICAL_SCANLINES.Sample(_VERTICAL_SCANLINES_sampler, _1039 - _1121).xyz;
    }
    else
    {
        _2430 = 0.0f.xxx;
        _2427 = 0.0f.xxx;
    }
    float3 _1219 = global_beam_horiz_linear_rgb_weight.xxx;
    float2 _1298 = (scanline_tex_uv - float2(_953.y, 0.0f)) * params_VERTICAL_SCANLINESSize.xy;
    float2 _1304 = floor(_1298 - 0.4995000064373016357421875f.xx) + 0.5f.xx;
    float _1306 = _1304.x;
    float2 _1312 = float2(_1306, _1298.y) * scanline_texture_size_inv;
    float _1317 = _1298.x - _1306;
    float4 _1325 = float4(1.0f + _1317, _1317, 1.0f - _1317, 2.0f - _1317);
    float4 _2450;
    if (_1055)
    {
        float _1343 = ((_1317 * _1317) * _1317) * ((_1317 * ((_1317 * 6.0f) - 15.0f)) + 10.0f);
        _2450 = float4(0.0f, 1.0f - _1343, _1343, 0.0f);
    }
    else
    {
        float4 _2451;
        if (global_beam_horiz_filter < 1.5f)
        {
            _2451 = exp((-(_1325 * _1325)) * (1.0f / ((2.0f * global_beam_horiz_sigma) * global_beam_horiz_sigma)));
        }
        else
        {
            float4 _1373 = max(abs(_1325 * 3.1415927410125732421875f), 1.52587890625e-05f.xxxx);
            _2451 = ((sin(_1373) * 2.0f) * sin(_1373 * 0.5f)) / (_1373 * _1373);
        }
        _2450 = _2451;
    }
    float4 _1391 = _2450 / dot(_2450, 1.0f.xxxx).xxxx;
    float4 _1412 = VERTICAL_SCANLINES.Sample(_VERTICAL_SCANLINES_sampler, _1312);
    float4 _1418 = VERTICAL_SCANLINES.Sample(_VERTICAL_SCANLINES_sampler, _1312 + _1121);
    float3 _2454;
    float3 _2457;
    if (_1149)
    {
        _2457 = VERTICAL_SCANLINES.Sample(_VERTICAL_SCANLINES_sampler, _1312 + (_1121 * 2.0f)).xyz;
        _2454 = VERTICAL_SCANLINES.Sample(_VERTICAL_SCANLINES_sampler, _1312 - _1121).xyz;
    }
    else
    {
        _2457 = 0.0f.xxx;
        _2454 = 0.0f.xxx;
    }
    float2 _1571 = (scanline_tex_uv - float2(_953.z, 0.0f)) * params_VERTICAL_SCANLINESSize.xy;
    float2 _1577 = floor(_1571 - 0.4995000064373016357421875f.xx) + 0.5f.xx;
    float _1579 = _1577.x;
    float2 _1585 = float2(_1579, _1571.y) * scanline_texture_size_inv;
    float _1590 = _1571.x - _1579;
    float4 _1598 = float4(1.0f + _1590, _1590, 1.0f - _1590, 2.0f - _1590);
    float4 _2480;
    if (_1055)
    {
        float _1616 = ((_1590 * _1590) * _1590) * ((_1590 * ((_1590 * 6.0f) - 15.0f)) + 10.0f);
        _2480 = float4(0.0f, 1.0f - _1616, _1616, 0.0f);
    }
    else
    {
        float4 _2481;
        if (global_beam_horiz_filter < 1.5f)
        {
            _2481 = exp((-(_1598 * _1598)) * (1.0f / ((2.0f * global_beam_horiz_sigma) * global_beam_horiz_sigma)));
        }
        else
        {
            float4 _1646 = max(abs(_1598 * 3.1415927410125732421875f), 1.52587890625e-05f.xxxx);
            _2481 = ((sin(_1646) * 2.0f) * sin(_1646 * 0.5f)) / (_1646 * _1646);
        }
        _2480 = _2481;
    }
    float4 _1664 = _2480 / dot(_2480, 1.0f.xxxx).xxxx;
    float4 _1685 = VERTICAL_SCANLINES.Sample(_VERTICAL_SCANLINES_sampler, _1585);
    float4 _1691 = VERTICAL_SCANLINES.Sample(_VERTICAL_SCANLINES_sampler, _1585 + _1121);
    float3 _2484;
    float3 _2487;
    if (_1149)
    {
        _2487 = VERTICAL_SCANLINES.Sample(_VERTICAL_SCANLINES_sampler, _1585 + (_1121 * 2.0f)).xyz;
        _2484 = VERTICAL_SCANLINES.Sample(_VERTICAL_SCANLINES_sampler, _1585 - _1121).xyz;
    }
    else
    {
        _2487 = 0.0f.xxx;
        _2484 = 0.0f.xxx;
    }
    float2 _813 = video_uv * mask_tiles_per_screen;
    float3 _2574;
    if (global_mask_type < 0.5f)
    {
        _2574 = mask_grille_texture_large.Sample(_mask_grille_texture_large_sampler, _813).xyz;
    }
    else
    {
        float3 _2575;
        if (global_mask_type < 1.5f)
        {
            _2575 = mask_slot_texture_large.Sample(_mask_slot_texture_large_sampler, _813).xyz;
        }
        else
        {
            _2575 = mask_shadow_texture_large.Sample(_mask_shadow_texture_large_sampler, _813).xyz;
        }
        _2574 = _2575;
    }
    float3 _883 = lerp(float3(lerp(max(mul(_1118, float4x3(pow(_2427, 0.454545438289642333984375f.xxx), pow(_1139.xyz, 0.454545438289642333984375f.xxx), pow(_1145.xyz, 0.454545438289642333984375f.xxx), pow(_2430, 0.454545438289642333984375f.xxx))), 0.0f.xxx), max(mul(_1118, float4x3(_2427, float3(_1139.xyz), float3(_1145.xyz), _2430)), 0.0f.xxx), _1219).x, lerp(max(mul(_1391, float4x3(pow(_2454, 0.454545438289642333984375f.xxx), pow(_1412.xyz, 0.454545438289642333984375f.xxx), pow(_1418.xyz, 0.454545438289642333984375f.xxx), pow(_2457, 0.454545438289642333984375f.xxx))), 0.0f.xxx), max(mul(_1391, float4x3(_2454, float3(_1412.xyz), float3(_1418.xyz), _2457)), 0.0f.xxx), _1219).y, lerp(max(mul(_1664, float4x3(pow(_2484, 0.454545438289642333984375f.xxx), pow(_1685.xyz, 0.454545438289642333984375f.xxx), pow(_1691.xyz, 0.454545438289642333984375f.xxx), pow(_2487, 0.454545438289642333984375f.xxx))), 0.0f.xxx), max(mul(_1664, float4x3(_2484, float3(_1685.xyz), float3(_1691.xyz), _2487)), 0.0f.xxx), _1219).z), dot(HALATION_BLUR.Sample(_HALATION_BLUR_sampler, halation_tex_uv).xyz, 0.16666667163372039794921875f.xxx).xxx, global_halation_weight.xxx);
    FragColor = float4(_883 * _2574, 1.0f);
}

SPIRV_Cross_Output main(SPIRV_Cross_Input stage_input)
{
    scanline_tex_uv = stage_input.scanline_tex_uv;
    scanline_texture_size_inv = stage_input.scanline_texture_size_inv;
    video_uv = stage_input.video_uv;
    mask_tiles_per_screen = stage_input.mask_tiles_per_screen;
    halation_tex_uv = stage_input.halation_tex_uv;
    frag_main();
    SPIRV_Cross_Output stage_output;
    stage_output.FragColor = FragColor;
    return stage_output;
}
