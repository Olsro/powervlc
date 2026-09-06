// Generated from crt/shaders/crt-royale/src-fast/crt-royale-scanlines-vertical-interlacing.slang. See slang/upstream for licence/source.
#version 130
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
    bool _316;
    do
    {
        if ((interlace_detect_toggle) != 0.0)
        {
            bool _314;
            if ((interlace_1080i) != 0.0)
            {
                _314 = ((vec4(TextureSize, 1.0 / TextureSize)).y > 1079.5) && ((vec4(TextureSize, 1.0 / TextureSize)).y < 1080.5);
            }
            else
            {
                _314 = false;
            }
            _316 = (((vec4(TextureSize, 1.0 / TextureSize)).y > 288.5) && ((vec4(TextureSize, 1.0 / TextureSize)).y < 576.5)) || _314;
            break;
        }
        else
        {
            _316 = false;
            break;
        }
        break; // unreachable workaround
    } while(false);
    RA_VARYING_2 = vec2(1.0, _316 ? 2.0 : 1.0);
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
    vec2 _1217 = RA_VARYING_0 * (vec4(TextureSize, 1.0 / TextureSize)).xy;
    vec2 _1222 = floor(_1217 - vec2(0.4995000064373016357421875));
    vec2 _1235 = (_1222 - vec2(0.0, mod(_1222.y + (floor(RA_VARYING_2.y * 0.75) * mod(float((uint(FrameCount))) + (interlace_bff), 2.0)), RA_VARYING_2.y))) + vec2(0.5);
    vec2 _1238 = _1235 * (vec4(TextureSize, 1.0 / TextureSize)).zw;
    float _1246 = (_1217.y - _1235.y) / RA_VARYING_2.y;
    vec2 _1046 = vec2(0.0, RA_VARYING_1.y);
    vec3 _1055 = texture(Texture, _1238).xyz;
    vec3 _1062 = texture(Texture, _1238 + _1046).xyz;
    float _1065 = round(_1246);
    vec3 _1080 = texture(Texture, _1238 + mix(-_1046, _1046 * 2.0, vec2(_1065))).xyz;
    vec3 _1092 = vec3(_1246) - vec3((convergence_offset_y_r), (convergence_offset_y_g), (convergence_offset_y_b));
    float _1102 = max((beam_max_sigma), (beam_min_sigma)) - (beam_min_sigma);
    float _1112 = max((beam_max_shape), (beam_min_shape)) - (beam_min_shape);
    vec3 _1882 = vec3((beam_min_sigma));
    vec3 _1887 = vec3((beam_spot_power));
    vec3 _1916 = vec3((beam_shape_power));
    vec3 _1919 = vec3((beam_min_shape));
    vec3 _1920 = _1919 + (pow(_1055, _1916) * _1112);
    vec3 _1798 = vec3(1.0) / ((_1882 + (pow(_1055, _1887) * _1102)) * 1.41421353816986083984375);
    vec3 _1800 = vec3(1.0) / _1920;
    vec3 _1816 = vec3(RA_VARYING_3 * 0.3333333432674407958984375);
    vec3 _1128 = abs(vec3(1.0) - _1092);
    vec3 _2905 = _1919 + (pow(_1062, _1916) * _1112);
    vec3 _2783 = vec3(1.0) / ((_1882 + (pow(_1062, _1887) * _1102)) * 1.41421353816986083984375);
    vec3 _2785 = vec3(1.0) / _2905;
    vec3 _1151 = mix(_1092 + vec3(1.0), vec3(2.0) - _1092, vec3(_1065));
    vec3 _3890 = _1919 + (pow(_1080, _1916) * _1112);
    vec3 _3768 = vec3(1.0) / ((_1882 + (pow(_1080, _1887) * _1102)) * 1.41421353816986083984375);
    vec3 _3770 = vec3(1.0) / _3890;
    vec3 _1166 = (((((((_1055 * _1920) * 0.5) * _1798) / ((pow((_1800 + vec3(1.62906825542449951171875)) * vec3(0.367879450321197509765625), _1800 + vec3(0.5)) * (vec3(0.810911953449249267578125) + (vec3(0.4808354675769805908203125) / (_1800 + vec3(1.0))))) * _1920)) * vec3(0.3333333432674407958984375)) * ((exp(-pow(abs(_1092 * _1798), _1920)) + exp(-pow(abs((_1092 + _1816) * _1798), _1920))) + exp(-pow(abs(abs(_1092 - _1816) * _1798), _1920)))) + ((((((_1062 * _2905) * 0.5) * _2783) / ((pow((_2785 + vec3(1.62906825542449951171875)) * vec3(0.367879450321197509765625), _2785 + vec3(0.5)) * (vec3(0.810911953449249267578125) + (vec3(0.4808354675769805908203125) / (_2785 + vec3(1.0))))) * _2905)) * vec3(0.3333333432674407958984375)) * ((exp(-pow(abs(_1128 * _2783), _2905)) + exp(-pow(abs((_1128 + _1816) * _2783), _2905))) + exp(-pow(abs(abs(_1128 - _1816) * _2783), _2905))))) + ((((((_1080 * _3890) * 0.5) * _3768) / ((pow((_3770 + vec3(1.62906825542449951171875)) * vec3(0.367879450321197509765625), _3770 + vec3(0.5)) * (vec3(0.810911953449249267578125) + (vec3(0.4808354675769805908203125) / (_3770 + vec3(1.0))))) * _3890)) * vec3(0.3333333432674407958984375)) * ((exp(-pow(abs(_1151 * _3768), _3890)) + exp(-pow(abs((_1151 + _1816) * _3768), _3890))) + exp(-pow(abs(abs(_1151 - _1816) * _3768), _3890))));
    FragColor = vec4(_1166 * 0.5, 1.0);
}


#endif
