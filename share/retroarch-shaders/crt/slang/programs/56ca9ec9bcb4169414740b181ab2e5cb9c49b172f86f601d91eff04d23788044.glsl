// Generated from crt/shaders/crt-royale/src/crt-royale-scanlines-horizontal-apply-mask-fake-bloom.slang. See slang/upstream for licence/source.
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
uniform vec2 Pass7TextureSize;
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
    vec4 MASK_RESIZESize;
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
    bool _473 = (mask_sample_mode_desired) < 0.5;
    vec2 _689;
    if (_473)
    {
        _689 = (vec4(Pass7TextureSize, 1.0 / Pass7TextureSize)).xy;
    }
    else
    {
        _689 = vec2(512.0);
    }
    vec2 _692;
    if (_473)
    {
        _692 = (vec4(Pass7TextureSize, 1.0 / Pass7TextureSize)).xy;
    }
    else
    {
        _692 = vec2(512.0);
    }
    vec4 _711;
    vec2 _712;
    do
    {
        vec2 _700;
        do
        {
            float _631 = 8.0 * mix((mask_triad_size_desired), (vec4(OutputSize, 1.0 / OutputSize)).x / (mask_num_triads_desired), (mask_specify_num_triads));
            if ((mask_sample_mode_desired) > 0.5)
            {
                _700 = vec2(1.0) * _631;
                break;
            }
            vec2 _656 = clamp(vec2(1.0) * min(_631, 64.0), vec2(1.0) * ceil(16.0), _692 * vec2(0.5));
            float _658 = _656.y;
            _700 = floor(vec2(min(_656.x, _658), min(_658, _658)) + vec2(1.52587890625e-05));
            break;
        } while(false);
        if (_473)
        {
            _712 = (vec4(OutputSize, 1.0 / OutputSize)).xy / _700;
            _711 = vec4(0.0, 0.0, _700 / _689);
            break;
        }
        else
        {
            vec2 _713;
            if ((mask_sample_mode_desired) > 1.5)
            {
                _713 = (vec4(OutputSize, 1.0 / OutputSize)).xy * vec2(0.001953125);
            }
            else
            {
                _713 = (vec4(OutputSize, 1.0 / OutputSize)).xy / _700;
            }
            _712 = _713;
            _711 = vec4(0.0, 0.0, 1.0, 1.0);
            break;
        }
        break; // unreachable workaround
    } while(false);
    RA_VARYING_6 = _712;
    RA_VARYING_5 = _711;
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
uniform float mask_sample_mode_desired;
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
    float mask_sample_mode_desired;
};



struct Push
{
    vec4 VERTICAL_SCANLINESSize;
};



uniform sampler2D Pass2Texture;
uniform sampler2D mask_grille_texture_large;
uniform sampler2D mask_slot_texture_large;
uniform sampler2D mask_shadow_texture_large;
uniform sampler2D Pass7Texture;
uniform sampler2D Pass5Texture;
uniform sampler2D Pass3Texture;

varying vec2 RA_VARYING_1;
varying vec2 RA_VARYING_4;
varying vec2 RA_VARYING_0;
varying vec2 RA_VARYING_6;
varying vec4 RA_VARYING_5;
varying vec2 RA_VARYING_3;
varying vec2 RA_VARYING_2;

