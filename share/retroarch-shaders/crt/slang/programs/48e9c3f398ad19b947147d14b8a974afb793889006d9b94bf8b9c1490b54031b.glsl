// Generated from crt/shaders/crt-gdv-mini-ultra.slang. See slang/upstream for licence/source.
#version 120
#pragma parameter scanline          "Scanline Adjust" 10.0 1.0 15.0 1.0
#pragma parameter beam_min          "Scanline Dark" 1.5 0.5 3.0 0.05
#pragma parameter beam_max          "Scanline Bright" 2.0 0.5 3.0 0.05
#pragma parameter h_sharp           "Horizontal Sharpness" 2.5 1.0 5.0 0.05
#pragma parameter shadowMask 		"  CRT Mask: 0:CGWG, 1-4:Lottes, 5-6:Trinitron" 11.0 -1.0 11.0 1.0
#pragma parameter thres "  Mask Effect Threshold" 0.4 0.0 0.9 0.02
#pragma parameter masksize 			"  CRT Mask Size (2.0 is nice in 4k)" 1.0 1.0 2.0 1.0
#pragma parameter mcut 				"  Mask 5-7-10 cutoff" 0.2 0.0 0.5 0.05
#pragma parameter maskDark          "  Lottes maskDark" 0.0 0.0 2.0 0.1
#pragma parameter maskLight 		"  Lottes maskLight" 1.5 0.0 2.0 0.1
#pragma parameter CGWG              "  CGWG Mask Str." 1.0 0.0 1.0 0.1
#pragma parameter warpX 			"CurvatureX (default 0.03)" 0.0 0.0 0.25 0.01
#pragma parameter warpY 			"CurvatureY (default 0.04)" 0.05 0.0 0.25 0.01
#pragma parameter vignette 			"Vignette On/Off" 1.0 0.0 1.0 1.0
#pragma parameter gamma_out_red 		"  Gamma out Red" 2.2 1.0 4.0 0.1
#pragma parameter gamma_out_green 		"  Gamma out Green" 2.2 1.0 4.0 0.1
#pragma parameter gamma_out_blue 		"  Gamma out Blue" 2.2 1.0 4.0 0.1
#pragma parameter brightboost 		"  Bright boost" 1.2 0.5 2.0 0.05
#pragma parameter sat 				"  Saturation adjustment" 1.2 0.0 2.0 0.05
#pragma parameter glow "Glow Strength" 0.35 0.0 1.0 0.01
#pragma parameter gdv_mono "Mono Display On/Off" 0.0 0.0 1.0 1.0
#pragma parameter gdv_R "Mono Red/Channel" 1.0 0.0 2.0 0.01
#pragma parameter gdv_G "Mono Green/Channel" 1.0 0.0 2.0 0.01
#pragma parameter gdv_B "Mono Blue/Channel" 1.0 0.0 2.0 0.01
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
    RA_VARYING_0 = TexCoord * 1.00010001659393310546875;
}


#endif
#ifdef FRAGMENT

uniform float CGWG;
uniform vec2 OrigTextureSize;
uniform vec2 OutputSize;
uniform vec2 TextureSize;
uniform float beam_max;
uniform float beam_min;
uniform float brightboost;
uniform float gamma_out_blue;
uniform float gamma_out_green;
uniform float gamma_out_red;
uniform float gdv_B;
uniform float gdv_G;
uniform float gdv_R;
uniform float gdv_mono;
uniform float glow;
uniform float h_sharp;
uniform float maskDark;
uniform float maskLight;
uniform float masksize;
uniform float mcut;
uniform float sat;
uniform float scanline;
uniform float shadowMask;
uniform float thres;
uniform float vignette;
uniform float warpX;
uniform float warpY;
struct UBO
{
    vec4 OutputSize;
    vec4 SourceSize;
    vec4 OriginalSize;
};



struct Push
{
    float brightboost;
    float sat;
    float glow;
    float scanline;
    float beam_min;
    float beam_max;
    float h_sharp;
    float shadowMask;
    float masksize;
    float mcut;
    float maskDark;
    float maskLight;
    float CGWG;
    float warpX;
    float warpY;
    float gamma_out_red;
    float gamma_out_green;
    float gamma_out_blue;
    float vignette;
    float gdv_mono;
    float gdv_R;
    float gdv_G;
    float gdv_B;
    float thres;
};



uniform sampler2D Texture;

varying vec2 RA_VARYING_0;

