// Generated from crt/shaders/crt-royale/src-fast/crt-royale-scanlines-horizontal-apply-mask.slang. See slang/upstream for licence/source.
#version 120
#pragma parameter geom_curvature "Geom Curvature Toggle" 0.0 0.0 1.0 1.0
#pragma parameter geom_R "Geom Curvature Radius" 4.0 0.3 10.0 0.1
#pragma parameter geom_d "Geom Distance" 1.5 0.1 3.0 0.1
#pragma parameter geom_invert_aspect "Geom Curvature Aspect Inversion" 0.0 0.0 1.0 1.0
#pragma parameter geom_cornersize "Geom Corner Size" 0.006 0.001 1.0 0.005
#pragma parameter geom_cornersmooth "Geom Corner Smoothness" 400.0 80.0 2000.0 100.0
#pragma parameter geom_x_tilt "Geom Horizontal Tilt" 0.0 -0.5 0.5 0.01
#pragma parameter geom_y_tilt "Geom Vertical Tilt" 0.0 -0.5 0.5 0.01
#pragma parameter geom_center_x "Geom Center X" 0.0 -1.0 1.0 0.001
#pragma parameter geom_center_y "Geom Center Y" 0.0 -1.0 1.0 0.001
#pragma parameter geom_overscanx "Geom Horiz. Overscan %" 100.0 -125.0 125.0 0.5
#pragma parameter geom_overscany "Geom Vert. Overscan %" 100.0 -125.0 125.0 0.5
#pragma parameter crt_gamma "Simulated CRT Gamma" 2.4 1.0 5.0 0.025
#pragma parameter lcd_gamma "Your Display Gamma" 2.4 1.0 5.0 0.025
#pragma parameter levels_contrast "Contrast" 0.671875 0.0 4.0 0.015625
#pragma parameter bloom_underestimate_levels "Bloom - Underestimate Levels" 1.0 0.0 5.0 0.01
#pragma parameter bloom_excess "Bloom - Excess" 0.0 0.0 1.0 0.005
#pragma parameter beam_min_sigma "Beam - Min Sigma" 0.055 0.005 1.0 0.005
#pragma parameter beam_max_sigma "Beam - Max Sigma" 0.2 0.005 1.0 0.005
#pragma parameter beam_spot_power "Beam - Spot Power" 0.38 0.01 16.0 0.01
#pragma parameter beam_min_shape "Beam - Min Shape" 2.0 2.0 32.0 0.1
#pragma parameter beam_max_shape "Beam - Max Shape" 2.0 2.0 32.0 0.1
#pragma parameter beam_shape_power "Beam - Shape Power" 0.25 0.01 16.0 0.01
#pragma parameter beam_horiz_filter "Beam - Horiz Filter" 0.0 0.0 3.0 1.0
#pragma parameter beam_horiz_sigma "Beam - Horiz Sigma" 0.35 0.0 0.67 0.005
#pragma parameter beam_horiz_linear_rgb_weight "Beam - Horiz Linear RGB Weight" 1.0 0.0 1.0 0.01
#pragma parameter convergence_offset_x_r "Convergence - Offset X Red" 0.0 -4.0 4.0 0.05
#pragma parameter convergence_offset_x_g "Convergence - Offset X Green" 0.0 -4.0 4.0 0.05
#pragma parameter convergence_offset_x_b "Convergence - Offset X Blue" 0.0 -4.0 4.0 0.05
#pragma parameter convergence_offset_y_r "Convergence - Offset Y Red" 0.05 -2.0 2.0 0.05
#pragma parameter convergence_offset_y_g "Convergence - Offset Y Green" -0.05 -2.0 2.0 0.05
#pragma parameter convergence_offset_y_b "Convergence - Offset Y Blue" 0.05 -2.0 2.0 0.05
#pragma parameter mask_type "Mask - Type" 0.0 0.0 2.0 1.0
#pragma parameter mask_specify_num_triads "Mask - Specify Number of Triads" 0.0 0.0 1.0 1.0
#pragma parameter mask_triad_size_desired "Mask - Triad Size Desired" 3.0 1.0 18.0 0.125
#pragma parameter mask_num_triads_desired "Mask - Number of Triads Desired" 480.0 342.0 1920.0 1.0
#pragma parameter aa_subpixel_r_offset_x_runtime "AA - Subpixel R Offset X" -0.333333333 -0.333333333 0.333333333 0.333333333
#pragma parameter aa_subpixel_r_offset_y_runtime "AA - Subpixel R Offset Y" 0.0 -0.333333333 0.333333333 0.333333333
#pragma parameter aa_cubic_c "AA - Cubic Sharpness" 0.5 0.0 4.0 0.015625
#pragma parameter aa_gauss_sigma "AA - Gaussian Sigma" 0.5 0.0625 1.0 0.015625
#pragma parameter interlace_detect_toggle "Interlacing - Toggle" 1.0 0.0 1.0 1.0
#pragma parameter interlace_bff "Interlacing - Bottom Field First" 0.0 0.0 1.0 1.0
#pragma parameter interlace_1080i "Interlace - Detect 1080i" 0.0 0.0 1.0 1.0
#ifdef VERTEX

