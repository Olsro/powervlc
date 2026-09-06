// Generated from crt/shaders/fakelottes.slang. See slang/upstream for licence/source.
#version 120
#pragma parameter shadowMask "shadowMask" 1.0 0.0 4.0 1.0
#pragma parameter SCANLINE_SINE_COMP_B "Scanline Intensity" 0.40 0.0 1.0 0.05
#pragma parameter warpX "warpX" 0.031 0.0 0.125 0.01
#pragma parameter warpY "warpY" 0.041 0.0 0.125 0.01
#pragma parameter maskDark "maskDark" 0.5 0.0 2.0 0.1
#pragma parameter maskLight "maskLight" 1.5 0.0 2.0 0.1
#pragma parameter crt_gamma "CRT Gamma" 2.5 1.0 4.0 0.05
#pragma parameter monitor_gamma "Monitor Gamma" 2.2 1.0 4.0 0.05
#pragma parameter SCANLINE_SINE_COMP_A "Scanline Sine Comp A" 0.0 0.0 0.10 0.01
#pragma parameter SCANLINE_BASE_BRIGHTNESS "Scanline Base Brightness" 0.95 0.0 1.0 0.01
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
    RA_VARYING_0 = TexCoord;
}


#endif
#ifdef FRAGMENT

uniform vec2 OutputSize;
uniform float SCANLINE_BASE_BRIGHTNESS;
uniform float SCANLINE_SINE_COMP_A;
uniform float SCANLINE_SINE_COMP_B;
uniform vec2 TextureSize;
uniform float crt_gamma;
uniform float maskDark;
uniform float maskLight;
uniform float monitor_gamma;
uniform float shadowMask;
uniform float warpX;
uniform float warpY;
struct Push
{
    vec4 SourceSize;
    vec4 OutputSize;
    float shadowMask;
    float SCANLINE_SINE_COMP_B;
    float warpX;
    float warpY;
    float maskDark;
    float maskLight;
    float monitor_gamma;
    float crt_gamma;
    float SCANLINE_SINE_COMP_A;
    float SCANLINE_BASE_BRIGHTNESS;
};



uniform sampler2D Texture;

varying vec2 RA_VARYING_0;

void main()
{
    vec2 _391 = (RA_VARYING_0 * 2.0) - vec2(1.0);
    float _393 = _391.y;
    float _402 = _391.x;
    vec2 _416 = ((_391 * vec2(1.0 + ((_393 * _393) * (warpX)), 1.0 + ((_402 * _402) * (warpY)))) * 0.5) + vec2(0.5);
    float _336 = 1.0 / (monitor_gamma);
    vec4 _351 = texture2D(Texture, _416);
    vec2 _361 = (RA_VARYING_0 * (vec4(OutputSize, 1.0 / OutputSize)).xy) * 1.00010001659393310546875;
    vec3 _428 = vec3((maskDark));
    vec3 _764;
    if ((shadowMask) == 1.0)
    {
        float _436 = _361.x;
        float _643;
        if (fract((_361.y + float(fract(_436 * 0.16666667163372039794921875) < 0.5)) * 0.5) < 0.5)
        {
            _643 = (maskDark);
        }
        else
        {
            _643 = (maskLight);
        }
        float _456 = fract(_436 * 0.3333333432674407958984375);
        vec3 _762;
        if (_456 < 0.333000004291534423828125)
        {
            vec3 _701 = _428;
            _701.x = (maskLight);
            _762 = _701;
        }
        else
        {
            vec3 _763;
            if (_456 < 0.66600000858306884765625)
            {
                vec3 _704 = _428;
                _704.y = (maskLight);
                _763 = _704;
            }
            else
            {
                vec3 _706 = _428;
                _706.z = (maskLight);
                _763 = _706;
            }
            _762 = _763;
        }
        _764 = _762 * _643;
    }
    else
    {
        vec3 _765;
        if ((shadowMask) == 2.0)
        {
            float _490 = fract(_361.x * 0.3333333432674407958984375);
            vec3 _766;
            if (_490 < 0.333000004291534423828125)
            {
                vec3 _712 = _428;
                _712.x = (maskLight);
                _766 = _712;
            }
            else
            {
                vec3 _767;
                if (_490 < 0.66600000858306884765625)
                {
                    vec3 _715 = _428;
                    _715.y = (maskLight);
                    _767 = _715;
                }
                else
                {
                    vec3 _717 = _428;
                    _717.z = (maskLight);
                    _767 = _717;
                }
                _766 = _767;
            }
            _765 = _766;
        }
        else
        {
            vec3 _768;
            if ((shadowMask) == 3.0)
            {
                float _528 = fract((_361.x + (_361.y * 3.0)) * 0.16666667163372039794921875);
                vec3 _769;
                if (_528 < 0.333000004291534423828125)
                {
                    vec3 _727 = _428;
                    _727.x = (maskLight);
                    _769 = _727;
                }
                else
                {
                    vec3 _770;
                    if (_528 < 0.66600000858306884765625)
                    {
                        vec3 _730 = _428;
                        _730.y = (maskLight);
                        _770 = _730;
                    }
                    else
                    {
                        vec3 _732 = _428;
                        _732.z = (maskLight);
                        _770 = _732;
                    }
                    _769 = _770;
                }
                _768 = _769;
            }
            else
            {
                vec3 _771;
                if ((shadowMask) == 4.0)
                {
                    vec2 _558 = floor(_361 * vec2(1.0, 0.5));
                    float _569 = fract((_558.x + (_558.y * 3.0)) * 0.16666667163372039794921875);
                    vec3 _772;
                    if (_569 < 0.333000004291534423828125)
                    {
                        vec3 _742 = _428;
                        _742.x = (maskLight);
                        _772 = _742;
                    }
                    else
                    {
                        vec3 _773;
                        if (_569 < 0.66600000858306884765625)
                        {
                            vec3 _745 = _428;
                            _745.y = (maskLight);
                            _773 = _745;
                        }
                        else
                        {
                            vec3 _747 = _428;
                            _747.z = (maskLight);
                            _773 = _747;
                        }
                        _772 = _773;
                    }
                    _771 = _772;
                }
                else
                {
                    _771 = vec3(1.0);
                }
                _768 = _771;
            }
            _765 = _768;
        }
        _764 = _765;
    }
    gl_FragData[0] = pow(vec4((pow(_351, vec4((crt_gamma), (crt_gamma), (crt_gamma), 1.0)) * vec4(_764, 1.0)).xyz * ((SCANLINE_BASE_BRIGHTNESS) + dot(vec2((SCANLINE_SINE_COMP_A), (SCANLINE_SINE_COMP_B)) * sin((_416 - vec2(0.0, 0.25 * (vec4(TextureSize, 1.0 / TextureSize)).w)) * vec2(3.141499996185302734375 * (vec4(OutputSize, 1.0 / OutputSize)).x, 6.28299999237060546875 * (vec4(TextureSize, 1.0 / TextureSize)).y)), vec2(1.0))), 1.0), vec4(_336, _336, _336, 1.0));
}


#endif
