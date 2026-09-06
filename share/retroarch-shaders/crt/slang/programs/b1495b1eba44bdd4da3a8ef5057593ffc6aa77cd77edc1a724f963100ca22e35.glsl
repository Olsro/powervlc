// Generated from crt/shaders/crt-sines.slang. See slang/upstream for licence/source.
#version 120
#pragma parameter dummy_beam " [ BEAM ] " 0.0 0.0 0.0 0.0
#pragma parameter filt "Filter Sharpness" 0.0 0.0 2.0 1.0
#pragma parameter profiler "Scanline profile soft/sharp" 0.0 0.0 1.0 1.0
#pragma parameter beam_min "Scanline Beam Min." 8.0 2.0 15.0 1.0 
#pragma parameter beam_max "Scanline Beam Max." 6.0 2.0 15.0 1.0 
#pragma parameter scan_min "Scanlines Min" 1.3 0.0 2.5 0.05
#pragma parameter scan_max "Scanlines Max" 1.0 0.0 2.5 0.05
#pragma parameter dummy_mask " [ MASK ] " 0.0 0.0 0.0 0.0
#pragma parameter mask_type "Mask Fine/Coarse" 0.0 0.0 1.0 1.0
#pragma parameter MSK_WIDTH "Mask Stagger Width" 1.0 1.0 4.0 1.0
#pragma parameter MSK_HEIGHT "Mask Stagger Height" 1.0 1.0 4.0 1.0
#pragma parameter MSK_STAG "Mask Stagger" 0.0 0.0 2.0 1.0
#pragma parameter MSK_BRI "Mask Brightness" 0.4 0.0 1.0 0.05
#pragma parameter dummy_tube " [ TUBE ] " 0.0 0.0 0.0 0.0
#pragma parameter CURVATURE_X "Curvature Horiz." 0.01 0.0 0.3 0.01
#pragma parameter CURVATURE_Y "Curvature Vert." 0.04 0.0 0.3 0.01
#pragma parameter corner_cut "Corners Cut" 1.0 0.0 1.0 1.0
#pragma parameter CURVATURE_SCALE "Curvature Scale" 0.0 -1.0 1.0 0.01
#pragma parameter u_vignette "Vignette" 0.25 0.0 1.0 0.01
#pragma parameter deconv "Deconvergence" 0.0 0.0 1.0 1.0
#pragma parameter glass_refl "Glass Reflection" 0.15 0.0 0.5 0.01
#pragma parameter glass_refl_pos "Glass Reflection Pos." 0.5 0.0 1.0 0.01
#pragma parameter dymmy_col " [ COLORS ] " 0.0 0.0 0.0 0.0
#pragma parameter crt_colors "CRT Colors" 1.0 0.0 1.0 1.0
#pragma parameter boost_dark "Boost Dark Pixels" 1.5 1.0 4.0 0.05
#pragma parameter boost_bright "Boost Bright Pixels" 1.2 1.0 4.0 0.05
#pragma parameter glow_str "Glow Strength" 0.06 0.0 1.0 0.01
#pragma parameter color_sat "Saturation" 1.0 0.0 2.0 0.05
#ifdef VERTEX

uniform float MSK_HEIGHT;
uniform float MSK_WIDTH;
uniform mat4 MVPMatrix;
uniform vec2 OutputSize;
uniform vec2 TextureSize;
struct UBO
{
    mat4 MVP;
    vec4 SourceSize;
    vec4 OutputSize;
};



struct Push
{
    float MSK_WIDTH;
    float MSK_HEIGHT;
};



attribute vec4 VertexCoord;
varying vec2 RA_VARYING_0;
attribute vec2 TexCoord;
varying vec2 RA_VARYING_1;
varying vec2 RA_VARYING_2;

void main()
{
    gl_Position = (MVPMatrix) * VertexCoord;
    RA_VARYING_0 = TexCoord * 1.00010001659393310546875;
    RA_VARYING_1 = vec2(1.0) / (vec4(TextureSize, 1.0 / TextureSize)).xy;
    RA_VARYING_2 = (RA_VARYING_0 * (vec4(OutputSize, 1.0 / OutputSize)).xy) / vec2((MSK_WIDTH), (MSK_HEIGHT));
}


#endif
#ifdef FRAGMENT

uniform float CURVATURE_SCALE;
uniform float CURVATURE_X;
uniform float CURVATURE_Y;
uniform float MSK_BRI;
uniform float MSK_STAG;
uniform vec2 TextureSize;
uniform float beam_max;
uniform float beam_min;
uniform float boost_bright;
uniform float boost_dark;
uniform float color_sat;
uniform float corner_cut;
uniform float crt_colors;
uniform float deconv;
uniform float filt;
uniform float glass_refl;
uniform float glass_refl_pos;
uniform float glow_str;
uniform float mask_type;
uniform float profiler;
uniform float scan_max;
uniform float scan_min;
uniform float u_vignette;
const float _44[5] = float[](0.0625, 0.25, 0.375, 0.25, 0.0625);

struct UBO
{
    vec4 SourceSize;
};



