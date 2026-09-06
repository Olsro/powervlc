// Generated from crt/shaders/crt-royale/src/crt-royale-geometry-aa-last-pass.slang. See slang/upstream for licence/source.
#version 120
#pragma parameter crt_gamma "Simulated CRT Gamma" 2.5 1.0 5.0 0.025
#pragma parameter lcd_gamma "Your Display Gamma" 2.2 1.0 5.0 0.025
#pragma parameter levels_contrast "Contrast" 1.0 0.0 4.0 0.015625
#pragma parameter halation_weight "Halation Weight" 0.0 0.0 1.0 0.005
#pragma parameter diffusion_weight "Diffusion Weight" 0.075 0.0 1.0 0.005
#pragma parameter bloom_underestimate_levels "Bloom - Underestimate Levels" 0.8 0.0 5.0 0.01
#pragma parameter bloom_excess "Bloom - Excess" 0.0 0.0 1.0 0.005
#pragma parameter beam_min_sigma "Beam - Min Sigma" 0.02 0.005 1.0 0.005
#pragma parameter beam_max_sigma "Beam - Max Sigma" 0.3 0.005 1.0 0.005
#pragma parameter beam_spot_power "Beam - Spot Power" 0.33 0.01 16.0 0.01
#pragma parameter beam_min_shape "Beam - Min Shape" 2.0 2.0 32.0 0.1
#pragma parameter beam_max_shape "Beam - Max Shape" 4.0 2.0 32.0 0.1
#pragma parameter beam_shape_power "Beam - Shape Power" 0.25 0.01 16.0 0.01
#pragma parameter beam_horiz_filter "Beam - Horiz Filter" 0.0 0.0 2.0 1.0
#pragma parameter beam_horiz_sigma "Beam - Horiz Sigma" 0.35 0.0 0.67 0.005
#pragma parameter beam_horiz_linear_rgb_weight "Beam - Horiz Linear RGB Weight" 1.0 0.0 1.0 0.01
#pragma parameter convergence_offset_x_r "Convergence - Offset X Red" 0.0 -4.0 4.0 0.05
#pragma parameter convergence_offset_x_g "Convergence - Offset X Green" 0.0 -4.0 4.0 0.05
#pragma parameter convergence_offset_x_b "Convergence - Offset X Blue" 0.0 -4.0 4.0 0.05
#pragma parameter convergence_offset_y_r "Convergence - Offset Y Red" 0.0 -2.0 2.0 0.05
#pragma parameter convergence_offset_y_g "Convergence - Offset Y Green" 0.0 -2.0 2.0 0.05
#pragma parameter convergence_offset_y_b "Convergence - Offset Y Blue" 0.0 -2.0 2.0 0.05
#pragma parameter mask_type "Mask - Type" 1.0 0.0 2.0 1.0
#pragma parameter mask_sample_mode_desired "Mask - Sample Mode" 0.0 0.0 2.0 1.0   //  Consider blocking mode 2.
#pragma parameter mask_specify_num_triads "Mask - Specify Number of Triads" 0.0 0.0 1.0 1.0
#pragma parameter mask_triad_size_desired "Mask - Triad Size Desired" 3.0 1.0 18.0 0.125
#pragma parameter mask_num_triads_desired "Mask - Number of Triads Desired" 480.0 342.0 1920.0 1.0
#pragma parameter aa_subpixel_r_offset_x_runtime "AA - Subpixel R Offset X" -0.333333333 -0.333333333 0.333333333 0.333333333
#pragma parameter aa_subpixel_r_offset_y_runtime "AA - Subpixel R Offset Y" 0.0 -0.333333333 0.333333333 0.333333333
#pragma parameter aa_cubic_c "AA - Cubic Sharpness" 0.5 0.0 4.0 0.015625
#pragma parameter aa_gauss_sigma "AA - Gaussian Sigma" 0.5 0.0625 1.0 0.015625
#pragma parameter geom_mode_runtime "Geometry - Mode" 0.0 0.0 3.0 1.0
#pragma parameter geom_radius "Geometry - Radius" 2.0 0.16 1024.0 0.1
#pragma parameter geom_view_dist "Geometry - View Distance" 2.0 0.5 1024.0 0.25
#pragma parameter geom_tilt_angle_x "Geometry - Tilt Angle X" 0.0 -3.14159265 3.14159265 0.017453292519943295
#pragma parameter geom_tilt_angle_y "Geometry - Tilt Angle Y" 0.0 -3.14159265 3.14159265 0.017453292519943295
#pragma parameter geom_aspect_ratio_x "Geometry - Aspect Ratio X" 432.0 1.0 512.0 1.0
#pragma parameter geom_aspect_ratio_y "Geometry - Aspect Ratio Y" 329.0 1.0 512.0 1.0
#pragma parameter geom_overscan_x "Geometry - Overscan X" 1.0 0.00390625 4.0 0.00390625
#pragma parameter geom_overscan_y "Geometry - Overscan Y" 1.0 0.00390625 4.0 0.00390625
#pragma parameter border_size "Border - Size" 0.015 0.0000001 0.5 0.005
#pragma parameter border_darkness "Border - Darkness" 2.0 0.0 16.0 0.0625
#pragma parameter border_compress "Border - Compression" 2.5 1.0 64.0 0.0625
#pragma parameter interlace_detect_toggle "Interlacing - Toggle" 1.0 0.0 1.0 1.0
#pragma parameter interlace_bff "Interlacing - Bottom Field First" 0.0 0.0 1.0 1.0
#pragma parameter interlace_1080i "Interlace - Detect 1080i" 0.0 0.0 1.0 1.0
#ifdef VERTEX

uniform mat4 MVPMatrix;
uniform vec2 OutputSize;
uniform vec2 TextureSize;
uniform float geom_mode_runtime;
uniform float geom_overscan_x;
uniform float geom_overscan_y;
uniform float geom_radius;
uniform float geom_tilt_angle_x;
uniform float geom_tilt_angle_y;
uniform float geom_view_dist;
struct UBO
{
    mat4 MVP;
    float geom_mode_runtime;
    float geom_radius;
    float geom_view_dist;
    float geom_tilt_angle_x;
    float geom_tilt_angle_y;
    float geom_overscan_x;
    float geom_overscan_y;
};



struct Push
{
    vec4 SourceSize;
    vec4 OutputSize;
};



attribute vec4 VertexCoord;
varying vec2 RA_VARYING_0;
attribute vec2 TexCoord;
varying vec4 RA_VARYING_1;
varying vec2 RA_VARYING_2;
varying vec4 RA_VARYING_4;
varying vec3 RA_VARYING_5;
varying vec3 RA_VARYING_6;
varying vec3 RA_VARYING_7;
varying vec3 RA_VARYING_3;

