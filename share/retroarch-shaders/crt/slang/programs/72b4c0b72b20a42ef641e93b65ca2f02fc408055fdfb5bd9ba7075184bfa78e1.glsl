// Generated from crt/shaders/crt-royale/src/crt-royale-scanlines-horizontal-apply-mask-intel.slang. See slang/upstream for licence/source.
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
uniform vec2 Pass2TextureSize;
uniform float mask_num_triads_desired;
uniform float mask_sample_mode_desired;
uniform float mask_specify_num_triads;
uniform float mask_triad_size_desired;
struct UBO
{
    mat4 MVP;
    float mask_sample_mode_desired;
    float mask_num_triads_desired;
    float mask_triad_size_desired;
    float mask_specify_num_triads;
};



struct Push
{
    vec4 SourceSize;
    vec4 OutputSize;
    vec4 VERTICAL_SCANLINESSize;
    vec4 BLOOM_APPROXSize;
    vec4 HALATION_BLURSize;
};



attribute vec4 VertexCoord;
attribute vec2 TexCoord;
varying vec2 RA_VARYING_0;
varying vec2 RA_VARYING_4;
varying vec2 RA_VARYING_1;
varying vec2 RA_VARYING_2;
varying vec2 RA_VARYING_3;
varying vec4 RA_VARYING_5;
varying vec2 RA_VARYING_6;

