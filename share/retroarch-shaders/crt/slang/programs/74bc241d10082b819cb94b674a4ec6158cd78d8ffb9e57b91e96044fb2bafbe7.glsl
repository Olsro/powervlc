// Generated from crt/shaders/cathode-retro/cathode-retro-crt-generate-masks.slang. See slang/upstream for licence/source.
#version 130
#pragma parameter div0 "--------Screen Settings--------" 0.0 0.0 0.0 0.0
#pragma parameter scan_intens "Scanline Intensity" 0.4 0.0 1.0 0.01
#pragma parameter cat_mask_picker "Mask (0=none, 1=aperture, 2=slot, 3=shadow)" 1.0 0.0 3.0 1.0
#pragma parameter mask_intens "Mask Strength" 0.4 0.0 1.0 0.01
#pragma parameter mask_scale "Mask Scale (2 or 3 for 4K)" 1.0 1.0 200.0 1.0
#pragma parameter mask_depth "Mask Background Darkness" 0.3 0.0 1.0 0.01
#pragma parameter warpX "Barrel Distortion X" 0.2 0.0 1.0 0.01
#pragma parameter warpY "Barrel Distortion Y" 0.1 0.0 1.0 0.01
#pragma parameter anim_noise "Animate Anti-Moire Noise" 0.0 0.0 1.0 1.0
#pragma parameter corner "Rounded Corner Size" 0.03 0.0 1.0 0.01
#pragma parameter persistence "Phosphor Persistence" 0.25 0.0 1.0 0.01
#pragma parameter diffusion "Diffusion Strength" 0.5 0.0 1.0 0.01
#pragma parameter div1 "---------TV Knob Settings---------" 0.0 0.0 0.0 0.0
#pragma parameter cat_sat "Saturation" 1.0 0.0 2.0 0.01
#pragma parameter cat_bright "Brightness" 1.0 0.0 2.0 0.01
#pragma parameter cat_white_lvl "White Level" 1.0 0.0 2.0 0.01
#pragma parameter cat_black_lvl "Black Level" 0.0 0.0 2.0 0.01
#pragma parameter tint "Tint Knob Adjustment" 0.0 -1.0 1.0 0.01
#pragma parameter blurStrength "Sharpness" -0.15 -1.0 1.0 0.01
#pragma parameter div2 "---------Signal Parameters---------" 0.0 0.0 0.0 0.0
#pragma parameter composite "Blend Chrome/Luma (aka Composite)" 1.0 0.0 1.0 1.0
#pragma parameter sig_pad "Signal Padding at Edges" 0.0 0.0 10.0 1.0
#pragma parameter minlum "Minimum Luminance" 1.0 0.0 1.0 0.01
#pragma parameter colorpower "Color Power" 1.0 0.0 2.0 0.01
#pragma parameter noise_seed "Noise Seed" 247.0 179.0 313.0 1.0
#pragma parameter cb_samples "Samples Per Color Burst Cyle" 2.0 1.0 100.0 1.0
#pragma parameter cb_first_start "Color Burst Phase First Scanline" 0.0 0.0 100.0 1.0
#pragma parameter cb_last_start "CB Phase Prev Frame First Scanline" 1.0 0.0 100.0 1.0
#pragma parameter cb_phase_inc "Color Burst Phase Increment" 1.66666 0.0 3.0 0.01
#pragma parameter stepSize "Texels Between Each Sample" 1.0 1.0 100.0 1.0
#pragma parameter div3 "-------Artifact Settings-------" 0.0 0.0 0.0 0.0
#pragma parameter horz_track_scale "Horizontal Tracking Instability Scale" 1.0 0.0 3.0 0.05
#pragma parameter ghost_vis "Ghost Visibility" 0.15 0.0 1.0 0.01
#pragma parameter ghost_dist "Ghost Delay Cycles" 1.0 0.0 100.0 1.0
#pragma parameter ghost_spread "Ghost Spread Cycles" 1.0 0.0 100.0 1.0
#pragma parameter noise_strength "Artifact Noise Strength" 0.15 0.0 1.0 0.01
#pragma parameter temp_artifact_blend "Temporal Artifact Blending (Toggle)" 0.0 0.0 1.0 1.0
#ifdef VERTEX

