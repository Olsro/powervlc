// Generated from crt/shaders/crt-royale/src/crt-royale-mask-resize-horizontal.slang. See slang/upstream for licence/source.
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
};



attribute vec4 VertexCoord;
attribute vec2 TexCoord;
varying vec2 RA_VARYING_1;
varying vec2 RA_VARYING_4;
varying vec2 RA_VARYING_5;
varying vec2 RA_VARYING_0;
varying vec2 RA_VARYING_2;
varying vec2 RA_VARYING_3;

void main()
{
    gl_Position = (MVPMatrix) * VertexCoord;
    vec2 _504;
    do
    {
        float _446 = 8.0 * mix((mask_triad_size_desired), ((vec4(OutputSize, 1.0 / OutputSize)).xy * vec2(16.0)).x / (mask_num_triads_desired), (mask_specify_num_triads));
        if ((mask_sample_mode_desired) > 0.5)
        {
            _504 = vec2(1.0) * _446;
            break;
        }
        vec2 _471 = clamp(vec2(1.0) * min(_446, 64.0), vec2(1.0) * ceil(16.0), (vec4(OutputSize, 1.0 / OutputSize)).xy * vec2(0.5));
        float _473 = _471.y;
        _504 = floor(vec2(min(_471.x, _473), min(_473, _473)) + vec2(1.52587890625e-05));
        break;
    } while(false);
    RA_VARYING_1 = TexCoord * ((vec4(OutputSize, 1.0 / OutputSize)).xy / _504);
    vec2 _377 = vec2(min(64.0, (vec4(TextureSize, 1.0 / TextureSize)).x), _504.y);
    RA_VARYING_4 = _377 / (vec4(TextureSize, 1.0 / TextureSize)).xy;
    RA_VARYING_5 = (vec4(TextureSize, 1.0 / TextureSize)).xy / _377;
    RA_VARYING_0 = RA_VARYING_1 * RA_VARYING_4;
    RA_VARYING_2 = _504 / _377;
    RA_VARYING_3 = vec2(1.0 / (vec4(TextureSize, 1.0 / TextureSize)).x, 0.0);
}


#endif
#ifdef FRAGMENT

uniform vec2 TextureSize;
uniform float mask_sample_mode_desired;
float _852;

struct UBO
{
    float mask_sample_mode_desired;
};



struct Push
{
    vec4 SourceSize;
};



uniform sampler2D Texture;

varying vec2 RA_VARYING_1;
varying vec2 RA_VARYING_3;
varying vec2 RA_VARYING_0;
varying vec2 RA_VARYING_2;
varying vec2 RA_VARYING_4;

void main()
{
    bool _495 = (mask_sample_mode_desired) < 0.5;
    bool _505;
    if (_495)
    {
        _505 = max(RA_VARYING_1.x, RA_VARYING_1.y) <= 2.0;
    }
    else
    {
        _505 = _495;
    }
    if (_505)
    {
        vec2 _516 = fract(RA_VARYING_0);
        int _592 = int(ceil(96.0 / ceil(16.0)) * 4.0);
        float _594 = 1.0 / RA_VARYING_4.x;
        vec2 _740 = _516 * (vec4(TextureSize, 1.0 / TextureSize)).xy;
        vec2 _752 = (floor(_740 - vec2(0.4995000064373016357421875)) + vec2(0.5)) - vec2((float(_592) * 0.5) - 1.0);
        vec2 _761 = (_752 * RA_VARYING_3.x) * _594;
        vec2 _779 = vec2((fract(_761) + vec2(float(_761.x < 0.0), _852)).x, (_740 - _752).x);
        vec4 _603 = _779.xxxx;
        vec4 _605 = _779.yyyy;
        float _608 = RA_VARYING_3.x * _594;
        vec4 _814;
        vec3 _815;
        _815 = vec3(0.0);
        _814 = vec4(0.0);
        for (int _812 = 0; _812 < _592; )
        {
            vec4 _620 = vec4(float(_812)) + vec4(0.0, 1.0, 2.0, 3.0);
            vec4 _629 = fract(_603 + (_620 * _608)) * RA_VARYING_4.x;
            float _633 = _516.y;
            vec4 _663 = abs(_605 - _620) * RA_VARYING_2.x;
            vec4 _666 = _663 * 3.1415927410125732421875;
            vec4 _669 = _663 * 1.0471975803375244140625;
            vec4 _679 = min((sin(_666) * sin(_669)) / (_666 * _669), vec4(1.0));
            _815 = (((_815 + (texture2D(Texture, vec2(_629.x, _633)).xyz * _679.xxx)) + (texture2D(Texture, vec2(_629.y, _633)).xyz * _679.yyy)) + (texture2D(Texture, vec2(_629.z, _633)).xyz * _679.zzz)) + (texture2D(Texture, vec2(_629.w, _633)).xyz * _679.www);
            _814 += _679;
            _812 += 4;
            continue;
        }
        vec2 _716 = _814.xy + _814.zw;
        gl_FragData[0] = vec4(_815 / vec3(_716.x + _716.y), 1.0);
    }
    else
    {
        discard;
    }
}


#endif
