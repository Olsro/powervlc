// Generated from crt/shaders/crt-royale/src-fast/crt-royale-mask-resize-vertical.slang. See slang/upstream for licence/source.
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
uniform float mask_num_triads_desired;
uniform float mask_specify_num_triads;
uniform float mask_triad_size_desired;
float _458;

struct UBO
{
    mat4 MVP;
    float mask_num_triads_desired;
    float mask_triad_size_desired;
    float mask_specify_num_triads;
};



struct Push
{
    vec4 OutputSize;
};



attribute vec4 VertexCoord;
attribute vec2 TexCoord;
varying vec2 RA_VARYING_0;
varying vec2 RA_VARYING_1;

void main()
{
    gl_Position = (MVPMatrix) * VertexCoord;
    vec2 _415 = clamp(vec2(1.0) * min(8.0 * mix((mask_triad_size_desired), ((vec4(OutputSize, 1.0 / OutputSize)).xy * vec2(16.0)).x / (mask_num_triads_desired), (mask_specify_num_triads)), 64.0), vec2(1.0) * ceil(16.0), (vec4(OutputSize, 1.0 / OutputSize)).xy / vec2(1.0 + (ceil(0.5) * 0.125)));
    float _417 = _415.y;
    vec2 _342 = vec2(min(64.0, (vec4(OutputSize, 1.0 / OutputSize)).x), floor(vec2(_458, min(_417, _417)) + vec2(1.52587890625e-05)).y);
    RA_VARYING_0 = TexCoord * ((vec4(OutputSize, 1.0 / OutputSize)).xy / _342);
    RA_VARYING_1 = _342 * vec2(0.015625);
}


#endif
#ifdef FRAGMENT

uniform float mask_type;
float _1422;

struct UBO
{
    float mask_type;
};



uniform sampler2D mask_grille_texture_small;
uniform sampler2D mask_slot_texture_small;
uniform sampler2D mask_shadow_texture_small;

varying vec2 RA_VARYING_0;
varying vec2 RA_VARYING_1;

