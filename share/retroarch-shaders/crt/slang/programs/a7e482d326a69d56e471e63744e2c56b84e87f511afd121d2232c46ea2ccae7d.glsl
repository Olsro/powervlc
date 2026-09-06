// Generated from crt/shaders/crt-royale/src/crt-royale-scanlines-vertical-interlacing.slang. See slang/upstream for licence/source.
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
uniform vec2 OutputSize;
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
    vec4 OutputSize;
};



in vec4 VertexCoord;
out vec2 RA_VARYING_0;
in vec2 TexCoord;
out vec2 RA_VARYING_2;
out vec2 RA_VARYING_1;
out float RA_VARYING_3;

void main()
{
    gl_Position = (MVPMatrix) * VertexCoord;
    RA_VARYING_0 = TexCoord * 1.000010013580322265625;
    bool _332;
    do
    {
        if ((interlace_detect_toggle) != 0.0)
        {
            bool _330;
            if ((interlace_1080i) != 0.0)
            {
                _330 = ((vec4(TextureSize, 1.0 / TextureSize)).y > 1079.5) && ((vec4(TextureSize, 1.0 / TextureSize)).y < 1080.5);
            }
            else
            {
                _330 = false;
            }
            _332 = (((vec4(TextureSize, 1.0 / TextureSize)).y > 288.5) && ((vec4(TextureSize, 1.0 / TextureSize)).y < 576.5)) || _330;
            break;
        }
        else
        {
            _332 = false;
            break;
        }
        break; // unreachable workaround
    } while(false);
    RA_VARYING_2 = vec2(1.0, _332 ? 2.0 : 1.0);
    RA_VARYING_1 = RA_VARYING_2 / (vec4(TextureSize, 1.0 / TextureSize)).xy;
    RA_VARYING_3 = ((vec4(TextureSize, 1.0 / TextureSize)).y / (vec4(OutputSize, 1.0 / OutputSize)).y) / RA_VARYING_2.y;
}


#endif
#ifdef FRAGMENT

uniform int FrameCount;
uniform vec2 TextureSize;
uniform float beam_max_shape;
uniform float beam_max_sigma;
uniform float beam_min_shape;
uniform float beam_min_sigma;
uniform float beam_shape_power;
uniform float beam_spot_power;
uniform float convergence_offset_y_b;
uniform float convergence_offset_y_g;
uniform float convergence_offset_y_r;
uniform float interlace_bff;
struct UBO
{
    float beam_min_sigma;
    float beam_max_sigma;
    float beam_spot_power;
    float beam_min_shape;
    float beam_max_shape;
    float beam_shape_power;
    float convergence_offset_y_r;
    float convergence_offset_y_g;
    float convergence_offset_y_b;
    float interlace_bff;
};



struct Push
{
    vec4 SourceSize;
    uint FrameCount;
};



uniform sampler2D Texture;

in float RA_VARYING_3;
in vec2 RA_VARYING_0;
in vec2 RA_VARYING_2;
in vec2 RA_VARYING_1;
out vec4 FragColor;

