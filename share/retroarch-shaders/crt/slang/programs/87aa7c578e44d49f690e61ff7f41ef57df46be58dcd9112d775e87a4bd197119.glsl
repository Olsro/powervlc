// Generated from crt/shaders/crt-royale/src/crt-royale-bloom-approx.slang. See slang/upstream for licence/source.
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
uniform float geom_aspect_ratio_x;
uniform float geom_aspect_ratio_y;
uniform float interlace_1080i;
uniform float interlace_detect_toggle;
struct UBO
{
    mat4 MVP;
    float geom_aspect_ratio_x;
    float geom_aspect_ratio_y;
    float interlace_1080i;
    float interlace_detect_toggle;
};



struct Push
{
    vec4 SourceSize;
    vec4 OutputSize;
};



attribute vec4 VertexCoord;
attribute vec2 TexCoord;
varying vec2 RA_VARYING_0;
varying float RA_VARYING_3;
varying vec2 RA_VARYING_4;
varying vec2 RA_VARYING_1;
varying vec2 RA_VARYING_5;
varying vec2 RA_VARYING_2;

void main()
{
    gl_Position = (MVPMatrix) * VertexCoord;
    RA_VARYING_0 = TexCoord;
    RA_VARYING_3 = ((vec4(TextureSize, 1.0 / TextureSize)).y * (geom_aspect_ratio_x)) / (geom_aspect_ratio_y);
    RA_VARYING_4 = vec2(1.0) / (vec4(TextureSize, 1.0 / TextureSize)).xy;
    RA_VARYING_1 = max((vec4(TextureSize, 1.0 / TextureSize)).xy / (vec4(OutputSize, 1.0 / OutputSize)).xy, vec2(1.0)) * RA_VARYING_4;
    RA_VARYING_5 = (vec4(OutputSize, 1.0 / OutputSize)).xy;
    bool _401;
    do
    {
        if ((interlace_detect_toggle) != 0.0)
        {
            bool _399;
            if ((interlace_1080i) != 0.0)
            {
                _399 = ((vec4(TextureSize, 1.0 / TextureSize)).y > 1079.5) && ((vec4(TextureSize, 1.0 / TextureSize)).y < 1080.5);
            }
            else
            {
                _399 = false;
            }
            _401 = (((vec4(TextureSize, 1.0 / TextureSize)).y > 288.5) && ((vec4(TextureSize, 1.0 / TextureSize)).y < 576.5)) || _399;
            break;
        }
        else
        {
            _401 = false;
            break;
        }
        break; // unreachable workaround
    } while(false);
    RA_VARYING_2 = vec2(1.0, _401 ? 2.0 : 1.0) / (vec4(TextureSize, 1.0 / TextureSize)).xy;
}


#endif
#ifdef FRAGMENT

uniform vec2 OutputSize;
uniform vec2 TextureSize;
uniform float beam_max_sigma;
uniform float convergence_offset_x_b;
uniform float convergence_offset_x_g;
uniform float convergence_offset_x_r;
uniform float convergence_offset_y_b;
uniform float convergence_offset_y_g;
uniform float convergence_offset_y_r;
uniform float mask_num_triads_desired;
uniform float mask_specify_num_triads;
uniform float mask_triad_size_desired;
struct UBO
{
    float beam_max_sigma;
    float convergence_offset_x_r;
    float convergence_offset_x_g;
    float convergence_offset_x_b;
    float convergence_offset_y_r;
    float convergence_offset_y_g;
    float convergence_offset_y_b;
    float mask_num_triads_desired;
    float mask_triad_size_desired;
    float mask_specify_num_triads;
};



struct Push
{
    vec4 SourceSize;
    vec4 OutputSize;
};



uniform sampler2D Pass1Texture;

varying vec2 RA_VARYING_2;
varying vec2 RA_VARYING_0;
varying float RA_VARYING_3;
varying vec2 RA_VARYING_1;
varying vec2 RA_VARYING_4;
varying vec2 RA_VARYING_5;

