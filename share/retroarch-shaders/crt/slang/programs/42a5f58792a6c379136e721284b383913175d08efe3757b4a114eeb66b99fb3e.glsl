// Generated from crt/shaders/glow/resolve.slang. See slang/upstream for licence/source.
#version 130
#pragma parameter BLOOM_STRENGTH "Glow Strength" 0.45 0.0 0.8 0.05
#pragma parameter OUTPUT_GAMMA "Monitor Gamma" 2.2 1.8 2.6 0.02
#pragma parameter CURVATURE "Curvature" 0.0 0.0 1.0 1.0
#pragma parameter warpX "Curvature X-Axis" 0.031 0.0 0.125 0.01
#pragma parameter warpY "Curvature Y-Axis" 0.041 0.0 0.125 0.01
#pragma parameter cornersize "Corner Size" 0.01 0.001 1.0 0.005
#pragma parameter cornersmooth "Corner Smoothness" 1000.0 80.0 2000.0 100.0
#pragma parameter noise_amt "Noise Amount" 1.0 0.0 5.0 0.25
#pragma parameter shadowMask "Mask Effect" 0.0 0.0 4.0 1.0
#pragma parameter maskDark "maskDark" 0.5 0.0 2.0 0.1
#pragma parameter maskLight "maskLight" 1.5 0.0 2.0 0.1
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
    RA_VARYING_0 = TexCoord;
}


#endif
#ifdef FRAGMENT

uniform float BLOOM_STRENGTH;
uniform float CURVATURE;
uniform int FrameCount;
uniform float OUTPUT_GAMMA;
uniform vec2 OutputSize;
uniform float cornersize;
uniform float cornersmooth;
uniform float maskDark;
uniform float maskLight;
uniform float noise_amt;
uniform float shadowMask;
uniform float warpX;
uniform float warpY;
struct UBO
{
    vec4 OutputSize;
    uint FrameCount;
};



struct Push
{
    float BLOOM_STRENGTH;
    float OUTPUT_GAMMA;
    float CURVATURE;
    float warpX;
    float warpY;
    float shadowMask;
    float maskDark;
    float maskLight;
    float cornersize;
    float cornersmooth;
    float noise_amt;
};



uniform sampler2D Pass3Texture;
uniform sampler2D Texture;

in vec2 RA_VARYING_0;
out vec4 FragColor;