struct Push
{
    float beam_max;
    float beam_min;
    float scan_max;
    float scan_min;
    float CURVATURE_X;
    float CURVATURE_Y;
    float CURVATURE_SCALE;
    float u_vignette;
    float MSK_BRI;
    float mask_type;
    float boost_bright;
    float boost_dark;
    float glow_str;
    float color_sat;
    float deconv;
    float glass_refl;
    float MSK_STAG;
    float glass_refl_pos;
    float profiler;
    float crt_colors;
    float filt;
    float corner_cut;
};



uniform sampler2D Texture;

varying vec2 RA_VARYING_1;
varying vec2 RA_VARYING_0;
varying vec2 RA_VARYING_2;

void main()
{
    vec2 _540 = (RA_VARYING_0 * 2.0) - vec2(1.0);
    float _543 = _540.y;
    float _548 = _540.x;
    vec2 _584 = ((vec2(_548 + (((_543 * _543) * _548) * (CURVATURE_X)), _540.y + (((_548 * _548) * _543) * (CURVATURE_Y))) * (1.0 - ((CURVATURE_SCALE) * 0.100000001490116119384765625))) * 0.5) + vec2(0.5);
    vec2 _241 = _584 * (vec4(TextureSize, 1.0 / TextureSize)).xy;
    vec2 _249 = floor(_241) + vec2(0.5);
    float _254 = _249.y;
    float _255 = _241.y - _254;
    float _265 = fract(_241.x) - (((filt) != 0.0) ? 0.5 : 0.0);
    float _677;
    if ((filt) == 0.0)
    {
        _677 = (_249.x + ((_265 * _265) * (2.0 - _265))) * RA_VARYING_1.x;
    }
    else
    {
        float _676;
        if ((filt) == 1.0)
        {
            _676 = (_249.x + (((sign(_265) * 2.0) * _265) * _265)) * RA_VARYING_1.x;
        }
        else
        {
            _676 = (_249.x + (((4.0 * _265) * _265) * _265)) * RA_VARYING_1.x;
        }
        _677 = _676;
    }
    vec2 _766 = vec2(_677, (_254 + (((((16.0 * _255) * _255) * _255) * _255) * _255)) * RA_VARYING_1.y);
    vec4 _345 = texture2D(Texture, _766);
    vec3 _346 = _345.xyz;
    vec3 _754;
    if ((deconv) == 1.0)
    {
        vec3 _738 = _346;
        _738.x = texture2D(Texture, _766 + vec2(0.001000000047497451305389404296875, 0.0)).x;
        _738.z = texture2D(Texture, _766 - vec2(0.001000000047497451305389404296875, 0.0)).z;
        _754 = _738;
    }
    else
    {
        _754 = _346;
    }
    vec3 _370 = _754 * 0.949999988079071044921875;
    vec3 _755;
    if ((crt_colors) == 1.0)
    {
        _755 = clamp(_370 * mat3(vec3(1.0499999523162841796875, 0.100000001490116119384765625, -0.100000001490116119384765625), vec3(-0.0500000007450580596923828125, 0.89999997615814208984375, 0.0), vec3(0.0500000007450580596923828125, 0.0, 1.10000002384185791015625)), vec3(0.0), vec3(1.0));
    }
    else
    {
        _755 = _370;
    }
    vec3 _401 = _755 + vec3((pow(1.0 - distance(_584, vec2((glass_refl_pos))), 6.0) * (glass_refl)) * 0.100000001490116119384765625);
    float _687;
    if ((profiler) == 0.0)
    {
        _687 = max(max(_401.x, _401.y), _401.z);
    }
    else
    {
        _687 = dot(vec3(0.300000011920928955078125), _401);
    }
    vec3 _691;
    if (int(mod(floor(RA_VARYING_2.x) + (mod(floor(RA_VARYING_2.y), 2.0) * (MSK_STAG)), ((mask_type) == 1.0) ? 3.0 : 2.0)) == 0)
    {
        _691 = vec3((MSK_BRI));
    }
    else
    {
        _691 = vec3(1.0);
    }
    int _693;
    vec3 _694;
    _694 = vec3(0.0);
    _693 = -2;
    vec3 _702;
    for (; _693 < 3; _694 = _702, _693++)
    {
        _702 = _694;
        for (int _698 = -1; _698 < 2; )
        {
            _702 += (texture2D(Texture, _766 + (RA_VARYING_1 * vec2(float(_693), float(_698) * 1.25))).xyz * (_44[_693 + 2] + _44[_698 + 2]));
            _698++;
            continue;
        }
    }
    float _486 = distance(_584, vec2(0.5));
    vec3 _496 = (sqrt(((_401 * exp((((-mix((beam_min), (beam_max), _687)) * _255) * _255) * mix((scan_min), (scan_max), _687))) * mix(_691, vec3((boost_bright)), vec3(_687 * 0.5))) * mix(vec3((boost_dark)), vec3(1.0), vec3(_687))) + ((_694 * vec3(0.533333361148834228515625)) * (glow_str))) * (1.0 - ((u_vignette) * _486));
    vec3 _763;
    if (((corner_cut) == 1.0) && (_486 > 0.699999988079071044921875))
    {
        _763 = vec3(0.0);
    }
    else
    {
        _763 = mix(vec3(dot(vec3(0.300000011920928955078125, 0.60000002384185791015625, 0.100000001490116119384765625), _496)), _496, vec3((color_sat)));
    }
    gl_FragData[0].x = _763.x;
    gl_FragData[0].y = _763.y;
    gl_FragData[0].z = _763.z;
}


#endif
