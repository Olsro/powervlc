// Generated from crt/shaders/crt-royale/src/crt-royale-mask-resize-vertical.slang. See slang/upstream for licence/source.
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
uniform float geom_aspect_ratio_x;
uniform float geom_aspect_ratio_y;
uniform float mask_num_triads_desired;
uniform float mask_sample_mode_desired;
uniform float mask_specify_num_triads;
uniform float mask_triad_size_desired;
float _527;

struct UBO
{
    mat4 MVP;
    float mask_sample_mode_desired;
    float mask_num_triads_desired;
    float mask_triad_size_desired;
    float mask_specify_num_triads;
    float geom_aspect_ratio_x;
    float geom_aspect_ratio_y;
};



struct Push
{
    vec4 SourceSize;
    vec4 OutputSize;
};



attribute vec4 VertexCoord;
attribute vec2 TexCoord;
varying vec2 RA_VARYING_0;
varying vec2 RA_VARYING_1;

void main()
{
    gl_Position = (MVPMatrix) * VertexCoord;
    float _345 = (geom_aspect_ratio_x) / (geom_aspect_ratio_y);
    vec2 _505;
    do
    {
        float _447 = 8.0 * mix((mask_triad_size_desired), (((vec4(OutputSize, 1.0 / OutputSize)).y * 16.0) * _345) / (mask_num_triads_desired), (mask_specify_num_triads));
        if ((mask_sample_mode_desired) > 0.5)
        {
            _505 = vec2(1.0) * _447;
            break;
        }
        vec2 _472 = clamp(vec2(1.0) * min(_447, 64.0), vec2(1.0) * ceil(16.0), vec2((vec4(OutputSize, 1.0 / OutputSize)).y * _345, (vec4(OutputSize, 1.0 / OutputSize)).y) * vec2(0.5));
        float _474 = _472.y;
        _505 = floor(vec2(_527, min(_474, _474)) + vec2(1.52587890625e-05));
        break;
    } while(false);
    vec2 _375 = vec2(min(64.0, (vec4(OutputSize, 1.0 / OutputSize)).x), _505.y);
    RA_VARYING_0 = TexCoord * ((vec4(OutputSize, 1.0 / OutputSize)).xy / _375);
    RA_VARYING_1 = _375 * vec2(0.015625);
}


#endif
#ifdef FRAGMENT

uniform float mask_sample_mode_desired;
uniform float mask_type;
float _1445;

struct UBO
{
    float mask_type;
    float mask_sample_mode_desired;
};



uniform sampler2D mask_grille_texture_small;
uniform sampler2D mask_slot_texture_small;
uniform sampler2D mask_shadow_texture_small;

varying vec2 RA_VARYING_0;
varying vec2 RA_VARYING_1;