void main()
{
    vec2 _1606 = RA_VARYING_0 * (vec4(TextureSize, 1.0 / TextureSize)).xy;
    vec2 _1611 = floor(_1606 - vec2(0.4995000064373016357421875));
    vec2 _1624 = (_1611 - vec2(0.0, mod(_1611.y + (floor(RA_VARYING_2.y * 0.75) * mod(float((uint(FrameCount))) + (interlace_bff), 2.0)), RA_VARYING_2.y))) + vec2(0.5);
    vec2 _1627 = _1624 * (vec2(1.0) / (vec4(TextureSize, 1.0 / TextureSize)).xy);
    float _1635 = (_1606.y - _1624.y) / RA_VARYING_2.y;
    vec2 _1163 = vec2(0.0, RA_VARYING_1.y);
    vec3 _1169 = texture(Texture, _1627).xyz;
    vec3 _1176 = texture(Texture, _1627 + _1163).xyz;
    float _1275 = round(_1635);
    vec3 _1289 = texture(Texture, _1627 + mix(-_1163, _1163 * 2.0, vec2(_1275))).xyz;
    vec3 _1301 = vec3(_1635) - vec3((convergence_offset_y_r), (convergence_offset_y_g), (convergence_offset_y_b));
    float _1311 = max((beam_max_sigma), (beam_min_sigma)) - (beam_min_sigma);
    float _1321 = max((beam_max_shape), (beam_min_shape)) - (beam_min_shape);
    vec3 _2835 = vec3((beam_min_sigma));
    vec3 _2840 = vec3((beam_spot_power));
    vec3 _2869 = vec3((beam_shape_power));
    vec3 _2872 = vec3((beam_min_shape));
    vec3 _2873 = _2872 + (pow(_1169, _2869) * _1321);
    vec3 _2751 = vec3(1.0) / ((_2835 + (pow(_1169, _2840) * _1311)) * 1.41421353816986083984375);
    vec3 _2753 = vec3(1.0) / _2873;
    vec3 _2769 = vec3(RA_VARYING_3 * 0.3333333432674407958984375);
    vec3 _1337 = abs(vec3(1.0) - _1301);
    vec3 _3858 = _2872 + (pow(_1176, _2869) * _1321);
    vec3 _3736 = vec3(1.0) / ((_2835 + (pow(_1176, _2840) * _1311)) * 1.41421353816986083984375);
    vec3 _3738 = vec3(1.0) / _3858;
    vec3 _1528 = mix(_1301 + vec3(1.0), vec3(2.0) - _1301, vec3(_1275));
    vec3 _13708 = _2872 + (pow(_1289, _2869) * _1321);
    vec3 _13586 = vec3(1.0) / ((_2835 + (pow(_1289, _2840) * _1311)) * 1.41421353816986083984375);
    vec3 _13588 = vec3(1.0) / _13708;
    vec3 _1543 = (((((((_1169 * _2873) * 0.5) * _2751) / ((pow((_2753 + vec3(1.62906825542449951171875)) * vec3(0.367879450321197509765625), _2753 + vec3(0.5)) * (vec3(0.810911953449249267578125) + (vec3(0.4808354675769805908203125) / (_2753 + vec3(1.0))))) * _2873)) * vec3(0.3333333432674407958984375)) * ((exp(-pow(abs(_1301 * _2751), _2873)) + exp(-pow(abs((_1301 + _2769) * _2751), _2873))) + exp(-pow(abs(abs(_1301 - _2769) * _2751), _2873)))) + ((((((_1176 * _3858) * 0.5) * _3736) / ((pow((_3738 + vec3(1.62906825542449951171875)) * vec3(0.367879450321197509765625), _3738 + vec3(0.5)) * (vec3(0.810911953449249267578125) + (vec3(0.4808354675769805908203125) / (_3738 + vec3(1.0))))) * _3858)) * vec3(0.3333333432674407958984375)) * ((exp(-pow(abs(_1337 * _3736), _3858)) + exp(-pow(abs((_1337 + _2769) * _3736), _3858))) + exp(-pow(abs(abs(_1337 - _2769) * _3736), _3858))))) + ((((((_1289 * _13708) * 0.5) * _13586) / ((pow((_13588 + vec3(1.62906825542449951171875)) * vec3(0.367879450321197509765625), _13588 + vec3(0.5)) * (vec3(0.810911953449249267578125) + (vec3(0.4808354675769805908203125) / (_13588 + vec3(1.0))))) * _13708)) * vec3(0.3333333432674407958984375)) * ((exp(-pow(abs(_1528 * _13586), _13708)) + exp(-pow(abs((_1528 + _2769) * _13586), _13708))) + exp(-pow(abs(abs(_1528 - _2769) * _13586), _13708))));
    FragColor = vec4(_1543 * 0.5, 1.0);
}


#endif
