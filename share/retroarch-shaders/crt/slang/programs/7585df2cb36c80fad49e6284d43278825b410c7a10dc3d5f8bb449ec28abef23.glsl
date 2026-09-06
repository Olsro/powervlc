// Generated from crt/shaders/crt-royale/src-fast/crt-royale-bloom-vertical.slang. See slang/upstream for licence/source.
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
uniform vec2 TextureSize;
uniform float mask_num_triads_desired;
uniform float mask_specify_num_triads;
uniform float mask_triad_size_desired;
float _752;

struct UBO
{
    mat4 MVP;
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
varying vec4 RA_VARYING_3;
varying vec4 RA_VARYING_4;
varying float RA_VARYING_5;

void main()
{
    gl_Position = (MVPMatrix) * VertexCoord;
    RA_VARYING_0 = TexCoord * 1.00010001659393310546875;
    RA_VARYING_1 = vec2(0.0, (((vec4(TextureSize, 1.0 / TextureSize)).xy / (vec4(OutputSize, 1.0 / OutputSize)).xy) / (vec4(TextureSize, 1.0 / TextureSize)).xy).y);
    vec2 _552 = clamp(vec2(1.0) * min(8.0 * mix((mask_triad_size_desired), (vec4(OutputSize, 1.0 / OutputSize)).x / (mask_num_triads_desired), (mask_specify_num_triads)), 64.0), vec2(1.0) * ceil(16.0), ((vec4(OutputSize, 1.0 / OutputSize)).xy * vec2(0.0625)) / vec2(1.0 + (ceil(0.5) * 0.125)));
    vec2 _577 = floor(vec2(min(_552.x, _552.y), _752) + vec2(1.52587890625e-05));
    float _474 = _577.x;
    RA_VARYING_2 = ((-0.0516799986362457275390625) + (_474 * 0.076412498950958251953125)) - (_474 * 0.0092205703258514404296875);
    float _606 = RA_VARYING_2 * RA_VARYING_2;
    float _613 = exp((-2.0) / _606);
    float _619 = exp((-8.0) / _606);
    float _625 = exp((-18.0) / _606);
    float _631 = exp((-32.0) / _606);
    float _634 = exp((-0.5) / _606) + _613;
    float _638 = exp((-4.5) / _606) + _619;
    float _642 = exp((-12.5) / _606) + _625;
    float _646 = exp((-24.5) / _606) + _631;
    RA_VARYING_3 = vec4(_634, _638, _642, _646);
    RA_VARYING_4 = vec4(_613 / _634, _619 / _638, _625 / _642, _631 / _646);
    RA_VARYING_5 = min(exp(exp(0.3483484089374542236328125 / (RA_VARYING_2 - 0.086058728396892547607421875))), 0.3993345797061920166015625 / RA_VARYING_2);
}


#endif
#ifdef FRAGMENT


uniform sampler2D Texture;

varying vec2 RA_VARYING_0;
varying vec2 RA_VARYING_1;
varying float RA_VARYING_5;
varying vec4 RA_VARYING_3;
varying vec4 RA_VARYING_4;

void main()
{
    vec2 _391 = RA_VARYING_1 * (7.0 + RA_VARYING_4.w);
    vec2 _406 = RA_VARYING_1 * (5.0 + RA_VARYING_4.z);
    vec2 _421 = RA_VARYING_1 * (3.0 + RA_VARYING_4.y);
    vec2 _436 = RA_VARYING_1 * (1.0 + RA_VARYING_4.x);
    vec3 _513 = (((((((((texture2D(Texture, RA_VARYING_0 - _391).xyz * RA_VARYING_3.w) + (texture2D(Texture, RA_VARYING_0 - _406).xyz * RA_VARYING_3.z)) + (texture2D(Texture, RA_VARYING_0 - _421).xyz * RA_VARYING_3.y)) + (texture2D(Texture, RA_VARYING_0 - _436).xyz * RA_VARYING_3.x)) + (texture2D(Texture, RA_VARYING_0).xyz * 1.0)) + (texture2D(Texture, RA_VARYING_0 + _436).xyz * RA_VARYING_3.x)) + (texture2D(Texture, RA_VARYING_0 + _421).xyz * RA_VARYING_3.y)) + (texture2D(Texture, RA_VARYING_0 + _406).xyz * RA_VARYING_3.z)) + (texture2D(Texture, RA_VARYING_0 + _391).xyz * RA_VARYING_3.w)) * RA_VARYING_5;
    gl_FragData[0] = vec4(_513, 1.0);
}


#endif
