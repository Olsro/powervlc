// Generated from crt/shaders/crt-consumer.slang. See slang/upstream for licence/source.
#version 130
#pragma parameter PRE_SCALE "Pre-Scale Sharpening" 1.5 1.0 4.0 0.1
#pragma parameter blurx "Convergence X" 0.25 -4.0 4.0 0.05
#pragma parameter blury "Convergence Y" -0.1 -4.0 4.0 0.05
#pragma parameter warpx "  Curvature X" 0.03 0.0 0.12 0.01
#pragma parameter warpy "  Curvature Y" 0.04 0.0 0.12 0.01
#pragma parameter corner "  Corner size" 0.03 0.0 0.10 0.01
#pragma parameter smoothness "  Border Smoothness" 400.0 100.0 600.0 5.0
#pragma parameter inter "Interlacing Toggle" 1.0 0.0 1.0 1.0
#pragma parameter Downscale "Interlacing Downscale Scanlines" 2.0 1.0 8.0 1.0  
#pragma parameter scanlow "Beam low" 6.0 1.0 15.0 1.0
#pragma parameter scanhigh "Beam high" 8.0 1.0 15.0 1.0
#pragma parameter beamlow "Scanlines dark" 1.45 0.5 2.5 0.05 
#pragma parameter beamhigh "Scanlines bright" 1.05 0.5 2.5 0.05 
#pragma parameter preserve "  Protect White On Masks" 0.98 0.0 1.0 0.01
#pragma parameter brightboost1 "  Bright boost dark pixels" 1.25 0.0 3.0 0.05
#pragma parameter brightboost2 "  Bright boost bright pixels" 1.0 0.0 3.0 0.05
#pragma parameter glow "  Glow pixels per axis" 3.0 1.0 6.0 1.0
#pragma parameter quality "  Glow quality" 1.0 0.25 4.0 0.05
#pragma parameter glow_str "  Glow intensity" 0.3 0.0001 2.0 0.05
#pragma parameter nois "  Add Noise" 0.0 0.0 32.0 1.0
#pragma parameter postbr "  Post Brightness" 1.0 0.0 2.5 0.02
#pragma parameter palette_fix "Palette Fixes. Sega, PUAE Atari ST dark colors " 0.0 0.0 2.0 1.0
#pragma parameter Shadowmask "Mask Type" 0.0 -1.0 8.0 1.0 
#pragma parameter masksize "Mask Size" 1.0 1.0 2.0 1.0
#pragma parameter MaskDark "Mask dark" 0.2 0.0 2.0 0.1
#pragma parameter MaskLight "Mask light" 1.5 0.0 2.0 0.1
#pragma parameter slotmask "Slot Mask Strength" 0.0 0.0 1.0 0.05
#pragma parameter slotwidth "Slot Mask Width" 2.0 1.0 6.0 0.5
#pragma parameter double_slot "Slot Mask Height: 2x1 or 4x1" 1.0 1.0 2.0 1.0
#pragma parameter slotms "Slot Mask Size" 1.0 1.0 2.0 1.0
#pragma parameter GAMMA_OUT "  Gamma Out" 2.25 0.0 4.0 0.05
#pragma parameter sat "  Saturation" 1.0 0.0 2.0 0.05
#pragma parameter contrast "  Contrast, 1.0:Off" 1.0 0.00 2.00 0.05
#pragma parameter WP "  Color Temperature %" 0.0 -100.0 100.0 5.0 
#pragma parameter rg             "  Red-Green Tint"       0.0 -1.0 1.0 0.005
#pragma parameter rb             "  Red-Blue Tint"        0.0 -1.0 1.0 0.005
#pragma parameter gr             "  Green-Red Tint"       0.0 -1.0 1.0 0.005
#pragma parameter gb             "  Green-Blue Tint"      0.0 -1.0 1.0 0.005
#pragma parameter br             "  Blue-Red Tint"        0.0 -1.0 1.0 0.005
#pragma parameter bg             "  Blue-Green Tint"      0.0 -1.0 1.0 0.005
#pragma parameter vignette "Vignette On/Off" 0.0 0.0 1.0 1.0
#pragma parameter vpower "Vignette Power" 0.15 0.0 1.0 0.01
#pragma parameter vstr "Vignette strength" 40.0 0.0 50.0 1.0
#pragma parameter alloff "Switch off shader" 0.0 0.0 1.0 1.0
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
    RA_VARYING_0 = TexCoord * 1.00010001659393310546875;
}


