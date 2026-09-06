// Generated from crt/shaders/crt-royale/src/crt-royale-scanlines-horizontal-apply-mask-fake-bloom-intel.slang. See slang/upstream for licence/source.
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
uniform float bloom_excess;
uniform float bloom_underestimate_levels;
uniform float convergence_offset_x_b;
uniform float convergence_offset_x_g;
uniform float convergence_offset_x_r;
uniform float diffusion_weight;
uniform float halation_weight;
uniform float mask_type;
struct UBO
{
    float halation_weight;
    float diffusion_weight;
    float bloom_underestimate_levels;
    float bloom_excess;
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
uniform sampler2D Pass3Texture;

varying vec2 RA_VARYING_1;
varying vec2 RA_VARYING_4;
varying vec2 RA_VARYING_0;
varying vec2 RA_VARYING_6;
varying vec2 RA_VARYING_3;
varying vec2 RA_VARYING_2;

void main()
{
    vec3 _1053 = vec3((convergence_offset_x_r), (convergence_offset_x_g), (convergence_offset_x_b)) * RA_VARYING_4.xxx;
    vec2 _1125 = (RA_VARYING_1 - vec2(_1053.x, 0.0)) * (vec4(Pass2TextureSize, 1.0 / Pass2TextureSize)).xy;
    vec2 _1131 = floor(_1125 - vec2(0.4995000064373016357421875)) + vec2(0.5);
    float _1133 = _1131.x;
    vec2 _1139 = vec2(_1133, _1125.y) * RA_VARYING_4;
    float _1144 = _1125.x - _1133;
    vec4 _1152 = vec4(1.0 + _1144, _1144, 1.0 - _1144, 2.0 - _1144);
    bool _1155 = (beam_horiz_filter) < 0.5;
    vec4 _2596;
    if (_1155)
    {
        float _1170 = ((_1144 * _1144) * _1144) * ((_1144 * ((_1144 * 6.0) - 15.0)) + 10.0);
        _2596 = vec4(0.0, 1.0 - _1170, _1170, 0.0);
    }
    else
    {
        vec4 _2597;
        if ((beam_horiz_filter) < 1.5)
        {
            _2597 = exp((-(_1152 * _1152)) * (1.0 / ((2.0 * (beam_horiz_sigma)) * (beam_horiz_sigma))));
        }
        else
        {
            vec4 _1200 = max(abs(_1152 * 3.1415927410125732421875), vec4(1.52587890625e-05));
            _2597 = ((sin(_1200) * 2.0) * sin(_1200 * 0.5)) / (_1200 * _1200);
        }
        _2596 = _2597;
    }
    vec4 _1218 = _2596 / vec4(dot(_2596, vec4(1.0)));
    vec2 _1221 = vec2(RA_VARYING_4.x, 0.0);
    vec4 _1239 = texture2D(Pass2Texture, _1139);
    vec4 _1245 = texture2D(Pass2Texture, _1139 + _1221);
    bool _1249 = (beam_horiz_filter) > 0.5;
    vec3 _2600;
    vec3 _2603;
    if (_1249)
    {
        _2603 = texture2D(Pass2Texture, _1139 + (_1221 * 2.0)).xyz;
        _2600 = texture2D(Pass2Texture, _1139 - _1221).xyz;
    }
    else
    {
        _2603 = vec3(0.0);
        _2600 = vec3(0.0);
    }
    vec3 _1319 = vec3((beam_horiz_linear_rgb_weight));
    vec2 _1398 = (RA_VARYING_1 - vec2(_1053.y, 0.0)) * (vec4(Pass2TextureSize, 1.0 / Pass2TextureSize)).xy;
    vec2 _1404 = floor(_1398 - vec2(0.4995000064373016357421875)) + vec2(0.5);
    float _1406 = _1404.x;
    vec2 _1412 = vec2(_1406, _1398.y) * RA_VARYING_4;
    float _1417 = _1398.x - _1406;
    vec4 _1425 = vec4(1.0 + _1417, _1417, 1.0 - _1417, 2.0 - _1417);
    vec4 _2623;
    if (_1155)
    {
        float _1443 = ((_1417 * _1417) * _1417) * ((_1417 * ((_1417 * 6.0) - 15.0)) + 10.0);
        _2623 = vec4(0.0, 1.0 - _1443, _1443, 0.0);
    }
    else
    {
        vec4 _2624;
        if ((beam_horiz_filter) < 1.5)
        {
            _2624 = exp((-(_1425 * _1425)) * (1.0 / ((2.0 * (beam_horiz_sigma)) * (beam_horiz_sigma))));
        }
        else
        {
            vec4 _1473 = max(abs(_1425 * 3.1415927410125732421875), vec4(1.52587890625e-05));
            _2624 = ((sin(_1473) * 2.0) * sin(_1473 * 0.5)) / (_1473 * _1473);
        }
        _2623 = _2624;
    }
    vec4 _1491 = _2623 / vec4(dot(_2623, vec4(1.0)));
    vec4 _1512 = texture2D(Pass2Texture, _1412);
    vec4 _1518 = texture2D(Pass2Texture, _1412 + _1221);
    vec3 _2627;
    vec3 _2630;
    if (_1249)
    {
        _2630 = texture2D(Pass2Texture, _1412 + (_1221 * 2.0)).xyz;
        _2627 = texture2D(Pass2Texture, _1412 - _1221).xyz;
    }
    else
    {
        _2630 = vec3(0.0);
        _2627 = vec3(0.0);
    }
    vec2 _1671 = (RA_VARYING_1 - vec2(_1053.z, 0.0)) * (vec4(Pass2TextureSize, 1.0 / Pass2TextureSize)).xy;
    vec2 _1677 = floor(_1671 - vec2(0.4995000064373016357421875)) + vec2(0.5);
    float _1679 = _1677.x;
    vec2 _1685 = vec2(_1679, _1671.y) * RA_VARYING_4;
    float _1690 = _1671.x - _1679;
    vec4 _1698 = vec4(1.0 + _1690, _1690, 1.0 - _1690, 2.0 - _1690);
    vec4 _2653;
    if (_1155)
    {
        float _1716 = ((_1690 * _1690) * _1690) * ((_1690 * ((_1690 * 6.0) - 15.0)) + 10.0);
        _2653 = vec4(0.0, 1.0 - _1716, _1716, 0.0);
    }
    else
    {
        vec4 _2654;
        if ((beam_horiz_filter) < 1.5)
        {
            _2654 = exp((-(_1698 * _1698)) * (1.0 / ((2.0 * (beam_horiz_sigma)) * (beam_horiz_sigma))));
        }
        else
        {
            vec4 _1746 = max(abs(_1698 * 3.1415927410125732421875), vec4(1.52587890625e-05));
            _2654 = ((sin(_1746) * 2.0) * sin(_1746 * 0.5)) / (_1746 * _1746);
        }
        _2653 = _2654;
    }
    vec4 _1764 = _2653 / vec4(dot(_2653, vec4(1.0)));
    vec4 _1785 = texture2D(Pass2Texture, _1685);
    vec4 _1791 = texture2D(Pass2Texture, _1685 + _1221);
    vec3 _2657;
    vec3 _2660;
    if (_1249)
    {
        _2660 = texture2D(Pass2Texture, _1685 + (_1221 * 2.0)).xyz;
        _2657 = texture2D(Pass2Texture, _1685 - _1221).xyz;
    }
    else
    {
        _2660 = vec3(0.0);
        _2657 = vec3(0.0);
    }
    vec2 _842 = RA_VARYING_0 * RA_VARYING_6;
    bool _858 = (mask_type) < 0.5;
    vec3 _2747;
    if (_858)
    {
        _2747 = texture2D(mask_grille_texture_large, _842).xyz;
    }
    else
    {
        vec3 _2748;
        if ((mask_type) < 1.5)
        {
            _2748 = texture2D(mask_slot_texture_large, _842).xyz;
        }
        else
        {
            _2748 = texture2D(mask_shadow_texture_large, _842).xyz;
        }
        _2747 = _2748;
    }
    vec4 _2427 = texture2D(Pass5Texture, RA_VARYING_3);
    vec3 _896 = _2427.xyz;
    vec3 _911 = mix(vec3(mix(max(mat4x3(pow(_2600, vec3(0.454545438289642333984375)), pow(_1239.xyz, vec3(0.454545438289642333984375)), pow(_1245.xyz, vec3(0.454545438289642333984375)), pow(_2603, vec3(0.454545438289642333984375))) * _1218, vec3(0.0)), max(mat4x3(_2600, vec3(_1239.xyz), vec3(_1245.xyz), _2603) * _1218, vec3(0.0)), _1319).x, mix(max(mat4x3(pow(_2627, vec3(0.454545438289642333984375)), pow(_1512.xyz, vec3(0.454545438289642333984375)), pow(_1518.xyz, vec3(0.454545438289642333984375)), pow(_2630, vec3(0.454545438289642333984375))) * _1491, vec3(0.0)), max(mat4x3(_2627, vec3(_1512.xyz), vec3(_1518.xyz), _2630) * _1491, vec3(0.0)), _1319).y, mix(max(mat4x3(pow(_2657, vec3(0.454545438289642333984375)), pow(_1785.xyz, vec3(0.454545438289642333984375)), pow(_1791.xyz, vec3(0.454545438289642333984375)), pow(_2660, vec3(0.454545438289642333984375))) * _1764, vec3(0.0)), max(mat4x3(_2657, vec3(_1785.xyz), vec3(_1791.xyz), _2660) * _1764, vec3(0.0)), _1319).z), vec3(dot(_896, vec3(0.16666667163372039794921875))), vec3((halation_weight)));
    float _2815;
    if (_858)
    {
        _2815 = 4.811320781707763671875;
    }
    else
    {
        _2815 = ((mask_type) < 1.5) ? 5.5434780120849609375 : 6.21951198577880859375;
    }
    vec3 _946 = mix(texture2D(Pass3Texture, RA_VARYING_2).xyz, _911 * 2.0, vec3(0.100000001490116119384765625)) * 1.0499999523162841796875;
    vec3 _952 = _946 * (bloom_underestimate_levels);
    vec3 _956 = _952 * _2815;
    gl_FragData[0] = vec4(mix(mix(((_911 * _2747) * 2.0) * _2815, _946, mix(max(clamp((_956 - vec3(1.0)) / (_956 - _952), vec3(0.0), vec3(1.0)), vec3(0.0)), vec3(1.0), vec3((bloom_excess)))), _896, vec3((diffusion_weight))), 1.0);
}


#endif
