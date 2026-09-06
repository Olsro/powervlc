// Generated from crt/shaders/crt-royale/src-fast/crt-royale-mask-resize-horizontal.slang. See slang/upstream for licence/source.
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
    vec2 _431 = clamp(vec2(1.0) * min(8.0 * mix((mask_triad_size_desired), ((vec4(OutputSize, 1.0 / OutputSize)).xy * vec2(16.0)).x / (mask_num_triads_desired), (mask_specify_num_triads)), 64.0), vec2(1.0) * ceil(16.0), (vec4(OutputSize, 1.0 / OutputSize)).xy / vec2(1.0 + (ceil(0.5) * 0.125)));
    float _433 = _431.y;
    vec2 _456 = floor(vec2(min(_431.x, _433), min(_433, _433)) + vec2(1.52587890625e-05));
    RA_VARYING_1 = TexCoord * ((vec4(OutputSize, 1.0 / OutputSize)).xy / _456);
    vec2 _352 = vec2(min(64.0, (vec4(TextureSize, 1.0 / TextureSize)).x), _456.y);
    RA_VARYING_4 = _352 / (vec4(TextureSize, 1.0 / TextureSize)).xy;
    RA_VARYING_5 = (vec4(TextureSize, 1.0 / TextureSize)).xy / _352;
    RA_VARYING_0 = RA_VARYING_1 * RA_VARYING_4;
    RA_VARYING_2 = _456 / _352;
    RA_VARYING_3 = vec2(1.0 / (vec4(TextureSize, 1.0 / TextureSize)).x, 0.0);
}


#endif
#ifdef FRAGMENT

uniform vec2 TextureSize;
float _829;

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
    if (max(RA_VARYING_1.x, RA_VARYING_1.y) <= (1.0 + (ceil(0.5) * 0.125)))
    {
        vec2 _502 = fract(RA_VARYING_0);
        int _574 = int(ceil(96.0 / ceil(16.0)) * 4.0);
        float _576 = 1.0 / RA_VARYING_4.x;
        vec2 _722 = _502 * (vec4(TextureSize, 1.0 / TextureSize)).xy;
        vec2 _734 = (floor(_722 - vec2(0.4995000064373016357421875)) + vec2(0.5)) - vec2((float(_574) * 0.5) - 1.0);
        vec2 _743 = (_734 * RA_VARYING_3.x) * _576;
        vec2 _761 = vec2((fract(_743) + vec2(float(_743.x < 0.0), _829)).x, (_722 - _734).x);
        vec4 _585 = _761.xxxx;
        vec4 _587 = _761.yyyy;
        float _590 = RA_VARYING_3.x * _576;
        vec4 _794;
        vec3 _795;
        _795 = vec3(0.0);
        _794 = vec4(0.0);
        for (int _792 = 0; _792 < _574; )
        {
            vec4 _602 = vec4(float(_792)) + vec4(0.0, 1.0, 2.0, 3.0);
            vec4 _611 = fract(_585 + (_602 * _590)) * RA_VARYING_4.x;
            float _615 = _502.y;
            vec4 _645 = abs(_587 - _602) * RA_VARYING_2.x;
            vec4 _648 = _645 * 3.1415927410125732421875;
            vec4 _651 = _645 * 1.0471975803375244140625;
            vec4 _661 = min((sin(_648) * sin(_651)) / (_648 * _651), vec4(1.0));
            _795 = (((_795 + (texture2D(Texture, vec2(_611.x, _615)).xyz * _661.xxx)) + (texture2D(Texture, vec2(_611.y, _615)).xyz * _661.yyy)) + (texture2D(Texture, vec2(_611.z, _615)).xyz * _661.zzz)) + (texture2D(Texture, vec2(_611.w, _615)).xyz * _661.www);
            _794 += _661;
            _792 += 4;
            continue;
        }
        vec2 _698 = _794.xy + _794.zw;
        gl_FragData[0] = vec4(_795 / vec3(_698.x + _698.y), 1.0);
    }
    else
    {
        discard;
    }
}


#endif