uniform mat4 MVPMatrix;
uniform vec2 OutputSize;
uniform vec2 Pass2TextureSize;
uniform vec2 Pass4TextureSize;
uniform float geom_R;
uniform float geom_center_x;
uniform float geom_center_y;
uniform float geom_d;
uniform float geom_invert_aspect;
uniform float geom_x_tilt;
uniform float geom_y_tilt;
uniform float mask_num_triads_desired;
uniform float mask_specify_num_triads;
uniform float mask_triad_size_desired;
struct UBO
{
    mat4 MVP;
    float mask_num_triads_desired;
    float mask_triad_size_desired;
    float mask_specify_num_triads;
};



struct Push
{
    vec4 OutputSize;
    vec4 VERTICAL_SCANLINESSize;
    vec4 MASK_RESIZESize;
    float geom_d;
    float geom_R;
    float geom_x_tilt;
    float geom_y_tilt;
    float geom_center_x;
    float geom_center_y;
    float geom_invert_aspect;
};



varying vec2 RA_VARYING_4;
varying vec2 RA_VARYING_5;
attribute vec4 VertexCoord;
varying vec2 RA_VARYING_0;
attribute vec2 TexCoord;
varying vec3 RA_VARYING_6;
varying float RA_VARYING_8;
varying float RA_VARYING_7;
varying vec2 RA_VARYING_1;
varying vec4 RA_VARYING_2;
varying vec2 RA_VARYING_3;