void main()
{
    vec3 _1052 = vec3((convergence_offset_x_r), (convergence_offset_x_g), (convergence_offset_x_b)) * RA_VARYING_4.xxx;
    vec2 _1124 = (RA_VARYING_1 - vec2(_1052.x, 0.0)) * (vec4(Pass2TextureSize, 1.0 / Pass2TextureSize)).xy;
    vec2 _1130 = floor(_1124 - vec2(0.4995000064373016357421875)) + vec2(0.5);
    float _1132 = _1130.x;
    vec2 _1138 = vec2(_1132, _1124.y) * RA_VARYING_4;
    float _1143 = _1124.x - _1132;
    vec4 _1151 = vec4(1.0 + _1143, _1143, 1.0 - _1143, 2.0 - _1143);
    bool _1154 = (beam_horiz_filter) < 0.5;
    vec4 _2598;
    if (_1154)
    {
        float _1169 = ((_1143 * _1143) * _1143) * ((_1143 * ((_1143 * 6.0) - 15.0)) + 10.0);
        _2598 = vec4(0.0, 1.0 - _1169, _1169, 0.0);
    }
    else
    {
        vec4 _2599;
        if ((beam_horiz_filter) < 1.5)
        {
            _2599 = exp((-(_1151 * _1151)) * (1.0 / ((2.0 * (beam_horiz_sigma)) * (beam_horiz_sigma))));
        }
        else
        {
            vec4 _1199 = max(abs(_1151 * 3.1415927410125732421875), vec4(1.52587890625e-05));
            _2599 = ((sin(_1199) * 2.0) * sin(_1199 * 0.5)) / (_1199 * _1199);
        }
        _2598 = _2599;
    }
    vec4 _1217 = _2598 / vec4(dot(_2598, vec4(1.0)));
    vec2 _1220 = vec2(RA_VARYING_4.x, 0.0);
    vec4 _1238 = texture2D(Pass2Texture, _1138);
    vec4 _1244 = texture2D(Pass2Texture, _1138 + _1220);
    bool _1248 = (beam_horiz_filter) > 0.5;
    vec3 _2602;
    vec3 _2605;
    if (_1248)
    {
        _2605 = texture2D(Pass2Texture, _1138 + (_1220 * 2.0)).xyz;
        _2602 = texture2D(Pass2Texture, _1138 - _1220).xyz;
    }
    else
    {
        _2605 = vec3(0.0);
        _2602 = vec3(0.0);
    }
    vec3 _1318 = vec3((beam_horiz_linear_rgb_weight));
    vec2 _1397 = (RA_VARYING_1 - vec2(_1052.y, 0.0)) * (vec4(Pass2TextureSize, 1.0 / Pass2TextureSize)).xy;
    vec2 _1403 = floor(_1397 - vec2(0.4995000064373016357421875)) + vec2(0.5);
    float _1405 = _1403.x;
    vec2 _1411 = vec2(_1405, _1397.y) * RA_VARYING_4;
    float _1416 = _1397.x - _1405;
    vec4 _1424 = vec4(1.0 + _1416, _1416, 1.0 - _1416, 2.0 - _1416);
    vec4 _2625;
    if (_1154)
    {
        float _1442 = ((_1416 * _1416) * _1416) * ((_1416 * ((_1416 * 6.0) - 15.0)) + 10.0);
        _2625 = vec4(0.0, 1.0 - _1442, _1442, 0.0);
    }
    else
    {
        vec4 _2626;
        if ((beam_horiz_filter) < 1.5)
        {
            _2626 = exp((-(_1424 * _1424)) * (1.0 / ((2.0 * (beam_horiz_sigma)) * (beam_horiz_sigma))));
        }
        else
        {
            vec4 _1472 = max(abs(_1424 * 3.1415927410125732421875), vec4(1.52587890625e-05));
            _2626 = ((sin(_1472) * 2.0) * sin(_1472 * 0.5)) / (_1472 * _1472);
        }
        _2625 = _2626;
    }
    vec4 _1490 = _2625 / vec4(dot(_2625, vec4(1.0)));
    vec4 _1511 = texture2D(Pass2Texture, _1411);
    vec4 _1517 = texture2D(Pass2Texture, _1411 + _1220);
    vec3 _2629;
    vec3 _2632;
    if (_1248)
    {
        _2632 = texture2D(Pass2Texture, _1411 + (_1220 * 2.0)).xyz;
        _2629 = texture2D(Pass2Texture, _1411 - _1220).xyz;
    }
    else
    {
        _2632 = vec3(0.0);
        _2629 = vec3(0.0);
    }
    vec2 _1670 = (RA_VARYING_1 - vec2(_1052.z, 0.0)) * (vec4(Pass2TextureSize, 1.0 / Pass2TextureSize)).xy;
    vec2 _1676 = floor(_1670 - vec2(0.4995000064373016357421875)) + vec2(0.5);
    float _1678 = _1676.x;
    vec2 _1684 = vec2(_1678, _1670.y) * RA_VARYING_4;
    float _1689 = _1670.x - _1678;
    vec4 _1697 = vec4(1.0 + _1689, _1689, 1.0 - _1689, 2.0 - _1689);
    vec4 _2655;
    if (_1154)
    {
        float _1715 = ((_1689 * _1689) * _1689) * ((_1689 * ((_1689 * 6.0) - 15.0)) + 10.0);
        _2655 = vec4(0.0, 1.0 - _1715, _1715, 0.0);
    }
    else
    {
        vec4 _2656;
        if ((beam_horiz_filter) < 1.5)
        {
            _2656 = exp((-(_1697 * _1697)) * (1.0 / ((2.0 * (beam_horiz_sigma)) * (beam_horiz_sigma))));
        }
        else
        {
            vec4 _1745 = max(abs(_1697 * 3.1415927410125732421875), vec4(1.52587890625e-05));
            _2656 = ((sin(_1745) * 2.0) * sin(_1745 * 0.5)) / (_1745 * _1745);
        }
        _2655 = _2656;
    }
    vec4 _1763 = _2655 / vec4(dot(_2655, vec4(1.0)));
    vec4 _1784 = texture2D(Pass2Texture, _1684);
    vec4 _1790 = texture2D(Pass2Texture, _1684 + _1220);
    vec3 _2659;
    vec3 _2662;
    if (_1248)
    {
        _2662 = texture2D(Pass2Texture, _1684 + (_1220 * 2.0)).xyz;
        _2659 = texture2D(Pass2Texture, _1684 - _1220).xyz;
    }
    else
    {
        _2662 = vec3(0.0);
        _2659 = vec3(0.0);
    }
    float _2226;
    vec2 _838 = RA_VARYING_0 * RA_VARYING_6;
    vec2 _2681;
    do
    {
        _2226 = (mask_sample_mode_desired);
        if (_2226 < 0.5)
        {
            _2681 = RA_VARYING_5.xy + ((fract(_838 * 0.5) * 2.0) * RA_VARYING_5.zw);
            break;
        }
        else
        {
            _2681 = _838;
            break;
        }
        break; // unreachable workaround
    } while(false);
    vec3 _2748;
    if (_2226 > 0.5)
    {
        vec3 _2749;
        if ((mask_type) < 0.5)
        {
            _2749 = texture2D(mask_grille_texture_large, _2681).xyz;
        }
        else
        {
            vec3 _2750;
            if ((mask_type) < 1.5)
            {
                _2750 = texture2D(mask_slot_texture_large, _2681).xyz;
            }
            else
            {
                _2750 = texture2D(mask_shadow_texture_large, _2681).xyz;
            }
            _2749 = _2750;
        }
        _2748 = _2749;
    }
    else
    {
        _2748 = texture2D(Pass7Texture, _2681).xyz;
    }
    vec4 _2429 = texture2D(Pass5Texture, RA_VARYING_3);
    vec3 _894 = _2429.xyz;
    vec3 _909 = mix(vec3(mix(max(mat4x3(pow(_2602, vec3(0.454545438289642333984375)), pow(_1238.xyz, vec3(0.454545438289642333984375)), pow(_1244.xyz, vec3(0.454545438289642333984375)), pow(_2605, vec3(0.454545438289642333984375))) * _1217, vec3(0.0)), max(mat4x3(_2602, vec3(_1238.xyz), vec3(_1244.xyz), _2605) * _1217, vec3(0.0)), _1318).x, mix(max(mat4x3(pow(_2629, vec3(0.454545438289642333984375)), pow(_1511.xyz, vec3(0.454545438289642333984375)), pow(_1517.xyz, vec3(0.454545438289642333984375)), pow(_2632, vec3(0.454545438289642333984375))) * _1490, vec3(0.0)), max(mat4x3(_2629, vec3(_1511.xyz), vec3(_1517.xyz), _2632) * _1490, vec3(0.0)), _1318).y, mix(max(mat4x3(pow(_2659, vec3(0.454545438289642333984375)), pow(_1784.xyz, vec3(0.454545438289642333984375)), pow(_1790.xyz, vec3(0.454545438289642333984375)), pow(_2662, vec3(0.454545438289642333984375))) * _1763, vec3(0.0)), max(mat4x3(_2659, vec3(_1784.xyz), vec3(_1790.xyz), _2662) * _1763, vec3(0.0)), _1318).z), vec3(dot(_894, vec3(0.16666667163372039794921875))), vec3((halation_weight)));
    float _2817;
    if ((mask_type) < 0.5)
    {
        _2817 = 4.811320781707763671875;
    }
    else
    {
        _2817 = ((mask_type) < 1.5) ? 5.5434780120849609375 : 6.21951198577880859375;
    }
    vec3 _944 = mix(texture2D(Pass3Texture, RA_VARYING_2).xyz, _909 * 2.0, vec3(0.100000001490116119384765625)) * 1.0499999523162841796875;
    vec3 _950 = _944 * (bloom_underestimate_levels);
    vec3 _954 = _950 * _2817;
    gl_FragData[0] = vec4(mix(mix(((_909 * _2748) * 2.0) * _2817, _944, mix(max(clamp((_954 - vec3(1.0)) / (_954 - _950), vec3(0.0), vec3(1.0)), vec3(0.0)), vec3(1.0), vec3((bloom_excess)))), _894, vec3((diffusion_weight))), 1.0);
}


#endif
