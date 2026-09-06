// Generated from crt/shaders/crt-royale/src/crt-royale-geometry-aa-last-pass.slang. See slang/upstream for licence/source.
cbuffer UBO : register(b0)
{
    row_major float4x4 global_MVP : packoffset(c0);
    float global_geom_mode_runtime : packoffset(c11.w);
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
    float2 _1049 = normalize(float2(min(params_OutputSize.x / params_OutputSize.y, 1.33333337306976318359375f), 1.0f));
    float _943 = _1049.x;
    geom_aspect_and_overscan = float4(_943, _1049.y, global_geom_overscan_x, global_geom_overscan_y);
    float2 _1064 = float2(global_geom_tilt_angle_x, global_geom_tilt_angle_y);
    float2 _952 = sin(_1064);
    float2 _955 = cos(_1064);
    float _958 = _955.y;
    float _960 = _952.y;
    float _972 = _955.x;
    float _974 = _952.x;
    float3x3 _987 = mul(float3x3(float3(_972, 0.0f, _974), float3(0.0f, 1.0f, 0.0f), float3(-_974, 0.0f, _972)), float3x3(float3(1.0f, 0.0f, 0.0f), float3(0.0f, _958, -_960), float3(0.0f, _960, _958)));
    float3x3 _990 = transpose(_987);
    global_to_local_row0 = _990[0];
    global_to_local_row1 = _990[1];
    global_to_local_row2 = _990[2];
    float3 _1115 = float3(0.0f, _1049.y, -global_geom_view_dist);
    float _1133 = global_geom_radius / sin(abs(acos(dot(_1115, _1115 * float3(1.0f, -1.0f, 1.0f)) / dot(_1115, _1115))) * 0.5f);
    bool _1135 = global_geom_mode_runtime < 2.5f;
    float3 _2822;
    if (_1135)
    {
        _2822 = float3(0.0f, 0.0f, _1133);
    }
    else
    {
        _2822 = float3(0.0f, 0.0f, max(global_geom_view_dist, _1133));
    }
    bool _1240 = global_geom_mode_runtime < 1.5f;
    float3 _2825;
    if (_1240)
    {
        _2825 = float3(0.0f, -0.0f, global_geom_radius);
    }
    else
    {
        float3 _2824;
        if (_1135)
        {
            _2824 = float3(0.0f, -0.0f, sqrt(global_geom_radius * global_geom_radius));
        }
        else
        {
            _2824 = float3(0.0f, -0.0f, global_geom_radius);
        }
        _2825 = _2824;
    }
    float3 _1151 = mul(_987, _2825);
    float3 _2832;
    if (_1240)
    {
        float2 _1420 = float2(0.0f, -0.5f) * _1049;
        float2 _1422 = normalize(_1420);
        float _1431 = (_1420.y / _1422.y) / global_geom_radius;
        float2 _1439 = _1422 * (sin(_1431) * global_geom_radius);
        _2832 = float3(_1439.x, -_1439.y, cos(_1431) * global_geom_radius);
    }
    else
    {
        float3 _2831;
        if (_1135)
        {
            float2 _1473 = sin((float2(0.0f, -0.5f) * _1049) / global_geom_radius.xx) * global_geom_radius;
            _2831 = float3(_1473.x, -_1473.y, sqrt((global_geom_radius * global_geom_radius) - dot(_1473, _1473)));
        }
        else
        {
            float2 _1501 = float2(0.0f, -0.5f) * _1049;
            float _1507 = _1501.x / global_geom_radius;
            _2831 = float3(sin(_1507) * global_geom_radius, -_1501.y, cos(_1507) * global_geom_radius);
        }
        _2832 = _2831;
    }
    float3 _2838;
    if (_1240)
    {
        float2 _1568 = float2(0.0f, 0.5f) * _1049;
        float2 _1570 = normalize(_1568);
        float _1579 = (_1568.y / _1570.y) / global_geom_radius;
        float2 _1587 = _1570 * (sin(_1579) * global_geom_radius);
        _2838 = float3(_1587.x, -_1587.y, cos(_1579) * global_geom_radius);
    }
    else
    {
        float3 _2837;
        if (_1135)
        {
            float2 _1621 = sin((float2(0.0f, 0.5f) * _1049) / global_geom_radius.xx) * global_geom_radius;
            _2837 = float3(_1621.x, -_1621.y, sqrt((global_geom_radius * global_geom_radius) - dot(_1621, _1621)));
        }
        else
        {
            float2 _1649 = float2(0.0f, 0.5f) * _1049;
            float _1655 = _1649.x / global_geom_radius;
            _2837 = float3(sin(_1655) * global_geom_radius, -_1649.y, cos(_1655) * global_geom_radius);
        }
        _2838 = _2837;
    }
    float3 _2844;
    if (_1240)
    {
        float2 _1716 = float2(-0.5f, 0.0f) * _1049;
        float2 _1718 = normalize(_1716);
        float _1727 = (_1716.y / _1718.y) / global_geom_radius;
        float2 _1735 = _1718 * (sin(_1727) * global_geom_radius);
        _2844 = float3(_1735.x, -_1735.y, cos(_1727) * global_geom_radius);
    }
    else
    {
        float3 _2843;
        if (_1135)
        {
            float2 _1769 = sin((float2(-0.5f, 0.0f) * _1049) / global_geom_radius.xx) * global_geom_radius;
            _2843 = float3(_1769.x, -_1769.y, sqrt((global_geom_radius * global_geom_radius) - dot(_1769, _1769)));
        }
        else
        {
            float2 _1797 = float2(-0.5f, 0.0f) * _1049;
            float _1803 = _1797.x / global_geom_radius;
            _2843 = float3(sin(_1803) * global_geom_radius, -_1797.y, cos(_1803) * global_geom_radius);
        }
        _2844 = _2843;
    }
    float3 _2850;
    if (_1240)
    {
        float2 _1864 = float2(0.5f, 0.0f) * _1049;
        float2 _1866 = normalize(_1864);
        float _1875 = (_1864.y / _1866.y) / global_geom_radius;
        float2 _1883 = _1866 * (sin(_1875) * global_geom_radius);
        _2850 = float3(_1883.x, -_1883.y, cos(_1875) * global_geom_radius);
    }
    else
    {
        float3 _2849;
        if (_1135)
        {
            float2 _1917 = sin((float2(0.5f, 0.0f) * _1049) / global_geom_radius.xx) * global_geom_radius;
            _2849 = float3(_1917.x, -_1917.y, sqrt((global_geom_radius * global_geom_radius) - dot(_1917, _1917)));
        }
        else
        {
            float2 _1945 = float2(0.5f, 0.0f) * _1049;
            float _1951 = _1945.x / global_geom_radius;
            _2849 = float3(sin(_1951) * global_geom_radius, -_1945.y, cos(_1951) * global_geom_radius);
        }
        _2850 = _2849;
    }
    float3 _2856;
    if (_1240)
    {
        float2 _2012 = (-0.5f).xx * _1049;
        float2 _2014 = normalize(_2012);
        float _2023 = (_2012.y / _2014.y) / global_geom_radius;
        float2 _2031 = _2014 * (sin(_2023) * global_geom_radius);
        _2856 = float3(_2031.x, -_2031.y, cos(_2023) * global_geom_radius);
    }
    else
    {
        float3 _2855;
        if (_1135)
        {
            float2 _2065 = sin(((-0.5f).xx * _1049) / global_geom_radius.xx) * global_geom_radius;
            _2855 = float3(_2065.x, -_2065.y, sqrt((global_geom_radius * global_geom_radius) - dot(_2065, _2065)));
        }
        else
        {
            float2 _2093 = (-0.5f).xx * _1049;
            float _2099 = _2093.x / global_geom_radius;
            _2855 = float3(sin(_2099) * global_geom_radius, -_2093.y, cos(_2099) * global_geom_radius);
        }
        _2856 = _2855;
    }
    float3 _2862;
    if (_1240)
    {
        float2 _2160 = float2(0.5f, -0.5f) * _1049;
        float2 _2162 = normalize(_2160);
        float _2171 = (_2160.y / _2162.y) / global_geom_radius;
        float2 _2179 = _2162 * (sin(_2171) * global_geom_radius);
        _2862 = float3(_2179.x, -_2179.y, cos(_2171) * global_geom_radius);
    }
    else
    {
        float3 _2861;
        if (_1135)
        {
            float2 _2213 = sin((float2(0.5f, -0.5f) * _1049) / global_geom_radius.xx) * global_geom_radius;
            _2861 = float3(_2213.x, -_2213.y, sqrt((global_geom_radius * global_geom_radius) - dot(_2213, _2213)));
        }
        else
        {
            float2 _2241 = float2(0.5f, -0.5f) * _1049;
            float _2247 = _2241.x / global_geom_radius;
            _2861 = float3(sin(_2247) * global_geom_radius, -_2241.y, cos(_2247) * global_geom_radius);
        }
        _2862 = _2861;
    }
    float3 _2868;
    if (_1240)
    {
        float2 _2308 = float2(-0.5f, 0.5f) * _1049;
        float2 _2310 = normalize(_2308);
        float _2319 = (_2308.y / _2310.y) / global_geom_radius;
        float2 _2327 = _2310 * (sin(_2319) * global_geom_radius);
        _2868 = float3(_2327.x, -_2327.y, cos(_2319) * global_geom_radius);
    }
    else
    {
        float3 _2867;
        if (_1135)
        {
            float2 _2361 = sin((float2(-0.5f, 0.5f) * _1049) / global_geom_radius.xx) * global_geom_radius;
            _2867 = float3(_2361.x, -_2361.y, sqrt((global_geom_radius * global_geom_radius) - dot(_2361, _2361)));
        }
        else
        {
            float2 _2389 = float2(-0.5f, 0.5f) * _1049;
            float _2395 = _2389.x / global_geom_radius;
            _2867 = float3(sin(_2395) * global_geom_radius, -_2389.y, cos(_2395) * global_geom_radius);
        }
        _2868 = _2867;
    }
    float3 _2874;
    if (_1240)
    {
        float2 _2456 = 0.5f.xx * _1049;
        float2 _2458 = normalize(_2456);
        float _2467 = (_2456.y / _2458.y) / global_geom_radius;
        float2 _2475 = _2458 * (sin(_2467) * global_geom_radius);
        _2874 = float3(_2475.x, -_2475.y, cos(_2467) * global_geom_radius);
    }
    else
    {
        float3 _2873;
        if (_1135)
        {
            float2 _2509 = sin((0.5f.xx * _1049) / global_geom_radius.xx) * global_geom_radius;
            _2873 = float3(_2509.x, -_2509.y, sqrt((global_geom_radius * global_geom_radius) - dot(_2509, _2509)));
        }
        else
        {
            float2 _2537 = 0.5f.xx * _1049;
            float _2543 = _2537.x / global_geom_radius;
            _2873 = float3(sin(_2543) * global_geom_radius, -_2537.y, cos(_2543) * global_geom_radius);
        }
        _2874 = _2873;
    }
    float _2897;
    _2897 = 0.0f;
    for (int _2877 = 0; _2877 < 9; )
    {
        _2897 += float(_1151.z < 0.0f);
        _2877++;
        continue;
    }
    float3 _3012;
    if (_2897 > 0.5f)
    {
        _3012 = _2822;
    }
    else
    {
        float3 _2815[9] = { _1151, mul(_987, _2832), mul(_987, _2838), mul(_987, _2844), mul(_987, _2850), mul(_987, _2856), mul(_987, _2862), mul(_987, _2868), mul(_987, _2874) };
        float3 _1106[9] = _2815;
        float3 _3154;
        _3154 = _2822;
        float3 _3166;
        float3 _2564[9];
        for (int _2981 = 0; _2981 < 1; _3154 = _3166, _2981++)
        {
            for (int _2983 = 0; _2983 < 9; )
            {
                _2564[_2983] = _1106[_2983] - _3154;
                _2983++;
                continue;
            }
            float _2610 = abs(global_geom_radius);
            float2 _2988;
            float2 _2989;
            _2989 = (10.0f * _2610).xx;
            _2988 = ((-10.0f) * _2610).xx;
            for (int _2986 = 0; _2986 < 9; )
            {
                float2 _2636 = _1049 * (-_2564[_2986].z);
                float2 _2641 = float2(1.0f, -1.0f) * global_geom_view_dist;
                _2989 = min(_2989, _2564[_2986].xy - (((-0.5f).xx * _2636) / _2641));
                _2988 = max(_2988, _2564[_2986].xy - ((0.5f.xx * _2636) / _2641));
                _2986++;
                continue;
            }
            float2 _2675 = _3154.xy + ((_2988 + _2989) * 0.5f);
            float _2677 = _2675.x;
            float3 _3133 = _3154;
            _3133.x = _2677;
            _3133.y = _2675.y;
            for (int _2990 = 0; _2990 < 9; )
            {
                _2564[_2990] = _1106[_2990] - _3133;
                _2990++;
                continue;
            }
            float _2994;
            _2994 = ((-10.0f) * global_geom_radius) * global_geom_view_dist;
            float _2780;
            for (int _2992 = 0; _2992 < 9; _2994 = _2780, _2992++)
            {
                float3 _2712 = _2564[_2992] * float3(1.0f, -1.0f, 1.0f);
                float4 _2728 = _2712.zzzz + ((_2712.xyxy * global_geom_view_dist) / (float4(-0.5f, -0.5f, 0.5f, 0.5f) * float4(_943, _1049.y, _943, _1049.y)));
                float _2730 = _2712.x;
                float _3004;
                if (_2730 < 0.0f)
                {
                    _3004 = max(_2994, _2728.x);
                }
                else
                {
                    _3004 = _2994;
                }
                float _2742 = _2712.y;
                float _3005;
                if (_2742 < 0.0f)
                {
                    _3005 = max(_3004, _2728.y);
                }
                else
                {
                    _3005 = _3004;
                }
                float _3006;
                if (_2730 > 0.0f)
                {
                    _3006 = max(_3005, _2728.z);
                }
                else
                {
                    _3006 = _3005;
                }
                float _3007;
                if (_2742 > 0.0f)
                {
                    _3007 = max(_3006, _2728.w);
                }
                else
                {
                    _3007 = _3006;
                }
                _2780 = max(_3007, _2712.z);
            }
            _3166 = float3(_2677, _2675.y, _3154.z + _2994);
        }
        _3012 = _3154;
    }
    eye_pos_local = mul(_990, _3012);
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
