// Generated from crt/shaders/crt-royale/src/crt-royale-bloom-horizontal-reconstitute.slang. See slang/upstream for licence/source.
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
float _589;

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
    vec4 MASKED_SCANLINESSize;
    vec4 HALATION_BLURSize;
    vec4 BRIGHTPASSSize;
};



attribute vec4 VertexCoord;
attribute vec2 TexCoord;
varying vec2 RA_VARYING_1;
varying vec2 RA_VARYING_2;
varying vec2 RA_VARYING_3;
varying vec2 RA_VARYING_4;
varying vec2 RA_VARYING_5;
varying float RA_VARYING_6;
varying vec2 RA_VARYING_0;

void main()
{
    gl_Position = (MVPMatrix) * VertexCoord;
    RA_VARYING_1 = TexCoord;
    RA_VARYING_2 = TexCoord;
    RA_VARYING_3 = TexCoord;
    RA_VARYING_4 = TexCoord;
    RA_VARYING_5 = vec2(1.0 / (vec4(TextureSize, 1.0 / TextureSize)).x, 0.0);
    vec2 _564;
    do
    {
        float _494 = 8.0 * mix((mask_triad_size_desired), (vec4(OutputSize, 1.0 / OutputSize)).x / (mask_num_triads_desired), (mask_specify_num_triads));
        if ((mask_sample_mode_desired) > 0.5)
        {
            _564 = vec2(1.0) * _494;
            break;
        }
        vec2 _519 = clamp(vec2(1.0) * min(_494, 64.0), vec2(1.0) * ceil(16.0), (vec4(OutputSize, 1.0 / OutputSize)).xy * vec2(0.03125));
        _564 = floor(vec2(min(_519.x, _519.y), _589) + vec2(1.52587890625e-05));
        break;
    } while(false);
    RA_VARYING_6 = ((-0.0516799986362457275390625) + (_564.x * 0.076412498950958251953125)) - (_564.x * 0.0092205703258514404296875);
}


#endif
#ifdef FRAGMENT

uniform float diffusion_weight;
uniform float levels_contrast;
uniform float mask_type;
struct UBO
{
    float levels_contrast;
    float diffusion_weight;
    float mask_type;
};



uniform sampler2D Texture;
uniform sampler2D Pass8Texture;
uniform sampler2D Pass9Texture;
uniform sampler2D Pass5Texture;

varying float RA_VARYING_6;
varying vec2 RA_VARYING_4;
varying vec2 RA_VARYING_5;
varying vec2 RA_VARYING_1;
varying vec2 RA_VARYING_3;
varying vec2 RA_VARYING_2;

void main()
{
    float _826 = RA_VARYING_6 * RA_VARYING_6;
    float _833 = exp((-2.0) / _826);
    float _839 = exp((-8.0) / _826);
    float _845 = exp((-18.0) / _826);
    float _851 = exp((-32.0) / _826);
    float _856 = exp((-0.5) / _826) + _833;
    float _859 = exp((-4.5) / _826) + _839;
    float _862 = exp((-12.5) / _826) + _845;
    float _865 = exp((-24.5) / _826) + _851;
    vec2 _883 = RA_VARYING_5 * (7.0 + (_851 / _865));
    vec4 _999 = texture2D(Texture, RA_VARYING_4 - _883);
    vec2 _895 = RA_VARYING_5 * (5.0 + (_845 / _862));
    vec4 _1046 = texture2D(Texture, RA_VARYING_4 - _895);
    vec2 _907 = RA_VARYING_5 * (3.0 + (_839 / _859));
    vec4 _1093 = texture2D(Texture, RA_VARYING_4 - _907);
    vec2 _919 = RA_VARYING_5 * (1.0 + (_833 / _856));
    vec4 _1140 = texture2D(Texture, RA_VARYING_4 - _919);
    vec4 _1187 = texture2D(Texture, RA_VARYING_4);
    vec4 _1234 = texture2D(Texture, RA_VARYING_4 + _919);
    vec4 _1281 = texture2D(Texture, RA_VARYING_4 + _907);
    vec4 _1328 = texture2D(Texture, RA_VARYING_4 + _895);
    vec4 _1375 = texture2D(Texture, RA_VARYING_4 + _883);
    vec4 _1422 = texture2D(Pass8Texture, RA_VARYING_1);
    float _1784;
    if ((mask_type) < 0.5)
    {
        _1784 = 4.811320781707763671875;
    }
    else
    {
        _1784 = ((mask_type) < 1.5) ? 5.5434780120849609375 : 6.21951198577880859375;
    }
    vec3 _739 = mix(((((_1422.xyz - texture2D(Pass9Texture, RA_VARYING_3).xyz) + ((((((((((_999.xyz * _865) + (_1046.xyz * _862)) + (_1093.xyz * _859)) + (_1140.xyz * _856)) + (_1187.xyz * 1.0)) + (_1234.xyz * _856)) + (_1281.xyz * _859)) + (_1328.xyz * _862)) + (_1375.xyz * _865)) * min(exp(exp(0.3483484089374542236328125 / (RA_VARYING_6 - 0.086058728396892547607421875))), 0.3993345797061920166015625 / RA_VARYING_6))) * _1784) * 2.0) * (levels_contrast), texture2D(Pass5Texture, RA_VARYING_2).xyz * (levels_contrast), vec3((diffusion_weight)));
    gl_FragData[0] = vec4(_739, 1.0);
}


#endif