void main()
{
    float _180 = ceil(0.5);
    vec2 _254 = vec2(((geom_invert_aspect) > 0.5) ? 1.0 : 0.75);
    gl_Position = (MVPMatrix) * VertexCoord;
    RA_VARYING_0 = (TexCoord * vec2(1.00010001659393310546875)) - vec2((geom_center_x), (geom_center_y));
    vec2 _724 = vec2((geom_x_tilt), (geom_y_tilt));
    RA_VARYING_4 = sin(_724);
    RA_VARYING_5 = cos(_724);
    float _796 = -(geom_R);
    vec2 _812 = (RA_VARYING_4 * _796) / vec2(1.0 + ((((geom_R) / (geom_d)) * RA_VARYING_5.x) * RA_VARYING_5.y));
    float _976 = (geom_d) * (geom_d);
    float _977 = dot(_812, _812) + _976;
    float _998 = ((geom_R) * (dot(_812, RA_VARYING_4) - (((geom_d) * RA_VARYING_5.x) * RA_VARYING_5.y))) - _976;
    vec2 _906 = ((vec2(((_998 * (-2.0)) - sqrt((4.0 * (_998 * _998)) - ((4.0 * _977) * (_976 + ((((2.0 * (geom_R)) * (geom_d)) * RA_VARYING_5.x) * RA_VARYING_5.y))))) / (2.0 * _977)) * _812) - (vec2(_796) * RA_VARYING_4)) / vec2((geom_R));
    vec2 _909 = _906 / RA_VARYING_5;
    vec2 _912 = RA_VARYING_4 / RA_VARYING_5;
    float _916 = dot(_912, _912) + 1.0;
    float _919 = dot(_909, _912);
    float _939 = ((_919 * 2.0) + sqrt((4.0 * (_919 * _919)) - ((4.0 * _916) * (dot(_909, _909) - 1.0)))) / (2.0 * _916);
    float _953 = max(abs((geom_R) * acos(_939)), 9.9999997473787516355514526367188e-06);
    vec2 _963 = (((_906 - (RA_VARYING_4 * _939)) / RA_VARYING_5) * _953) / vec2(sin(_953 / (geom_R)));
    vec2 _815 = vec2(0.5) * _254;
    float _817 = _815.x;
    vec2 _821 = vec2(-_817, _963.y);
    float _1043 = max(abs(sqrt(dot(_821, _821))), 9.9999997473787516355514526367188e-06);
    float _1047 = _1043 / (geom_R);
    vec2 _1052 = _821 * (sin(_1047) / _1043);
    float _1058 = 1.0 - cos(_1047);
    float _1063 = (geom_d) / (geom_R);
    float _827 = _815.y;
    vec2 _829 = vec2(_963.x, -_827);
    float _1099 = max(abs(sqrt(dot(_829, _829))), 9.9999997473787516355514526367188e-06);
    float _1103 = _1099 / (geom_R);
    vec2 _1108 = _829 * (sin(_1103) / _1099);
    float _1114 = 1.0 - cos(_1103);
    vec2 _834 = vec2(((((_1052 * RA_VARYING_5) - (RA_VARYING_4 * _1058)) * (geom_d)) / vec2((_1063 + ((_1058 * RA_VARYING_5.x) * RA_VARYING_5.y)) + dot(_1052, RA_VARYING_4))).x, ((((_1108 * RA_VARYING_5) - (RA_VARYING_4 * _1114)) * (geom_d)) / vec2((_1063 + ((_1114 * RA_VARYING_5.x) * RA_VARYING_5.y)) + dot(_1108, RA_VARYING_4))).y) / _254;
    vec2 _839 = vec2(_817, _963.y);
    float _1155 = max(abs(sqrt(dot(_839, _839))), 9.9999997473787516355514526367188e-06);
    float _1159 = _1155 / (geom_R);
    vec2 _1164 = _839 * (sin(_1159) / _1155);
    float _1170 = 1.0 - cos(_1159);
    vec2 _846 = vec2(_963.x, _827);
    float _1211 = max(abs(sqrt(dot(_846, _846))), 9.9999997473787516355514526367188e-06);
    float _1215 = _1211 / (geom_R);
    vec2 _1220 = _846 * (sin(_1215) / _1211);
    float _1226 = 1.0 - cos(_1215);
    vec2 _851 = vec2(((((_1164 * RA_VARYING_5) - (RA_VARYING_4 * _1170)) * (geom_d)) / vec2((_1063 + ((_1170 * RA_VARYING_5.x) * RA_VARYING_5.y)) + dot(_1164, RA_VARYING_4))).x, ((((_1220 * RA_VARYING_5) - (RA_VARYING_4 * _1226)) * (geom_d)) / vec2((_1063 + ((_1226 * RA_VARYING_5.x) * RA_VARYING_5.y)) + dot(_1220, RA_VARYING_4))).y) / _254;
    RA_VARYING_6 = vec3(((_851 + _834) * _254) * 0.5, max(_851.x - _834.x, _851.y - _834.y));
    RA_VARYING_8 = _976;
    RA_VARYING_7 = (((geom_R) * (geom_d)) * RA_VARYING_5.x) * RA_VARYING_5.y;
    RA_VARYING_1 = vec2(1.0) / (vec4(Pass2TextureSize, 1.0 / Pass2TextureSize)).xy;
    vec2 _1343 = clamp(vec2(1.0) * min(8.0 * mix((mask_triad_size_desired), (vec4(OutputSize, 1.0 / OutputSize)).x / (mask_num_triads_desired), (mask_specify_num_triads)), 64.0), vec2(1.0) * ceil(16.0), (vec4(Pass4TextureSize, 1.0 / Pass4TextureSize)).xy / vec2(1.0 + (_180 * 0.125)));
    float _1345 = _1343.y;
    vec2 _1368 = floor(vec2(min(_1343.x, _1345), min(_1345, _1345)) + vec2(1.52587890625e-05));
    vec2 _1272 = _1368 / (vec4(Pass4TextureSize, 1.0 / Pass4TextureSize)).xy;
    RA_VARYING_3 = (vec4(OutputSize, 1.0 / OutputSize)).xy / _1368;
    RA_VARYING_2 = vec4((vec2(_180) / _1368) * _1272, _1272);
}