void main()
{
    vec2 _1678;
    float _1680;
    vec3 _1685;
    float _1687;
    bool _1688;
    vec2 _1617 = (RA_VARYING_0 * 2.0) - vec2(1.0);
    float _1619 = _1617.y;
    float _1628 = _1617.x;
    vec2 _1312 = (((_1617 * vec2(1.0 + ((_1619 * _1619) * (warpX)), 1.0 + ((_1628 * _1628) * (warpY)))) * 0.5) + vec2(0.5)) * (vec4(TextureSize, 1.0 / TextureSize)).xy;
    vec2 _1315 = fract(_1312);
    vec2 _1331 = (floor(_1312) * (vec4(TextureSize, 1.0 / TextureSize)).zw) + ((vec4(TextureSize, 1.0 / TextureSize)).zw * 0.5);
    vec4 _1335 = texture2D(Texture, _1331);
    vec4 _1342 = texture2D(Texture, _1331 + vec2((vec4(TextureSize, 1.0 / TextureSize)).z, 0.0));
    vec4 _1349 = texture2D(Texture, _1331 + vec2(0.0, (vec4(TextureSize, 1.0 / TextureSize)).w));
    vec4 _1356 = texture2D(Texture, _1331 + (vec4(TextureSize, 1.0 / TextureSize)).zw);
    float _1360 = _1315.x;
    float _1365 = pow(_1360, (h_sharp));
    float _1373 = pow(1.0 - _1360, (h_sharp));
    vec3 _1385 = vec3(_1365 + _1373);
    vec3 _1386 = ((_1342.xyz * _1365) + (_1335.xyz * _1373)) / _1385;
    vec3 _1399 = ((_1356.xyz * _1365) + (_1349.xyz * _1373)) / _1385;
    float _1402 = _1315.y;
    float _1414 = ((_1386.x * 0.300000011920928955078125) + (_1386.y * 0.60000002384185791015625)) + (_1386.z * 0.100000001490116119384765625);
    float _1426 = ((_1399.x * 0.300000011920928955078125) + (_1399.y * 0.60000002384185791015625)) + (_1399.z * 0.100000001490116119384765625);
    vec3 _1436 = (pow(_1386, vec3(2.7999999523162841796875)) * 2.0) - pow(_1386, vec3(3.599999904632568359375));
    vec3 _1442 = (pow(_1399, vec3(2.7999999523162841796875)) * 2.0) - pow(_1399, vec3(3.599999904632568359375));
    vec3 _3458;
    do
    {
        _1678 = floor((RA_VARYING_0 * (vec4(OutputSize, 1.0 / OutputSize)).xy) / vec2((masksize)));
        _1680 = (maskDark);
        _1685 = vec3(_1680);
        _1687 = (shadowMask);
        _1688 = _1687 == (-1.0);
        vec3 _4268;
        if (_1688)
        {
            _4268 = vec3(1.0);
        }
        else
        {
            vec3 _4269;
            if (_1687 == 0.0)
            {
                float _1702 = 1.0 - (CGWG);
                vec3 _4270;
                if (fract(_1678.x * 0.5) < 0.5)
                {
                    _4270 = vec3(1.10000002384185791015625, _1702, 1.10000002384185791015625);
                }
                else
                {
                    _4270 = vec3(_1702, 1.10000002384185791015625, _1702);
                }
                _4269 = _4270;
            }
            else
            {
                vec3 _4271;
                if (_1687 == 1.0)
                {
                    float _3455;
                    if (fract((_1678.y + float(fract(_1678.x * 0.16666667163372039794921875) < 0.5)) * 0.5) < 0.5)
                    {
                        _3455 = _1680;
                    }
                    else
                    {
                        _3455 = (maskLight);
                    }
                    float _1746 = fract(_1678.x * 0.3333333432674407958984375);
                    vec3 _4266;
                    if (_1746 < 0.333000004291534423828125)
                    {
                        vec3 _3891 = _1685;
                        _3891.z = (maskLight);
                        _4266 = _3891;
                    }
                    else
                    {
                        vec3 _4267;
                        if (_1746 < 0.66600000858306884765625)
                        {
                            vec3 _3894 = _1685;
                            _3894.y = (maskLight);
                            _4267 = _3894;
                        }
                        else
                        {
                            vec3 _3896 = _1685;
                            _3896.x = (maskLight);
                            _4267 = _3896;
                        }
                        _4266 = _4267;
                    }
                    _4271 = _4266 * _3455;
                }
                else
                {
                    vec3 _4272;
                    if (_1687 == 2.0)
                    {
                        float _1780 = fract(_1678.x * 0.3333333432674407958984375);
                        vec3 _4273;
                        if (_1780 < 0.333000004291534423828125)
                        {
                            vec3 _3902 = _1685;
                            _3902.z = (maskLight);
                            _4273 = _3902;
                        }
                        else
                        {
                            vec3 _4274;
                            if (_1780 < 0.66600000858306884765625)
                            {
                                vec3 _3905 = _1685;
                                _3905.y = (maskLight);
                                _4274 = _3905;
                            }
                            else
                            {
                                vec3 _3907 = _1685;
                                _3907.x = (maskLight);
                                _4274 = _3907;
                            }
                            _4273 = _4274;
                        }
                        _4272 = _4273;
                    }
                    else
                    {
                        vec3 _4275;
                        if (_1687 == 3.0)
                        {
                            float _1818 = fract((_1678.x + (_1678.y * 3.0)) * 0.16666667163372039794921875);
                            vec3 _4276;
                            if (_1818 < 0.333000004291534423828125)
                            {
                                vec3 _3917 = _1685;
                                _3917.z = (maskLight);
                                _4276 = _3917;
                            }
                            else
                            {
                                vec3 _4277;
                                if (_1818 < 0.66600000858306884765625)
                                {
                                    vec3 _3920 = _1685;
                                    _3920.y = (maskLight);
                                    _4277 = _3920;
                                }
                                else
                                {
                                    vec3 _3922 = _1685;
                                    _3922.x = (maskLight);
                                    _4277 = _3922;
                                }
                                _4276 = _4277;
                            }
                            _4275 = _4276;
                        }
                        else
                        {
                            vec3 _4278;
                            if (_1687 == 4.0)
                            {
                                vec2 _1848 = floor(_1678 * vec2(1.0, 0.5));
                                float _1859 = fract((_1848.x + (_1848.y * 3.0)) * 0.16666667163372039794921875);
                                vec3 _4279;
                                if (_1859 < 0.333000004291534423828125)
                                {
                                    vec3 _3932 = _1685;
                                    _3932.z = (maskLight);
                                    _4279 = _3932;
                                }
                                else
                                {
                                    vec3 _4280;
                                    if (_1859 < 0.66600000858306884765625)
                                    {
                                        vec3 _3935 = _1685;
                                        _3935.y = (maskLight);
                                        _4280 = _3935;
                                    }
                                    else
                                    {
                                        vec3 _3937 = _1685;
                                        _3937.x = (maskLight);
                                        _4280 = _3937;
                                    }
                                    _4279 = _4280;
                                }
                                _4278 = _4279;
                            }
                            else
                            {
                                vec3 _4281;
                                if (_1687 == 5.0)
                                {
                                    float _1894 = max(max(_1436.x, _1436.y), _1436.z);
                                    vec3 _1915 = vec3(min((1.25 * max(_1894 - (mcut), 0.0)) / (1.0 - (mcut)), _1680 + ((0.20000000298023223876953125 * (1.0 - _1680)) * _1894)));
                                    float _1918 = 0.800000011920928955078125 * (maskLight);
                                    float _1930 = (_1918 - ((0.5 * (_1918 - 1.0)) * _1894)) + (0.75 * (1.0 - _1894));
                                    vec3 _4282;
                                    if (fract(_1678.x * 0.5) < 0.5)
                                    {
                                        vec3 _3946 = _1915;
                                        _3946.x = _1930;
                                        _3946.z = _1930;
                                        _4282 = _3946;
                                    }
                                    else
                                    {
                                        vec3 _3950 = _1915;
                                        _3950.y = _1930;
                                        _4282 = _3950;
                                    }
                                    _4281 = _4282;
                                }
                                else
                                {
                                    vec3 _4283;
                                    if (_1687 == 6.0)
                                    {
                                        float _1961 = max(max(_1436.x, _1436.y), _1436.z);
                                        vec3 _1982 = vec3(min((1.33000004291534423828125 * max(_1961 - (mcut), 0.0)) / (1.0 - (mcut)), _1680 + ((0.2249999940395355224609375 * (1.0 - _1680)) * _1961)));
                                        float _1985 = 0.800000011920928955078125 * (maskLight);
                                        float _1997 = (_1985 - ((0.5 * (_1985 - 1.0)) * _1961)) + (0.75 * (1.0 - _1961));
                                        float _2002 = fract(_1678.x * 0.3333333432674407958984375);
                                        vec3 _4284;
                                        if (_2002 < 0.333000004291534423828125)
                                        {
                                            vec3 _3959 = _1982;
                                            _3959.x = _1997;
                                            _4284 = _3959;
                                        }
                                        else
                                        {
                                            vec3 _4285;
                                            if (_2002 < 0.66600000858306884765625)
                                            {
                                                vec3 _3962 = _1982;
                                                _3962.y = _1997;
                                                _4285 = _3962;
                                            }
                                            else
                                            {
                                                vec3 _3964 = _1982;
                                                _3964.z = _1997;
                                                _4285 = _3964;
                                            }
                                            _4284 = _4285;
                                        }
                                        _4283 = _4284;
                                    }
                                    else
                                    {
                                        vec3 _4286;
                                        if (_1687 == 7.0)
                                        {
                                            float _2037 = max(max(_1436.x, _1436.y), _1436.z);
                                            vec3 _4287;
                                            if (fract(_1678.x * 0.5) < 0.5)
                                            {
                                                _4287 = vec3(1.0 + (0.60000002384185791015625 * (1.0 - _2037)));
                                            }
                                            else
                                            {
                                                _4287 = vec3(min((1.60000002384185791015625 * max(_2037 - (mcut), 0.0)) / (1.0 - (mcut)), 1.0 - (CGWG)));
                                            }
                                            _4286 = _4287;
                                        }
                                        else
                                        {
                                            vec3 _4288;
                                            if (_1687 == 8.0)
                                            {
                                                float _3451;
                                                if (fract((_1678.y + float(fract(_1678.x * 0.25) < 0.5)) * 0.5) < 0.5)
                                                {
                                                    _3451 = _1680;
                                                }
                                                else
                                                {
                                                    _3451 = (maskLight);
                                                }
                                                vec3 _4263;
                                                if (fract(_1678.x * 0.5) < 0.5)
                                                {
                                                    vec3 _3979 = _1685;
                                                    _3979.x = (maskLight);
                                                    _3979.z = (maskLight);
                                                    _4263 = _3979;
                                                }
                                                else
                                                {
                                                    vec3 _3983 = _1685;
                                                    _3983.y = (maskLight);
                                                    _4263 = _3983;
                                                }
                                                _4288 = _4263 * _3451;
                                            }
                                            else
                                            {
                                                if (_1687 == 9.0)
                                                {
                                                    bool _2129 = fract(_1678.x * 0.16666667163372039794921875) < 0.5;
                                                    float _2135 = fract(_1678.x * 0.3333333432674407958984375);
                                                    vec3 _4258;
                                                    if (_2135 < 0.33329999446868896484375)
                                                    {
                                                        vec3 _3987 = _1685;
                                                        _3987.z = 0.89999997615814208984375;
                                                        _4258 = _3987;
                                                    }
                                                    else
                                                    {
                                                        vec3 _4259;
                                                        if (_2135 < 0.6665999889373779296875)
                                                        {
                                                            vec3 _3989 = _1685;
                                                            _3989.y = 0.89999997615814208984375;
                                                            _4259 = _3989;
                                                        }
                                                        else
                                                        {
                                                            vec3 _3991 = _1685;
                                                            _3991.x = 0.89999997615814208984375;
                                                            _4259 = _3991;
                                                        }
                                                        _4258 = _4259;
                                                    }
                                                    float _2151 = mod(_1678.y, 2.0);
                                                    bool _2155 = (_2151 == 1.0) && _2129;
                                                    bool _2166;
                                                    if (!_2155)
                                                    {
                                                        _2166 = (_2151 == 0.0) && (!_2129);
                                                    }
                                                    else
                                                    {
                                                        _2166 = _2155;
                                                    }
                                                    vec3 _4260;
                                                    if (_2166)
                                                    {
                                                        _4260 = _4258 * (maskLight);
                                                    }
                                                    else
                                                    {
                                                        _4260 = _4258;
                                                    }
                                                    _3458 = _4260;
                                                    break;
                                                }
                                                else
                                                {
                                                    if (_1687 == 10.0)
                                                    {
                                                        float _2202 = fract(_1678.x * 0.3333333432674407958984375);
                                                        vec3 _4252;
                                                        if (_2202 > 0.33329999446868896484375)
                                                        {
                                                            vec3 _3998 = _1685;
                                                            _3998.x = 1.0;
                                                            _3998.z = 1.0;
                                                            _4252 = _3998;
                                                        }
                                                        else
                                                        {
                                                            vec3 _4253;
                                                            if (_2202 > 0.6665999889373779296875)
                                                            {
                                                                vec3 _4002 = _1685;
                                                                _4002.y = 1.0;
                                                                _4253 = _4002;
                                                            }
                                                            else
                                                            {
                                                                _4253 = vec3((mcut));
                                                            }
                                                            _4252 = _4253;
                                                        }
                                                        vec3 _4254;
                                                        if (_2202 > 0.333000004291534423828125)
                                                        {
                                                            _4254 = _4252 * ((fract((_1678.y + float(fract(_1678.x * 0.16666667163372039794921875) < 0.5)) * 0.5) < 0.5) ? 1.0 : (maskLight));
                                                        }
                                                        else
                                                        {
                                                            _4254 = _4252;
                                                        }
                                                        _3458 = _4254;
                                                        break;
                                                    }
                                                    else
                                                    {
                                                        if (_1687 == 11.0)
                                                        {
                                                            bvec3 _3833 = bvec3(fract(_1678.x * 0.3333333432674407958984375) > 0.333000004291534423828125);
                                                            _3458 = vec3(_3833.x ? vec3(1.0).x : _1685.x, _3833.y ? vec3(1.0).y : _1685.y, _3833.z ? vec3(1.0).z : _1685.z);
                                                            break;
                                                        }
                                                    }
                                                }
                                                _4288 = _1685;
                                            }
                                            _4286 = _4288;
                                        }
                                        _4283 = _4286;
                                    }
                                    _4281 = _4283;
                                }
                                _4278 = _4281;
                            }
                            _4275 = _4278;
                        }
                        _4272 = _4275;
                    }
                    _4271 = _4272;
                }
                _4269 = _4271;
            }
            _4268 = _4269;
        }
        _3458 = _4268;
        break;
    } while(false);
    vec3 _1460 = _1436 * mix(_3458, vec3(1.0), vec3(_1414 * (thres)));
    vec3 _3523;
    do
    {
        vec3 _4339;
        if (_1688)
        {
            _4339 = vec3(1.0);
        }
        else
        {
            vec3 _4340;
            if (_1687 == 0.0)
            {
                float _2325 = 1.0 - (CGWG);
                vec3 _4341;
                if (fract(_1678.x * 0.5) < 0.5)
                {
                    _4341 = vec3(1.10000002384185791015625, _2325, 1.10000002384185791015625);
                }
                else
                {
                    _4341 = vec3(_2325, 1.10000002384185791015625, _2325);
                }
                _4340 = _4341;
            }
            else
            {
                vec3 _4342;
                if (_1687 == 1.0)
                {
                    float _3520;
                    if (fract((_1678.y + float(fract(_1678.x * 0.16666667163372039794921875) < 0.5)) * 0.5) < 0.5)
                    {
                        _3520 = _1680;
                    }
                    else
                    {
                        _3520 = (maskLight);
                    }
                    float _2369 = fract(_1678.x * 0.3333333432674407958984375);
                    vec3 _4337;
                    if (_2369 < 0.333000004291534423828125)
                    {
                        vec3 _4030 = _1685;
                        _4030.z = (maskLight);
                        _4337 = _4030;
                    }
                    else
                    {
                        vec3 _4338;
                        if (_2369 < 0.66600000858306884765625)
                        {
                            vec3 _4033 = _1685;
                            _4033.y = (maskLight);
                            _4338 = _4033;
                        }
                        else
                        {
                            vec3 _4035 = _1685;
                            _4035.x = (maskLight);
                            _4338 = _4035;
                        }
                        _4337 = _4338;
                    }
                    _4342 = _4337 * _3520;
                }
                else
                {
                    vec3 _4343;
                    if (_1687 == 2.0)
                    {
                        float _2403 = fract(_1678.x * 0.3333333432674407958984375);
                        vec3 _4344;
                        if (_2403 < 0.333000004291534423828125)
                        {
                            vec3 _4041 = _1685;
                            _4041.z = (maskLight);
                            _4344 = _4041;
                        }
                        else
                        {
                            vec3 _4345;
                            if (_2403 < 0.66600000858306884765625)
                            {
                                vec3 _4044 = _1685;
                                _4044.y = (maskLight);
                                _4345 = _4044;
                            }
                            else
                            {
                                vec3 _4046 = _1685;
                                _4046.x = (maskLight);
                                _4345 = _4046;
                            }
                            _4344 = _4345;
                        }
                        _4343 = _4344;
                    }
                    else
                    {
                        vec3 _4346;
                        if (_1687 == 3.0)
                        {
                            float _2441 = fract((_1678.x + (_1678.y * 3.0)) * 0.16666667163372039794921875);
                            vec3 _4347;
                            if (_2441 < 0.333000004291534423828125)
                            {
                                vec3 _4056 = _1685;
                                _4056.z = (maskLight);
                                _4347 = _4056;
                            }
                            else
                            {
                                vec3 _4348;
                                if (_2441 < 0.66600000858306884765625)
                                {
                                    vec3 _4059 = _1685;
                                    _4059.y = (maskLight);
                                    _4348 = _4059;
                                }
                                else
                                {
                                    vec3 _4061 = _1685;
                                    _4061.x = (maskLight);
                                    _4348 = _4061;
                                }
                                _4347 = _4348;
                            }
                            _4346 = _4347;
                        }
                        else
                        {
                            vec3 _4349;
                            if (_1687 == 4.0)
                            {
                                vec2 _2471 = floor(_1678 * vec2(1.0, 0.5));
                                float _2482 = fract((_2471.x + (_2471.y * 3.0)) * 0.16666667163372039794921875);
                                vec3 _4350;
                                if (_2482 < 0.333000004291534423828125)
                                {
                                    vec3 _4071 = _1685;
                                    _4071.z = (maskLight);
                                    _4350 = _4071;
                                }
                                else
                                {
                                    vec3 _4351;
                                    if (_2482 < 0.66600000858306884765625)
                                    {
                                        vec3 _4074 = _1685;
                                        _4074.y = (maskLight);
                                        _4351 = _4074;
                                    }
                                    else
                                    {
                                        vec3 _4076 = _1685;
                                        _4076.x = (maskLight);
                                        _4351 = _4076;
                                    }
                                    _4350 = _4351;
                                }
                                _4349 = _4350;
                            }
                            else
                            {
                                vec3 _4352;
                                if (_1687 == 5.0)
                                {
                                    float _2517 = max(max(_1442.x, _1442.y), _1442.z);
                                    vec3 _2538 = vec3(min((1.25 * max(_2517 - (mcut), 0.0)) / (1.0 - (mcut)), _1680 + ((0.20000000298023223876953125 * (1.0 - _1680)) * _2517)));
                                    float _2541 = 0.800000011920928955078125 * (maskLight);
                                    float _2553 = (_2541 - ((0.5 * (_2541 - 1.0)) * _2517)) + (0.75 * (1.0 - _2517));
                                    vec3 _4353;
                                    if (fract(_1678.x * 0.5) < 0.5)
                                    {
                                        vec3 _4085 = _2538;
                                        _4085.x = _2553;
                                        _4085.z = _2553;
                                        _4353 = _4085;
                                    }
                                    else
                                    {
                                        vec3 _4089 = _2538;
                                        _4089.y = _2553;
                                        _4353 = _4089;
                                    }
                                    _4352 = _4353;
                                }
                                else
                                {
                                    vec3 _4354;
                                    if (_1687 == 6.0)
                                    {
                                        float _2584 = max(max(_1442.x, _1442.y), _1442.z);
                                        vec3 _2605 = vec3(min((1.33000004291534423828125 * max(_2584 - (mcut), 0.0)) / (1.0 - (mcut)), _1680 + ((0.2249999940395355224609375 * (1.0 - _1680)) * _2584)));
                                        float _2608 = 0.800000011920928955078125 * (maskLight);
                                        float _2620 = (_2608 - ((0.5 * (_2608 - 1.0)) * _2584)) + (0.75 * (1.0 - _2584));
                                        float _2625 = fract(_1678.x * 0.3333333432674407958984375);
                                        vec3 _4355;
                                        if (_2625 < 0.333000004291534423828125)
                                        {
                                            vec3 _4098 = _2605;
                                            _4098.x = _2620;
                                            _4355 = _4098;
                                        }
                                        else
                                        {
                                            vec3 _4356;
                                            if (_2625 < 0.66600000858306884765625)
                                            {
                                                vec3 _4101 = _2605;
                                                _4101.y = _2620;
                                                _4356 = _4101;
                                            }
                                            else
                                            {
                                                vec3 _4103 = _2605;
                                                _4103.z = _2620;
                                                _4356 = _4103;
                                            }
                                            _4355 = _4356;
                                        }
                                        _4354 = _4355;
                                    }
                                    else
                                    {
                                        vec3 _4357;
                                        if (_1687 == 7.0)
                                        {
                                            float _2660 = max(max(_1442.x, _1442.y), _1442.z);
                                            vec3 _4358;
                                            if (fract(_1678.x * 0.5) < 0.5)
                                            {
                                                _4358 = vec3(1.0 + (0.60000002384185791015625 * (1.0 - _2660)));
                                            }
                                            else
                                            {
                                                _4358 = vec3(min((1.60000002384185791015625 * max(_2660 - (mcut), 0.0)) / (1.0 - (mcut)), 1.0 - (CGWG)));
                                            }
                                            _4357 = _4358;
                                        }
                                        else
                                        {
                                            vec3 _4359;
                                            if (_1687 == 8.0)
                                            {
                                                float _3516;
                                                if (fract((_1678.y + float(fract(_1678.x * 0.25) < 0.5)) * 0.5) < 0.5)
                                                {
                                                    _3516 = _1680;
                                                }
                                                else
                                                {
                                                    _3516 = (maskLight);
                                                }
                                                vec3 _4334;
                                                if (fract(_1678.x * 0.5) < 0.5)
                                                {
                                                    vec3 _4118 = _1685;
                                                    _4118.x = (maskLight);
                                                    _4118.z = (maskLight);
                                                    _4334 = _4118;
                                                }
                                                else
                                                {
                                                    vec3 _4122 = _1685;
                                                    _4122.y = (maskLight);
                                                    _4334 = _4122;
                                                }
                                                _4359 = _4334 * _3516;
                                            }
                                            else
                                            {
                                                if (_1687 == 9.0)
                                                {
                                                    bool _2752 = fract(_1678.x * 0.16666667163372039794921875) < 0.5;
                                                    float _2758 = fract(_1678.x * 0.3333333432674407958984375);
                                                    vec3 _4329;
                                                    if (_2758 < 0.33329999446868896484375)
                                                    {
                                                        vec3 _4126 = _1685;
                                                        _4126.z = 0.89999997615814208984375;
                                                        _4329 = _4126;
                                                    }
                                                    else
                                                    {
                                                        vec3 _4330;
                                                        if (_2758 < 0.6665999889373779296875)
                                                        {
                                                            vec3 _4128 = _1685;
                                                            _4128.y = 0.89999997615814208984375;
                                                            _4330 = _4128;
                                                        }
                                                        else
                                                        {
                                                            vec3 _4130 = _1685;
                                                            _4130.x = 0.89999997615814208984375;
                                                            _4330 = _4130;
                                                        }
                                                        _4329 = _4330;
                                                    }
                                                    float _2774 = mod(_1678.y, 2.0);
                                                    bool _2778 = (_2774 == 1.0) && _2752;
                                                    bool _2789;
                                                    if (!_2778)
                                                    {
                                                        _2789 = (_2774 == 0.0) && (!_2752);
                                                    }
                                                    else
                                                    {
                                                        _2789 = _2778;
                                                    }
                                                    vec3 _4331;
                                                    if (_2789)
                                                    {
                                                        _4331 = _4329 * (maskLight);
                                                    }
                                                    else
                                                    {
                                                        _4331 = _4329;
                                                    }
                                                    _3523 = _4331;
                                                    break;
                                                }
                                                else
                                                {
                                                    if (_1687 == 10.0)
                                                    {
                                                        float _2825 = fract(_1678.x * 0.3333333432674407958984375);
                                                        vec3 _4323;
                                                        if (_2825 > 0.33329999446868896484375)
                                                        {
                                                            vec3 _4137 = _1685;
                                                            _4137.x = 1.0;
                                                            _4137.z = 1.0;
                                                            _4323 = _4137;
                                                        }
                                                        else
                                                        {
                                                            vec3 _4324;
                                                            if (_2825 > 0.6665999889373779296875)
                                                            {
                                                                vec3 _4141 = _1685;
                                                                _4141.y = 1.0;
                                                                _4324 = _4141;
                                                            }
                                                            else
                                                            {
                                                                _4324 = vec3((mcut));
                                                            }
                                                            _4323 = _4324;
                                                        }
                                                        vec3 _4325;
                                                        if (_2825 > 0.333000004291534423828125)
                                                        {
                                                            _4325 = _4323 * ((fract((_1678.y + float(fract(_1678.x * 0.16666667163372039794921875) < 0.5)) * 0.5) < 0.5) ? 1.0 : (maskLight));
                                                        }
                                                        else
                                                        {
                                                            _4325 = _4323;
                                                        }
                                                        _3523 = _4325;
                                                        break;
                                                    }
                                                    else
                                                    {
                                                        if (_1687 == 11.0)
                                                        {
                                                            bvec3 _3840 = bvec3(fract(_1678.x * 0.3333333432674407958984375) > 0.333000004291534423828125);
                                                            _3523 = vec3(_3840.x ? vec3(1.0).x : _1685.x, _3840.y ? vec3(1.0).y : _1685.y, _3840.z ? vec3(1.0).z : _1685.z);
                                                            break;
                                                        }
                                                    }
                                                }
                                                _4359 = _1685;
                                            }
                                            _4357 = _4359;
                                        }
                                        _4354 = _4357;
                                    }
                                    _4352 = _4354;
                                }
                                _4349 = _4352;
                            }
                            _4346 = _4349;
                        }
                        _4343 = _4346;
                    }
                    _4342 = _4343;
                }
                _4340 = _4342;
            }
            _4339 = _4340;
        }
        _3523 = _4339;
        break;
    } while(false);
    vec3 _1477 = _1442 * mix(_3523, vec3(1.0), vec3(_1426 * (thres)));
    float _2904 = -(scanline);
    vec3 _4394;
    if ((vec4(OrigTextureSize, 1.0 / OrigTextureSize)).y >= 400.0)
    {
        _4394 = (_1460 + _1477) * vec3(0.5);
    }
    else
    {
        _4394 = (_1460 * exp2(_2904 * pow(_1402, mix((beam_min), (beam_max), _1414)))) + (_1477 * exp2(_2904 * pow(1.0 - _1402, mix((beam_min), (beam_max), _1426))));
    }
    vec3 _1511 = min(_4394, vec3(1.0));
    float _2963 = _1331.x;
    float _2966 = 2.0 * (vec4(TextureSize, 1.0 / TextureSize)).z;
    float _2967 = _2963 - _2966;
    float _2969 = _1331.y;
    float _2981 = _2963 - (vec4(TextureSize, 1.0 / TextureSize)).z;
    float _3006 = _2963 + (vec4(TextureSize, 1.0 / TextureSize)).z;
    float _3021 = _2963 + _2966;
    float _3041 = _2969 - (vec4(TextureSize, 1.0 / TextureSize)).w;
    float _3058 = 2.0 * (vec4(TextureSize, 1.0 / TextureSize)).w;
    float _3059 = _2969 - _3058;
    float _3093 = _2969 + (vec4(TextureSize, 1.0 / TextureSize)).w;
    float _3111 = _2969 + _3058;
    vec3 _3345 = (((texture2D(Texture, _1331).xyz * 3.0) + ((((((((texture2D(Texture, vec2(_2981, _2969)).xyz + texture2D(Texture, vec2(_3006, _2969)).xyz) + texture2D(Texture, vec2(_2981, _3041)).xyz) + texture2D(Texture, vec2(_3006, _3093)).xyz) + texture2D(Texture, vec2(_2981, _3093)).xyz) + texture2D(Texture, vec2(_3006, _3041)).xyz) + texture2D(Texture, vec2(_2963, _3041)).xyz) + texture2D(Texture, vec2(_2963, _3093)).xyz) * 2.5)) + ((((((((((((texture2D(Texture, vec2(_2967, _2969)).xyz + texture2D(Texture, vec2(_3021, _2969)).xyz) + texture2D(Texture, vec2(_2967, _3041)).xyz) + texture2D(Texture, vec2(_2981, _3059)).xyz) + texture2D(Texture, vec2(_3006, _3111)).xyz) + texture2D(Texture, vec2(_3021, _3093)).xyz) + texture2D(Texture, vec2(_2967, _3093)).xyz) + texture2D(Texture, vec2(_2981, _3111)).xyz) + texture2D(Texture, vec2(_3006, _3059)).xyz) + texture2D(Texture, vec2(_3021, _3041)).xyz) + texture2D(Texture, vec2(_2963, _3059)).xyz) + texture2D(Texture, vec2(_2963, _3111)).xyz) * 1.5)) * vec3(0.02222222276031970977783203125);
    vec3 _1558 = (pow(pow(pow(_1511, vec3(1.0 / (gamma_out_red), 1.0, 1.0)), vec3(1.0, 1.0 / (gamma_out_green), 1.0)), vec3(1.0, 1.0, 1.0 / (gamma_out_blue))) + (_3345 * (glow))) * mix(1.0, (brightboost), ((_1511.x * 0.300000011920928955078125) + (_1511.y * 0.60000002384185791015625)) + (_1511.z * 0.100000001490116119384765625));
    bvec3 _3842 = bvec3((length(_1558) * 0.57749998569488525390625) < 0.5);
    vec2 _3393 = RA_VARYING_0 * (vec2(1.0) - RA_VARYING_0);
    float _3844 = ((vignette) == 0.0) ? 1.0 : min(pow((_3393.x * _3393.y) * 45.0, 0.1500000059604644775390625), 1.0);
    vec3 _1566 = mix(vec3(dot(_1558, vec3(_3842.x ? vec3(0.180000007152557373046875, 0.7200000286102294921875, 0.02000000141561031341552734375).x : vec3(0.300000011920928955078125, 0.60000002384185791015625, 0.100000001490116119384765625).x, _3842.y ? vec3(0.180000007152557373046875, 0.7200000286102294921875, 0.02000000141561031341552734375).y : vec3(0.300000011920928955078125, 0.60000002384185791015625, 0.100000001490116119384765625).y, _3842.z ? vec3(0.180000007152557373046875, 0.7200000286102294921875, 0.02000000141561031341552734375).z : vec3(0.300000011920928955078125, 0.60000002384185791015625, 0.100000001490116119384765625).z))), _1558, vec3((sat))) * mat3(vec3(_3844, 0.0, 0.0), vec3(0.0, _3844, 0.0), vec3(0.0, 0.0, _3844));
    vec3 _4395;
    if ((gdv_mono) == 1.0)
    {
        _4395 = vec3(((_1566.x + _1566.y) + _1566.z) * 0.3333333432674407958984375) * vec3((gdv_R), (gdv_G), (gdv_B));
    }
    else
    {
        _4395 = _1566;
    }
    gl_FragData[0] = vec4(_4395, 1.0);
}


#endif
