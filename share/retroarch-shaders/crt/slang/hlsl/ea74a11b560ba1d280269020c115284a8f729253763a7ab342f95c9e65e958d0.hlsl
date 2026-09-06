// Generated from crt/shaders/crt-royale/src/crt-royale-geometry-aa-last-pass-intel.slang. See slang/upstream for licence/source.
cbuffer UBO : register(b0)
{
    row_major float4x4 global_MVP : packoffset(c0);
    float global_geom_radius : packoffset(c12);
    float global_geom_view_dist : packoffset(c12.y);
    float global_geom_tilt_angle_x : packoffset(c12.z);
    float global_geom_tilt_angle_y : packoffset(c12.w);
    float global_geom_overscan_x : packoffset(c13.z);
    float global_geom_overscan_y : packoffset(c13.w);
};

cbuffer Push : register(b1)
{
    float4 params_SourceSize : packoffset(c0);
    float4 params_OutputSize : packoffset(c2);
};


static float4 gl_Position;
static float4 Position;
static float2 tex_uv;
static float2 TexCoord;
static float4 video_and_texture_size_inv;
static float2 output_size_inv;
static float4 geom_aspect_and_overscan;
static float3 global_to_local_row0;
static float3 global_to_local_row1;
static float3 global_to_local_row2;
static float3 eye_pos_local;

struct SPIRV_Cross_Input
{
    float4 Position : TEXCOORD0;
    float2 TexCoord : TEXCOORD1;
};

struct SPIRV_Cross_Output
{
    float2 tex_uv : TEXCOORD0;
    float4 video_and_texture_size_inv : TEXCOORD1;
    float2 output_size_inv : TEXCOORD2;
    float3 eye_pos_local : TEXCOORD3;
    float4 geom_aspect_and_overscan : TEXCOORD4;
    float3 global_to_local_row0 : TEXCOORD5;
    float3 global_to_local_row1 : TEXCOORD6;
    float3 global_to_local_row2 : TEXCOORD7;
    float4 gl_Position : SV_Position;
};