#endif
#ifdef FRAGMENT

uniform vec2 Pass2TextureSize;
uniform float beam_horiz_filter;
uniform float beam_horiz_linear_rgb_weight;
uniform float beam_horiz_sigma;
uniform float convergence_offset_x_b;
uniform float convergence_offset_x_g;
uniform float convergence_offset_x_r;
uniform float geom_R;
uniform float geom_cornersize;
uniform float geom_cornersmooth;
uniform float geom_curvature;
uniform float geom_invert_aspect;
uniform float geom_overscanx;
uniform float geom_overscany;
uniform float lcd_gamma;
struct UBO
{
    float lcd_gamma;
    float beam_horiz_filter;
    float beam_horiz_sigma;
    float beam_horiz_linear_rgb_weight;
    float convergence_offset_x_r;
    float convergence_offset_x_g;
    float convergence_offset_x_b;
};



struct Push
{
    vec4 VERTICAL_SCANLINESSize;
    float geom_R;
    float geom_cornersize;
    float geom_cornersmooth;
    float geom_overscanx;
    float geom_overscany;
    float geom_curvature;
    float geom_invert_aspect;
};



uniform sampler2D Pass2Texture;
uniform sampler2D Pass4Texture;

varying vec2 RA_VARYING_4;
varying vec2 RA_VARYING_5;
varying vec3 RA_VARYING_6;
varying vec2 RA_VARYING_0;
varying float RA_VARYING_8;
varying float RA_VARYING_7;
varying vec2 RA_VARYING_1;
varying vec2 RA_VARYING_3;
varying vec4 RA_VARYING_2;

