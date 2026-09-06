// Generated from crt/shaders/crt-royale/src-fast/crt-royale-scanlines-horizontal-apply-mask.slang. See slang/upstream for licence/source.
cbuffer UBO : register(b0)
{
    row_major float4x4 global_MVP : packoffset(c0);
    float global_mask_num_triads_desired : packoffset(c9.y);
    float global_mask_triad_size_desired : packoffset(c9.z);
    float global_mask_specify_num_triads : packoffset(c9.w);
};

cbuffer Push : register(b1)
{
    float4 params_OutputSize : packoffset(c2);
    float4 params_VERTICAL_SCANLINESSize : packoffset(c3);
    float4 params_MASK_RESIZESize : packoffset(c4);
    float params_geom_d : packoffset(c5);
    float params_geom_R : packoffset(c5.y);
    float params_geom_x_tilt : packoffset(c6);
    float params_geom_y_tilt : packoffset(c6.y);
    float params_geom_center_x : packoffset(c7);
    float params_geom_center_y : packoffset(c7.y);
    float params_geom_invert_aspect : packoffset(c7.w);
};


static float4 gl_Position;
static float2 sinangle;
static float2 cosangle;
static float4 Position;
static float2 video_uv;
static float2 TexCoord;
static float3 stretch;
static float d2;
static float R_d_cx_cy;
static float2 scanline_texture_size_inv;
static float4 mask_tile_start_uv_and_size;
static float2 mask_tiles_per_screen;

struct SPIRV_Cross_Input
{
    float4 Position : TEXCOORD0;
    float2 TexCoord : TEXCOORD1;
};

struct SPIRV_Cross_Output
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
    float4 gl_Position : SV_Position;
};