#endif
#ifdef FRAGMENT

uniform float Downscale;
uniform int FrameCount;
uniform float GAMMA_OUT;
uniform float MaskDark;
uniform float MaskLight;
uniform vec2 OutputSize;
uniform float PRE_SCALE;
uniform float Shadowmask;
uniform vec2 TextureSize;
uniform float WP;
uniform float alloff;
uniform float beamhigh;
uniform float beamlow;
uniform float bg;
uniform float blurx;
uniform float blury;
uniform float br;
uniform float brightboost1;
uniform float brightboost2;
uniform float contrast;
uniform float corner;
uniform float double_slot;
uniform float gb;
uniform float glow;
uniform float glow_str;
uniform float gr;
uniform float inter;
uniform float masksize;
uniform float nois;
uniform float palette_fix;
uniform float postbr;
uniform float preserve;
uniform float quality;
uniform float rb;
uniform float rg;
uniform float sat;
uniform float scanhigh;
uniform float scanlow;
uniform float slotmask;
uniform float slotms;
uniform float slotwidth;
uniform float smoothness;
uniform float vignette;
uniform float vpower;
uniform float vstr;
uniform float warpx;
uniform float warpy;
struct UBO
{
    float blurx;
    float blury;
    float warpx;
    float warpy;
    float corner;
    float smoothness;
    float scanlow;
    float scanhigh;
    float beamlow;
    float beamhigh;
    float brightboost1;
    float brightboost2;
    float Shadowmask;
    float masksize;
    float MaskDark;
    float MaskLight;
    float slotmask;
    float slotwidth;
    float double_slot;
    float slotms;
    float GAMMA_OUT;
    float glow;
    float glow_str;
    float sat;
    float contrast;
    float nois;
    float WP;
    float inter;
    float vignette;
    float vpower;
    float vstr;
    float alloff;
    float postbr;
    float PRE_SCALE;
    float preserve;
};



struct Push
{
    vec4 SourceSize;
    vec4 OutputSize;
    uint FrameCount;
    float rg;
    float rb;
    float gr;
    float gb;
    float br;
    float bg;
    float Downscale;
    float quality;
    float palette_fix;
};



uniform sampler2D Texture;

in vec2 RA_VARYING_0;
out vec4 FragColor;