void main()
{
    float _230 = ceil(96.0 / ceil(16.0)) * 4.0;
    bool _495 = (mask_sample_mode_desired) < 0.5;
    bool _502;
    if (_495)
    {
        _502 = RA_VARYING_0.y <= 2.0;
    }
    else
    {
        _502 = _495;
    }
    if (_502)
    {
        vec2 _511 = fract(RA_VARYING_0);
        vec3 _1381;
        if ((mask_type) < 0.5)
        {
            int _619 = int(_230);
            vec2 _767 = _511 * vec2(64.0);
            vec2 _779 = (floor(_767 - vec2(0.4995000064373016357421875)) + vec2(0.5)) - vec2((float(_619) * 0.5) - 1.0);
            vec2 _788 = (_779 * 0.015625) * 1.0;
            vec2 _811 = vec2((fract(_788) + vec2(_1445, float(_788.y < 0.0))).y, (_767 - _779).y);
            vec4 _630 = _811.xxxx;
            vec4 _632 = _811.yyyy;
            vec4 _1379;
            vec3 _1380;
            _1380 = vec3(0.0);
            _1379 = vec4(0.0);
            for (int _1377 = 0; _1377 < _619; )
            {
                vec4 _647 = vec4(float(_1377)) + vec4(0.0, 1.0, 2.0, 3.0);
                vec4 _656 = fract(_630 + (_647 * 0.015625)) * 1.0;
                float _658 = _511.x;
                vec4 _690 = abs(_632 - _647) * RA_VARYING_1.y;
                vec4 _693 = _690 * 3.1415927410125732421875;
                vec4 _696 = _690 * 1.0471975803375244140625;
                vec4 _706 = min((sin(_693) * sin(_696)) / (_693 * _696), vec4(1.0));
                _1380 = (((_1380 + (texture2D(mask_grille_texture_small, vec2(_658, _656.x)).xyz * _706.xxx)) + (texture2D(mask_grille_texture_small, vec2(_658, _656.y)).xyz * _706.yyy)) + (texture2D(mask_grille_texture_small, vec2(_658, _656.z)).xyz * _706.zzz)) + (texture2D(mask_grille_texture_small, vec2(_658, _656.w)).xyz * _706.www);
                _1379 += _706;
                _1377 += 4;
                continue;
            }
            vec2 _743 = _1379.xy + _1379.zw;
            _1381 = _1380 / vec3(_743.x + _743.y);
        }
        else
        {
            vec3 _1382;
            if ((mask_type) < 1.5)
            {
                int _874 = int(_230);
                vec2 _1022 = _511 * vec2(64.0);
                vec2 _1034 = (floor(_1022 - vec2(0.4995000064373016357421875)) + vec2(0.5)) - vec2((float(_874) * 0.5) - 1.0);
                vec2 _1043 = (_1034 * 0.015625) * 1.0;
                vec2 _1066 = vec2((fract(_1043) + vec2(_1445, float(_1043.y < 0.0))).y, (_1022 - _1034).y);
                vec4 _885 = _1066.xxxx;
                vec4 _887 = _1066.yyyy;
                vec4 _1366;
                vec3 _1367;
                _1367 = vec3(0.0);
                _1366 = vec4(0.0);
                for (int _1364 = 0; _1364 < _874; )
                {
                    vec4 _902 = vec4(float(_1364)) + vec4(0.0, 1.0, 2.0, 3.0);
                    vec4 _911 = fract(_885 + (_902 * 0.015625)) * 1.0;
                    float _913 = _511.x;
                    vec4 _945 = abs(_887 - _902) * RA_VARYING_1.y;
                    vec4 _948 = _945 * 3.1415927410125732421875;
                    vec4 _951 = _945 * 1.0471975803375244140625;
                    vec4 _961 = min((sin(_948) * sin(_951)) / (_948 * _951), vec4(1.0));
                    _1367 = (((_1367 + (texture2D(mask_slot_texture_small, vec2(_913, _911.x)).xyz * _961.xxx)) + (texture2D(mask_slot_texture_small, vec2(_913, _911.y)).xyz * _961.yyy)) + (texture2D(mask_slot_texture_small, vec2(_913, _911.z)).xyz * _961.zzz)) + (texture2D(mask_slot_texture_small, vec2(_913, _911.w)).xyz * _961.www);
                    _1366 += _961;
                    _1364 += 4;
                    continue;
                }
                vec2 _998 = _1366.xy + _1366.zw;
                _1382 = _1367 / vec3(_998.x + _998.y);
            }
            else
            {
                int _1129 = int(_230);
                vec2 _1277 = _511 * vec2(64.0);
                vec2 _1289 = (floor(_1277 - vec2(0.4995000064373016357421875)) + vec2(0.5)) - vec2((float(_1129) * 0.5) - 1.0);
                vec2 _1298 = (_1289 * 0.015625) * 1.0;
                vec2 _1321 = vec2((fract(_1298) + vec2(_1445, float(_1298.y < 0.0))).y, (_1277 - _1289).y);
                vec4 _1140 = _1321.xxxx;
                vec4 _1142 = _1321.yyyy;
                vec4 _1351;
                vec3 _1352;
                _1352 = vec3(0.0);
                _1351 = vec4(0.0);
                for (int _1349 = 0; _1349 < _1129; )
                {
                    vec4 _1157 = vec4(float(_1349)) + vec4(0.0, 1.0, 2.0, 3.0);
                    vec4 _1166 = fract(_1140 + (_1157 * 0.015625)) * 1.0;
                    float _1168 = _511.x;
                    vec4 _1200 = abs(_1142 - _1157) * RA_VARYING_1.y;
                    vec4 _1203 = _1200 * 3.1415927410125732421875;
                    vec4 _1206 = _1200 * 1.0471975803375244140625;
                    vec4 _1216 = min((sin(_1203) * sin(_1206)) / (_1203 * _1206), vec4(1.0));
                    _1352 = (((_1352 + (texture2D(mask_shadow_texture_small, vec2(_1168, _1166.x)).xyz * _1216.xxx)) + (texture2D(mask_shadow_texture_small, vec2(_1168, _1166.y)).xyz * _1216.yyy)) + (texture2D(mask_shadow_texture_small, vec2(_1168, _1166.z)).xyz * _1216.zzz)) + (texture2D(mask_shadow_texture_small, vec2(_1168, _1166.w)).xyz * _1216.www);
                    _1351 += _1216;
                    _1349 += 4;
                    continue;
                }
                vec2 _1253 = _1351.xy + _1351.zw;
                _1382 = _1352 / vec3(_1253.x + _1253.y);
            }
            _1381 = _1382;
        }
        gl_FragData[0] = vec4(_1381, 1.0);
    }
    else
    {
        discard;
    }
}


#endif