void main()
{
    bool _449 = (CURVATURE) > 0.5;
    vec2 _1033;
    if (_449)
    {
        float _605 = float((uint(FrameCount)));
        vec2 _607 = sin(gl_FragCoord.xy) * mod(_605, 361.0);
        vec2 _687 = floor(_607);
        vec2 _689 = fract(_607);
        vec2 _697 = (_689 * _689) * (vec2(3.0) - (_689 * 2.0));
        float _704 = _697.x;
        float _717 = mix(mix(fract(sin(dot(_687, vec2(12.98980045318603515625, 4.141399860382080078125))) * 43758.546875), fract(sin(dot(_687 + vec2(1.0, 0.0), vec2(12.98980045318603515625, 4.141399860382080078125))) * 43758.546875), _704), mix(fract(sin(dot(_687 + vec2(0.0, 1.0), vec2(12.98980045318603515625, 4.141399860382080078125))) * 43758.546875), fract(sin(dot(_687 + vec2(1.0), vec2(12.98980045318603515625, 4.141399860382080078125))) * 43758.546875), _704), _697.y);
        vec2 _616 = cos(gl_FragCoord.yx) * mod(_605, 873.0);
        vec2 _759 = floor(_616);
        vec2 _761 = fract(_616);
        vec2 _769 = (_761 * _761) * (vec2(3.0) - (_761 * 2.0));
        float _776 = _769.x;
        float _789 = mix(mix(fract(sin(dot(_759, vec2(12.98980045318603515625, 4.141399860382080078125))) * 43758.546875), fract(sin(dot(_759 + vec2(1.0, 0.0), vec2(12.98980045318603515625, 4.141399860382080078125))) * 43758.546875), _776), mix(fract(sin(dot(_759 + vec2(0.0, 1.0), vec2(12.98980045318603515625, 4.141399860382080078125))) * 43758.546875), fract(sin(dot(_759 + vec2(1.0), vec2(12.98980045318603515625, 4.141399860382080078125))) * 43758.546875), _776), _769.y);
        vec2 _630 = ((RA_VARYING_0 + ((vec2(_717 * _717, _789 * _789) * 0.001000000047497451305389404296875) * (noise_amt))) * 2.0) - vec2(1.0);
        float _632 = _630.x;
        float _637 = _630.y;
        float _642 = sqrt((_632 * _632) + (_637 * _637));
        vec2 _657 = vec2(1.0) / (vec2(1.0) + ((vec2((warpX), (warpY)) * 15.0) * 0.20000000298023223876953125));
        _1033 = ((((_630 / vec2(_642)) * (vec2(1.0) - pow(vec2(1.0 - (_642 * 0.707106769084930419921875)), _657))) / (vec2(1.0) - pow(vec2(0.292893230915069580078125), _657))) * 0.5) + vec2(0.5);
    }
    else
    {
        _1033 = RA_VARYING_0;
    }
    FragColor = vec4(pow(clamp((texture(Pass3Texture, _1033).xyz * 1.14999997615814208984375) + (texture(Texture, _1033).xyz * (BLOOM_STRENGTH)), vec3(0.0), vec3(1.0)), vec3(1.0 / (OUTPUT_GAMMA))), 1.0);
    bool _502 = _1033.x > 9.9999997473787516355514526367188e-05;
    bool _509;
    if (_502)
    {
        _509 = _1033.x < 0.99989998340606689453125;
    }
    else
    {
        _509 = _502;
    }
    bool _515;
    if (_509)
    {
        _515 = _1033.y > 9.9999997473787516355514526367188e-05;
    }
    else
    {
        _515 = _509;
    }
    bool _521;
    if (_515)
    {
        _521 = _1033.y < 0.99989998340606689453125;
    }
    else
    {
        _521 = _515;
    }
    if (_521)
    {
        vec4 _524 = FragColor;
        FragColor.x = _524.x;
        FragColor.y = _524.y;
        FragColor.z = _524.z;
    }
    else
    {
        FragColor.x = 0.0;
        FragColor.y = 0.0;
        FragColor.z = 0.0;
    }
    float _1034;
    if (_449)
    {
        vec2 _835 = vec2((cornersize));
        vec2 _840 = _835 - min(min(_1033, vec2(1.0) - _1033) * vec2(1.0, 0.75), _835);
        _1034 = clamp(((cornersize) - sqrt(dot(_840, _840))) * (cornersmooth), 0.0, 1.0);
    }
    else
    {
        _1034 = 1.0;
    }
    vec4 _552 = FragColor;
    vec3 _554 = _552.xyz * _1034;
    FragColor.x = _554.x;
    FragColor.y = _554.y;
    FragColor.z = _554.z;
    if ((shadowMask) > 0.0)
    {
        vec4 _566 = FragColor;
        vec2 _578 = (RA_VARYING_0 * (vec4(OutputSize, 1.0 / OutputSize)).xy) * 1.00000095367431640625;
        vec3 _864 = vec3((maskDark));
        vec3 _1122;
        if ((shadowMask) == 1.0)
        {
            float _872 = _578.x;
            float _1037;
            if (fract((_578.y + float(fract(_872 * 0.16666667163372039794921875) < 0.5)) * 0.5) < 0.5)
            {
                _1037 = (maskDark);
            }
            else
            {
                _1037 = (maskLight);
            }
            float _892 = fract(_872 * 0.3333333432674407958984375);
            vec3 _1120;
            if (_892 < 0.333000004291534423828125)
            {
                vec3 _1067 = _864;
                _1067.x = (maskLight);
                _1120 = _1067;
            }
            else
            {
                vec3 _1121;
                if (_892 < 0.66600000858306884765625)
                {
                    vec3 _1070 = _864;
                    _1070.y = (maskLight);
                    _1121 = _1070;
                }
                else
                {
                    vec3 _1072 = _864;
                    _1072.z = (maskLight);
                    _1121 = _1072;
                }
                _1120 = _1121;
            }
            _1122 = _1120 * _1037;
        }
        else
        {
            vec3 _1123;
            if ((shadowMask) == 2.0)
            {
                float _926 = fract(_578.x * 0.3333333432674407958984375);
                vec3 _1124;
                if (_926 < 0.333000004291534423828125)
                {
                    vec3 _1078 = _864;
                    _1078.x = (maskLight);
                    _1124 = _1078;
                }
                else
                {
                    vec3 _1125;
                    if (_926 < 0.66600000858306884765625)
                    {
                        vec3 _1081 = _864;
                        _1081.y = (maskLight);
                        _1125 = _1081;
                    }
                    else
                    {
                        vec3 _1083 = _864;
                        _1083.z = (maskLight);
                        _1125 = _1083;
                    }
                    _1124 = _1125;
                }
                _1123 = _1124;
            }
            else
            {
                vec3 _1126;
                if ((shadowMask) == 3.0)
                {
                    float _964 = fract((_578.x + (_578.y * 3.0)) * 0.16666667163372039794921875);
                    vec3 _1127;
                    if (_964 < 0.333000004291534423828125)
                    {
                        vec3 _1093 = _864;
                        _1093.x = (maskLight);
                        _1127 = _1093;
                    }
                    else
                    {
                        vec3 _1128;
                        if (_964 < 0.66600000858306884765625)
                        {
                            vec3 _1096 = _864;
                            _1096.y = (maskLight);
                            _1128 = _1096;
                        }
                        else
                        {
                            vec3 _1098 = _864;
                            _1098.z = (maskLight);
                            _1128 = _1098;
                        }
                        _1127 = _1128;
                    }
                    _1126 = _1127;
                }
                else
                {
                    vec3 _1129;
                    if ((shadowMask) == 4.0)
                    {
                        vec2 _994 = floor(_578 * vec2(1.0, 0.5));
                        float _1005 = fract((_994.x + (_994.y * 3.0)) * 0.16666667163372039794921875);
                        vec3 _1130;
                        if (_1005 < 0.333000004291534423828125)
                        {
                            vec3 _1108 = _864;
                            _1108.x = (maskLight);
                            _1130 = _1108;
                        }
                        else
                        {
                            vec3 _1131;
                            if (_1005 < 0.66600000858306884765625)
                            {
                                vec3 _1111 = _864;
                                _1111.y = (maskLight);
                                _1131 = _1111;
                            }
                            else
                            {
                                vec3 _1113 = _864;
                                _1113.z = (maskLight);
                                _1131 = _1113;
                            }
                            _1130 = _1131;
                        }
                        _1129 = _1130;
                    }
                    else
                    {
                        _1129 = _864;
                    }
                    _1126 = _1129;
                }
                _1123 = _1126;
            }
            _1122 = _1123;
        }
        vec3 _584 = pow(pow(_566.xyz, vec3(2.2000000476837158203125)) * _1122, vec3(0.4545454680919647216796875));
        FragColor.x = _584.x;
        FragColor.y = _584.y;
        FragColor.z = _584.z;
    }
}


#endif