void main()
{
    vec2 _1593 = (RA_VARYING_0 * 2.0) - vec2(1.0);
    float _1595 = _1593.y;
    float _1604 = _1593.x;
    vec2 _1618 = ((_1593 * vec2(1.0 + ((_1595 * _1595) * (warpx)), 1.0 + ((_1604 * _1604) * (warpy)))) * 0.5) + vec2(0.5);
    vec2 _1040 = _1618 + (vec2(0.5) / (vec4(TextureSize, 1.0 / TextureSize)).xy);
    vec2 _1044 = _1618 * (vec4(TextureSize, 1.0 / TextureSize)).xy;
    vec2 _1045 = fract(_1044);
    bool _1049 = (inter) < 0.5;
    bool _1056;
    if (_1049)
    {
        _1056 = (vec4(TextureSize, 1.0 / TextureSize)).y > 400.0;
    }
    else
    {
        _1056 = _1049;
    }
    vec2 _2821;
    if (_1056)
    {
        vec2 _2690 = _1045;
        _2690.y = fract((_1618.y * (vec4(TextureSize, 1.0 / TextureSize)).y) / (Downscale));
        _2821 = _2690;
    }
    else
    {
        _2821 = _1045;
    }
    vec4 _2892;
    if ((alloff) == 1.0)
    {
        _2892 = texture(Texture, _1040);
    }
    else
    {
        float _1096 = 0.5 / (PRE_SCALE);
        vec2 _1101 = _2821 - vec2(0.5);
        vec2 _1125 = (floor(_1044) + (((_1101 - clamp(_1101, vec2(_1096 - 0.5), vec2(0.5 - _1096))) * (PRE_SCALE)) + vec2(0.5))) / (vec4(TextureSize, 1.0 / TextureSize)).xy;
        float _1129 = _1125.x;
        float _1135 = (blurx) * (vec4(TextureSize, 1.0 / TextureSize)).z;
        float _1138 = _1125.y;
        float _1144 = (blury) * (vec4(TextureSize, 1.0 / TextureSize)).w;
        vec4 _1147 = texture(Texture, vec2(_1129 + _1135, _1138 - _1144));
        vec4 _1152 = texture(Texture, _1125);
        vec4 _1173 = texture(Texture, vec2(_1129 - _1135, _1138 + _1144));
        vec3 _1201 = vec3(0.5 * (_1147.x + _1152.x), ((_1147.y * 0.25) + (_1152.y * 0.5)) + (_1173.y * 0.25), 0.5 * (_1152.z + _1173.z));
        vec3 _2822;
        if ((palette_fix) != 0.0)
        {
            vec3 _2823;
            if ((palette_fix) == 1.0)
            {
                _2823 = _1201 * 1.066699981689453125;
            }
            else
            {
                vec3 _2824;
                if ((palette_fix) == 2.0)
                {
                    _2824 = _1201 * 2.0;
                }
                else
                {
                    _2824 = _1201;
                }
                _2823 = _2824;
            }
            _2822 = _2823;
        }
        else
        {
            _2822 = _1201;
        }
        vec3 _2825;
        if ((WP) != 0.0)
        {
            vec3 _1260 = mat3(vec3(3.062897205352783203125, -0.969265997409820556640625, 0.0678775012493133544921875), vec3(-1.39317905902862548828125, 1.87601077556610107421875, -0.2288548052310943603515625), vec3(-0.475751698017120361328125, 0.04155600070953369140625, 1.0693490505218505859375)) * (mat3(vec3(0.4552772939205169677734375, 0.23230250179767608642578125, 0.01454569958150386810302734375), vec3(0.3675499856472015380859375, 0.707795619964599609375, 0.104915402829647064208984375), vec3(0.14139260351657867431640625, 0.059901900589466094970703125, 0.70574891567230224609375)) * _2822);
            vec3 _1291 = mat3(vec3(2.960394382476806640625, -0.978768408298492431640625, 0.084487400949001312255859375), vec3(-1.4678518772125244140625, 1.916141510009765625, -0.25459730625152587890625), vec3(-0.46851050853729248046875, 0.033454000949859619140625, 1.42161738872528076171875)) * (mat3(vec3(0.4306190013885498046875, 0.22203789651393890380859375, 0.020185299217700958251953125), vec3(0.34154188632965087890625, 0.706638395786285400390625, 0.129550397396087646484375), vec3(0.17830909788608551025390625, 0.0713236033916473388671875, 0.93909442424774169921875)) * _2822);
            bvec3 _1305 = bvec3((WP) < 0.0);
            _2825 = mix(_2822, clamp(vec3(_1305.x ? _1291.x : _1260.x, _1305.y ? _1291.y : _1260.y, _1305.z ? _1291.z : _1260.z), vec3(0.0), vec3(1.0)), vec3(abs((WP)) * 0.00999999977648258209228515625));
        }
        else
        {
            _2825 = _2822;
        }
        vec3 _1336 = mat3(vec3(1.0, (rg), (rb)), vec3((gr), 1.0, (gb)), vec3((br), (bg), 1.0)) * _2825;
        vec3 _1346 = (pow(_1336, vec3(2.7999999523162841796875)) * 2.0) - pow(_1336, vec3(3.599999904632568359375));
        float _1360 = ((_1346.x * 0.300000011920928955078125) + (_1346.y * 0.60000002384185791015625)) + (_1346.z * 0.100000001490116119384765625);
        float _1365 = fract(_2821.y - 0.5);
        bool _1368 = (inter) > 0.5;
        bool _1374;
        if (_1368)
        {
            _1374 = (vec4(TextureSize, 1.0 / TextureSize)).y > 400.0;
        }
        else
        {
            _1374 = _1368;
        }
        vec3 _2831;
        if (_1374)
        {
            _2831 = _1346;
        }
        else
        {
            float _1635 = mix((beamlow), (beamhigh), _1360);
            float _1638 = _1365 * _1635;
            float _1388 = 1.0 - _1365;
            float _1665 = _1388 * _1635;
            _2831 = (_1346 * exp2(((-mix((scanlow), (scanhigh), _1365)) * _1638) * _1638)) + (_1346 * exp2(((-mix((scanlow), (scanhigh), _1388)) * _1665) * _1665));
        }
        float _1406 = ((_2831.x * 0.300000011920928955078125) + (_2831.y * 0.60000002384185791015625)) + (_2831.z * 0.100000001490116119384765625);
        vec2 _1411 = RA_VARYING_0 * (vec4(OutputSize, 1.0 / OutputSize)).xy;
        vec3 _2522;
        do
        {
            vec2 _1701 = floor(_1411 / vec2((masksize)));
            if ((Shadowmask) == 0.0)
            {
                if (fract(_1701.x * 0.4999000132083892822265625) < 0.4999000132083892822265625)
                {
                    _2522 = vec3(1.0, (MaskDark), 1.0);
                    break;
                }
                else
                {
                    _2522 = vec3((MaskDark), 1.0, (MaskDark));
                    break;
                }
                break; // unreachable workaround
            }
            else
            {
                if ((Shadowmask) == 1.0)
                {
                    vec3 _1734 = vec3((MaskDark));
                    float _1738 = _1701.x;
                    float _2519;
                    if (fract((_1701.y + float(fract(_1738 * 0.16666667163372039794921875) < 0.5)) * 0.5) < 0.5)
                    {
                        _2519 = (MaskDark);
                    }
                    else
                    {
                        _2519 = (MaskLight);
                    }
                    float _1758 = fract(_1738 * 0.3333333432674407958984375);
                    vec3 _2853;
                    if (_1758 < 0.333000004291534423828125)
                    {
                        vec3 _2719 = _1734;
                        _2719.z = (MaskLight);
                        _2853 = _2719;
                    }
                    else
                    {
                        vec3 _2854;
                        if (_1758 < 0.66600000858306884765625)
                        {
                            vec3 _2717 = _1734;
                            _2717.y = (MaskLight);
                            _2854 = _2717;
                        }
                        else
                        {
                            vec3 _2715 = _1734;
                            _2715.x = (MaskLight);
                            _2854 = _2715;
                        }
                        _2853 = _2854;
                    }
                    _2522 = _2853 * _2519;
                    break;
                }
                else
                {
                    if ((Shadowmask) == 2.0)
                    {
                        float _1790 = fract(_1701.x * 0.33329999446868896484375);
                        if (_1790 < 0.33329999446868896484375)
                        {
                            _2522 = vec3((MaskDark), (MaskDark), (MaskLight));
                            break;
                        }
                        if (_1790 < 0.6665999889373779296875)
                        {
                            _2522 = vec3((MaskDark), (MaskLight), (MaskDark));
                            break;
                        }
                        else
                        {
                            _2522 = vec3((MaskLight), (MaskDark), (MaskDark));
                            break;
                        }
                        break; // unreachable workaround
                    }
                }
            }
            if ((Shadowmask) == 3.0)
            {
                if (fract(_1701.x * 0.5) < 0.5)
                {
                    _2522 = vec3(1.0);
                    break;
                }
                else
                {
                    _2522 = vec3((MaskDark));
                    break;
                }
                break; // unreachable workaround
            }
            else
            {
                if ((Shadowmask) == 4.0)
                {
                    float _1853 = _1701.x;
                    float _2515;
                    if (fract((_1701.y + float(fract(_1853 * 0.25) < 0.5)) * 0.5) < 0.5)
                    {
                        _2515 = (MaskDark);
                    }
                    else
                    {
                        _2515 = (MaskLight);
                    }
                    vec3 _2850;
                    if (fract(_1853 * 0.5) < 0.5)
                    {
                        vec3 _2768 = _2831;
                        _2768.x = 1.0;
                        _2768.z = 1.0;
                        _2850 = _2768;
                    }
                    else
                    {
                        vec3 _2766 = _2831;
                        _2766.y = 1.0;
                        _2850 = _2766;
                    }
                    _2522 = _2850 * _2515;
                    break;
                }
                else
                {
                    if ((Shadowmask) == 5.0)
                    {
                        float _1892 = _1701.x;
                        float _1894 = fract(_1892 * 0.25);
                        vec3 _2507;
                        if (_1894 < 0.5)
                        {
                            vec3 _2508;
                            if (fract(_1701.y * 0.3333333432674407958984375) < 0.66600000858306884765625)
                            {
                                vec3 _2509;
                                if (fract(_1892 * 0.5) < 0.5)
                                {
                                    _2509 = vec3(1.0, (MaskDark), 1.0);
                                }
                                else
                                {
                                    _2509 = vec3((MaskDark), 1.0, (MaskDark));
                                }
                                _2508 = _2509;
                            }
                            else
                            {
                                _2508 = vec3(1.0) * _1406;
                            }
                            _2507 = _2508;
                        }
                        else
                        {
                            vec3 _2510;
                            if (_1894 >= 0.5)
                            {
                                vec3 _2511;
                                if (fract(_1701.y * 0.3333333432674407958984375) > 0.333000004291534423828125)
                                {
                                    vec3 _2512;
                                    if (fract(_1892 * 0.5) < 0.5)
                                    {
                                        _2512 = vec3(1.0, (MaskDark), 1.0);
                                    }
                                    else
                                    {
                                        _2512 = vec3((MaskDark), 1.0, (MaskDark));
                                    }
                                    _2511 = _2512;
                                }
                                else
                                {
                                    _2511 = vec3(1.0) * _1406;
                                }
                                _2510 = _2511;
                            }
                            else
                            {
                                _2510 = vec3(1.0);
                            }
                            _2507 = _2510;
                        }
                        _2522 = _2507;
                        break;
                    }
                    else
                    {
                        if ((Shadowmask) == 6.0)
                        {
                            vec3 _1972 = vec3((MaskDark));
                            float _1974 = _1701.x;
                            float _1976 = fract(_1974 * 0.16666667163372039794921875);
                            vec3 _2840;
                            if (_1976 < 0.5)
                            {
                                vec3 _2845;
                                if (fract(_1701.y * 0.25) < 0.75)
                                {
                                    float _1988 = fract(_1974 * 0.3333333432674407958984375);
                                    vec3 _2846;
                                    if (_1988 < 0.33329999446868896484375)
                                    {
                                        vec3 _2755 = _1972;
                                        _2755.x = (MaskLight);
                                        _2846 = _2755;
                                    }
                                    else
                                    {
                                        vec3 _2847;
                                        if (_1988 < 0.6665999889373779296875)
                                        {
                                            vec3 _2753 = _1972;
                                            _2753.y = (MaskLight);
                                            _2847 = _2753;
                                        }
                                        else
                                        {
                                            vec3 _2751 = _1972;
                                            _2751.z = (MaskLight);
                                            _2847 = _2751;
                                        }
                                        _2846 = _2847;
                                    }
                                    _2845 = _2846;
                                }
                                else
                                {
                                    _2845 = _1972;
                                }
                                _2840 = _2845;
                            }
                            else
                            {
                                vec3 _2841;
                                if (_1976 >= 0.5)
                                {
                                    float _2026 = fract(_1701.y * 0.25);
                                    bool _2027 = _2026 >= 0.5;
                                    bool _2036;
                                    if (!_2027)
                                    {
                                        _2036 = _2026 < 0.25;
                                    }
                                    else
                                    {
                                        _2036 = _2027;
                                    }
                                    vec3 _2842;
                                    if (_2036)
                                    {
                                        float _2041 = fract(_1974 * 0.3333333432674407958984375);
                                        vec3 _2843;
                                        if (_2041 < 0.33329999446868896484375)
                                        {
                                            vec3 _2746 = _1972;
                                            _2746.x = (MaskLight);
                                            _2843 = _2746;
                                        }
                                        else
                                        {
                                            vec3 _2844;
                                            if (_2041 < 0.6665999889373779296875)
                                            {
                                                vec3 _2744 = _1972;
                                                _2744.y = (MaskLight);
                                                _2844 = _2744;
                                            }
                                            else
                                            {
                                                vec3 _2742 = _1972;
                                                _2742.z = (MaskLight);
                                                _2844 = _2742;
                                            }
                                            _2843 = _2844;
                                        }
                                        _2842 = _2843;
                                    }
                                    else
                                    {
                                        _2842 = _1972;
                                    }
                                    _2841 = _2842;
                                }
                                else
                                {
                                    _2841 = _1972;
                                }
                                _2840 = _2841;
                            }
                            _2522 = _2840;
                            break;
                        }
                        else
                        {
                            if ((Shadowmask) == 7.0)
                            {
                                float _2080 = fract(_1701.x * 0.33329999446868896484375);
                                if (_2080 < 0.33329999446868896484375)
                                {
                                    _2522 = vec3((MaskDark), (MaskLight), (MaskLight) * _2831.z);
                                    break;
                                }
                                if (_2080 < 0.6665999889373779296875)
                                {
                                    _2522 = vec3((MaskLight) * _2831.x, (MaskDark), (MaskLight));
                                    break;
                                }
                                else
                                {
                                    _2522 = vec3((MaskLight), (MaskLight) * _2831.y, (MaskDark));
                                    break;
                                }
                                break; // unreachable workaround
                            }
                            else
                            {
                                if ((Shadowmask) == 8.0)
                                {
                                    vec3 _2131 = vec3((MaskDark));
                                    float _2135 = _1701.x;
                                    bool _2138 = fract(_2135 * 0.16666667163372039794921875) < 0.5;
                                    float _2144 = fract(_2135 * 0.3333333432674407958984375);
                                    vec3 _2835;
                                    if (_2144 < 0.333000004291534423828125)
                                    {
                                        vec3 _2728 = _2131;
                                        _2728.z = 0.89999997615814208984375;
                                        _2835 = _2728;
                                    }
                                    else
                                    {
                                        vec3 _2836;
                                        if (_2144 < 0.66600000858306884765625)
                                        {
                                            vec3 _2726 = _2131;
                                            _2726.y = 0.89999997615814208984375;
                                            _2836 = _2726;
                                        }
                                        else
                                        {
                                            vec3 _2724 = _2131;
                                            _2724.x = 0.89999997615814208984375;
                                            _2836 = _2724;
                                        }
                                        _2835 = _2836;
                                    }
                                    float _2160 = mod(_1701.y, 2.0);
                                    bool _2164 = (_2160 == 1.0) && _2138;
                                    bool _2175;
                                    if (!_2164)
                                    {
                                        _2175 = (_2160 == 0.0) && (!_2138);
                                    }
                                    else
                                    {
                                        _2175 = _2164;
                                    }
                                    vec3 _2837;
                                    if (_2175)
                                    {
                                        _2837 = _2835 * (MaskLight);
                                    }
                                    else
                                    {
                                        _2837 = _2835;
                                    }
                                    _2522 = _2837;
                                    break;
                                }
                                else
                                {
                                    _2522 = vec3(1.0);
                                    break;
                                }
                                break; // unreachable workaround
                            }
                            break; // unreachable workaround
                        }
                        break; // unreachable workaround
                    }
                    break; // unreachable workaround
                }
                break; // unreachable workaround
            }
            break; // unreachable workaround
        } while(false);
        vec3 _1426 = _2831 * mix(_2522, vec3(1.0), vec3(_1406 * (preserve)));
        vec3 _2882;
        if ((slotmask) != 0.0)
        {
            float _2553;
            do
            {
                if ((slotmask) == 0.0)
                {
                    _2553 = 1.0;
                    break;
                }
                vec2 _2212 = floor((_1411 * 1.00010001659393310546875) / vec2((slotms)));
                float _2221 = pow(max(max(_1426.x, _1426.y), _1426.z), 1.33000004291534423828125);
                float _2229 = fract(_2212.x / ((slotwidth) * 2.0));
                float _2241 = floor((fract(_2212.y / (2.0 * (double_slot))) * 2.0) * (double_slot));
                float _2250 = mix(1.0 - (slotmask), 1.0 - (0.800000011920928955078125 * (slotmask)), _2221);
                float _2551;
                if ((_2241 == 0.0) && (_2229 < 0.5))
                {
                    _2551 = _2250;
                }
                else
                {
                    _2551 = ((_2241 == (double_slot)) && (_2229 >= 0.5)) ? _2250 : (1.0 + ((0.699999988079071044921875 * (slotmask)) * (1.0 - _2221)));
                }
                _2553 = _2551;
                break;
            } while(false);
            _2882 = _1426 * _2553;
        }
        else
        {
            _2882 = _1426;
        }
        vec3 _1467 = pow(_2882 * mix((brightboost1), (brightboost2), max(max(_2882.x, _2882.y), _2882.z)), vec3(1.0 / (GAMMA_OUT)));
        vec3 _2884;
        if ((glow_str) != 0.0)
        {
            vec2 _2295 = (vec4(TextureSize, 1.0 / TextureSize)).zw / vec2((quality));
            float _2298 = -(glow);
            float _2554;
            vec3 _2555;
            _2555 = vec3(0.0);
            _2554 = _2298;
            vec3 _2653;
            for (; _2554 <= (glow); _2555 = _2653, _2554 += 1.0)
            {
                float _2308 = 1.0 / (glow);
                _2653 = _2555;
                for (float _2646 = _2298; _2646 <= (glow); )
                {
                    vec3 _2331 = texture(Texture, _1125 + (vec2(_2554, _2646) * _2295)).xyz * _2308;
                    _2653 += (_2331 * _2331);
                    _2646 += 1.0;
                    continue;
                }
            }
            _2884 = _1467 + ((_2555 * (glow_str)) / vec3((glow) * (glow)));
        }
        else
        {
            _2884 = _1467;
        }
        vec3 _2885;
        if ((sat) != 1.0)
        {
            bvec3 _2675 = bvec3((length(_2884) * 0.57749998569488525390625) < 0.5);
            _2885 = mix(vec3(dot(_2884, vec3(_2675.x ? vec3(0.3200000226497650146484375, 0.5, 0.02000000141561031341552734375).x : vec3(0.4000000059604644775390625, 0.5, 0.100000001490116119384765625).x, _2675.y ? vec3(0.3200000226497650146484375, 0.5, 0.02000000141561031341552734375).y : vec3(0.4000000059604644775390625, 0.5, 0.100000001490116119384765625).y, _2675.z ? vec3(0.3200000226497650146484375, 0.5, 0.02000000141561031341552734375).z : vec3(0.4000000059604644775390625, 0.5, 0.100000001490116119384765625).z))), _2884, vec3((sat)));
        }
        else
        {
            _2885 = _2884;
        }
        vec3 _2886;
        if ((corner) != 0.0)
        {
            vec2 _2395 = (_1040 - vec2(0.5)) * 1.0;
            vec2 _2412 = vec2((corner));
            vec2 _2417 = _2412 - min(min(_2395 + vec2(0.5), vec2(0.5) - _2395) * vec2(1.0, (vec4(TextureSize, 1.0 / TextureSize)).y / (vec4(TextureSize, 1.0 / TextureSize)).x), _2412);
            _2886 = _2885 * clamp(((corner) - sqrt(dot(_2417, _2417))) * (smoothness), 0.0, 1.0);
        }
        else
        {
            _2886 = _2885;
        }
        vec3 _2887;
        if ((nois) != 0.0)
        {
            _2887 = _2886 * (1.0 + (fract(sin((float((uint(FrameCount))) * 0.01666666753590106964111328125) * dot(_1125 * 2.0, vec2(12.98980045318603515625, 78.233001708984375))) * 43758.546875) / (nois)));
        }
        else
        {
            _2887 = _2886;
        }
        vec4 _1525 = vec4(_2887 * mix(1.0, (postbr), _1360), 1.0);
        vec4 _2890;
        if ((contrast) != 1.0)
        {
            float _2449 = (1.0 - (contrast)) * 0.5;
            _2890 = mat4(vec4((contrast), 0.0, 0.0, 0.0), vec4(0.0, (contrast), 0.0, 0.0), vec4(0.0, 0.0, (contrast), 0.0), vec4(_2449, _2449, _2449, 1.0)) * _1525;
        }
        else
        {
            _2890 = _1525;
        }
        bool _1545;
        if (_1368)
        {
            _1545 = (vec4(TextureSize, 1.0 / TextureSize)).y > 400.0;
        }
        else
        {
            _1545 = _1368;
        }
        bool _1554;
        if (_1545)
        {
            _1554 = fract(float((uint(FrameCount))) * 0.5) < 0.5;
        }
        else
        {
            _1554 = _1545;
        }
        vec4 _2891;
        if (_1554)
        {
            _2891 = _2890 * 0.949999988079071044921875;
        }
        else
        {
            _2891 = _2890;
        }
        vec2 _2471 = RA_VARYING_0 * (vec2(1.0) - RA_VARYING_0);
        float _2677 = ((vignette) == 0.0) ? 1.0 : min(pow((_2471.x * _2471.y) * (vstr), (vpower)), 1.0);
        vec3 _1565 = _2891.xyz * mat3(vec3(_2677, 0.0, 0.0), vec3(0.0, _2677, 0.0), vec3(0.0, 0.0, _2677));
        vec4 _2784 = _2891;
        _2784.x = _1565.x;
        _2784.y = _1565.y;
        _2784.z = _1565.z;
        _2892 = _2784;
    }
    FragColor = _2892;
}


#endif
