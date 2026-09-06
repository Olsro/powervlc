// Generated from crt/shaders/crt-royale/src/crt-royale-geometry-aa-last-pass-intel.slang. See slang/upstream for licence/source.
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
uniform float geom_overscan_x;
uniform float geom_overscan_y;
uniform float geom_radius;
uniform float geom_tilt_angle_x;
uniform float geom_tilt_angle_y;
uniform float geom_view_dist;
struct UBO
{
    mat4 MVP;
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
    vec2 _1050 = normalize(vec2(min((vec4(OutputSize, 1.0 / OutputSize)).x / (vec4(OutputSize, 1.0 / OutputSize)).y, 1.33333337306976318359375), 1.0));
    float _946 = _1050.x;
    RA_VARYING_4 = vec4(_946, _1050.y, (geom_overscan_x), (geom_overscan_y));
    vec2 _1065 = vec2((geom_tilt_angle_x), (geom_tilt_angle_y));
    vec2 _955 = sin(_1065);
    vec2 _958 = cos(_1065);
    float _961 = _958.y;
    float _963 = _955.y;
    float _975 = _958.x;
    float _977 = _955.x;
    mat3 _990 = mat3(vec3(1.0, 0.0, 0.0), vec3(0.0, _961, -_963), vec3(0.0, _963, _961)) * mat3(vec3(_975, 0.0, _977), vec3(0.0, 1.0, 0.0), vec3(-_977, 0.0, _975));
    mat3 _993 = transpose(_990);
    RA_VARYING_5 = _993[0];
    RA_VARYING_6 = _993[1];
    RA_VARYING_7 = _993[2];
    vec3 _1116 = vec3(0.0, _1050.y, -(geom_view_dist));
    vec3 _1139 = vec3(0.0, 0.0, (geom_radius) / sin(abs(acos(dot(_1116, _1116 * vec3(1.0, -1.0, 1.0)) / dot(_1116, _1116))) * 0.5));
    vec3 _1152 = vec3(0.0, -0.0, (geom_radius)) * _990;
    vec2 _1421 = vec2(0.0, -0.5) * _1050;
    vec2 _1423 = normalize(_1421);
    float _1432 = (_1421.y / _1423.y) / (geom_radius);
    vec2 _1440 = _1423 * (sin(_1432) * (geom_radius));
    vec2 _1569 = vec2(0.0, 0.5) * _1050;
    vec2 _1571 = normalize(_1569);
    float _1580 = (_1569.y / _1571.y) / (geom_radius);
    vec2 _1588 = _1571 * (sin(_1580) * (geom_radius));
    vec2 _1717 = vec2(-0.5, 0.0) * _1050;
    vec2 _1719 = normalize(_1717);
    float _1728 = (_1717.y / _1719.y) / (geom_radius);
    vec2 _1736 = _1719 * (sin(_1728) * (geom_radius));
    vec2 _1865 = vec2(0.5, 0.0) * _1050;
    vec2 _1867 = normalize(_1865);
    float _1876 = (_1865.y / _1867.y) / (geom_radius);
    vec2 _1884 = _1867 * (sin(_1876) * (geom_radius));
    vec2 _2013 = vec2(-0.5) * _1050;
    vec2 _2015 = normalize(_2013);
    float _2024 = (_2013.y / _2015.y) / (geom_radius);
    vec2 _2032 = _2015 * (sin(_2024) * (geom_radius));
    vec2 _2161 = vec2(0.5, -0.5) * _1050;
    vec2 _2163 = normalize(_2161);
    float _2172 = (_2161.y / _2163.y) / (geom_radius);
    vec2 _2180 = _2163 * (sin(_2172) * (geom_radius));
    vec2 _2309 = vec2(-0.5, 0.5) * _1050;
    vec2 _2311 = normalize(_2309);
    float _2320 = (_2309.y / _2311.y) / (geom_radius);
    vec2 _2328 = _2311 * (sin(_2320) * (geom_radius));
    vec2 _2457 = vec2(0.5) * _1050;
    vec2 _2459 = normalize(_2457);
    float _2468 = (_2457.y / _2459.y) / (geom_radius);
    vec2 _2476 = _2459 * (sin(_2468) * (geom_radius));
    float _2901;
    _2901 = 0.0;
    for (int _2881 = 0; _2881 < 9; )
    {
        _2901 += float(_1152.z < 0.0);
        _2881++;
        continue;
    }
    vec3 _3016;
    if (_2901 > 0.5)
    {
        _3016 = _1139;
    }
    else
    {
        vec3 _1107[9] = vec3[](_1152, vec3(_1440.x, -_1440.y, cos(_1432) * (geom_radius)) * _990, vec3(_1588.x, -_1588.y, cos(_1580) * (geom_radius)) * _990, vec3(_1736.x, -_1736.y, cos(_1728) * (geom_radius)) * _990, vec3(_1884.x, -_1884.y, cos(_1876) * (geom_radius)) * _990, vec3(_2032.x, -_2032.y, cos(_2024) * (geom_radius)) * _990, vec3(_2180.x, -_2180.y, cos(_2172) * (geom_radius)) * _990, vec3(_2328.x, -_2328.y, cos(_2320) * (geom_radius)) * _990, vec3(_2476.x, -_2476.y, cos(_2468) * (geom_radius)) * _990);
        vec3 _3121;
        _3121 = _1139;
        vec3 _3133;
        vec3 _2565[9];
        for (int _2985 = 0; _2985 < 1; _3121 = _3133, _2985++)
        {
            for (int _2987 = 0; _2987 < 9; )
            {
                _2565[_2987] = _1107[_2987] - _3121;
                _2987++;
                continue;
            }
            float _2611 = abs((geom_radius));
            vec2 _2992;
            vec2 _2993;
            _2993 = vec2(10.0 * _2611);
            _2992 = vec2((-10.0) * _2611);
            for (int _2990 = 0; _2990 < 9; )
            {
                vec2 _2637 = _1050 * (-_2565[_2990].z);
                vec2 _2642 = vec2(1.0, -1.0) * (geom_view_dist);
                _2993 = min(_2993, _2565[_2990].xy - ((vec2(-0.5) * _2637) / _2642));
                _2992 = max(_2992, _2565[_2990].xy - ((vec2(0.5) * _2637) / _2642));
                _2990++;
                continue;
            }
            vec2 _2676 = _3121.xy + ((_2992 + _2993) * 0.5);
            float _2678 = _2676.x;
            vec3 _3101 = _3121;
            _3101.x = _2678;
            _3101.y = _2676.y;
            for (int _2994 = 0; _2994 < 9; )
            {
                _2565[_2994] = _1107[_2994] - _3101;
                _2994++;
                continue;
            }
            float _2998;
            _2998 = ((-10.0) * (geom_radius)) * (geom_view_dist);
            float _2781;
            for (int _2996 = 0; _2996 < 9; _2998 = _2781, _2996++)
            {
                vec3 _2713 = _2565[_2996] * vec3(1.0, -1.0, 1.0);
                vec4 _2729 = _2713.zzzz + ((_2713.xyxy * (geom_view_dist)) / (vec4(-0.5, -0.5, 0.5, 0.5) * vec4(_946, _1050.y, _946, _1050.y)));
                float _2731 = _2713.x;
                float _3008;
                if (_2731 < 0.0)
                {
                    _3008 = max(_2998, _2729.x);
                }
                else
                {
                    _3008 = _2998;
                }
                float _2743 = _2713.y;
                float _3009;
                if (_2743 < 0.0)
                {
                    _3009 = max(_3008, _2729.y);
                }
                else
                {
                    _3009 = _3008;
                }
                float _3010;
                if (_2731 > 0.0)
                {
                    _3010 = max(_3009, _2729.z);
                }
                else
                {
                    _3010 = _3009;
                }
                float _3011;
                if (_2743 > 0.0)
                {
                    _3011 = max(_3010, _2729.w);
                }
                else
                {
                    _3011 = _3010;
                }
                _2781 = max(_3011, _2713.z);
            }
            _3133 = vec3(_2678, _2676.y, _3121.z + _2998);
        }
        _3016 = _3121;
    }
    RA_VARYING_3 = _3016 * _993;
}


