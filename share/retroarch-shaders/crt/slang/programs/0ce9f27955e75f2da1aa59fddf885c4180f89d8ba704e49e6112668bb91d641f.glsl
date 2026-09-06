// Generated from crt/shaders/crt-royale/src-fast/crt-royale-brightpass.slang. See slang/upstream for licence/source.
#version 120
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
uniform float levels_contrast;
uniform float mask_num_triads_desired;
uniform float mask_specify_num_triads;
uniform float mask_triad_size_desired;
uniform float mask_type;
float _563;

struct UBO
{
    mat4 MVP;
    float levels_contrast;
    float mask_type;
    float mask_num_triads_desired;
    float mask_triad_size_desired;
    float mask_specify_num_triads;
};



struct Push
{
    vec4 OutputSize;
};



attribute vec4 VertexCoord;
varying vec2 RA_VARYING_0;
attribute vec2 TexCoord;
varying float RA_VARYING_1;
varying float RA_VARYING_2;

void main()
{
    gl_Position = (MVPMatrix) * VertexCoord;
    RA_VARYING_0 = TexCoord;
    vec2 _468 = clamp(vec2(1.0) * min(8.0 * mix((mask_triad_size_desired), (vec4(OutputSize, 1.0 / OutputSize)).x / (mask_num_triads_desired), (mask_specify_num_triads)), 64.0), vec2(1.0) * ceil(16.0), ((vec4(OutputSize, 1.0 / OutputSize)).xy * vec2(0.0625)) / vec2(1.0 + (ceil(0.5) * 0.125)));
    vec2 _493 = floor(vec2(min(_468.x, _468.y), _563) + vec2(1.52587890625e-05));
    float _390 = _493.x;
    float _506 = ((-0.0516799986362457275390625) + (_390 * 0.076412498950958251953125)) - (_390 * 0.0092205703258514404296875);
    RA_VARYING_1 = min(exp(exp(0.3483484089374542236328125 / (_506 - 0.086058728396892547607421875))), 0.3993345797061920166015625 / _506);
    float _543;
    if ((mask_type) < 0.5)
    {
        _543 = 4.811320781707763671875;
    }
    else
    {
        _543 = ((mask_type) < 1.5) ? 5.5434780120849609375 : 6.21951198577880859375;
    }
    RA_VARYING_2 = (2.0 * _543) * (levels_contrast);
}


#endif
#ifdef FRAGMENT

uniform float bloom_excess;
uniform float bloom_underestimate_levels;
uniform float levels_contrast;
struct UBO
{
    float levels_contrast;
    float bloom_underestimate_levels;
    float bloom_excess;
};



uniform sampler2D Pass5Texture;
uniform sampler2D Pass1Texture;

varying vec2 RA_VARYING_0;
varying float RA_VARYING_2;
varying float RA_VARYING_1;

void main()
{
    vec3 _207 = texture2D(Pass5Texture, RA_VARYING_0).xyz;
    vec3 _213 = _207 * RA_VARYING_2;
    gl_FragData[0] = vec4(_207 * mix(clamp((((vec3(1.0) - (max(vec3(0.0), (texture2D(Pass1Texture, RA_VARYING_0).xyz * (levels_contrast)) - (_213 * RA_VARYING_1)) * (bloom_underestimate_levels))) / (_213 * (bloom_underestimate_levels))) - vec3(1.0)) / vec3(RA_VARYING_1 - 1.0), vec3(0.0), vec3(1.0)), vec3(1.0), vec3((bloom_excess))), 1.0);
}


#endif
