// Generated from crt/shaders/cathode-retro/cathode-retro-crt-rgb-to-crt_no-signal.slang. See slang/upstream for licence/source.
#version 120
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



attribute vec4 VertexCoord;
varying vec2 RA_VARYING_0;
attribute vec2 TexCoord;

void main()
{
    gl_Position = (MVPMatrix) * VertexCoord;
    RA_VARYING_0 = vec2(TexCoord.x, TexCoord.y) * 1.00010001659393310546875;
}


#endif
#ifdef FRAGMENT

uniform vec2 OrigTextureSize;
uniform float cat_mask_picker;
uniform float diffusion;
uniform float mask_depth;
uniform float mask_intens;
uniform float persistence;
uniform float scan_intens;
uniform float warpX;
uniform float warpY;
struct UBO
{
    float persistence;
    float scan_intens;
    float diffusion;
    float mask_intens;
    float mask_depth;
    float cat_mask_picker;
};



struct Push
{
    vec4 OriginalSize;
    float warpX;
    float warpY;
};



uniform sampler2D Pass10Texture;
uniform sampler2D Pass8Texture;
uniform sampler2D Pass1Texture;
uniform sampler2D FeedbackTexture;

varying vec2 RA_VARYING_0;

void main()
{
    float _652;
    if ((vec4(OrigTextureSize, 1.0 / OrigTextureSize)).y < 400.0)
    {
        _652 = (vec4(OrigTextureSize, 1.0 / OrigTextureSize)).y;
    }
    else
    {
        _652 = (vec4(OrigTextureSize, 1.0 / OrigTextureSize)).y * 0.5;
    }
    vec4 _251 = texture2D(Pass10Texture, RA_VARYING_0);
    vec2 _256 = (RA_VARYING_0 * 2.0) - vec2(1.0);
    vec2 _656;
    do
    {
        bool _519 = (warpX) == 0.0;
        bool _525;
        if (_519)
        {
            _525 = (warpY) == 0.0;
        }
        else
        {
            _525 = _519;
        }
        if (_525)
        {
            _656 = _256;
            break;
        }
        vec2 _530 = max(vec2(9.9999997473787516355514526367188e-05), vec2((warpX), (warpY)));
        vec3 _536 = vec3(_256 * _530, -2.0);
        float _539 = dot(_536, _536);
        float _552 = (4.0 / _539) - sqrt(max(0.0, (16.0 / (_539 * _539)) - (3.0 / _539)));
        vec2 _615 = (_536.xy * _552) / (vec2(2.0) + (_536.zz * _552));
        vec2 _618 = _615 * _615;
        vec3 _567 = vec3(_530, -2.0);
        vec2 _569 = _567.xz;
        vec2 _574 = _567.yz;
        vec2 _578 = vec2(dot(_569, _569), dot(_574, _574));
        vec2 _593 = (vec2(4.0) / _578) - sqrt(max(vec2(0.0), (vec2(16.0) / (_578 * _578)) - (vec2(3.0) / _578)));
        vec2 _634 = (_567.xy * _593) / (vec2(2.0) + (_567.zz * _593));
        vec2 _637 = _634 * _634;
        _656 = (_615 * (vec2(1.0) + (_618 * ((_618 * 0.20000000298023223876953125) - vec2(0.3333333432674407958984375))))) / (_634 * (vec2(1.0) + (_637 * ((_637 * 0.20000000298023223876953125) - vec2(0.3333333432674407958984375)))));
        break;
    } while(false);
    float _282 = _656.y + (0.5 / _652);
    vec2 _709 = _656;
    _709.y = _282;
    float _290 = (_282 * _652) + _652;
    float _303 = ((_282 * 0.5) + 0.5) * _652;
    float _306 = fract(_303);
    float _311 = _306 - 0.5;
    vec2 _713 = _709;
    _713.y = ((((_303 - _306) + (((sign(_311) * clamp(abs(_311) - 0.100000001490116119384765625, 0.0, 1.0)) * 1.25) + 0.5)) / _652) * 2.0) - 1.0;
    vec2 _343 = (_713 * 0.5) + vec2(0.5);
    float _360 = mix((scan_intens), 0.0, smoothstep(1.0, 1.39999997615814208984375, (length(dFdy(RA_VARYING_0)) * _652) * 2.0));
    float _365 = pow(abs(length(dFdy(_709)) * _652), 2.599999904632568359375);
    float _367 = _365 * 7.0;
    float _371 = _290 - _367;
    float _375 = _290 + _367;
    float _394 = ((0.5 * (_375 - _371)) + (0.15915493667125701904296875 * (sin(3.1415927410125732421875 * _371) - sin(3.1415927410125732421875 * _375)))) / (_365 * 14.0);
    float _396 = 1.0 - _360;
    vec2 _716 = _343;
    _716.y = _343.y + ((-0.5) / _652);
    vec3 _453 = (_251.xyz * ((2.0 + (cat_mask_picker)) - (mask_depth))) + vec3((mask_depth));
    vec4 _718 = _251;
    _718.x = _453.x;
    _718.y = _453.y;
    _718.z = _453.z;
    vec3 _474 = max(texture2D(Pass8Texture, (_656 * 0.5) + vec2(0.5)).xyz * (diffusion), (max((texture2D(FeedbackTexture, _716).xyz * mix(_396, 1.0, 1.0 - _394)) * (persistence), texture2D(Pass1Texture, _343).xyz * mix(_396, 1.0, _394)) / vec3(1.0 - (_360 * 0.5))) * mix(vec3(1.0), _718.xyz, vec3((mask_intens))));
    gl_FragData[0] = mix(vec4(0.0), vec4(_474, 1.0), vec4(_251.w));
}


#endif