void main()
{
    vec2 _295 = vec2(((geom_invert_aspect) > 0.5) ? 1.0 : 0.75);
    float _2507;
    vec2 _2566;
    if ((geom_curvature) > 0.5)
    {
        vec2 _978 = (((RA_VARYING_0 - vec2(0.5)) * _295) * RA_VARYING_6.z) + RA_VARYING_6.xy;
        float _1099 = dot(_978, _978) + RA_VARYING_8;
        float _1109 = (((geom_R) * dot(_978, RA_VARYING_4)) - RA_VARYING_7) - RA_VARYING_8;
        vec2 _1032 = ((vec2(((_1109 * (-2.0)) - sqrt((4.0 * (_1109 * _1109)) - ((4.0 * _1099) * (RA_VARYING_8 + (2.0 * RA_VARYING_7))))) / (2.0 * _1099)) * _978) - (vec2(-(geom_R)) * RA_VARYING_4)) / vec2((geom_R));
        vec2 _1035 = _1032 / RA_VARYING_5;
        vec2 _1038 = RA_VARYING_4 / RA_VARYING_5;
        float _1042 = dot(_1038, _1038) + 1.0;
        float _1045 = dot(_1035, _1038);
        float _1065 = ((_1045 * 2.0) + sqrt((4.0 * (_1045 * _1045)) - ((4.0 * _1042) * (dot(_1035, _1035) - 1.0)))) / (2.0 * _1042);
        float _1079 = max(abs((geom_R) * acos(_1065)), 9.9999997473787516355514526367188e-06);
        vec2 _989 = vec2((geom_overscanx) * 0.00999999977648258209228515625, (geom_overscany) * 0.00999999977648258209228515625);
        vec2 _992 = (((((_1032 - (RA_VARYING_4 * _1065)) / RA_VARYING_5) * _1079) / vec2(sin(_1079 / (geom_R)))) / _989) / _295;
        vec2 _1143 = _992 * _989;
        vec2 _1153 = vec2((geom_cornersize));
        vec2 _1158 = _1153 - min(min(_1143 + vec2(0.5), vec2(0.5) - _1143) * _295, _1153);
        _2566 = _992 + vec2(0.5);
        _2507 = clamp(((geom_cornersize) - sqrt(dot(_1158, _1158))) * (geom_cornersmooth), 0.0, 1.0);
    }
    else
    {
        _2566 = RA_VARYING_0;
        _2507 = 1.0;
    }
    vec3 _1202 = vec3((convergence_offset_x_r), (convergence_offset_x_g), (convergence_offset_x_b)) * RA_VARYING_1.xxx;
    vec2 _1275 = (_2566 - vec2(_1202.x, 0.0)) * (vec4(Pass2TextureSize, 1.0 / Pass2TextureSize)).xy;
    vec2 _1281 = floor(_1275 - vec2(0.4995000064373016357421875)) + vec2(0.5);
    float _1283 = _1281.x;
    vec2 _1289 = vec2(_1283, _1275.y) * RA_VARYING_1;
    float _1294 = _1275.x - _1283;
    vec4 _1302 = vec4(1.0 + _1294, _1294, 1.0 - _1294, 2.0 - _1294);
    bool _1305 = (beam_horiz_filter) < 0.5;
    vec4 _2422;
    if (_1305)
    {
        float _1320 = ((_1294 * _1294) * _1294) * ((_1294 * ((_1294 * 6.0) - 15.0)) + 10.0);
        _2422 = vec4(0.0, 1.0 - _1320, _1320, 0.0);
    }
    else
    {
        vec4 _2423;
        if ((beam_horiz_filter) < 1.5)
        {
            _2423 = exp((-(_1302 * _1302)) * (1.0 / ((2.0 * (beam_horiz_sigma)) * (beam_horiz_sigma))));
        }
        else
        {
            vec4 _2424;
            if ((beam_horiz_filter) < 2.5)
            {
                vec4 _1354 = max(abs(_1302 * 3.1415927410125732421875), vec4(1.52587890625e-05));
                _2424 = ((sin(_1354) * 2.0) * sin(_1354 * 0.5)) / (_1354 * _1354);
            }
            else
            {
                _2424 = vec4(0.0, 1.0 - _1294, _1294, 0.0);
            }
            _2423 = _2424;
        }
        _2422 = _2423;
    }
    vec4 _1380 = _2422 / vec4(dot(_2422, vec4(1.0)));
    vec2 _1383 = vec2(RA_VARYING_1.x, 0.0);
    vec4 _1401 = texture2D(Pass2Texture, _1289);
    vec4 _1407 = texture2D(Pass2Texture, _1289 + _1383);
    bool _1411 = (beam_horiz_filter) > 0.5;
    vec3 _2428;
    vec3 _2431;
    if (_1411)
    {
        _2431 = texture2D(Pass2Texture, _1289 + (_1383 * 2.0)).xyz;
        _2428 = texture2D(Pass2Texture, _1289 - _1383).xyz;
    }
    else
    {
        _2431 = vec3(0.0);
        _2428 = vec3(0.0);
    }
    vec3 _1459 = vec3(1.0 / (lcd_gamma));
    vec3 _1482 = vec3((beam_horiz_linear_rgb_weight));
    vec2 _1559 = (_2566 - vec2(_1202.y, 0.0)) * (vec4(Pass2TextureSize, 1.0 / Pass2TextureSize)).xy;
    vec2 _1565 = floor(_1559 - vec2(0.4995000064373016357421875)) + vec2(0.5);
    float _1567 = _1565.x;
    vec2 _1573 = vec2(_1567, _1559.y) * RA_VARYING_1;
    float _1578 = _1559.x - _1567;
    vec4 _1586 = vec4(1.0 + _1578, _1578, 1.0 - _1578, 2.0 - _1578);
    vec4 _2453;
    if (_1305)
    {
        float _1604 = ((_1578 * _1578) * _1578) * ((_1578 * ((_1578 * 6.0) - 15.0)) + 10.0);
        _2453 = vec4(0.0, 1.0 - _1604, _1604, 0.0);
    }
    else
    {
        vec4 _2454;
        if ((beam_horiz_filter) < 1.5)
        {
            _2454 = exp((-(_1586 * _1586)) * (1.0 / ((2.0 * (beam_horiz_sigma)) * (beam_horiz_sigma))));
        }
        else
        {
            vec4 _2455;
            if ((beam_horiz_filter) < 2.5)
            {
                vec4 _1638 = max(abs(_1586 * 3.1415927410125732421875), vec4(1.52587890625e-05));
                _2455 = ((sin(_1638) * 2.0) * sin(_1638 * 0.5)) / (_1638 * _1638);
            }
            else
            {
                _2455 = vec4(0.0, 1.0 - _1578, _1578, 0.0);
            }
            _2454 = _2455;
        }
        _2453 = _2454;
    }
    vec4 _1664 = _2453 / vec4(dot(_2453, vec4(1.0)));
    vec4 _1685 = texture2D(Pass2Texture, _1573);
    vec4 _1691 = texture2D(Pass2Texture, _1573 + _1383);
    vec3 _2459;
    vec3 _2462;
    if (_1411)
    {
        _2462 = texture2D(Pass2Texture, _1573 + (_1383 * 2.0)).xyz;
        _2459 = texture2D(Pass2Texture, _1573 - _1383).xyz;
    }
    else
    {
        _2462 = vec3(0.0);
        _2459 = vec3(0.0);
    }
    vec2 _1843 = (_2566 - vec2(_1202.z, 0.0)) * (vec4(Pass2TextureSize, 1.0 / Pass2TextureSize)).xy;
    vec2 _1849 = floor(_1843 - vec2(0.4995000064373016357421875)) + vec2(0.5);
    float _1851 = _1849.x;
    vec2 _1857 = vec2(_1851, _1843.y) * RA_VARYING_1;
    float _1862 = _1843.x - _1851;
    vec4 _1870 = vec4(1.0 + _1862, _1862, 1.0 - _1862, 2.0 - _1862);
    vec4 _2488;
    if (_1305)
    {
        float _1888 = ((_1862 * _1862) * _1862) * ((_1862 * ((_1862 * 6.0) - 15.0)) + 10.0);
        _2488 = vec4(0.0, 1.0 - _1888, _1888, 0.0);
    }
    else
    {
        vec4 _2489;
        if ((beam_horiz_filter) < 1.5)
        {
            _2489 = exp((-(_1870 * _1870)) * (1.0 / ((2.0 * (beam_horiz_sigma)) * (beam_horiz_sigma))));
        }
        else
        {
            vec4 _2490;
            if ((beam_horiz_filter) < 2.5)
            {
                vec4 _1922 = max(abs(_1870 * 3.1415927410125732421875), vec4(1.52587890625e-05));
                _2490 = ((sin(_1922) * 2.0) * sin(_1922 * 0.5)) / (_1922 * _1922);
            }
            else
            {
                _2490 = vec4(0.0, 1.0 - _1862, _1862, 0.0);
            }
            _2489 = _2490;
        }
        _2488 = _2489;
    }
    vec4 _1948 = _2488 / vec4(dot(_2488, vec4(1.0)));
    vec4 _1969 = texture2D(Pass2Texture, _1857);
    vec4 _1975 = texture2D(Pass2Texture, _1857 + _1383);
    vec3 _2494;
    vec3 _2497;
    if (_1411)
    {
        _2497 = texture2D(Pass2Texture, _1857 + (_1383 * 2.0)).xyz;
        _2494 = texture2D(Pass2Texture, _1857 - _1383).xyz;
    }
    else
    {
        _2497 = vec3(0.0);
        _2494 = vec3(0.0);
    }
    vec3 _940 = vec3(mix(max(mat4x3(pow(_2428, _1459), pow(_1401.xyz, _1459), pow(_1407.xyz, _1459), pow(_2431, _1459)) * _1380, vec3(0.0)), max(mat4x3(_2428, vec3(_1401.xyz), vec3(_1407.xyz), _2431) * _1380, vec3(0.0)), _1482).x, mix(max(mat4x3(pow(_2459, _1459), pow(_1685.xyz, _1459), pow(_1691.xyz, _1459), pow(_2462, _1459)) * _1664, vec3(0.0)), max(mat4x3(_2459, vec3(_1685.xyz), vec3(_1691.xyz), _2462) * _1664, vec3(0.0)), _1482).y, mix(max(mat4x3(pow(_2494, _1459), pow(_1969.xyz, _1459), pow(_1975.xyz, _1459), pow(_2497, _1459)) * _1948, vec3(0.0)), max(mat4x3(_2494, vec3(_1969.xyz), vec3(_1975.xyz), _2497) * _1948, vec3(0.0)), _1482).z) * texture2D(Pass4Texture, RA_VARYING_2.xy + (fract(RA_VARYING_0 * RA_VARYING_3) * RA_VARYING_2.zw)).xyz;
    gl_FragData[0] = vec4((_940 * vec3(_2507)) * step(0.0, fract(_2566.y)), 1.0);
}


#endif