void main()
{
    gl_Position = (MVPMatrix) * VertexCoord;
    RA_VARYING_0 = TexCoord;
    RA_VARYING_4 = vec2(1.0) / (vec4(Pass2TextureSize, 1.0 / Pass2TextureSize)).xy;
    RA_VARYING_1 = (RA_VARYING_0 * (vec4(Pass2TextureSize, 1.0 / Pass2TextureSize)).xy) * RA_VARYING_4;
    RA_VARYING_2 = RA_VARYING_0;
    RA_VARYING_3 = RA_VARYING_0;
    vec2 _678;
    if (clamp((mask_sample_mode_desired), 1.0, 2.0) > 1.5)
    {
        _678 = (vec4(OutputSize, 1.0 / OutputSize)).xy * vec2(0.001953125);
    }
    else
    {
        _678 = (vec4(OutputSize, 1.0 / OutputSize)).xy / (vec2(1.0) * (8.0 * mix((mask_triad_size_desired), (vec4(OutputSize, 1.0 / OutputSize)).x / (mask_num_triads_desired), (mask_specify_num_triads))));
    }
    RA_VARYING_6 = _678;
    RA_VARYING_5 = vec4(0.0, 0.0, 1.0, 1.0);
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
uniform float halation_weight;
uniform float mask_type;
struct UBO
{
    float halation_weight;
    float beam_horiz_filter;
    float beam_horiz_sigma;
    float beam_horiz_linear_rgb_weight;
    float convergence_offset_x_r;
    float convergence_offset_x_g;
    float convergence_offset_x_b;
    float mask_type;
};



struct Push
{
    vec4 VERTICAL_SCANLINESSize;
};



uniform sampler2D Pass2Texture;
uniform sampler2D mask_grille_texture_large;
uniform sampler2D mask_slot_texture_large;
uniform sampler2D mask_shadow_texture_large;
uniform sampler2D Pass5Texture;

varying vec2 RA_VARYING_1;
varying vec2 RA_VARYING_4;
varying vec2 RA_VARYING_0;
varying vec2 RA_VARYING_6;
varying vec2 RA_VARYING_3;

void main()
{
    vec3 _953 = vec3((convergence_offset_x_r), (convergence_offset_x_g), (convergence_offset_x_b)) * RA_VARYING_4.xxx;
    vec2 _1025 = (RA_VARYING_1 - vec2(_953.x, 0.0)) * (vec4(Pass2TextureSize, 1.0 / Pass2TextureSize)).xy;
    vec2 _1031 = floor(_1025 - vec2(0.4995000064373016357421875)) + vec2(0.5);
    float _1033 = _1031.x;
    vec2 _1039 = vec2(_1033, _1025.y) * RA_VARYING_4;
    float _1044 = _1025.x - _1033;
    vec4 _1052 = vec4(1.0 + _1044, _1044, 1.0 - _1044, 2.0 - _1044);
    bool _1055 = (beam_horiz_filter) < 0.5;
    vec4 _2423;
    if (_1055)
    {
        float _1070 = ((_1044 * _1044) * _1044) * ((_1044 * ((_1044 * 6.0) - 15.0)) + 10.0);
        _2423 = vec4(0.0, 1.0 - _1070, _1070, 0.0);
    }
    else
    {
        vec4 _2424;
        if ((beam_horiz_filter) < 1.5)
        {
            _2424 = exp((-(_1052 * _1052)) * (1.0 / ((2.0 * (beam_horiz_sigma)) * (beam_horiz_sigma))));
        }
        else
        {
            vec4 _1100 = max(abs(_1052 * 3.1415927410125732421875), vec4(1.52587890625e-05));
            _2424 = ((sin(_1100) * 2.0) * sin(_1100 * 0.5)) / (_1100 * _1100);
        }
        _2423 = _2424;
    }
    vec4 _1118 = _2423 / vec4(dot(_2423, vec4(1.0)));
    vec2 _1121 = vec2(RA_VARYING_4.x, 0.0);
    vec4 _1139 = texture2D(Pass2Texture, _1039);
    vec4 _1145 = texture2D(Pass2Texture, _1039 + _1121);
    bool _1149 = (beam_horiz_filter) > 0.5;
    vec3 _2427;
    vec3 _2430;
    if (_1149)
    {
        _2430 = texture2D(Pass2Texture, _1039 + (_1121 * 2.0)).xyz;
        _2427 = texture2D(Pass2Texture, _1039 - _1121).xyz;
    }
    else
    {
        _2430 = vec3(0.0);
        _2427 = vec3(0.0);
    }
    vec3 _1219 = vec3((beam_horiz_linear_rgb_weight));
    vec2 _1298 = (RA_VARYING_1 - vec2(_953.y, 0.0)) * (vec4(Pass2TextureSize, 1.0 / Pass2TextureSize)).xy;
    vec2 _1304 = floor(_1298 - vec2(0.4995000064373016357421875)) + vec2(0.5);
    float _1306 = _1304.x;
    vec2 _1312 = vec2(_1306, _1298.y) * RA_VARYING_4;
    float _1317 = _1298.x - _1306;
    vec4 _1325 = vec4(1.0 + _1317, _1317, 1.0 - _1317, 2.0 - _1317);
    vec4 _2450;
    if (_1055)
    {
        float _1343 = ((_1317 * _1317) * _1317) * ((_1317 * ((_1317 * 6.0) - 15.0)) + 10.0);
        _2450 = vec4(0.0, 1.0 - _1343, _1343, 0.0);
    }
    else
    {
        vec4 _2451;
        if ((beam_horiz_filter) < 1.5)
        {
            _2451 = exp((-(_1325 * _1325)) * (1.0 / ((2.0 * (beam_horiz_sigma)) * (beam_horiz_sigma))));
        }
        else
        {
            vec4 _1373 = max(abs(_1325 * 3.1415927410125732421875), vec4(1.52587890625e-05));
            _2451 = ((sin(_1373) * 2.0) * sin(_1373 * 0.5)) / (_1373 * _1373);
        }
        _2450 = _2451;
    }
    vec4 _1391 = _2450 / vec4(dot(_2450, vec4(1.0)));
    vec4 _1412 = texture2D(Pass2Texture, _1312);
    vec4 _1418 = texture2D(Pass2Texture, _1312 + _1121);
    vec3 _2454;
    vec3 _2457;
    if (_1149)
    {
        _2457 = texture2D(Pass2Texture, _1312 + (_1121 * 2.0)).xyz;
        _2454 = texture2D(Pass2Texture, _1312 - _1121).xyz;
    }
    else
    {
        _2457 = vec3(0.0);
        _2454 = vec3(0.0);
    }
    vec2 _1571 = (RA_VARYING_1 - vec2(_953.z, 0.0)) * (vec4(Pass2TextureSize, 1.0 / Pass2TextureSize)).xy;
    vec2 _1577 = floor(_1571 - vec2(0.4995000064373016357421875)) + vec2(0.5);
    float _1579 = _1577.x;
    vec2 _1585 = vec2(_1579, _1571.y) * RA_VARYING_4;
    float _1590 = _1571.x - _1579;
    vec4 _1598 = vec4(1.0 + _1590, _1590, 1.0 - _1590, 2.0 - _1590);
    vec4 _2480;
    if (_1055)
    {
        float _1616 = ((_1590 * _1590) * _1590) * ((_1590 * ((_1590 * 6.0) - 15.0)) + 10.0);
        _2480 = vec4(0.0, 1.0 - _1616, _1616, 0.0);
    }
    else
    {
        vec4 _2481;
        if ((beam_horiz_filter) < 1.5)
        {
            _2481 = exp((-(_1598 * _1598)) * (1.0 / ((2.0 * (beam_horiz_sigma)) * (beam_horiz_sigma))));
        }
        else
        {
            vec4 _1646 = max(abs(_1598 * 3.1415927410125732421875), vec4(1.52587890625e-05));
            _2481 = ((sin(_1646) * 2.0) * sin(_1646 * 0.5)) / (_1646 * _1646);
        }
        _2480 = _2481;
    }
    vec4 _1664 = _2480 / vec4(dot(_2480, vec4(1.0)));
    vec4 _1685 = texture2D(Pass2Texture, _1585);
    vec4 _1691 = texture2D(Pass2Texture, _1585 + _1121);
    vec3 _2484;
    vec3 _2487;
    if (_1149)
    {
        _2487 = texture2D(Pass2Texture, _1585 + (_1121 * 2.0)).xyz;
        _2484 = texture2D(Pass2Texture, _1585 - _1121).xyz;
    }
    else
    {
        _2487 = vec3(0.0);
        _2484 = vec3(0.0);
    }
    vec2 _813 = RA_VARYING_0 * RA_VARYING_6;
    vec3 _2574;
    if ((mask_type) < 0.5)
    {
        _2574 = texture2D(mask_grille_texture_large, _813).xyz;
    }
    else
    {
        vec3 _2575;
        if ((mask_type) < 1.5)
        {
            _2575 = texture2D(mask_slot_texture_large, _813).xyz;
        }
        else
        {
            _2575 = texture2D(mask_shadow_texture_large, _813).xyz;
        }
        _2574 = _2575;
    }
    vec3 _883 = mix(vec3(mix(max(mat4x3(pow(_2427, vec3(0.454545438289642333984375)), pow(_1139.xyz, vec3(0.454545438289642333984375)), pow(_1145.xyz, vec3(0.454545438289642333984375)), pow(_2430, vec3(0.454545438289642333984375))) * _1118, vec3(0.0)), max(mat4x3(_2427, vec3(_1139.xyz), vec3(_1145.xyz), _2430) * _1118, vec3(0.0)), _1219).x, mix(max(mat4x3(pow(_2454, vec3(0.454545438289642333984375)), pow(_1412.xyz, vec3(0.454545438289642333984375)), pow(_1418.xyz, vec3(0.454545438289642333984375)), pow(_2457, vec3(0.454545438289642333984375))) * _1391, vec3(0.0)), max(mat4x3(_2454, vec3(_1412.xyz), vec3(_1418.xyz), _2457) * _1391, vec3(0.0)), _1219).y, mix(max(mat4x3(pow(_2484, vec3(0.454545438289642333984375)), pow(_1685.xyz, vec3(0.454545438289642333984375)), pow(_1691.xyz, vec3(0.454545438289642333984375)), pow(_2487, vec3(0.454545438289642333984375))) * _1664, vec3(0.0)), max(mat4x3(_2484, vec3(_1685.xyz), vec3(_1691.xyz), _2487) * _1664, vec3(0.0)), _1219).z), vec3(dot(texture2D(Pass5Texture, RA_VARYING_3).xyz, vec3(0.16666667163372039794921875))), vec3((halation_weight)));
    gl_FragData[0] = vec4(_883 * _2574, 1.0);
}


#endif