void vert_main()
{
    float _180 = ceil(0.5f);
    float2 _254 = ((params_geom_invert_aspect > 0.5f) ? 1.0f : 0.75f).xx;
    gl_Position = mul(Position, global_MVP);
    video_uv = (TexCoord * 1.00010001659393310546875f.xx) - float2(params_geom_center_x, params_geom_center_y);
    float2 _724 = float2(params_geom_x_tilt, params_geom_y_tilt);
    sinangle = sin(_724);
    cosangle = cos(_724);
    float _796 = -params_geom_R;
    float2 _812 = (sinangle * _796) / (1.0f + (((params_geom_R / params_geom_d) * cosangle.x) * cosangle.y)).xx;
    float _976 = params_geom_d * params_geom_d;
    float _977 = dot(_812, _812) + _976;
    float _998 = (params_geom_R * (dot(_812, sinangle) - ((params_geom_d * cosangle.x) * cosangle.y))) - _976;
    float2 _906 = (((((_998 * (-2.0f)) - sqrt((4.0f * (_998 * _998)) - ((4.0f * _977) * (_976 + ((((2.0f * params_geom_R) * params_geom_d) * cosangle.x) * cosangle.y))))) / (2.0f * _977)).xx * _812) - (_796.xx * sinangle)) / params_geom_R.xx;
    float2 _909 = _906 / cosangle;
    float2 _912 = sinangle / cosangle;
    float _916 = dot(_912, _912) + 1.0f;
    float _919 = dot(_909, _912);
    float _939 = ((_919 * 2.0f) + sqrt((4.0f * (_919 * _919)) - ((4.0f * _916) * (dot(_909, _909) - 1.0f)))) / (2.0f * _916);
    float _953 = max(abs(params_geom_R * acos(_939)), 9.9999997473787516355514526367188e-06f);
    float2 _963 = (((_906 - (sinangle * _939)) / cosangle) * _953) / sin(_953 / params_geom_R).xx;
    float2 _815 = 0.5f.xx * _254;
    float _817 = _815.x;
    float2 _821 = float2(-_817, _963.y);
    float _1043 = max(abs(sqrt(dot(_821, _821))), 9.9999997473787516355514526367188e-06f);
    float _1047 = _1043 / params_geom_R;
    float2 _1052 = _821 * (sin(_1047) / _1043);
    float _1058 = 1.0f - cos(_1047);
    float _1063 = params_geom_d / params_geom_R;
    float _827 = _815.y;
    float2 _829 = float2(_963.x, -_827);
    float _1099 = max(abs(sqrt(dot(_829, _829))), 9.9999997473787516355514526367188e-06f);
    float _1103 = _1099 / params_geom_R;
    float2 _1108 = _829 * (sin(_1103) / _1099);
    float _1114 = 1.0f - cos(_1103);
    float2 _834 = float2(((((_1052 * cosangle) - (sinangle * _1058)) * params_geom_d) / ((_1063 + ((_1058 * cosangle.x) * cosangle.y)) + dot(_1052, sinangle)).xx).x, ((((_1108 * cosangle) - (sinangle * _1114)) * params_geom_d) / ((_1063 + ((_1114 * cosangle.x) * cosangle.y)) + dot(_1108, sinangle)).xx).y) / _254;
    float2 _839 = float2(_817, _963.y);
    float _1155 = max(abs(sqrt(dot(_839, _839))), 9.9999997473787516355514526367188e-06f);
    float _1159 = _1155 / params_geom_R;
    float2 _1164 = _839 * (sin(_1159) / _1155);
    float _1170 = 1.0f - cos(_1159);
    float2 _846 = float2(_963.x, _827);
    float _1211 = max(abs(sqrt(dot(_846, _846))), 9.9999997473787516355514526367188e-06f);
    float _1215 = _1211 / params_geom_R;
    float2 _1220 = _846 * (sin(_1215) / _1211);
    float _1226 = 1.0f - cos(_1215);
    float2 _851 = float2(((((_1164 * cosangle) - (sinangle * _1170)) * params_geom_d) / ((_1063 + ((_1170 * cosangle.x) * cosangle.y)) + dot(_1164, sinangle)).xx).x, ((((_1220 * cosangle) - (sinangle * _1226)) * params_geom_d) / ((_1063 + ((_1226 * cosangle.x) * cosangle.y)) + dot(_1220, sinangle)).xx).y) / _254;
    stretch = float3(((_851 + _834) * _254) * 0.5f, max(_851.x - _834.x, _851.y - _834.y));
    d2 = _976;
    R_d_cx_cy = ((params_geom_R * params_geom_d) * cosangle.x) * cosangle.y;
    scanline_texture_size_inv = 1.0f.xx / params_VERTICAL_SCANLINESSize.xy;
    float2 _1343 = clamp(1.0f.xx * min(8.0f * lerp(global_mask_triad_size_desired, params_OutputSize.x / global_mask_num_triads_desired, global_mask_specify_num_triads), 64.0f), 1.0f.xx * ceil(16.0f), params_MASK_RESIZESize.xy / (1.0f + (_180 * 0.125f)).xx);
    float _1345 = _1343.y;
    float2 _1368 = floor(float2(min(_1343.x, _1345), min(_1345, _1345)) + 1.52587890625e-05f.xx);
    float2 _1272 = _1368 / params_MASK_RESIZESize.xy;
    mask_tiles_per_screen = params_OutputSize.xy / _1368;
    mask_tile_start_uv_and_size = float4((_180.xx / _1368) * _1272, _1272);
}

SPIRV_Cross_Output main(SPIRV_Cross_Input stage_input)
{
    Position = stage_input.Position;
    TexCoord = stage_input.TexCoord;
    vert_main();
    SPIRV_Cross_Output stage_output;
    stage_output.gl_Position = gl_Position;
    stage_output.sinangle = sinangle;
    stage_output.cosangle = cosangle;
    stage_output.video_uv = video_uv;
    stage_output.stretch = stretch;
    stage_output.d2 = d2;
    stage_output.R_d_cx_cy = R_d_cx_cy;
    stage_output.scanline_texture_size_inv = scanline_texture_size_inv;
    stage_output.mask_tile_start_uv_and_size = mask_tile_start_uv_and_size;
    stage_output.mask_tiles_per_screen = mask_tiles_per_screen;
    return stage_output;
}
