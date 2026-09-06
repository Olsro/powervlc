// Generated from crt/shaders/crt-royale/src/crt-royale-bloom-vertical.slang. See slang/upstream for licence/source.
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
float _563;

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
varying vec2 RA_VARYING_0;
attribute vec2 TexCoord;
varying vec2 RA_VARYING_1;
varying float RA_VARYING_2;

void main()
{
    gl_Position = (MVPMatrix) * VertexCoord;
    RA_VARYING_0 = TexCoord * 1.00010001659393310546875;
    RA_VARYING_1 = vec2(0.0, (((vec4(TextureSize, 1.0 / TextureSize)).xy / (vec4(OutputSize, 1.0 / OutputSize)).xy) / (vec4(TextureSize, 1.0 / TextureSize)).xy).y);
    vec2 _536;
    do
    {
        float _466 = 8.0 * mix((mask_triad_size_desired), (vec4(OutputSize, 1.0 / OutputSize)).x / (mask_num_triads_desired), (mask_specify_num_triads));
        if ((mask_sample_mode_desired) > 0.5)
        {
            _536 = vec2(1.0) * _466;
            break;
        }
        vec2 _491 = clamp(vec2(1.0) * min(_466, 64.0), vec2(1.0) * ceil(16.0), (vec4(OutputSize, 1.0 / OutputSize)).xy * vec2(0.03125));
        _536 = floor(vec2(min(_491.x, _491.y), _563) + vec2(1.52587890625e-05));
        break;
    } while(false);
    RA_VARYING_2 = ((-0.0516799986362457275390625) + (_536.x * 0.076412498950958251953125)) - (_536.x * 0.0092205703258514404296875);
}


#endif
#ifdef FRAGMENT


uniform sampler2D Texture;

varying float RA_VARYING_2;
varying vec2 RA_VARYING_0;
varying vec2 RA_VARYING_1;

void main()
{
    float _742 = RA_VARYING_2 * RA_VARYING_2;
    float _749 = exp((-2.0) / _742);
    float _755 = exp((-8.0) / _742);
    float _761 = exp((-18.0) / _742);
    float _767 = exp((-32.0) / _742);
    float _772 = exp((-0.5) / _742) + _749;
    float _775 = exp((-4.5) / _742) + _755;
    float _778 = exp((-12.5) / _742) + _761;
    float _781 = exp((-24.5) / _742) + _767;
    vec2 _799 = RA_VARYING_1 * (7.0 + (_767 / _781));
    vec2 _811 = RA_VARYING_1 * (5.0 + (_761 / _778));
    vec2 _823 = RA_VARYING_1 * (3.0 + (_755 / _775));
    vec2 _835 = RA_VARYING_1 * (1.0 + (_749 / _772));
    gl_FragData[0] = vec4((((((((((texture2D(Texture, RA_VARYING_0 - _799).xyz * _781) + (texture2D(Texture, RA_VARYING_0 - _811).xyz * _778)) + (texture2D(Texture, RA_VARYING_0 - _823).xyz * _775)) + (texture2D(Texture, RA_VARYING_0 - _835).xyz * _772)) + (texture2D(Texture, RA_VARYING_0).xyz * 1.0)) + (texture2D(Texture, RA_VARYING_0 + _835).xyz * _772)) + (texture2D(Texture, RA_VARYING_0 + _823).xyz * _775)) + (texture2D(Texture, RA_VARYING_0 + _811).xyz * _778)) + (texture2D(Texture, RA_VARYING_0 + _799).xyz * _781)) * min(exp(exp(0.3483484089374542236328125 / (RA_VARYING_2 - 0.086058728396892547607421875))), 0.3993345797061920166015625 / RA_VARYING_2), 1.0);
}


#endif
