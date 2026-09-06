// Generated from crt/shaders/crt-royale/src/crt-royale-first-pass-linearize-crt-gamma-bob-fields.slang. See slang/upstream for licence/source.
#version 130
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
uniform vec2 TextureSize;
uniform float interlace_1080i;
uniform float interlace_detect_toggle;
struct UBO
{
    mat4 MVP;
    float interlace_1080i;
    float interlace_detect_toggle;
};



struct Push
{
    vec4 SourceSize;
};



in vec4 VertexCoord;
out vec2 RA_VARYING_0;
in vec2 TexCoord;
out vec2 RA_VARYING_1;
out float RA_VARYING_2;

void main()
{
    gl_Position = (MVPMatrix) * VertexCoord;
    RA_VARYING_0 = TexCoord * 1.000010013580322265625;
    RA_VARYING_1 = vec2(1.0) / (vec4(TextureSize, 1.0 / TextureSize)).xy;
    bool _314;
    do
    {
        if ((interlace_detect_toggle) != 0.0)
        {
            bool _312;
            if ((interlace_1080i) != 0.0)
            {
                _312 = ((vec4(TextureSize, 1.0 / TextureSize)).y > 1079.5) && ((vec4(TextureSize, 1.0 / TextureSize)).y < 1080.5);
            }
            else
            {
                _312 = false;
            }
            _314 = (((vec4(TextureSize, 1.0 / TextureSize)).y > 288.5) && ((vec4(TextureSize, 1.0 / TextureSize)).y < 576.5)) || _312;
            break;
        }
        else
        {
            _314 = false;
            break;
        }
        break; // unreachable workaround
    } while(false);
    RA_VARYING_2 = float(_314);
}


#endif
#ifdef FRAGMENT

uniform int FrameCount;
uniform vec2 TextureSize;
uniform float crt_gamma;
uniform float interlace_bff;
uniform float interlace_detect_toggle;
float _787;

struct UBO
{
    float crt_gamma;
    float interlace_bff;
    float interlace_detect_toggle;
};



struct Push
{
    vec4 SourceSize;
    uint FrameCount;
};



uniform sampler2D Texture;

in vec2 RA_VARYING_1;
in vec2 RA_VARYING_0;
in float RA_VARYING_2;
out vec4 FragColor;

void main()
{
    if ((interlace_detect_toggle) != 0.0)
    {
        vec2 _315 = vec2(0.0, RA_VARYING_1.y);
        vec3 _443 = vec3((crt_gamma));
        float _346 = RA_VARYING_2 + 1.0;
        FragColor = vec4(mix(vec4(pow(texture(Texture, RA_VARYING_0).xyz, _443), _787).xyz, (vec4(pow(texture(Texture, RA_VARYING_0 - _315).xyz, _443), _787).xyz + vec4(pow(texture(Texture, RA_VARYING_0 + _315).xyz, _443), _787).xyz) * 0.5, vec3(mod(floor((RA_VARYING_0.y * (vec4(TextureSize, 1.0 / TextureSize)).y) - 0.4995000064373016357421875) + mod(float((uint(FrameCount))) + (interlace_bff), _346), _346))), 1.0);
    }
    else
    {
        vec4 _650 = texture(Texture, RA_VARYING_0);
        FragColor = vec4(pow(_650.xyz, vec3((crt_gamma))), _650.w);
    }
}


#endif