void main()
{
    vec2 _1185 = RA_VARYING_0 - (vec2((convergence_offset_x_r), (convergence_offset_y_r)) * RA_VARYING_2);
    vec2 _1191 = RA_VARYING_0 - (vec2((convergence_offset_x_g), (convergence_offset_y_g)) * RA_VARYING_2);
    vec2 _1197 = RA_VARYING_0 - (vec2((convergence_offset_x_b), (convergence_offset_y_b)) * RA_VARYING_2);
    float _1426 = max(256.0, mix(RA_VARYING_3 / (mask_triad_size_desired), (mask_num_triads_desired), (mask_specify_num_triads)));
    float _1445 = length(vec2(((((-0.0516799986362457275390625) + (901398.5 / _1426)) - (108770.2734375 / _1426)) * (vec4(OutputSize, 1.0 / OutputSize)).x) * 6.7816841919920989312231540679932e-07, (beam_max_sigma)));
    float _1585 = 0.5 / (_1445 * _1445);
    vec2 _1610 = vec2(float(RA_VARYING_1.x <= RA_VARYING_4.x), float(RA_VARYING_1.y <= RA_VARYING_4.y));
    vec2 _1613 = RA_VARYING_1 * 0.5;
    vec2 _1618 = mix(_1185 - _1613, (floor((_1185 * (vec4(TextureSize, 1.0 / TextureSize)).xy) - vec2(0.4995000064373016357421875)) + vec2(0.5)) * RA_VARYING_4, _1610);
    vec2 _1621 = vec2(RA_VARYING_1.x, 0.0);
    vec2 _1624 = _1618 - RA_VARYING_1;
    vec2 _1627 = _1618 + RA_VARYING_1;
    vec2 _1630 = RA_VARYING_1 * 2.0;
    vec2 _1631 = _1618 + _1630;
    vec2 _1634 = _1624 + _1621;
    vec2 _1637 = _1621 * 2.0;
    vec2 _1641 = _1621 * 3.0;
    vec2 _1642 = _1624 + _1641;
    vec2 _1645 = _1618 - _1621;
    vec2 _1648 = _1618 + _1621;
    vec2 _1652 = _1618 + _1637;
    vec2 _1656 = _1627 - _1637;
    vec2 _1659 = _1627 - _1621;
    vec2 _1662 = _1627 + _1621;
    vec2 _1666 = _1631 - _1641;
    vec2 _1670 = _1631 - _1637;
    vec2 _1673 = _1631 - _1621;
    vec2 _1724 = _1185 * RA_VARYING_5;
    vec2 _1729 = (_1624 * RA_VARYING_5) - _1724;
    vec2 _1734 = (_1634 * RA_VARYING_5) - _1724;
    vec2 _1739 = ((_1624 + _1637) * RA_VARYING_5) - _1724;
    vec2 _1744 = (_1642 * RA_VARYING_5) - _1724;
    vec2 _1749 = (_1645 * RA_VARYING_5) - _1724;
    vec2 _1754 = (_1618 * RA_VARYING_5) - _1724;
    vec2 _1759 = (_1648 * RA_VARYING_5) - _1724;
    vec2 _1764 = (_1652 * RA_VARYING_5) - _1724;
    vec2 _1769 = (_1656 * RA_VARYING_5) - _1724;
    vec2 _1774 = (_1659 * RA_VARYING_5) - _1724;
    vec2 _1779 = (_1627 * RA_VARYING_5) - _1724;
    vec2 _1784 = (_1662 * RA_VARYING_5) - _1724;
    vec2 _1789 = (_1666 * RA_VARYING_5) - _1724;
    vec2 _1794 = (_1670 * RA_VARYING_5) - _1724;
    vec2 _1799 = (_1673 * RA_VARYING_5) - _1724;
    vec2 _1804 = (_1631 * RA_VARYING_5) - _1724;
    float _1811 = exp((-dot(_1729, _1729)) * _1585);
    float _1818 = exp((-dot(_1734, _1734)) * _1585);
    float _1825 = exp((-dot(_1739, _1739)) * _1585);
    float _1832 = exp((-dot(_1744, _1744)) * _1585);
    float _1839 = exp((-dot(_1749, _1749)) * _1585);
    float _1846 = exp((-dot(_1754, _1754)) * _1585);
    float _1853 = exp((-dot(_1759, _1759)) * _1585);
    float _1860 = exp((-dot(_1764, _1764)) * _1585);
    float _1867 = exp((-dot(_1769, _1769)) * _1585);
    float _1874 = exp((-dot(_1774, _1774)) * _1585);
    float _1881 = exp((-dot(_1779, _1779)) * _1585);
    float _1888 = exp((-dot(_1784, _1784)) * _1585);
    float _1895 = exp((-dot(_1789, _1789)) * _1585);
    float _1902 = exp((-dot(_1794, _1794)) * _1585);
    float _1909 = exp((-dot(_1799, _1799)) * _1585);
    float _1916 = exp((-dot(_1804, _1804)) * _1585);
    vec3 _1995 = (((((((((((texture2D(Pass1Texture, _1624).xyz * _1811) + (texture2D(Pass1Texture, _1634).xyz * _1818)) + (texture2D(Pass1Texture, _1621).xyz * _1825)) + (texture2D(Pass1Texture, _1642).xyz * _1832)) + (texture2D(Pass1Texture, _1645).xyz * _1839)) + (texture2D(Pass1Texture, _1618).xyz * _1846)) + (texture2D(Pass1Texture, _1648).xyz * _1853)) + (texture2D(Pass1Texture, _1652).xyz * _1860)) + (texture2D(Pass1Texture, _1656).xyz * _1867)) + (texture2D(Pass1Texture, _1659).xyz * _1874)) + (texture2D(Pass1Texture, _1627).xyz * _1881)) + (texture2D(Pass1Texture, _1662).xyz * _1888);
    vec2 _2895 = mix(_1191 - _1613, (floor((_1191 * (vec4(TextureSize, 1.0 / TextureSize)).xy) - vec2(0.4995000064373016357421875)) + vec2(0.5)) * RA_VARYING_4, _1610);
    vec2 _2901 = _2895 - RA_VARYING_1;
    vec2 _2904 = _2895 + RA_VARYING_1;
    vec2 _2908 = _2895 + _1630;
    vec2 _2911 = _2901 + _1621;
    vec2 _2919 = _2901 + _1641;
    vec2 _2922 = _2895 - _1621;
    vec2 _2925 = _2895 + _1621;
    vec2 _2929 = _2895 + _1637;
    vec2 _2933 = _2904 - _1637;
    vec2 _2936 = _2904 - _1621;
    vec2 _2939 = _2904 + _1621;
    vec2 _2943 = _2908 - _1641;
    vec2 _2947 = _2908 - _1637;
    vec2 _2950 = _2908 - _1621;
    vec2 _3001 = _1191 * RA_VARYING_5;
    vec2 _3006 = (_2901 * RA_VARYING_5) - _3001;
    vec2 _3011 = (_2911 * RA_VARYING_5) - _3001;
    vec2 _3016 = ((_2901 + _1637) * RA_VARYING_5) - _3001;
    vec2 _3021 = (_2919 * RA_VARYING_5) - _3001;
    vec2 _3026 = (_2922 * RA_VARYING_5) - _3001;
    vec2 _3031 = (_2895 * RA_VARYING_5) - _3001;
    vec2 _3036 = (_2925 * RA_VARYING_5) - _3001;
    vec2 _3041 = (_2929 * RA_VARYING_5) - _3001;
    vec2 _3046 = (_2933 * RA_VARYING_5) - _3001;
    vec2 _3051 = (_2936 * RA_VARYING_5) - _3001;
    vec2 _3056 = (_2904 * RA_VARYING_5) - _3001;
    vec2 _3061 = (_2939 * RA_VARYING_5) - _3001;
    vec2 _3066 = (_2943 * RA_VARYING_5) - _3001;
    vec2 _3071 = (_2947 * RA_VARYING_5) - _3001;
    vec2 _3076 = (_2950 * RA_VARYING_5) - _3001;
    vec2 _3081 = (_2908 * RA_VARYING_5) - _3001;
    float _3088 = exp((-dot(_3006, _3006)) * _1585);
    float _3095 = exp((-dot(_3011, _3011)) * _1585);
    float _3102 = exp((-dot(_3016, _3016)) * _1585);
    float _3109 = exp((-dot(_3021, _3021)) * _1585);
    float _3116 = exp((-dot(_3026, _3026)) * _1585);
    float _3123 = exp((-dot(_3031, _3031)) * _1585);
    float _3130 = exp((-dot(_3036, _3036)) * _1585);
    float _3137 = exp((-dot(_3041, _3041)) * _1585);
    float _3144 = exp((-dot(_3046, _3046)) * _1585);
    float _3151 = exp((-dot(_3051, _3051)) * _1585);
    float _3158 = exp((-dot(_3056, _3056)) * _1585);
    float _3165 = exp((-dot(_3061, _3061)) * _1585);
    float _3172 = exp((-dot(_3066, _3066)) * _1585);
    float _3179 = exp((-dot(_3071, _3071)) * _1585);
    float _3186 = exp((-dot(_3076, _3076)) * _1585);
    float _3193 = exp((-dot(_3081, _3081)) * _1585);
    vec3 _3272 = (((((((((((texture2D(Pass1Texture, _2901).xyz * _3088) + (texture2D(Pass1Texture, _2911).xyz * _3095)) + (texture2D(Pass1Texture, _1621).xyz * _3102)) + (texture2D(Pass1Texture, _2919).xyz * _3109)) + (texture2D(Pass1Texture, _2922).xyz * _3116)) + (texture2D(Pass1Texture, _2895).xyz * _3123)) + (texture2D(Pass1Texture, _2925).xyz * _3130)) + (texture2D(Pass1Texture, _2929).xyz * _3137)) + (texture2D(Pass1Texture, _2933).xyz * _3144)) + (texture2D(Pass1Texture, _2936).xyz * _3151)) + (texture2D(Pass1Texture, _2904).xyz * _3158)) + (texture2D(Pass1Texture, _2939).xyz * _3165);
    vec2 _4172 = mix(_1197 - _1613, (floor((_1197 * (vec4(TextureSize, 1.0 / TextureSize)).xy) - vec2(0.4995000064373016357421875)) + vec2(0.5)) * RA_VARYING_4, _1610);
    vec2 _4178 = _4172 - RA_VARYING_1;
    vec2 _4181 = _4172 + RA_VARYING_1;
    vec2 _4185 = _4172 + _1630;
    vec2 _4188 = _4178 + _1621;
    vec2 _4196 = _4178 + _1641;
    vec2 _4199 = _4172 - _1621;
    vec2 _4202 = _4172 + _1621;
    vec2 _4206 = _4172 + _1637;
    vec2 _4210 = _4181 - _1637;
    vec2 _4213 = _4181 - _1621;
    vec2 _4216 = _4181 + _1621;
    vec2 _4220 = _4185 - _1641;
    vec2 _4224 = _4185 - _1637;
    vec2 _4227 = _4185 - _1621;
    vec2 _4278 = _1197 * RA_VARYING_5;
    vec2 _4283 = (_4178 * RA_VARYING_5) - _4278;
    vec2 _4288 = (_4188 * RA_VARYING_5) - _4278;
    vec2 _4293 = ((_4178 + _1637) * RA_VARYING_5) - _4278;
    vec2 _4298 = (_4196 * RA_VARYING_5) - _4278;
    vec2 _4303 = (_4199 * RA_VARYING_5) - _4278;
    vec2 _4308 = (_4172 * RA_VARYING_5) - _4278;
    vec2 _4313 = (_4202 * RA_VARYING_5) - _4278;
    vec2 _4318 = (_4206 * RA_VARYING_5) - _4278;
    vec2 _4323 = (_4210 * RA_VARYING_5) - _4278;
    vec2 _4328 = (_4213 * RA_VARYING_5) - _4278;
    vec2 _4333 = (_4181 * RA_VARYING_5) - _4278;
    vec2 _4338 = (_4216 * RA_VARYING_5) - _4278;
    vec2 _4343 = (_4220 * RA_VARYING_5) - _4278;
    vec2 _4348 = (_4224 * RA_VARYING_5) - _4278;
    vec2 _4353 = (_4227 * RA_VARYING_5) - _4278;
    vec2 _4358 = (_4185 * RA_VARYING_5) - _4278;
    float _4365 = exp((-dot(_4283, _4283)) * _1585);
    float _4372 = exp((-dot(_4288, _4288)) * _1585);
    float _4379 = exp((-dot(_4293, _4293)) * _1585);
    float _4386 = exp((-dot(_4298, _4298)) * _1585);
    float _4393 = exp((-dot(_4303, _4303)) * _1585);
    float _4400 = exp((-dot(_4308, _4308)) * _1585);
    float _4407 = exp((-dot(_4313, _4313)) * _1585);
    float _4414 = exp((-dot(_4318, _4318)) * _1585);
    float _4421 = exp((-dot(_4323, _4323)) * _1585);
    float _4428 = exp((-dot(_4328, _4328)) * _1585);
    float _4435 = exp((-dot(_4333, _4333)) * _1585);
    float _4442 = exp((-dot(_4338, _4338)) * _1585);
    float _4449 = exp((-dot(_4343, _4343)) * _1585);
    float _4456 = exp((-dot(_4348, _4348)) * _1585);
    float _4463 = exp((-dot(_4353, _4353)) * _1585);
    float _4470 = exp((-dot(_4358, _4358)) * _1585);
    vec3 _4549 = (((((((((((texture2D(Pass1Texture, _4178).xyz * _4365) + (texture2D(Pass1Texture, _4188).xyz * _4372)) + (texture2D(Pass1Texture, _1621).xyz * _4379)) + (texture2D(Pass1Texture, _4196).xyz * _4386)) + (texture2D(Pass1Texture, _4199).xyz * _4393)) + (texture2D(Pass1Texture, _4172).xyz * _4400)) + (texture2D(Pass1Texture, _4202).xyz * _4407)) + (texture2D(Pass1Texture, _4206).xyz * _4414)) + (texture2D(Pass1Texture, _4210).xyz * _4421)) + (texture2D(Pass1Texture, _4213).xyz * _4428)) + (texture2D(Pass1Texture, _4181).xyz * _4435)) + (texture2D(Pass1Texture, _4216).xyz * _4442);
    gl_FragData[0] = vec4((((((_1995 + (texture2D(Pass1Texture, _1666).xyz * _1895)) + (texture2D(Pass1Texture, _1670).xyz * _1902)) + (texture2D(Pass1Texture, _1673).xyz * _1909)) + (texture2D(Pass1Texture, _1631).xyz * _1916)) * (1.0 / (((((((((((((((_1811 + _1818) + _1825) + _1832) + _1839) + _1846) + _1853) + _1860) + _1867) + _1874) + _1881) + _1888) + _1895) + _1902) + _1909) + _1916))).x, (((((_3272 + (texture2D(Pass1Texture, _2943).xyz * _3172)) + (texture2D(Pass1Texture, _2947).xyz * _3179)) + (texture2D(Pass1Texture, _2950).xyz * _3186)) + (texture2D(Pass1Texture, _2908).xyz * _3193)) * (1.0 / (((((((((((((((_3088 + _3095) + _3102) + _3109) + _3116) + _3123) + _3130) + _3137) + _3144) + _3151) + _3158) + _3165) + _3172) + _3179) + _3186) + _3193))).y, (((((_4549 + (texture2D(Pass1Texture, _4220).xyz * _4449)) + (texture2D(Pass1Texture, _4224).xyz * _4456)) + (texture2D(Pass1Texture, _4227).xyz * _4463)) + (texture2D(Pass1Texture, _4185).xyz * _4470)) * (1.0 / (((((((((((((((_4365 + _4372) + _4379) + _4386) + _4393) + _4400) + _4407) + _4414) + _4421) + _4428) + _4435) + _4442) + _4449) + _4456) + _4463) + _4470))).z, 1.0);
}


#endif