void vert_main()
{
    gl_Position = mul(Position, global_MVP);
    tex_uv = TexCoord;
    video_and_texture_size_inv = 1.0f.xxxx / float4(params_SourceSize.xyxy);
    output_size_inv = 1.0f.xx / params_OutputSize.xy;
    float2 _1050 = normalize(float2(min(params_OutputSize.x / params_OutputSize.y, 1.33333337306976318359375f), 1.0f));
    float _946 = _1050.x;
    geom_aspect_and_overscan = float4(_946, _1050.y, global_geom_overscan_x, global_geom_overscan_y);
    float2 _1065 = float2(global_geom_tilt_angle_x, global_geom_tilt_angle_y);
    float2 _955 = sin(_1065);
    float2 _958 = cos(_1065);
    float _961 = _958.y;
    float _963 = _955.y;
    float _975 = _958.x;
    float _977 = _955.x;
    float3x3 _990 = mul(float3x3(float3(_975, 0.0f, _977), float3(0.0f, 1.0f, 0.0f), float3(-_977, 0.0f, _975)), float3x3(float3(1.0f, 0.0f, 0.0f), float3(0.0f, _961, -_963), float3(0.0f, _963, _961)));
    float3x3 _993 = transpose(_990);
    global_to_local_row0 = _993[0];
    global_to_local_row1 = _993[1];
    global_to_local_row2 = _993[2];
    float3 _1116 = float3(0.0f, _1050.y, -global_geom_view_dist);
    float3 _1139 = float3(0.0f, 0.0f, global_geom_radius / sin(abs(acos(dot(_1116, _1116 * float3(1.0f, -1.0f, 1.0f)) / dot(_1116, _1116))) * 0.5f));
    float3 _1152 = mul(_990, float3(0.0f, -0.0f, global_geom_radius));
    float2 _1421 = float2(0.0f, -0.5f) * _1050;
    float2 _1423 = normalize(_1421);
    float _1432 = (_1421.y / _1423.y) / global_geom_radius;
    float2 _1440 = _1423 * (sin(_1432) * global_geom_radius);
    float2 _1569 = float2(0.0f, 0.5f) * _1050;
    float2 _1571 = normalize(_1569);
    float _1580 = (_1569.y / _1571.y) / global_geom_radius;
    float2 _1588 = _1571 * (sin(_1580) * global_geom_radius);
    float2 _1717 = float2(-0.5f, 0.0f) * _1050;
    float2 _1719 = normalize(_1717);
    float _1728 = (_1717.y / _1719.y) / global_geom_radius;
    float2 _1736 = _1719 * (sin(_1728) * global_geom_radius);
    float2 _1865 = float2(0.5f, 0.0f) * _1050;
    float2 _1867 = normalize(_1865);
    float _1876 = (_1865.y / _1867.y) / global_geom_radius;
    float2 _1884 = _1867 * (sin(_1876) * global_geom_radius);
    float2 _2013 = (-0.5f).xx * _1050;
    float2 _2015 = normalize(_2013);
    float _2024 = (_2013.y / _2015.y) / global_geom_radius;
    float2 _2032 = _2015 * (sin(_2024) * global_geom_radius);
    float2 _2161 = float2(0.5f, -0.5f) * _1050;
    float2 _2163 = normalize(_2161);
    float _2172 = (_2161.y / _2163.y) / global_geom_radius;
    float2 _2180 = _2163 * (sin(_2172) * global_geom_radius);
    float2 _2309 = float2(-0.5f, 0.5f) * _1050;
    float2 _2311 = normalize(_2309);
    float _2320 = (_2309.y / _2311.y) / global_geom_radius;
    float2 _2328 = _2311 * (sin(_2320) * global_geom_radius);
    float2 _2457 = 0.5f.xx * _1050;
    float2 _2459 = normalize(_2457);
    float _2468 = (_2457.y / _2459.y) / global_geom_radius;
    float2 _2476 = _2459 * (sin(_2468) * global_geom_radius);
    float _2901;
    _2901 = 0.0f;
    for (int _2881 = 0; _2881 < 9; )
    {
        _2901 += float(_1152.z < 0.0f);
        _2881++;
        continue;
    }
    float3 _3016;
    if (_2901 > 0.5f)
    {
        _3016 = _1139;
    }
    else
    {
        float3 _2816[9] = { _1152, mul(_990, float3(_1440.x, -_1440.y, cos(_1432) * global_geom_radius)), mul(_990, float3(_1588.x, -_1588.y, cos(_1580) * global_geom_radius)), mul(_990, float3(_1736.x, -_1736.y, cos(_1728) * global_geom_radius)), mul(_990, float3(_1884.x, -_1884.y, cos(_1876) * global_geom_radius)), mul(_990, float3(_2032.x, -_2032.y, cos(_2024) * global_geom_radius)), mul(_990, float3(_2180.x, -_2180.y, cos(_2172) * global_geom_radius)), mul(_990, float3(_2328.x, -_2328.y, cos(_2320) * global_geom_radius)), mul(_990, float3(_2476.x, -_2476.y, cos(_2468) * global_geom_radius)) };
        float3 _1107[9] = _2816;
        float3 _3121;
        _3121 = _1139;
        float3 _3133;
        float3 _2565[9];
        for (int _2985 = 0; _2985 < 1; _3121 = _3133, _2985++)
        {
            for (int _2987 = 0; _2987 < 9; )
            {
                _2565[_2987] = _1107[_2987] - _3121;
                _2987++;
                continue;
            }
            float _2611 = abs(global_geom_radius);
            float2 _2992;
            float2 _2993;
            _2993 = (10.0f * _2611).xx;
            _2992 = ((-10.0f) * _2611).xx;
            for (int _2990 = 0; _2990 < 9; )
            {
                float2 _2637 = _1050 * (-_2565[_2990].z);
                float2 _2642 = float2(1.0f, -1.0f) * global_geom_view_dist;
                _2993 = min(_2993, _2565[_2990].xy - (((-0.5f).xx * _2637) / _2642));
                _2992 = max(_2992, _2565[_2990].xy - ((0.5f.xx * _2637) / _2642));
                _2990++;
                continue;
            }
            float2 _2676 = _3121.xy + ((_2992 + _2993) * 0.5f);
            float _2678 = _2676.x;
            float3 _3101 = _3121;
            _3101.x = _2678;
            _3101.y = _2676.y;
            for (int _2994 = 0; _2994 < 9; )
            {
                _2565[_2994] = _1107[_2994] - _3101;
                _2994++;
                continue;
            }
            float _2998;
            _2998 = ((-10.0f) * global_geom_radius) * global_geom_view_dist;
            float _2781;
            for (int _2996 = 0; _2996 < 9; _2998 = _2781, _2996++)
            {
                float3 _2713 = _2565[_2996] * float3(1.0f, -1.0f, 1.0f);
                float4 _2729 = _2713.zzzz + ((_2713.xyxy * global_geom_view_dist) / (float4(-0.5f, -0.5f, 0.5f, 0.5f) * float4(_946, _1050.y, _946, _1050.y)));
                float _2731 = _2713.x;
                float _3008;
                if (_2731 < 0.0f)
                {
                    _3008 = max(_2998, _2729.x);
                }
                else
                {
                    _3008 = _2998;
                }
                float _2743 = _2713.y;
                float _3009;
                if (_2743 < 0.0f)
                {
                    _3009 = max(_3008, _2729.y);
                }
                else
                {
                    _3009 = _3008;
                }
                float _3010;
                if (_2731 > 0.0f)
                {
                    _3010 = max(_3009, _2729.z);
                }
                else
                {
                    _3010 = _3009;
                }
                float _3011;
                if (_2743 > 0.0f)
                {
                    _3011 = max(_3010, _2729.w);
                }
                else
                {
                    _3011 = _3010;
                }
                _2781 = max(_3011, _2713.z);
            }
            _3133 = float3(_2678, _2676.y, _3121.z + _2998);
        }
        _3016 = _3121;
    }
    eye_pos_local = mul(_993, _3016);
}

SPIRV_Cross_Output main(SPIRV_Cross_Input stage_input)
{
    Position = stage_input.Position;
    TexCoord = stage_input.TexCoord;
    vert_main();
    SPIRV_Cross_Output stage_output;
    stage_output.gl_Position = gl_Position;
    stage_output.tex_uv = tex_uv;
    stage_output.video_and_texture_size_inv = video_and_texture_size_inv;
    stage_output.output_size_inv = output_size_inv;
    stage_output.geom_aspect_and_overscan = geom_aspect_and_overscan;
    stage_output.global_to_local_row0 = global_to_local_row0;
    stage_output.global_to_local_row1 = global_to_local_row1;
    stage_output.global_to_local_row2 = global_to_local_row2;
    stage_output.eye_pos_local = eye_pos_local;
    return stage_output;
}
