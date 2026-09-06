// Generated from crt/shaders/crt-royale/src/crt-royale-scanlines-horizontal-apply-mask.slang. See slang/upstream for licence/source.
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
uniform float convergence_offset_x_b;
uniform float convergence_offset_x_g;
uniform float convergence_offset_x_r;
uniform float halation_weight;
uniform float mask_sample_mode_desired;
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

varying vec2 RA_VARYING_1;
varying vec2 RA_VARYING_4;
varying vec2 RA_VARYING_0;
varying vec2 RA_VARYING_6;
varying vec4 RA_VARYING_5;
varying vec2 RA_VARYING_3;

void main()
{
    vec3 _952 = vec3((convergence_offset_x_r), (convergence_offset_x_g), (convergence_offset_x_b)) * RA_VARYING_4.xxx;
    vec2 _1024 = (RA_VARYING_1 - vec2(_952.x, 0.0)) * (vec4(Pass2TextureSize, 1.0 / Pass2TextureSize)).xy;
    vec2 _1030 = floor(_1024 - vec2(0.4995000064373016357421875)) + vec2(0.5);
    float _1032 = _1030.x;
    vec2 _1038 = vec2(_1032, _1024.y) * RA_VARYING_4;
    float _1043 = _1024.x - _1032;
    vec4 _1051 = vec4(1.0 + _1043, _1043, 1.0 - _1043, 2.0 - _1043);
    bool _1054 = (beam_horiz_filter) < 0.5;
    vec4 _2425;
    if (_1054)
    {
        float _1069 = ((_1043 * _1043) * _1043) * ((_1043 * ((_1043 * 6.0) - 15.0)) + 10.0);
        _2425 = vec4(0.0, 1.0 - _1069, _1069, 0.0);
    }
    else
    {
        vec4 _2426;
        if ((beam_horiz_filter) < 1.5)
        {
            _2426 = exp((-(_1051 * _1051)) * (1.0 / ((2.0 * (beam_horiz_sigma)) * (beam_horiz_sigma))));
        }
        else
        {
            vec4 _1099 = max(abs(_1051 * 3.1415927410125732421875), vec4(1.52587890625e-05));
            _2426 = ((sin(_1099) * 2.0) * sin(_1099 * 0.5)) / (_1099 * _1099);
        }
        _2425 = _2426;
    }
    vec4 _1117 = _2425 / vec4(dot(_2425, vec4(1.0)));
    vec2 _1120 = vec2(RA_VARYING_4.x, 0.0);
    vec4 _1138 = texture2D(Pass2Texture, _1038);
    vec4 _1144 = texture2D(Pass2Texture, _1038 + _1120);
    bool _1148 = (beam_horiz_filter) > 0.5;
    vec3 _2429;
    vec3 _2432;
    if (_1148)
    {
        _2432 = texture2D(Pass2Texture, _1038 + (_1120 * 2.0)).xyz;
        _2429 = texture2D(Pass2Texture, _1038 - _1120).xyz;
    }
    else
    {
        _2432 = vec3(0.0);
        _2429 = vec3(0.0);
    }
    vec3 _1218 = vec3((beam_horiz_linear_rgb_weight));
    vec2 _1297 = (RA_VARYING_1 - vec2(_952.y, 0.0)) * (vec4(Pass2TextureSize, 1.0 / Pass2TextureSize)).xy;
    vec2 _1303 = floor(_1297 - vec2(0.4995000064373016357421875)) + vec2(0.5);
    float _1305 = _1303.x;
    vec2 _1311 = vec2(_1305, _1297.y) * RA_VARYING_4;
    float _1316 = _1297.x - _1305;
    vec4 _1324 = vec4(1.0 + _1316, _1316, 1.0 - _1316, 2.0 - _1316);
    vec4 _2452;
    if (_1054)
    {
        float _1342 = ((_1316 * _1316) * _1316) * ((_1316 * ((_1316 * 6.0) - 15.0)) + 10.0);
        _2452 = vec4(0.0, 1.0 - _1342, _1342, 0.0);
    }
    else
    {
        vec4 _2453;
        if ((beam_horiz_filter) < 1.5)
        {
            _2453 = exp((-(_1324 * _1324)) * (1.0 / ((2.0 * (beam_horiz_sigma)) * (beam_horiz_sigma))));
        }
        else
        {
            vec4 _1372 = max(abs(_1324 * 3.1415927410125732421875), vec4(1.52587890625e-05));
            _2453 = ((sin(_1372) * 2.0) * sin(_1372 * 0.5)) / (_1372 * _1372);
        }
        _2452 = _2453;
    }
    vec4 _1390 = _2452 / vec4(dot(_2452, vec4(1.0)));
    vec4 _1411 = texture2D(Pass2Texture, _1311);
    vec4 _1417 = texture2D(Pass2Texture, _1311 + _1120);
    vec3 _2456;
    vec3 _2459;
    if (_1148)
    {
        _2459 = texture2D(Pass2Texture, _1311 + (_1120 * 2.0)).xyz;
        _2456 = texture2D(Pass2Texture, _1311 - _1120).xyz;
    }
    else
    {
        _2459 = vec3(0.0);
        _2456 = vec3(0.0);
    }
    vec2 _1570 = (RA_VARYING_1 - vec2(_952.z, 0.0)) * (vec4(Pass2TextureSize, 1.0 / Pass2TextureSize)).xy;
    vec2 _1576 = floor(_1570 - vec2(0.4995000064373016357421875)) + vec2(0.5);
    float _1578 = _1576.x;
    vec2 _1584 = vec2(_1578, _1570.y) * RA_VARYING_4;
    float _1589 = _1570.x - _1578;
    vec4 _1597 = vec4(1.0 + _1589, _1589, 1.0 - _1589, 2.0 - _1589);
    vec4 _2482;
    if (_1054)
    {
        float _1615 = ((_1589 * _1589) * _1589) * ((_1589 * ((_1589 * 6.0) - 15.0)) + 10.0);
        _2482 = vec4(0.0, 1.0 - _1615, _1615, 0.0);
    }
    else
    {
        vec4 _2483;
        if ((beam_horiz_filter) < 1.5)
        {
            _2483 = exp((-(_1597 * _1597)) * (1.0 / ((2.0 * (beam_horiz_sigma)) * (beam_horiz_sigma))));
        }
        else
        {
            vec4 _1645 = max(abs(_1597 * 3.1415927410125732421875), vec4(1.52587890625e-05));
            _2483 = ((sin(_1645) * 2.0) * sin(_1645 * 0.5)) / (_1645 * _1645);
        }
        _2482 = _2483;
    }
    vec4 _1663 = _2482 / vec4(dot(_2482, vec4(1.0)));
    vec4 _1684 = texture2D(Pass2Texture, _1584);
    vec4 _1690 = texture2D(Pass2Texture, _1584 + _1120);
    vec3 _2486;
    vec3 _2489;
    if (_1148)
    {
        _2489 = texture2D(Pass2Texture, _1584 + (_1120 * 2.0)).xyz;
        _2486 = texture2D(Pass2Texture, _1584 - _1120).xyz;
    }
    else
    {
        _2489 = vec3(0.0);
        _2486 = vec3(0.0);
    }
    float _2126;
    vec2 _809 = RA_VARYING_0 * RA_VARYING_6;
    vec2 _2508;
    do
    {
        _2126 = (mask_sample_mode_desired);
        if (_2126 < 0.5)
        {
            _2508 = RA_VARYING_5.xy + ((fract(_809 * 0.5) * 2.0) * RA_VARYING_5.zw);
            break;
        }
        else
        {
            _2508 = _809;
            break;
        }
        break; // unreachable workaround
    } while(false);
    vec3 _2575;
    if (_2126 > 0.5)
    {
        vec3 _2576;
        if ((mask_type) < 0.5)
        {
            _2576 = texture2D(mask_grille_texture_large, _2508).xyz;
        }
        else
        {
            vec3 _2577;
            if ((mask_type) < 1.5)
            {
                _2577 = texture2D(mask_slot_texture_large, _2508).xyz;
            }
            else
            {
                _2577 = texture2D(mask_shadow_texture_large, _2508).xyz;
            }
            _2576 = _2577;
        }
        _2575 = _2576;
    }
    else
    {
        _2575 = texture2D(Pass7Texture, _2508).xyz;
    }
    vec3 _881 = mix(vec3(mix(max(mat4x3(pow(_2429, vec3(0.454545438289642333984375)), pow(_1138.xyz, vec3(0.454545438289642333984375)), pow(_1144.xyz, vec3(0.454545438289642333984375)), pow(_2432, vec3(0.454545438289642333984375))) * _1117, vec3(0.0)), max(mat4x3(_2429, vec3(_1138.xyz), vec3(_1144.xyz), _2432) * _1117, vec3(0.0)), _1218).x, mix(max(mat4x3(pow(_2456, vec3(0.454545438289642333984375)), pow(_1411.xyz, vec3(0.454545438289642333984375)), pow(_1417.xyz, vec3(0.454545438289642333984375)), pow(_2459, vec3(0.454545438289642333984375))) * _1390, vec3(0.0)), max(mat4x3(_2456, vec3(_1411.xyz), vec3(_1417.xyz), _2459) * _1390, vec3(0.0)), _1218).y, mix(max(mat4x3(pow(_2486, vec3(0.454545438289642333984375)), pow(_1684.xyz, vec3(0.454545438289642333984375)), pow(_1690.xyz, vec3(0.454545438289642333984375)), pow(_2489, vec3(0.454545438289642333984375))) * _1663, vec3(0.0)), max(mat4x3(_2486, vec3(_1684.xyz), vec3(_1690.xyz), _2489) * _1663, vec3(0.0)), _1218).z), vec3(dot(texture2D(Pass5Texture, RA_VARYING_3).xyz, vec3(0.16666667163372039794921875))), vec3((halation_weight)));
    gl_FragData[0] = vec4(_881 * _2575, 1.0);
}


#endif