void main()
{
    float _226 = ceil(96.0 / ceil(16.0)) * 4.0;
    if (RA_VARYING_0.y <= (1.0 + (ceil(0.5) * 0.125)))
    {
        vec2 _497 = fract(RA_VARYING_0);
        vec3 _1359;
        if ((mask_type) < 0.5)
        {
            int _601 = int(_226);
            vec2 _749 = _497 * vec2(64.0);
            vec2 _761 = (floor(_749 - vec2(0.4995000064373016357421875)) + vec2(0.5)) - vec2((float(_601) * 0.5) - 1.0);
            vec2 _770 = (_761 * 0.015625) * 1.0;
            vec2 _793 = vec2((fract(_770) + vec2(_1422, float(_770.y < 0.0))).y, (_749 - _761).y);
            vec4 _612 = _793.xxxx;
            vec4 _614 = _793.yyyy;
            vec4 _1357;
            vec3 _1358;
            _1358 = vec3(0.0);
            _1357 = vec4(0.0);
            for (int _1355 = 0; _1355 < _601; )
            {
                vec4 _629 = vec4(float(_1355)) + vec4(0.0, 1.0, 2.0, 3.0);
                vec4 _638 = fract(_612 + (_629 * 0.015625)) * 1.0;
                float _640 = _497.x;
                vec4 _672 = abs(_614 - _629) * RA_VARYING_1.y;
                vec4 _675 = _672 * 3.1415927410125732421875;
                vec4 _678 = _672 * 1.0471975803375244140625;
                vec4 _688 = min((sin(_675) * sin(_678)) / (_675 * _678), vec4(1.0));
                _1358 = (((_1358 + (texture2D(mask_grille_texture_small, vec2(_640, _638.x)).xyz * _688.xxx)) + (texture2D(mask_grille_texture_small, vec2(_640, _638.y)).xyz * _688.yyy)) + (texture2D(mask_grille_texture_small, vec2(_640, _638.z)).xyz * _688.zzz)) + (texture2D(mask_grille_texture_small, vec2(_640, _638.w)).xyz * _688.www);
                _1357 += _688;
                _1355 += 4;
                continue;
            }
            vec2 _725 = _1357.xy + _1357.zw;
            _1359 = _1358 / vec3(_725.x + _725.y);
        }
        else
        {
            vec3 _1360;
            if ((mask_type) < 1.5)
            {
                int _856 = int(_226);
                vec2 _1004 = _497 * vec2(64.0);
                vec2 _1016 = (floor(_1004 - vec2(0.4995000064373016357421875)) + vec2(0.5)) - vec2((float(_856) * 0.5) - 1.0);
                vec2 _1025 = (_1016 * 0.015625) * 1.0;
                vec2 _1048 = vec2((fract(_1025) + vec2(_1422, float(_1025.y < 0.0))).y, (_1004 - _1016).y);
                vec4 _867 = _1048.xxxx;
                vec4 _869 = _1048.yyyy;
                vec4 _1344;
                vec3 _1345;
                _1345 = vec3(0.0);
                _1344 = vec4(0.0);
                for (int _1342 = 0; _1342 < _856; )
                {
                    vec4 _884 = vec4(float(_1342)) + vec4(0.0, 1.0, 2.0, 3.0);
                    vec4 _893 = fract(_867 + (_884 * 0.015625)) * 1.0;
                    float _895 = _497.x;
                    vec4 _927 = abs(_869 - _884) * RA_VARYING_1.y;
                    vec4 _930 = _927 * 3.1415927410125732421875;
                    vec4 _933 = _927 * 1.0471975803375244140625;
                    vec4 _943 = min((sin(_930) * sin(_933)) / (_930 * _933), vec4(1.0));
                    _1345 = (((_1345 + (texture2D(mask_slot_texture_small, vec2(_895, _893.x)).xyz * _943.xxx)) + (texture2D(mask_slot_texture_small, vec2(_895, _893.y)).xyz * _943.yyy)) + (texture2D(mask_slot_texture_small, vec2(_895, _893.z)).xyz * _943.zzz)) + (texture2D(mask_slot_texture_small, vec2(_895, _893.w)).xyz * _943.www);
                    _1344 += _943;
                    _1342 += 4;
                    continue;
                }
                vec2 _980 = _1344.xy + _1344.zw;
                _1360 = _1345 / vec3(_980.x + _980.y);
            }
            else
            {
                int _1111 = int(_226);
                vec2 _1259 = _497 * vec2(64.0);
                vec2 _1271 = (floor(_1259 - vec2(0.4995000064373016357421875)) + vec2(0.5)) - vec2((float(_1111) * 0.5) - 1.0);
                vec2 _1280 = (_1271 * 0.015625) * 1.0;
                vec2 _1303 = vec2((fract(_1280) + vec2(_1422, float(_1280.y < 0.0))).y, (_1259 - _1271).y);
                vec4 _1122 = _1303.xxxx;
                vec4 _1124 = _1303.yyyy;
                vec4 _1331;
                vec3 _1332;
                _1332 = vec3(0.0);
                _1331 = vec4(0.0);
                for (int _1329 = 0; _1329 < _1111; )
                {
                    vec4 _1139 = vec4(float(_1329)) + vec4(0.0, 1.0, 2.0, 3.0);
                    vec4 _1148 = fract(_1122 + (_1139 * 0.015625)) * 1.0;
                    float _1150 = _497.x;
                    vec4 _1182 = abs(_1124 - _1139) * RA_VARYING_1.y;
                    vec4 _1185 = _1182 * 3.1415927410125732421875;
                    vec4 _1188 = _1182 * 1.0471975803375244140625;
                    vec4 _1198 = min((sin(_1185) * sin(_1188)) / (_1185 * _1188), vec4(1.0));
                    _1332 = (((_1332 + (texture2D(mask_shadow_texture_small, vec2(_1150, _1148.x)).xyz * _1198.xxx)) + (texture2D(mask_shadow_texture_small, vec2(_1150, _1148.y)).xyz * _1198.yyy)) + (texture2D(mask_shadow_texture_small, vec2(_1150, _1148.z)).xyz * _1198.zzz)) + (texture2D(mask_shadow_texture_small, vec2(_1150, _1148.w)).xyz * _1198.www);
                    _1331 += _1198;
                    _1329 += 4;
                    continue;
                }
                vec2 _1235 = _1331.xy + _1331.zw;
                _1360 = _1332 / vec3(_1235.x + _1235.y);
            }
            _1359 = _1360;
        }
        gl_FragData[0] = vec4(_1359, 1.0);
    }
    else
    {
        discard;
    }
}


#endif