void main()
{
    gl_Position = (MVPMatrix) * VertexCoord;
    RA_VARYING_0 = TexCoord;
    RA_VARYING_1 = vec4(1.0) / vec4((vec4(TextureSize, 1.0 / TextureSize)).xyxy);
    RA_VARYING_2 = vec2(1.0) / (vec4(OutputSize, 1.0 / OutputSize)).xy;
    vec2 _1049 = normalize(vec2(min((vec4(OutputSize, 1.0 / OutputSize)).x / (vec4(OutputSize, 1.0 / OutputSize)).y, 1.33333337306976318359375), 1.0));
    float _943 = _1049.x;
    RA_VARYING_4 = vec4(_943, _1049.y, (geom_overscan_x), (geom_overscan_y));
    vec2 _1064 = vec2((geom_tilt_angle_x), (geom_tilt_angle_y));
    vec2 _952 = sin(_1064);
    vec2 _955 = cos(_1064);
    float _958 = _955.y;
    float _960 = _952.y;
    float _972 = _955.x;
    float _974 = _952.x;
    mat3 _987 = mat3(vec3(1.0, 0.0, 0.0), vec3(0.0, _958, -_960), vec3(0.0, _960, _958)) * mat3(vec3(_972, 0.0, _974), vec3(0.0, 1.0, 0.0), vec3(-_974, 0.0, _972));
    mat3 _990 = transpose(_987);
    RA_VARYING_5 = _990[0];
    RA_VARYING_6 = _990[1];
    RA_VARYING_7 = _990[2];
    vec3 _1115 = vec3(0.0, _1049.y, -(geom_view_dist));
    float _1133 = (geom_radius) / sin(abs(acos(dot(_1115, _1115 * vec3(1.0, -1.0, 1.0)) / dot(_1115, _1115))) * 0.5);
    bool _1135 = (geom_mode_runtime) < 2.5;
    vec3 _2822;
    if (_1135)
    {
        _2822 = vec3(0.0, 0.0, _1133);
    }
    else
    {
        _2822 = vec3(0.0, 0.0, max((geom_view_dist), _1133));
    }
    bool _1240 = (geom_mode_runtime) < 1.5;
    vec3 _2825;
    if (_1240)
    {
        _2825 = vec3(0.0, -0.0, (geom_radius));
    }
    else
    {
        vec3 _2824;
        if (_1135)
        {
            _2824 = vec3(0.0, -0.0, sqrt((geom_radius) * (geom_radius)));
        }
        else
        {
            _2824 = vec3(0.0, -0.0, (geom_radius));
        }
        _2825 = _2824;
    }
    vec3 _1151 = _2825 * _987;
    vec3 _2832;
    if (_1240)
    {
        vec2 _1420 = vec2(0.0, -0.5) * _1049;
        vec2 _1422 = normalize(_1420);
        float _1431 = (_1420.y / _1422.y) / (geom_radius);
        vec2 _1439 = _1422 * (sin(_1431) * (geom_radius));
        _2832 = vec3(_1439.x, -_1439.y, cos(_1431) * (geom_radius));
    }
    else
    {
        vec3 _2831;
        if (_1135)
        {
            vec2 _1473 = sin((vec2(0.0, -0.5) * _1049) / vec2((geom_radius))) * (geom_radius);
            _2831 = vec3(_1473.x, -_1473.y, sqrt(((geom_radius) * (geom_radius)) - dot(_1473, _1473)));
        }
        else
        {
            vec2 _1501 = vec2(0.0, -0.5) * _1049;
            float _1507 = _1501.x / (geom_radius);
            _2831 = vec3(sin(_1507) * (geom_radius), -_1501.y, cos(_1507) * (geom_radius));
        }
        _2832 = _2831;
    }
    vec3 _2838;
    if (_1240)
    {
        vec2 _1568 = vec2(0.0, 0.5) * _1049;
        vec2 _1570 = normalize(_1568);
        float _1579 = (_1568.y / _1570.y) / (geom_radius);
        vec2 _1587 = _1570 * (sin(_1579) * (geom_radius));
        _2838 = vec3(_1587.x, -_1587.y, cos(_1579) * (geom_radius));
    }
    else
    {
        vec3 _2837;
        if (_1135)
        {
            vec2 _1621 = sin((vec2(0.0, 0.5) * _1049) / vec2((geom_radius))) * (geom_radius);
            _2837 = vec3(_1621.x, -_1621.y, sqrt(((geom_radius) * (geom_radius)) - dot(_1621, _1621)));
        }
        else
        {
            vec2 _1649 = vec2(0.0, 0.5) * _1049;
            float _1655 = _1649.x / (geom_radius);
            _2837 = vec3(sin(_1655) * (geom_radius), -_1649.y, cos(_1655) * (geom_radius));
        }
        _2838 = _2837;
    }
    vec3 _2844;
    if (_1240)
    {
        vec2 _1716 = vec2(-0.5, 0.0) * _1049;
        vec2 _1718 = normalize(_1716);
        float _1727 = (_1716.y / _1718.y) / (geom_radius);
        vec2 _1735 = _1718 * (sin(_1727) * (geom_radius));
        _2844 = vec3(_1735.x, -_1735.y, cos(_1727) * (geom_radius));
    }
    else
    {
        vec3 _2843;
        if (_1135)
        {
            vec2 _1769 = sin((vec2(-0.5, 0.0) * _1049) / vec2((geom_radius))) * (geom_radius);
            _2843 = vec3(_1769.x, -_1769.y, sqrt(((geom_radius) * (geom_radius)) - dot(_1769, _1769)));
        }
        else
        {
            vec2 _1797 = vec2(-0.5, 0.0) * _1049;
            float _1803 = _1797.x / (geom_radius);
            _2843 = vec3(sin(_1803) * (geom_radius), -_1797.y, cos(_1803) * (geom_radius));
        }
        _2844 = _2843;
    }
    vec3 _2850;
    if (_1240)
    {
        vec2 _1864 = vec2(0.5, 0.0) * _1049;
        vec2 _1866 = normalize(_1864);
        float _1875 = (_1864.y / _1866.y) / (geom_radius);
        vec2 _1883 = _1866 * (sin(_1875) * (geom_radius));
        _2850 = vec3(_1883.x, -_1883.y, cos(_1875) * (geom_radius));
    }
    else
    {
        vec3 _2849;
        if (_1135)
        {
            vec2 _1917 = sin((vec2(0.5, 0.0) * _1049) / vec2((geom_radius))) * (geom_radius);
            _2849 = vec3(_1917.x, -_1917.y, sqrt(((geom_radius) * (geom_radius)) - dot(_1917, _1917)));
        }
        else
        {
            vec2 _1945 = vec2(0.5, 0.0) * _1049;
            float _1951 = _1945.x / (geom_radius);
            _2849 = vec3(sin(_1951) * (geom_radius), -_1945.y, cos(_1951) * (geom_radius));
        }
        _2850 = _2849;
    }
    vec3 _2856;
    if (_1240)
    {
        vec2 _2012 = vec2(-0.5) * _1049;
        vec2 _2014 = normalize(_2012);
        float _2023 = (_2012.y / _2014.y) / (geom_radius);
        vec2 _2031 = _2014 * (sin(_2023) * (geom_radius));
        _2856 = vec3(_2031.x, -_2031.y, cos(_2023) * (geom_radius));
    }
    else
    {
        vec3 _2855;
        if (_1135)
        {
            vec2 _2065 = sin((vec2(-0.5) * _1049) / vec2((geom_radius))) * (geom_radius);
            _2855 = vec3(_2065.x, -_2065.y, sqrt(((geom_radius) * (geom_radius)) - dot(_2065, _2065)));
        }
        else
        {
            vec2 _2093 = vec2(-0.5) * _1049;
            float _2099 = _2093.x / (geom_radius);
            _2855 = vec3(sin(_2099) * (geom_radius), -_2093.y, cos(_2099) * (geom_radius));
        }
        _2856 = _2855;
    }
    vec3 _2862;
    if (_1240)
    {
        vec2 _2160 = vec2(0.5, -0.5) * _1049;
        vec2 _2162 = normalize(_2160);
        float _2171 = (_2160.y / _2162.y) / (geom_radius);
        vec2 _2179 = _2162 * (sin(_2171) * (geom_radius));
        _2862 = vec3(_2179.x, -_2179.y, cos(_2171) * (geom_radius));
    }
    else
    {
        vec3 _2861;
        if (_1135)
        {
            vec2 _2213 = sin((vec2(0.5, -0.5) * _1049) / vec2((geom_radius))) * (geom_radius);
            _2861 = vec3(_2213.x, -_2213.y, sqrt(((geom_radius) * (geom_radius)) - dot(_2213, _2213)));
        }
        else
        {
            vec2 _2241 = vec2(0.5, -0.5) * _1049;
            float _2247 = _2241.x / (geom_radius);
            _2861 = vec3(sin(_2247) * (geom_radius), -_2241.y, cos(_2247) * (geom_radius));
        }
        _2862 = _2861;
    }
    vec3 _2868;
    if (_1240)
    {
        vec2 _2308 = vec2(-0.5, 0.5) * _1049;
        vec2 _2310 = normalize(_2308);
        float _2319 = (_2308.y / _2310.y) / (geom_radius);
        vec2 _2327 = _2310 * (sin(_2319) * (geom_radius));
        _2868 = vec3(_2327.x, -_2327.y, cos(_2319) * (geom_radius));
    }
    else
    {
        vec3 _2867;
        if (_1135)
        {
            vec2 _2361 = sin((vec2(-0.5, 0.5) * _1049) / vec2((geom_radius))) * (geom_radius);
            _2867 = vec3(_2361.x, -_2361.y, sqrt(((geom_radius) * (geom_radius)) - dot(_2361, _2361)));
        }
        else
        {
            vec2 _2389 = vec2(-0.5, 0.5) * _1049;
            float _2395 = _2389.x / (geom_radius);
            _2867 = vec3(sin(_2395) * (geom_radius), -_2389.y, cos(_2395) * (geom_radius));
        }
        _2868 = _2867;
    }
    vec3 _2874;
    if (_1240)
    {
        vec2 _2456 = vec2(0.5) * _1049;
        vec2 _2458 = normalize(_2456);
        float _2467 = (_2456.y / _2458.y) / (geom_radius);
        vec2 _2475 = _2458 * (sin(_2467) * (geom_radius));
        _2874 = vec3(_2475.x, -_2475.y, cos(_2467) * (geom_radius));
    }
    else
    {
        vec3 _2873;
        if (_1135)
        {
            vec2 _2509 = sin((vec2(0.5) * _1049) / vec2((geom_radius))) * (geom_radius);
            _2873 = vec3(_2509.x, -_2509.y, sqrt(((geom_radius) * (geom_radius)) - dot(_2509, _2509)));
        }
        else
        {
            vec2 _2537 = vec2(0.5) * _1049;
            float _2543 = _2537.x / (geom_radius);
            _2873 = vec3(sin(_2543) * (geom_radius), -_2537.y, cos(_2543) * (geom_radius));
        }
        _2874 = _2873;
    }
    float _2897;
    _2897 = 0.0;
    for (int _2877 = 0; _2877 < 9; )
    {
        _2897 += float(_1151.z < 0.0);
        _2877++;
        continue;
    }
    vec3 _3012;
    if (_2897 > 0.5)
    {
        _3012 = _2822;
    }
    else
    {
        vec3 _1106[9] = vec3[](_1151, _2832 * _987, _2838 * _987, _2844 * _987, _2850 * _987, _2856 * _987, _2862 * _987, _2868 * _987, _2874 * _987);
        vec3 _3154;
        _3154 = _2822;
        vec3 _3166;
        vec3 _2564[9];
        for (int _2981 = 0; _2981 < 1; _3154 = _3166, _2981++)
        {
            for (int _2983 = 0; _2983 < 9; )
            {
                _2564[_2983] = _1106[_2983] - _3154;
                _2983++;
                continue;
            }
            float _2610 = abs((geom_radius));
            vec2 _2988;
            vec2 _2989;
            _2989 = vec2(10.0 * _2610);
            _2988 = vec2((-10.0) * _2610);
            for (int _2986 = 0; _2986 < 9; )
            {
                vec2 _2636 = _1049 * (-_2564[_2986].z);
                vec2 _2641 = vec2(1.0, -1.0) * (geom_view_dist);
                _2989 = min(_2989, _2564[_2986].xy - ((vec2(-0.5) * _2636) / _2641));
                _2988 = max(_2988, _2564[_2986].xy - ((vec2(0.5) * _2636) / _2641));
                _2986++;
                continue;
            }
            vec2 _2675 = _3154.xy + ((_2988 + _2989) * 0.5);
            float _2677 = _2675.x;
            vec3 _3133 = _3154;
            _3133.x = _2677;
            _3133.y = _2675.y;
            for (int _2990 = 0; _2990 < 9; )
            {
                _2564[_2990] = _1106[_2990] - _3133;
                _2990++;
                continue;
            }
            float _2994;
            _2994 = ((-10.0) * (geom_radius)) * (geom_view_dist);
            float _2780;
            for (int _2992 = 0; _2992 < 9; _2994 = _2780, _2992++)
            {
                vec3 _2712 = _2564[_2992] * vec3(1.0, -1.0, 1.0);
                vec4 _2728 = _2712.zzzz + ((_2712.xyxy * (geom_view_dist)) / (vec4(-0.5, -0.5, 0.5, 0.5) * vec4(_943, _1049.y, _943, _1049.y)));
                float _2730 = _2712.x;
                float _3004;
                if (_2730 < 0.0)
                {
                    _3004 = max(_2994, _2728.x);
                }
                else
                {
                    _3004 = _2994;
                }
                float _2742 = _2712.y;
                float _3005;
                if (_2742 < 0.0)
                {
                    _3005 = max(_3004, _2728.y);
                }
                else
                {
                    _3005 = _3004;
                }
                float _3006;
                if (_2730 > 0.0)
                {
                    _3006 = max(_3005, _2728.z);
                }
                else
                {
                    _3006 = _3005;
                }
                float _3007;
                if (_2742 > 0.0)
                {
                    _3007 = max(_3006, _2728.w);
                }
                else
                {
                    _3007 = _3006;
                }
                _2780 = max(_3007, _2712.z);
            }
            _3166 = vec3(_2677, _2675.y, _3154.z + _2994);
        }
        _3012 = _3154;
    }
    RA_VARYING_3 = _3012 * _990;
}