uniform mat4 MVPMatrix;
struct UBO
{
    mat4 MVP;
};



in vec4 VertexCoord;
out vec2 RA_VARYING_0;
in vec2 TexCoord;

void main()
{
    gl_Position = (MVPMatrix) * VertexCoord;
    RA_VARYING_0 = vec2(TexCoord.x, TexCoord.y) * 1.00010001659393310546875;
}


#endif
#ifdef FRAGMENT

uniform vec2 RAViewportSize;
uniform float cat_mask_picker;
uniform float mask_scale;
struct UBO
{
    float cat_mask_picker;
    float mask_scale;
};



struct Push
{
    vec4 FinalViewportSize;
};



out vec4 FragColor;
in vec2 RA_VARYING_0;

void main()
{
    float _38 = (vec4(RAViewportSize, 1.0 / RAViewportSize)).y * 2.0;
    int _418 = int((cat_mask_picker));
    if (_418 == 1)
    {
        float _514 = fract((float(uint((fract((RA_VARYING_0 * ((vec4(RAViewportSize, 1.0 / RAViewportSize)).xy * vec2(0.16666667163372039794921875))) / vec2((mask_scale))).x * _38) - 0.5)) / _38) * 2.0) * 3.0;
        vec3 _830;
        if (_514 >= 2.0)
        {
            _830 = vec3(0.0, 0.0, 1.0);
        }
        else
        {
            bvec3 _841 = bvec3(_514 >= 1.0);
            _830 = vec3(_841.x ? vec3(0.0, 1.0, 0.0).x : vec3(1.0, 0.0, 0.0).x, _841.y ? vec3(0.0, 1.0, 0.0).y : vec3(1.0, 0.0, 0.0).y, _841.z ? vec3(0.0, 1.0, 0.0).z : vec3(1.0, 0.0, 0.0).z);
        }
        float _553 = 9.0 / (vec4(RAViewportSize, 1.0 / RAViewportSize)).y;
        FragColor = vec4(_830 * clamp(1.0 - smoothstep(1.0 - _553, 1.0 + _553, max(0.0, (abs((fract(_514) * 0.3333333432674407958984375) - 0.16666667163372039794921875) - 0.083333335816860198974609375) * 36.0)), 0.0, 1.0), 1.0);
    }
    else
    {
        if (_418 == 2)
        {
            vec2 _597 = (vec2(uvec2((fract((RA_VARYING_0 * ((vec4(RAViewportSize, 1.0 / RAViewportSize)).xy * vec2(0.16666667163372039794921875))) / vec2((mask_scale))) * vec2(_38, (vec4(RAViewportSize, 1.0 / RAViewportSize)).y)) - vec2(0.5))) / vec2(_38)) * vec2(1.0, 2.0);
            float _599 = _597.x;
            vec2 _918;
            if (_599 > 0.5)
            {
                _918 = vec2((_597.x * 2.0) - 1.0, fract(_597.y + 0.5));
            }
            else
            {
                _597.x = _599 * 2.0;
                _918 = _597;
            }
            float _620 = _918.x * 3.0;
            vec2 _864 = _918;
            _864.x = _620;
            vec3 _826;
            if (_620 >= 2.0)
            {
                _826 = vec3(0.0, 0.0, 1.0);
            }
            else
            {
                bvec3 _843 = bvec3(_620 >= 1.0);
                _826 = vec3(_843.x ? vec3(0.0, 1.0, 0.0).x : vec3(1.0, 0.0, 0.0).x, _843.y ? vec3(0.0, 1.0, 0.0).y : vec3(1.0, 0.0, 0.0).y, _843.z ? vec3(0.0, 1.0, 0.0).z : vec3(1.0, 0.0, 0.0).z);
            }
            float _635 = fract(_620);
            _864.x = _635;
            _864.x = _635 * 0.3333333432674407958984375;
            float _673 = 8.99999904632568359375 / (vec4(RAViewportSize, 1.0 / RAViewportSize)).y;
            FragColor = vec4(_826 * clamp(1.0 - smoothstep(1.0 - _673, 1.0 + _673, length(max(vec2(0.0), (abs(_864 - vec2(0.16666667163372039794921875, 0.5)) - vec2(0.083333335816860198974609375, 0.333333313465118408203125)) * vec2(35.999996185302734375)))), 0.0, 1.0), 1.0);
        }
        else
        {
            if (_418 == 3)
            {
                vec2 _704 = fract((RA_VARYING_0 * ((vec4(RAViewportSize, 1.0 / RAViewportSize)).xy * vec2(0.16666667163372039794921875))) / vec2((mask_scale))) * vec2(6.0);
                bool _709 = fract(_704.y * 0.5) >= 0.5;
                vec2 _909;
                if (_709)
                {
                    vec2 _878 = _704;
                    _878.x = _704.x + 0.5;
                    _909 = _878;
                }
                else
                {
                    _909 = _704;
                }
                ivec2 _719 = ivec2(floor(_909));
                vec2 _721 = fract(_909);
                float _723 = _721.y;
                float _725 = _721.x;
                ivec2 _910;
                vec2 _912;
                if (_723 < (((-0.57735025882720947265625) * _725) + 0.288675129413604736328125))
                {
                    vec2 _886 = _909;
                    _886.x = _909.x + (_709 ? (-0.5) : 0.5);
                    _912 = _886;
                    _910 = ivec2(_719.x - int(_709), _719.y - 1);
                }
                else
                {
                    ivec2 _911;
                    vec2 _913;
                    if (_723 < ((0.57735025882720947265625 * _725) - 0.288675129413604736328125))
                    {
                        vec2 _897 = _909;
                        _897.x = _909.x + (_709 ? (-0.5) : 0.5);
                        _913 = _897;
                        _911 = ivec2(_719.x + int(!_709), _719.y - 1);
                    }
                    else
                    {
                        _913 = _909;
                        _911 = _719;
                    }
                    _912 = _913;
                    _910 = _911;
                }
                ivec2 _914;
                vec2 _916;
                if (fract(float(_910.y) * 0.5) >= 0.5)
                {
                    vec2 _904 = _912;
                    _904.x = _912.x + 1.0;
                    ivec2 _907 = _910;
                    _907.x = _910.x + 1;
                    _916 = _904;
                    _914 = _907;
                }
                else
                {
                    _916 = _912;
                    _914 = _910;
                }
                uint _791 = uint(_914.x + 1) % 3u;
                vec3 _824;
                if (_791 == 0u)
                {
                    _824 = vec3(1.0, 0.0, 0.0);
                }
                else
                {
                    bvec3 _845 = bvec3(_791 == 1u);
                    _824 = vec3(_845.x ? vec3(0.0, 1.0, 0.0).x : vec3(0.0, 0.0, 1.0).x, _845.y ? vec3(0.0, 1.0, 0.0).y : vec3(0.0, 0.0, 1.0).y, _845.z ? vec3(0.0, 1.0, 0.0).z : vec3(0.0, 0.0, 1.0).z);
                }
                FragColor = vec4(_824 * (1.0 - smoothstep(0.75, 0.800000011920928955078125, length((((_916 - vec2(_914)) * vec2(1.0, 0.775990784168243408203125)) * 2.0) - vec2(1.0)))), 1.0);
            }
            else
            {
                FragColor = vec4(0.5);
            }
        }
    }
}


#endif