#endif
#ifdef FRAGMENT

uniform vec2 TextureSize;
uniform float aa_cubic_c;
uniform float border_compress;
uniform float border_darkness;
uniform float border_size;
uniform float lcd_gamma;
struct UBO
{
    float lcd_gamma;
    float aa_cubic_c;
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
varying vec2 RA_VARYING_0;
varying vec2 RA_VARYING_2;

void main()
{
    vec2 _5419 = ((RA_VARYING_0 * ((vec4(TextureSize, 1.0 / TextureSize)).xy * RA_VARYING_1.xy)) - vec2(0.5)) / RA_VARYING_4.zw;
    vec2 _5420 = _5419 + vec2(0.5);
    vec2 _5427 = (vec4(TextureSize, 1.0 / TextureSize)).xy * RA_VARYING_1.zw;
    vec2 _5428 = _5420 * _5427;
    vec4 _6143 = vec4(RA_VARYING_2.x, 0.0, 0.0, RA_VARYING_2.y) * (_5427 / RA_VARYING_4.zw).xxyy;
    vec3 _150622;
    if (any(bvec2(RA_VARYING_4.z != 1.0, RA_VARYING_4.w != 1.0)))
    {
        float _33388 = 2.0 * (aa_cubic_c);
        float _33389 = 1.0 - _33388;
        float _33395 = 6.0 * (aa_cubic_c);
        float _33396 = (12.0 - (9.0 * _33389)) - _33395;
        float _33403 = ((-18.0) + (12.0 * _33389)) + _33395;
        float _33406 = 6.0 - (2.0 * _33389);
        float _33412 = (_33388 - 1.0) - _33395;
        float _33418 = (6.0 * _33389) + (30.0 * (aa_cubic_c));
        float _33424 = ((-12.0) * _33389) - (48.0 * (aa_cubic_c));
        float _33430 = (8.0 * _33389) + (24.0 * (aa_cubic_c));
        vec2 _33503 = (vec2(2.0) + abs(vec2(-0.3333333432674407958984375, 0.0))) * vec2(1.0, 0.0);
        vec2 _33504 = max(vec2(0.5), _33503);
        vec4 _33518 = vec4(_33504 * 2.0, _33503 / _33504);
        vec2 _33147 = _33518.xy;
        vec2 _33149 = _33518.zw;
        vec2 _33160 = _33147 * vec2(-0.4583333432674407958984375);
        vec2 _33164 = _33160 + (_33147 * vec2(0.25, 0.0));
        vec2 _33168 = _33160 + (_33147 * vec2(0.75, 0.083333335816860198974609375));
        vec2 _33172 = _33160 + (_33147 * vec2(0.5, 0.16666667163372039794921875));
        vec2 _33176 = _33160 + (_33147 * vec2(0.083333335816860198974609375, 0.25));
        vec2 _33180 = _33160 + (_33147 * vec2(0.916666686534881591796875, 0.3333333432674407958984375));
        vec2 _33184 = _33160 + (_33147 * vec2(0.3333333432674407958984375, 0.416666686534881591796875));
        vec2 _33578 = _33164 * _33149;
        vec2 _33583 = vec2(-0.3333333432674407958984375, 0.0) * _33149;
        vec2 _33584 = _33578 - _33583;
        vec2 _33589 = _33578 + _33583;
        float _34052 = abs(_33584.x);
        float _135622;
        if (_34052 < 1.0)
        {
            _135622 = ((((_33396 * _34052) + _33403) * _34052) * _34052) + _33406;
        }
        else
        {
            float _135621;
            if (_34052 < 2.0)
            {
                _135621 = (((((_33412 * _34052) + _33418) * _34052) + _33424) * _34052) + _33430;
            }
            else
            {
                _135621 = 0.0;
            }
            _135622 = _135621;
        }
        float _34096 = abs(_33584.y);
        float _135638;
        if (_34096 < 1.0)
        {
            _135638 = ((((_33396 * _34096) + _33403) * _34096) * _34096) + _33406;
        }
        else
        {
            float _135631;
            if (_34096 < 2.0)
            {
                _135631 = (((((_33412 * _34096) + _33418) * _34096) + _33424) * _34096) + _33430;
            }
            else
            {
                _135631 = 0.0;
            }
            _135638 = _135631;
        }
        float _34140 = abs(_33578.x);
        float _135654;
        if (_34140 < 1.0)
        {
            _135654 = ((((_33396 * _34140) + _33403) * _34140) * _34140) + _33406;
        }
        else
        {
            float _135647;
            if (_34140 < 2.0)
            {
                _135647 = (((((_33412 * _34140) + _33418) * _34140) + _33424) * _34140) + _33430;
            }
            else
            {
                _135647 = 0.0;
            }
            _135654 = _135647;
        }
        float _34184 = abs(_33578.y);
        float _135670;
        if (_34184 < 1.0)
        {
            _135670 = ((((_33396 * _34184) + _33403) * _34184) * _34184) + _33406;
        }
        else
        {
            float _135663;
            if (_34184 < 2.0)
            {
                _135663 = (((((_33412 * _34184) + _33418) * _34184) + _33424) * _34184) + _33430;
            }
            else
            {
                _135663 = 0.0;
            }
            _135670 = _135663;
        }
        float _34228 = abs(_33589.x);
        float _135686;
        if (_34228 < 1.0)
        {
            _135686 = ((((_33396 * _34228) + _33403) * _34228) * _34228) + _33406;
        }
        else
        {
            float _135679;
            if (_34228 < 2.0)
            {
                _135679 = (((((_33412 * _34228) + _33418) * _34228) + _33424) * _34228) + _33430;
            }
            else
            {
                _135679 = 0.0;
            }
            _135686 = _135679;
        }
        float _34272 = abs(_33589.y);
        float _135702;
        if (_34272 < 1.0)
        {
            _135702 = ((((_33396 * _34272) + _33403) * _34272) * _34272) + _33406;
        }
        else
        {
            float _135695;
            if (_34272 < 2.0)
            {
                _135695 = (((((_33412 * _34272) + _33418) * _34272) + _33424) * _34272) + _33430;
            }
            else
            {
                _135695 = 0.0;
            }
            _135702 = _135695;
        }
        vec3 _33719 = vec3(0.0277777798473834991455078125 * (_135622 * _135638), 0.0277777798473834991455078125 * (_135654 * _135670), 0.0277777798473834991455078125 * (_135686 * _135702));
        vec2 _35026 = _33168 * _33149;
        vec2 _35032 = _35026 - _33583;
        vec2 _35037 = _35026 + _33583;
        float _35500 = abs(_35032.x);
        float _135912;
        if (_35500 < 1.0)
        {
            _135912 = ((((_33396 * _35500) + _33403) * _35500) * _35500) + _33406;
        }
        else
        {
            float _135911;
            if (_35500 < 2.0)
            {
                _135911 = (((((_33412 * _35500) + _33418) * _35500) + _33424) * _35500) + _33430;
            }
            else
            {
                _135911 = 0.0;
            }
            _135912 = _135911;
        }
        float _35544 = abs(_35032.y);
        float _135928;
        if (_35544 < 1.0)
        {
            _135928 = ((((_33396 * _35544) + _33403) * _35544) * _35544) + _33406;
        }
        else
        {
            float _135921;
            if (_35544 < 2.0)
            {
                _135921 = (((((_33412 * _35544) + _33418) * _35544) + _33424) * _35544) + _33430;
            }
            else
            {
                _135921 = 0.0;
            }
            _135928 = _135921;
        }
        float _35588 = abs(_35026.x);
        float _135944;
        if (_35588 < 1.0)
        {
            _135944 = ((((_33396 * _35588) + _33403) * _35588) * _35588) + _33406;
        }
        else
        {
            float _135937;
            if (_35588 < 2.0)
            {
                _135937 = (((((_33412 * _35588) + _33418) * _35588) + _33424) * _35588) + _33430;
            }
            else
            {
                _135937 = 0.0;
            }
            _135944 = _135937;
        }
        float _35632 = abs(_35026.y);
        float _135960;
        if (_35632 < 1.0)
        {
            _135960 = ((((_33396 * _35632) + _33403) * _35632) * _35632) + _33406;
        }
        else
        {
            float _135953;
            if (_35632 < 2.0)
            {
                _135953 = (((((_33412 * _35632) + _33418) * _35632) + _33424) * _35632) + _33430;
            }
            else
            {
                _135953 = 0.0;
            }
            _135960 = _135953;
        }
        float _35676 = abs(_35037.x);
        float _135976;
        if (_35676 < 1.0)
        {
            _135976 = ((((_33396 * _35676) + _33403) * _35676) * _35676) + _33406;
        }
        else
        {
            float _135969;
            if (_35676 < 2.0)
            {
                _135969 = (((((_33412 * _35676) + _33418) * _35676) + _33424) * _35676) + _33430;
            }
            else
            {
                _135969 = 0.0;
            }
            _135976 = _135969;
        }
        float _35720 = abs(_35037.y);
        float _135992;
        if (_35720 < 1.0)
        {
            _135992 = ((((_33396 * _35720) + _33403) * _35720) * _35720) + _33406;
        }
        else
        {
            float _135985;
            if (_35720 < 2.0)
            {
                _135985 = (((((_33412 * _35720) + _33418) * _35720) + _33424) * _35720) + _33430;
            }
            else
            {
                _135985 = 0.0;
            }
            _135992 = _135985;
        }
        vec3 _35167 = vec3(0.0277777798473834991455078125 * (_135912 * _135928), 0.0277777798473834991455078125 * (_135944 * _135960), 0.0277777798473834991455078125 * (_135976 * _135992));
        vec2 _36474 = _33172 * _33149;
        vec2 _36480 = _36474 - _33583;
        vec2 _36485 = _36474 + _33583;
        float _36948 = abs(_36480.x);
        float _136235;
        if (_36948 < 1.0)
        {
            _136235 = ((((_33396 * _36948) + _33403) * _36948) * _36948) + _33406;
        }
        else
        {
            float _136234;
            if (_36948 < 2.0)
            {
                _136234 = (((((_33412 * _36948) + _33418) * _36948) + _33424) * _36948) + _33430;
            }
            else
            {
                _136234 = 0.0;
            }
            _136235 = _136234;
        }
        float _36992 = abs(_36480.y);
        float _136251;
        if (_36992 < 1.0)
        {
            _136251 = ((((_33396 * _36992) + _33403) * _36992) * _36992) + _33406;
        }
        else
        {
            float _136244;
            if (_36992 < 2.0)
            {
                _136244 = (((((_33412 * _36992) + _33418) * _36992) + _33424) * _36992) + _33430;
            }
            else
            {
                _136244 = 0.0;
            }
            _136251 = _136244;
        }
        float _37036 = abs(_36474.x);
        float _136267;
        if (_37036 < 1.0)
        {
            _136267 = ((((_33396 * _37036) + _33403) * _37036) * _37036) + _33406;
        }
        else
        {
            float _136260;
            if (_37036 < 2.0)
            {
                _136260 = (((((_33412 * _37036) + _33418) * _37036) + _33424) * _37036) + _33430;
            }
            else
            {
                _136260 = 0.0;
            }
            _136267 = _136260;
        }
        float _37080 = abs(_36474.y);
        float _136283;
        if (_37080 < 1.0)
        {
            _136283 = ((((_33396 * _37080) + _33403) * _37080) * _37080) + _33406;
        }
        else
        {
            float _136276;
            if (_37080 < 2.0)
            {
                _136276 = (((((_33412 * _37080) + _33418) * _37080) + _33424) * _37080) + _33430;
            }
            else
            {
                _136276 = 0.0;
            }
            _136283 = _136276;
        }
        float _37124 = abs(_36485.x);
        float _136299;
        if (_37124 < 1.0)
        {
            _136299 = ((((_33396 * _37124) + _33403) * _37124) * _37124) + _33406;
        }
        else
        {
            float _136292;
            if (_37124 < 2.0)
            {
                _136292 = (((((_33412 * _37124) + _33418) * _37124) + _33424) * _37124) + _33430;
            }
            else
            {
                _136292 = 0.0;
            }
            _136299 = _136292;
        }
        float _37168 = abs(_36485.y);
        float _136315;
        if (_37168 < 1.0)
        {
            _136315 = ((((_33396 * _37168) + _33403) * _37168) * _37168) + _33406;
        }
        else
        {
            float _136308;
            if (_37168 < 2.0)
            {
                _136308 = (((((_33412 * _37168) + _33418) * _37168) + _33424) * _37168) + _33430;
            }
            else
            {
                _136308 = 0.0;
            }
            _136315 = _136308;
        }
        vec3 _36615 = vec3(0.0277777798473834991455078125 * (_136235 * _136251), 0.0277777798473834991455078125 * (_136267 * _136283), 0.0277777798473834991455078125 * (_136299 * _136315));
        vec2 _37922 = _33176 * _33149;
        vec2 _37928 = _37922 - _33583;
        vec2 _37933 = _37922 + _33583;
        float _38396 = abs(_37928.x);
        float _136577;
        if (_38396 < 1.0)
        {
            _136577 = ((((_33396 * _38396) + _33403) * _38396) * _38396) + _33406;
        }
        else
        {
            float _136576;
            if (_38396 < 2.0)
            {
                _136576 = (((((_33412 * _38396) + _33418) * _38396) + _33424) * _38396) + _33430;
            }
            else
            {
                _136576 = 0.0;
            }
            _136577 = _136576;
        }
        float _38440 = abs(_37928.y);
        float _136593;
        if (_38440 < 1.0)
        {
            _136593 = ((((_33396 * _38440) + _33403) * _38440) * _38440) + _33406;
        }
        else
        {
            float _136586;
            if (_38440 < 2.0)
            {
                _136586 = (((((_33412 * _38440) + _33418) * _38440) + _33424) * _38440) + _33430;
            }
            else
            {
                _136586 = 0.0;
            }
            _136593 = _136586;
        }
        float _38484 = abs(_37922.x);
        float _136609;
        if (_38484 < 1.0)
        {
            _136609 = ((((_33396 * _38484) + _33403) * _38484) * _38484) + _33406;
        }
        else
        {
            float _136602;
            if (_38484 < 2.0)
            {
                _136602 = (((((_33412 * _38484) + _33418) * _38484) + _33424) * _38484) + _33430;
            }
            else
            {
                _136602 = 0.0;
            }
            _136609 = _136602;
        }
        float _38528 = abs(_37922.y);
        float _136625;
        if (_38528 < 1.0)
        {
            _136625 = ((((_33396 * _38528) + _33403) * _38528) * _38528) + _33406;
        }
        else
        {
            float _136618;
            if (_38528 < 2.0)
            {
                _136618 = (((((_33412 * _38528) + _33418) * _38528) + _33424) * _38528) + _33430;
            }
            else
            {
                _136618 = 0.0;
            }
            _136625 = _136618;
        }
        float _38572 = abs(_37933.x);
        float _136641;
        if (_38572 < 1.0)
        {
            _136641 = ((((_33396 * _38572) + _33403) * _38572) * _38572) + _33406;
        }
        else
        {
            float _136634;
            if (_38572 < 2.0)
            {
                _136634 = (((((_33412 * _38572) + _33418) * _38572) + _33424) * _38572) + _33430;
            }
            else
            {
                _136634 = 0.0;
            }
            _136641 = _136634;
        }
        float _38616 = abs(_37933.y);
        float _136657;
        if (_38616 < 1.0)
        {
            _136657 = ((((_33396 * _38616) + _33403) * _38616) * _38616) + _33406;
        }
        else
        {
            float _136650;
            if (_38616 < 2.0)
            {
                _136650 = (((((_33412 * _38616) + _33418) * _38616) + _33424) * _38616) + _33430;
            }
            else
            {
                _136650 = 0.0;
            }
            _136657 = _136650;
        }
        vec3 _38063 = vec3(0.0277777798473834991455078125 * (_136577 * _136593), 0.0277777798473834991455078125 * (_136609 * _136625), 0.0277777798473834991455078125 * (_136641 * _136657));
        vec2 _39370 = _33180 * _33149;
        vec2 _39376 = _39370 - _33583;
        vec2 _39381 = _39370 + _33583;
        float _39844 = abs(_39376.x);
        float _136938;
        if (_39844 < 1.0)
        {
            _136938 = ((((_33396 * _39844) + _33403) * _39844) * _39844) + _33406;
        }
        else
        {
            float _136937;
            if (_39844 < 2.0)
            {
                _136937 = (((((_33412 * _39844) + _33418) * _39844) + _33424) * _39844) + _33430;
            }
            else
            {
                _136937 = 0.0;
            }
            _136938 = _136937;
        }
        float _39888 = abs(_39376.y);
        float _136954;
        if (_39888 < 1.0)
        {
            _136954 = ((((_33396 * _39888) + _33403) * _39888) * _39888) + _33406;
        }
        else
        {
            float _136947;
            if (_39888 < 2.0)
            {
                _136947 = (((((_33412 * _39888) + _33418) * _39888) + _33424) * _39888) + _33430;
            }
            else
            {
                _136947 = 0.0;
            }
            _136954 = _136947;
        }
        float _39932 = abs(_39370.x);
        float _136970;
        if (_39932 < 1.0)
        {
            _136970 = ((((_33396 * _39932) + _33403) * _39932) * _39932) + _33406;
        }
        else
        {
            float _136963;
            if (_39932 < 2.0)
            {
                _136963 = (((((_33412 * _39932) + _33418) * _39932) + _33424) * _39932) + _33430;
            }
            else
            {
                _136963 = 0.0;
            }
            _136970 = _136963;
        }
        float _39976 = abs(_39370.y);
        float _136986;
        if (_39976 < 1.0)
        {
            _136986 = ((((_33396 * _39976) + _33403) * _39976) * _39976) + _33406;
        }
        else
        {
            float _136979;
            if (_39976 < 2.0)
            {
                _136979 = (((((_33412 * _39976) + _33418) * _39976) + _33424) * _39976) + _33430;
            }
            else
            {
                _136979 = 0.0;
            }
            _136986 = _136979;
        }
        float _40020 = abs(_39381.x);
        float _137002;
        if (_40020 < 1.0)
        {
            _137002 = ((((_33396 * _40020) + _33403) * _40020) * _40020) + _33406;
        }
        else
        {
            float _136995;
            if (_40020 < 2.0)
            {
                _136995 = (((((_33412 * _40020) + _33418) * _40020) + _33424) * _40020) + _33430;
            }
            else
            {
                _136995 = 0.0;
            }
            _137002 = _136995;
        }
        float _40064 = abs(_39381.y);
        float _137018;
        if (_40064 < 1.0)
        {
            _137018 = ((((_33396 * _40064) + _33403) * _40064) * _40064) + _33406;
        }
        else
        {
            float _137011;
            if (_40064 < 2.0)
            {
                _137011 = (((((_33412 * _40064) + _33418) * _40064) + _33424) * _40064) + _33430;
            }
            else
            {
                _137011 = 0.0;
            }
            _137018 = _137011;
        }
        vec3 _39511 = vec3(0.0277777798473834991455078125 * (_136938 * _136954), 0.0277777798473834991455078125 * (_136970 * _136986), 0.0277777798473834991455078125 * (_137002 * _137018));
        vec2 _40818 = _33184 * _33149;
        vec2 _40824 = _40818 - _33583;
        vec2 _40829 = _40818 + _33583;
        float _41292 = abs(_40824.x);
        float _137318;
        if (_41292 < 1.0)
        {
            _137318 = ((((_33396 * _41292) + _33403) * _41292) * _41292) + _33406;
        }
        else
        {
            float _137317;
            if (_41292 < 2.0)
            {
                _137317 = (((((_33412 * _41292) + _33418) * _41292) + _33424) * _41292) + _33430;
            }
            else
            {
                _137317 = 0.0;
            }
            _137318 = _137317;
        }
        float _41336 = abs(_40824.y);
        float _137334;
        if (_41336 < 1.0)
        {
            _137334 = ((((_33396 * _41336) + _33403) * _41336) * _41336) + _33406;
        }
        else
        {
            float _137327;
            if (_41336 < 2.0)
            {
                _137327 = (((((_33412 * _41336) + _33418) * _41336) + _33424) * _41336) + _33430;
            }
            else
            {
                _137327 = 0.0;
            }
            _137334 = _137327;
        }
        float _41380 = abs(_40818.x);
        float _137350;
        if (_41380 < 1.0)
        {
            _137350 = ((((_33396 * _41380) + _33403) * _41380) * _41380) + _33406;
        }
        else
        {
            float _137343;
            if (_41380 < 2.0)
            {
                _137343 = (((((_33412 * _41380) + _33418) * _41380) + _33424) * _41380) + _33430;
            }
            else
            {
                _137343 = 0.0;
            }
            _137350 = _137343;
        }
        float _41424 = abs(_40818.y);
        float _137366;
        if (_41424 < 1.0)
        {
            _137366 = ((((_33396 * _41424) + _33403) * _41424) * _41424) + _33406;
        }
        else
        {
            float _137359;
            if (_41424 < 2.0)
            {
                _137359 = (((((_33412 * _41424) + _33418) * _41424) + _33424) * _41424) + _33430;
            }
            else
            {
                _137359 = 0.0;
            }
            _137366 = _137359;
        }
        float _41468 = abs(_40829.x);
        float _137382;
        if (_41468 < 1.0)
        {
            _137382 = ((((_33396 * _41468) + _33403) * _41468) * _41468) + _33406;
        }
        else
        {
            float _137375;
            if (_41468 < 2.0)
            {
                _137375 = (((((_33412 * _41468) + _33418) * _41468) + _33424) * _41468) + _33430;
            }
            else
            {
                _137375 = 0.0;
            }
            _137382 = _137375;
        }
        float _41512 = abs(_40829.y);
        float _137398;
        if (_41512 < 1.0)
        {
            _137398 = ((((_33396 * _41512) + _33403) * _41512) * _41512) + _33406;
        }
        else
        {
            float _137391;
            if (_41512 < 2.0)
            {
                _137391 = (((((_33412 * _41512) + _33418) * _41512) + _33424) * _41512) + _33430;
            }
            else
            {
                _137391 = 0.0;
            }
            _137398 = _137391;
        }
        vec3 _40959 = vec3(0.0277777798473834991455078125 * (_137318 * _137334), 0.0277777798473834991455078125 * (_137350 * _137366), 0.0277777798473834991455078125 * (_137382 * _137398));
        vec3 _33225 = ((((_33719 + _35167) + _36615) + _38063) + _39511) + _40959;
        mat2 _33234 = mat2(vec2(_6143.xy), vec2(_6143.zw)) * 1.0;
        vec2 _33244 = _33164 * _33234;
        vec2 _33249 = _33168 * _33234;
        vec2 _33254 = _33172 * _33234;
        vec2 _33259 = _33176 * _33234;
        vec2 _33264 = _33180 * _33234;
        vec2 _33269 = _33184 * _33234;
        vec3 _33373 = ((((((((((_33719 * texture2D(Texture, _5428 + _33244).xyz) + (_35167 * texture2D(Texture, _5428 + _33249).xyz)) + (_36615 * texture2D(Texture, _5428 + _33254).xyz)) + (_38063 * texture2D(Texture, _5428 + _33259).xyz)) + (_39511 * texture2D(Texture, _5428 + _33264).xyz)) + (_40959 * texture2D(Texture, _5428 + _33269).xyz)) + (_40959.zyx * texture2D(Texture, _5428 - _33269).xyz)) + (_39511.zyx * texture2D(Texture, _5428 - _33264).xyz)) + (_38063.zyx * texture2D(Texture, _5428 - _33259).xyz)) + (_36615.zyx * texture2D(Texture, _5428 - _33254).xyz)) + (_35167.zyx * texture2D(Texture, _5428 - _33249).xyz);
        _150622 = (vec3(1.0) / (_33225 + _33225.zyx)) * (_33373 + (_33719.zyx * texture2D(Texture, _5428 - _33244).xyz));
    }
    else
    {
        _150622 = texture2D(Texture, _5428).xyz;
    }
    gl_FragData[0] = vec4(pow(vec4(_150622 * min(pow(max(1.0 - (((border_size) == 0.0) ? 0.0 : (length(max(vec2((border_size)) - (min(_5420, vec2(0.5) - _5419) * RA_VARYING_4.xy), vec2(0.0))) / (border_size))), 0.0), (border_darkness)) * max(1.0, (border_compress)), 1.0), 1.0).xyz, vec3(1.0 / (lcd_gamma))), 1.0);
}


#endif