#endif
#ifdef FRAGMENT

uniform vec2 TextureSize;
uniform float aa_cubic_c;
uniform float border_compress;
uniform float border_darkness;
uniform float border_size;
uniform float geom_mode_runtime;
uniform float geom_radius;
uniform float geom_view_dist;
uniform float lcd_gamma;
struct UBO
{
    float lcd_gamma;
    float aa_cubic_c;
    float geom_mode_runtime;
    float geom_radius;
    float geom_view_dist;
    float border_size;
    float border_darkness;
    float border_compress;
};



struct Push
{
    vec4 SourceSize;
};



uniform sampler2D Texture;

varying vec4 RA_VARYING_4;
varying vec4 RA_VARYING_1;
varying vec3 RA_VARYING_5;
varying vec3 RA_VARYING_6;
varying vec3 RA_VARYING_7;
varying vec2 RA_VARYING_0;
varying vec3 RA_VARYING_3;
varying vec2 RA_VARYING_2;

void main()
{
    mat3 _5362 = mat3(RA_VARYING_5, RA_VARYING_6, RA_VARYING_7);
    vec2 _5380 = RA_VARYING_0 * ((vec4(TextureSize, 1.0 / TextureSize)).xy * RA_VARYING_1.xy);
    bool _5382 = (geom_mode_runtime) > 0.5;
    vec2 _106564;
    mat2 _106574;
    if (_5382)
    {
        vec2 _5573 = (_5380 - vec2(0.5)) * RA_VARYING_4.xy;
        vec3 _5582 = vec3(_5573.x, -_5573.y, -(geom_view_dist));
        vec3 _5585 = _5582 * _5362;
        bool _5687 = (geom_mode_runtime) < 2.5;
        vec2 _106507;
        if (_5687)
        {
            float _5711 = dot(_5585, RA_VARYING_3);
            float _5720 = dot(RA_VARYING_3, RA_VARYING_3) - ((geom_radius) * (geom_radius));
            float _5735 = (_5711 * _5711) - (dot(_5585, _5585) * _5720);
            _106507 = vec2(_5720 / (sqrt(_5735) - _5711), _5735);
        }
        else
        {
            vec3 _5767 = cross(vec3(0.0, 1.0, 0.0), _5585);
            vec3 _5770 = cross(vec3(0.0, 1.0, 0.0), RA_VARYING_3 - vec3(0.0, (geom_radius), 0.0));
            float _5776 = dot(_5770, _5767);
            float _5785 = dot(_5770, _5770) - ((geom_radius) * (geom_radius));
            float _5800 = (_5776 * _5776) - (dot(_5767, _5767) * _5785);
            _106507 = vec2(_5785 / (sqrt(_5800) - _5776), _5800);
        }
        vec3 _5666 = RA_VARYING_3 + (_5585 * _106507.x);
        vec2 _106514;
        if (_106507.y > 0.004999999888241291046142578125)
        {
            vec2 _106513;
            if ((geom_mode_runtime) < 1.5)
            {
                vec3 _5854 = vec3(0.0, 0.0, (geom_radius));
                _106513 = (normalize(vec2(_5666.x, -_5666.y)) * (atan(length(cross(_5666, _5854)), dot(_5666, _5854)) * (geom_radius))) / RA_VARYING_4.xy;
            }
            else
            {
                vec2 _106512;
                if (_5687)
                {
                    _106512 = (atan(vec2(_5666.x, -_5666.y), _5666.zz) * (geom_radius)) / RA_VARYING_4.xy;
                }
                else
                {
                    _106512 = vec2(atan(_5666.x, _5666.z) * (geom_radius), -_5666.y) / RA_VARYING_4.xy;
                }
                _106513 = _106512;
            }
            _106514 = _106513;
        }
        else
        {
            _106514 = vec2(1.0);
        }
        vec3 _106529;
        if (_5687)
        {
            _106529 = _5666;
        }
        else
        {
            _106529 = vec3(_5666.x, 0.0, _5666.z);
        }
        vec3 _5609 = normalize(_106529);
        vec3 _5958 = (_5582 + vec3(RA_VARYING_2.x, 0.0, 0.0)) * _5362;
        vec3 _5961 = (_5582 + vec3(0.0, -RA_VARYING_2.y, 0.0)) * _5362;
        vec3 _5977 = vec3(dot(_5666 - RA_VARYING_3, _5609));
        vec3 _6000 = (RA_VARYING_3 + ((_5977 / vec3(dot(_5958, _5609))) * _5958)) - _5666;
        vec3 _6003 = (RA_VARYING_3 + ((_5977 / vec3(dot(_5961, _5609))) * _5961)) - _5666;
        vec3 _106551;
        vec3 _106553;
        if ((geom_mode_runtime) < 1.5)
        {
            _106553 = normalize(cross(vec3(0.0, 1.0, 0.0), _5666)) * RA_VARYING_4.y;
            _106551 = normalize(cross(vec3(1.0, 0.0, 0.0), _5666)) * RA_VARYING_4.x;
        }
        else
        {
            vec3 _106552;
            vec3 _106554;
            if (_5687)
            {
                _106554 = cross(_5609, normalize(cross(vec3(1.0, 0.0, 0.0), vec3(0.0, _5666.yz))) * RA_VARYING_4.y);
                _106552 = cross(normalize(cross(vec3(0.0, 1.0, 0.0), vec3(_5666.x, 0.0, _5666.z))) * RA_VARYING_4.x, _5609);
            }
            else
            {
                _106554 = cross(vec3(0.0, 1.0, 0.0), _5609) * RA_VARYING_4.y;
                _106552 = vec3(0.0, -RA_VARYING_4.x, 0.0);
            }
            _106553 = _106554;
            _106551 = _106552;
        }
        vec3 _6100 = cross(_106551, _106553);
        float _6104 = inversesqrt(dot(_6100, _6100));
        mat3 _5624 = mat3(vec3(_6000.x, _6003.x, 0.0), vec3(_6000.y, _6003.y, 0.0), vec3(_6000.z, _6003.z, 0.0)) * mat3(_106553 * _6104, _106551 * _6104, _5609);
        _106574 = mat2(vec2(_5624[0].x, _5624[0].y), vec2(_5624[1].x, _5624[1].y));
        _106564 = _106514 + vec2(0.5);
    }
    else
    {
        _106574 = mat2(vec2(RA_VARYING_2.x, 0.0), vec2(0.0, RA_VARYING_2.y));
        _106564 = _5380;
    }
    vec2 _5418 = (_106564 - vec2(0.5)) / RA_VARYING_4.zw;
    vec2 _5419 = _5418 + vec2(0.5);
    vec2 _5426 = (vec4(TextureSize, 1.0 / TextureSize)).xy * RA_VARYING_1.zw;
    vec2 _5427 = _5419 * _5426;
    vec4 _6142 = vec4(_106574[0].x, _106574[0].y, _106574[1].x, _106574[1].y) * (_5426 / RA_VARYING_4.zw).xxyy;
    bool _5463;
    if (!_5382)
    {
        _5463 = any(bvec2(RA_VARYING_4.z != 1.0, RA_VARYING_4.w != 1.0));
    }
    else
    {
        _5463 = _5382;
    }
    vec3 _150618;
    if (_5463)
    {
        float _33387 = 2.0 * (aa_cubic_c);
        float _33388 = 1.0 - _33387;
        float _33394 = 6.0 * (aa_cubic_c);
        float _33395 = (12.0 - (9.0 * _33388)) - _33394;
        float _33402 = ((-18.0) + (12.0 * _33388)) + _33394;
        float _33405 = 6.0 - (2.0 * _33388);
        float _33411 = (_33387 - 1.0) - _33394;
        float _33417 = (6.0 * _33388) + (30.0 * (aa_cubic_c));
        float _33423 = ((-12.0) * _33388) - (48.0 * (aa_cubic_c));
        float _33429 = (8.0 * _33388) + (24.0 * (aa_cubic_c));
        vec2 _33502 = (vec2(2.0) + abs(vec2(-0.3333333432674407958984375, 0.0))) * vec2(1.0, 0.0);
        vec2 _33503 = max(vec2(0.5), _33502);
        vec4 _33517 = vec4(_33503 * 2.0, _33502 / _33503);
        vec2 _33146 = _33517.xy;
        vec2 _33148 = _33517.zw;
        vec2 _33159 = _33146 * vec2(-0.4583333432674407958984375);
        vec2 _33163 = _33159 + (_33146 * vec2(0.25, 0.0));
        vec2 _33167 = _33159 + (_33146 * vec2(0.75, 0.083333335816860198974609375));
        vec2 _33171 = _33159 + (_33146 * vec2(0.5, 0.16666667163372039794921875));
        vec2 _33175 = _33159 + (_33146 * vec2(0.083333335816860198974609375, 0.25));
        vec2 _33179 = _33159 + (_33146 * vec2(0.916666686534881591796875, 0.3333333432674407958984375));
        vec2 _33183 = _33159 + (_33146 * vec2(0.3333333432674407958984375, 0.416666686534881591796875));
        vec2 _33577 = _33163 * _33148;
        vec2 _33582 = vec2(-0.3333333432674407958984375, 0.0) * _33148;
        vec2 _33583 = _33577 - _33582;
        vec2 _33588 = _33577 + _33582;
        float _34051 = abs(_33583.x);
        float _135618;
        if (_34051 < 1.0)
        {
            _135618 = ((((_33395 * _34051) + _33402) * _34051) * _34051) + _33405;
        }
        else
        {
            float _135617;
            if (_34051 < 2.0)
            {
                _135617 = (((((_33411 * _34051) + _33417) * _34051) + _33423) * _34051) + _33429;
            }
            else
            {
                _135617 = 0.0;
            }
            _135618 = _135617;
        }
        float _34095 = abs(_33583.y);
        float _135634;
        if (_34095 < 1.0)
        {
            _135634 = ((((_33395 * _34095) + _33402) * _34095) * _34095) + _33405;
        }
        else
        {
            float _135627;
            if (_34095 < 2.0)
            {
                _135627 = (((((_33411 * _34095) + _33417) * _34095) + _33423) * _34095) + _33429;
            }
            else
            {
                _135627 = 0.0;
            }
            _135634 = _135627;
        }
        float _34139 = abs(_33577.x);
        float _135650;
        if (_34139 < 1.0)
        {
            _135650 = ((((_33395 * _34139) + _33402) * _34139) * _34139) + _33405;
        }
        else
        {
            float _135643;
            if (_34139 < 2.0)
            {
                _135643 = (((((_33411 * _34139) + _33417) * _34139) + _33423) * _34139) + _33429;
            }
            else
            {
                _135643 = 0.0;
            }
            _135650 = _135643;
        }
        float _34183 = abs(_33577.y);
        float _135666;
        if (_34183 < 1.0)
        {
            _135666 = ((((_33395 * _34183) + _33402) * _34183) * _34183) + _33405;
        }
        else
        {
            float _135659;
            if (_34183 < 2.0)
            {
                _135659 = (((((_33411 * _34183) + _33417) * _34183) + _33423) * _34183) + _33429;
            }
            else
            {
                _135659 = 0.0;
            }
            _135666 = _135659;
        }
        float _34227 = abs(_33588.x);
        float _135682;
        if (_34227 < 1.0)
        {
            _135682 = ((((_33395 * _34227) + _33402) * _34227) * _34227) + _33405;
        }
        else
        {
            float _135675;
            if (_34227 < 2.0)
            {
                _135675 = (((((_33411 * _34227) + _33417) * _34227) + _33423) * _34227) + _33429;
            }
            else
            {
                _135675 = 0.0;
            }
            _135682 = _135675;
        }
        float _34271 = abs(_33588.y);
        float _135698;
        if (_34271 < 1.0)
        {
            _135698 = ((((_33395 * _34271) + _33402) * _34271) * _34271) + _33405;
        }
        else
        {
            float _135691;
            if (_34271 < 2.0)
            {
                _135691 = (((((_33411 * _34271) + _33417) * _34271) + _33423) * _34271) + _33429;
            }
            else
            {
                _135691 = 0.0;
            }
            _135698 = _135691;
        }
        vec3 _33718 = vec3(0.0277777798473834991455078125 * (_135618 * _135634), 0.0277777798473834991455078125 * (_135650 * _135666), 0.0277777798473834991455078125 * (_135682 * _135698));
        vec2 _35025 = _33167 * _33148;
        vec2 _35031 = _35025 - _33582;
        vec2 _35036 = _35025 + _33582;
        float _35499 = abs(_35031.x);
        float _135908;
        if (_35499 < 1.0)
        {
            _135908 = ((((_33395 * _35499) + _33402) * _35499) * _35499) + _33405;
        }
        else
        {
            float _135907;
            if (_35499 < 2.0)
            {
                _135907 = (((((_33411 * _35499) + _33417) * _35499) + _33423) * _35499) + _33429;
            }
            else
            {
                _135907 = 0.0;
            }
            _135908 = _135907;
        }
        float _35543 = abs(_35031.y);
        float _135924;
        if (_35543 < 1.0)
        {
            _135924 = ((((_33395 * _35543) + _33402) * _35543) * _35543) + _33405;
        }
        else
        {
            float _135917;
            if (_35543 < 2.0)
            {
                _135917 = (((((_33411 * _35543) + _33417) * _35543) + _33423) * _35543) + _33429;
            }
            else
            {
                _135917 = 0.0;
            }
            _135924 = _135917;
        }
        float _35587 = abs(_35025.x);
        float _135940;
        if (_35587 < 1.0)
        {
            _135940 = ((((_33395 * _35587) + _33402) * _35587) * _35587) + _33405;
        }
        else
        {
            float _135933;
            if (_35587 < 2.0)
            {
                _135933 = (((((_33411 * _35587) + _33417) * _35587) + _33423) * _35587) + _33429;
            }
            else
            {
                _135933 = 0.0;
            }
            _135940 = _135933;
        }
        float _35631 = abs(_35025.y);
        float _135956;
        if (_35631 < 1.0)
        {
            _135956 = ((((_33395 * _35631) + _33402) * _35631) * _35631) + _33405;
        }
        else
        {
            float _135949;
            if (_35631 < 2.0)
            {
                _135949 = (((((_33411 * _35631) + _33417) * _35631) + _33423) * _35631) + _33429;
            }
            else
            {
                _135949 = 0.0;
            }
            _135956 = _135949;
        }
        float _35675 = abs(_35036.x);
        float _135972;
        if (_35675 < 1.0)
        {
            _135972 = ((((_33395 * _35675) + _33402) * _35675) * _35675) + _33405;
        }
        else
        {
            float _135965;
            if (_35675 < 2.0)
            {
                _135965 = (((((_33411 * _35675) + _33417) * _35675) + _33423) * _35675) + _33429;
            }
            else
            {
                _135965 = 0.0;
            }
            _135972 = _135965;
        }
        float _35719 = abs(_35036.y);
        float _135988;
        if (_35719 < 1.0)
        {
            _135988 = ((((_33395 * _35719) + _33402) * _35719) * _35719) + _33405;
        }
        else
        {
            float _135981;
            if (_35719 < 2.0)
            {
                _135981 = (((((_33411 * _35719) + _33417) * _35719) + _33423) * _35719) + _33429;
            }
            else
            {
                _135981 = 0.0;
            }
            _135988 = _135981;
        }
        vec3 _35166 = vec3(0.0277777798473834991455078125 * (_135908 * _135924), 0.0277777798473834991455078125 * (_135940 * _135956), 0.0277777798473834991455078125 * (_135972 * _135988));
        vec2 _36473 = _33171 * _33148;
        vec2 _36479 = _36473 - _33582;
        vec2 _36484 = _36473 + _33582;
        float _36947 = abs(_36479.x);
        float _136231;
        if (_36947 < 1.0)
        {
            _136231 = ((((_33395 * _36947) + _33402) * _36947) * _36947) + _33405;
        }
        else
        {
            float _136230;
            if (_36947 < 2.0)
            {
                _136230 = (((((_33411 * _36947) + _33417) * _36947) + _33423) * _36947) + _33429;
            }
            else
            {
                _136230 = 0.0;
            }
            _136231 = _136230;
        }
        float _36991 = abs(_36479.y);
        float _136247;
        if (_36991 < 1.0)
        {
            _136247 = ((((_33395 * _36991) + _33402) * _36991) * _36991) + _33405;
        }
        else
        {
            float _136240;
            if (_36991 < 2.0)
            {
                _136240 = (((((_33411 * _36991) + _33417) * _36991) + _33423) * _36991) + _33429;
            }
            else
            {
                _136240 = 0.0;
            }
            _136247 = _136240;
        }
        float _37035 = abs(_36473.x);
        float _136263;
        if (_37035 < 1.0)
        {
            _136263 = ((((_33395 * _37035) + _33402) * _37035) * _37035) + _33405;
        }
        else
        {
            float _136256;
            if (_37035 < 2.0)
            {
                _136256 = (((((_33411 * _37035) + _33417) * _37035) + _33423) * _37035) + _33429;
            }
            else
            {
                _136256 = 0.0;
            }
            _136263 = _136256;
        }
        float _37079 = abs(_36473.y);
        float _136279;
        if (_37079 < 1.0)
        {
            _136279 = ((((_33395 * _37079) + _33402) * _37079) * _37079) + _33405;
        }
        else
        {
            float _136272;
            if (_37079 < 2.0)
            {
                _136272 = (((((_33411 * _37079) + _33417) * _37079) + _33423) * _37079) + _33429;
            }
            else
            {
                _136272 = 0.0;
            }
            _136279 = _136272;
        }
        float _37123 = abs(_36484.x);
        float _136295;
        if (_37123 < 1.0)
        {
            _136295 = ((((_33395 * _37123) + _33402) * _37123) * _37123) + _33405;
        }
        else
        {
            float _136288;
            if (_37123 < 2.0)
            {
                _136288 = (((((_33411 * _37123) + _33417) * _37123) + _33423) * _37123) + _33429;
            }
            else
            {
                _136288 = 0.0;
            }
            _136295 = _136288;
        }
        float _37167 = abs(_36484.y);
        float _136311;
        if (_37167 < 1.0)
        {
            _136311 = ((((_33395 * _37167) + _33402) * _37167) * _37167) + _33405;
        }
        else
        {
            float _136304;
            if (_37167 < 2.0)
            {
                _136304 = (((((_33411 * _37167) + _33417) * _37167) + _33423) * _37167) + _33429;
            }
            else
            {
                _136304 = 0.0;
            }
            _136311 = _136304;
        }
        vec3 _36614 = vec3(0.0277777798473834991455078125 * (_136231 * _136247), 0.0277777798473834991455078125 * (_136263 * _136279), 0.0277777798473834991455078125 * (_136295 * _136311));
        vec2 _37921 = _33175 * _33148;
        vec2 _37927 = _37921 - _33582;
        vec2 _37932 = _37921 + _33582;
        float _38395 = abs(_37927.x);
        float _136573;
        if (_38395 < 1.0)
        {
            _136573 = ((((_33395 * _38395) + _33402) * _38395) * _38395) + _33405;
        }
        else
        {
            float _136572;
            if (_38395 < 2.0)
            {
                _136572 = (((((_33411 * _38395) + _33417) * _38395) + _33423) * _38395) + _33429;
            }
            else
            {
                _136572 = 0.0;
            }
            _136573 = _136572;
        }
        float _38439 = abs(_37927.y);
        float _136589;
        if (_38439 < 1.0)
        {
            _136589 = ((((_33395 * _38439) + _33402) * _38439) * _38439) + _33405;
        }
        else
        {
            float _136582;
            if (_38439 < 2.0)
            {
                _136582 = (((((_33411 * _38439) + _33417) * _38439) + _33423) * _38439) + _33429;
            }
            else
            {
                _136582 = 0.0;
            }
            _136589 = _136582;
        }
        float _38483 = abs(_37921.x);
        float _136605;
        if (_38483 < 1.0)
        {
            _136605 = ((((_33395 * _38483) + _33402) * _38483) * _38483) + _33405;
        }
        else
        {
            float _136598;
            if (_38483 < 2.0)
            {
                _136598 = (((((_33411 * _38483) + _33417) * _38483) + _33423) * _38483) + _33429;
            }
            else
            {
                _136598 = 0.0;
            }
            _136605 = _136598;
        }
        float _38527 = abs(_37921.y);
        float _136621;
        if (_38527 < 1.0)
        {
            _136621 = ((((_33395 * _38527) + _33402) * _38527) * _38527) + _33405;
        }
        else
        {
            float _136614;
            if (_38527 < 2.0)
            {
                _136614 = (((((_33411 * _38527) + _33417) * _38527) + _33423) * _38527) + _33429;
            }
            else
            {
                _136614 = 0.0;
            }
            _136621 = _136614;
        }
        float _38571 = abs(_37932.x);
        float _136637;
        if (_38571 < 1.0)
        {
            _136637 = ((((_33395 * _38571) + _33402) * _38571) * _38571) + _33405;
        }
        else
        {
            float _136630;
            if (_38571 < 2.0)
            {
                _136630 = (((((_33411 * _38571) + _33417) * _38571) + _33423) * _38571) + _33429;
            }
            else
            {
                _136630 = 0.0;
            }
            _136637 = _136630;
        }
        float _38615 = abs(_37932.y);
        float _136653;
        if (_38615 < 1.0)
        {
            _136653 = ((((_33395 * _38615) + _33402) * _38615) * _38615) + _33405;
        }
        else
        {
            float _136646;
            if (_38615 < 2.0)
            {
                _136646 = (((((_33411 * _38615) + _33417) * _38615) + _33423) * _38615) + _33429;
            }
            else
            {
                _136646 = 0.0;
            }
            _136653 = _136646;
        }
        vec3 _38062 = vec3(0.0277777798473834991455078125 * (_136573 * _136589), 0.0277777798473834991455078125 * (_136605 * _136621), 0.0277777798473834991455078125 * (_136637 * _136653));
        vec2 _39369 = _33179 * _33148;
        vec2 _39375 = _39369 - _33582;
        vec2 _39380 = _39369 + _33582;
        float _39843 = abs(_39375.x);
        float _136934;
        if (_39843 < 1.0)
        {
            _136934 = ((((_33395 * _39843) + _33402) * _39843) * _39843) + _33405;
        }
        else
        {
            float _136933;
            if (_39843 < 2.0)
            {
                _136933 = (((((_33411 * _39843) + _33417) * _39843) + _33423) * _39843) + _33429;
            }
            else
            {
                _136933 = 0.0;
            }
            _136934 = _136933;
        }
        float _39887 = abs(_39375.y);
        float _136950;
        if (_39887 < 1.0)
        {
            _136950 = ((((_33395 * _39887) + _33402) * _39887) * _39887) + _33405;
        }
        else
        {
            float _136943;
            if (_39887 < 2.0)
            {
                _136943 = (((((_33411 * _39887) + _33417) * _39887) + _33423) * _39887) + _33429;
            }
            else
            {
                _136943 = 0.0;
            }
            _136950 = _136943;
        }
        float _39931 = abs(_39369.x);
        float _136966;
        if (_39931 < 1.0)
        {
            _136966 = ((((_33395 * _39931) + _33402) * _39931) * _39931) + _33405;
        }
        else
        {
            float _136959;
            if (_39931 < 2.0)
            {
                _136959 = (((((_33411 * _39931) + _33417) * _39931) + _33423) * _39931) + _33429;
            }
            else
            {
                _136959 = 0.0;
            }
            _136966 = _136959;
        }
        float _39975 = abs(_39369.y);
        float _136982;
        if (_39975 < 1.0)
        {
            _136982 = ((((_33395 * _39975) + _33402) * _39975) * _39975) + _33405;
        }
        else
        {
            float _136975;
            if (_39975 < 2.0)
            {
                _136975 = (((((_33411 * _39975) + _33417) * _39975) + _33423) * _39975) + _33429;
            }
            else
            {
                _136975 = 0.0;
            }
            _136982 = _136975;
        }
        float _40019 = abs(_39380.x);
        float _136998;
        if (_40019 < 1.0)
        {
            _136998 = ((((_33395 * _40019) + _33402) * _40019) * _40019) + _33405;
        }
        else
        {
            float _136991;
            if (_40019 < 2.0)
            {
                _136991 = (((((_33411 * _40019) + _33417) * _40019) + _33423) * _40019) + _33429;
            }
            else
            {
                _136991 = 0.0;
            }
            _136998 = _136991;
        }
        float _40063 = abs(_39380.y);
        float _137014;
        if (_40063 < 1.0)
        {
            _137014 = ((((_33395 * _40063) + _33402) * _40063) * _40063) + _33405;
        }
        else
        {
            float _137007;
            if (_40063 < 2.0)
            {
                _137007 = (((((_33411 * _40063) + _33417) * _40063) + _33423) * _40063) + _33429;
            }
            else
            {
                _137007 = 0.0;
            }
            _137014 = _137007;
        }
        vec3 _39510 = vec3(0.0277777798473834991455078125 * (_136934 * _136950), 0.0277777798473834991455078125 * (_136966 * _136982), 0.0277777798473834991455078125 * (_136998 * _137014));
        vec2 _40817 = _33183 * _33148;
        vec2 _40823 = _40817 - _33582;
        vec2 _40828 = _40817 + _33582;
        float _41291 = abs(_40823.x);
        float _137314;
        if (_41291 < 1.0)
        {
            _137314 = ((((_33395 * _41291) + _33402) * _41291) * _41291) + _33405;
        }
        else
        {
            float _137313;
            if (_41291 < 2.0)
            {
                _137313 = (((((_33411 * _41291) + _33417) * _41291) + _33423) * _41291) + _33429;
            }
            else
            {
                _137313 = 0.0;
            }
            _137314 = _137313;
        }
        float _41335 = abs(_40823.y);
        float _137330;
        if (_41335 < 1.0)
        {
            _137330 = ((((_33395 * _41335) + _33402) * _41335) * _41335) + _33405;
        }
        else
        {
            float _137323;
            if (_41335 < 2.0)
            {
                _137323 = (((((_33411 * _41335) + _33417) * _41335) + _33423) * _41335) + _33429;
            }
            else
            {
                _137323 = 0.0;
            }
            _137330 = _137323;
        }
        float _41379 = abs(_40817.x);
        float _137346;
        if (_41379 < 1.0)
        {
            _137346 = ((((_33395 * _41379) + _33402) * _41379) * _41379) + _33405;
        }
        else
        {
            float _137339;
            if (_41379 < 2.0)
            {
                _137339 = (((((_33411 * _41379) + _33417) * _41379) + _33423) * _41379) + _33429;
            }
            else
            {
                _137339 = 0.0;
            }
            _137346 = _137339;
        }
        float _41423 = abs(_40817.y);
        float _137362;
        if (_41423 < 1.0)
        {
            _137362 = ((((_33395 * _41423) + _33402) * _41423) * _41423) + _33405;
        }
        else
        {
            float _137355;
            if (_41423 < 2.0)
            {
                _137355 = (((((_33411 * _41423) + _33417) * _41423) + _33423) * _41423) + _33429;
            }
            else
            {
                _137355 = 0.0;
            }
            _137362 = _137355;
        }
        float _41467 = abs(_40828.x);
        float _137378;
        if (_41467 < 1.0)
        {
            _137378 = ((((_33395 * _41467) + _33402) * _41467) * _41467) + _33405;
        }
        else
        {
            float _137371;
            if (_41467 < 2.0)
            {
                _137371 = (((((_33411 * _41467) + _33417) * _41467) + _33423) * _41467) + _33429;
            }
            else
            {
                _137371 = 0.0;
            }
            _137378 = _137371;
        }
        float _41511 = abs(_40828.y);
        float _137394;
        if (_41511 < 1.0)
        {
            _137394 = ((((_33395 * _41511) + _33402) * _41511) * _41511) + _33405;
        }
        else
        {
            float _137387;
            if (_41511 < 2.0)
            {
                _137387 = (((((_33411 * _41511) + _33417) * _41511) + _33423) * _41511) + _33429;
            }
            else
            {
                _137387 = 0.0;
            }
            _137394 = _137387;
        }
        vec3 _40958 = vec3(0.0277777798473834991455078125 * (_137314 * _137330), 0.0277777798473834991455078125 * (_137346 * _137362), 0.0277777798473834991455078125 * (_137378 * _137394));
        vec3 _33224 = ((((_33718 + _35166) + _36614) + _38062) + _39510) + _40958;
        mat2 _33233 = mat2(vec2(_6142.xy), vec2(_6142.zw)) * 1.0;
        vec2 _33243 = _33163 * _33233;
        vec2 _33248 = _33167 * _33233;
        vec2 _33253 = _33171 * _33233;
        vec2 _33258 = _33175 * _33233;
        vec2 _33263 = _33179 * _33233;
        vec2 _33268 = _33183 * _33233;
        vec3 _33372 = ((((((((((_33718 * texture2D(Texture, _5427 + _33243).xyz) + (_35166 * texture2D(Texture, _5427 + _33248).xyz)) + (_36614 * texture2D(Texture, _5427 + _33253).xyz)) + (_38062 * texture2D(Texture, _5427 + _33258).xyz)) + (_39510 * texture2D(Texture, _5427 + _33263).xyz)) + (_40958 * texture2D(Texture, _5427 + _33268).xyz)) + (_40958.zyx * texture2D(Texture, _5427 - _33268).xyz)) + (_39510.zyx * texture2D(Texture, _5427 - _33263).xyz)) + (_38062.zyx * texture2D(Texture, _5427 - _33258).xyz)) + (_36614.zyx * texture2D(Texture, _5427 - _33253).xyz)) + (_35166.zyx * texture2D(Texture, _5427 - _33248).xyz);
        _150618 = (vec3(1.0) / (_33224 + _33224.zyx)) * (_33372 + (_33718.zyx * texture2D(Texture, _5427 - _33243).xyz));
    }
    else
    {
        _150618 = texture2D(Texture, _5427).xyz;
    }
    gl_FragData[0] = vec4(pow(vec4(_150618 * min(pow(max(1.0 - (((border_size) == 0.0) ? 0.0 : (length(max(vec2((border_size)) - (min(_5419, vec2(0.5) - _5418) * RA_VARYING_4.xy), vec2(0.0))) / (border_size))), 0.0), (border_darkness)) * max(1.0, (border_compress)), 1.0), 1.0).xyz, vec3(1.0 / (lcd_gamma))), 1.0);
}


#endif
