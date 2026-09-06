// Generated from crt/shaders/crt-Cyclon.slang. See slang/upstream for licence/source.
#version 130
#pragma parameter SCANLINE "Scanline Weight" 0.3 0.2 0.6 0.05
#pragma parameter INTERLACE "Interlacing On/Off" 1.0 0.0 1.0 1.0
#pragma parameter bogus_msk " [ MASK SETTINGS ] " 0.0 0.0 0.0 0.0
#pragma parameter M_TYPE "Mask Type: -1:None, 0:CGWG, 1:RGB" 1.0 -1.0 1.0 1.0
#pragma parameter MSIZE "Mask Size" 1.0 1.0 2.0 1.0
#pragma parameter SLOT "Slot Mask On/Off" 1.0 0.0 1.0 1.0
#pragma parameter SLOTW "Slot Mask Width" 3.0 2.0 3.0 1.0
#pragma parameter BGR "Subpixels BGR/RGB" 0.0 0.0 1.0 1.0
#pragma parameter Maskl "Mask Brightness Dark" 0.3 0.0 1.0 0.05
#pragma parameter Maskh "Mask Brightness Bright" 0.75 0.0 1.0 0.05
#pragma parameter bogus_geom " [ GEOMETRY SETTINGS ] " 0.0 0.0 0.0 0.0
#pragma parameter bzl "Bezel On/Off" 1.0 0.0 1.0 1.0
#pragma parameter ambient "Ambient Light" 0.1 0.0 1.0 0.05
#pragma parameter REFLECT "Reflection Strength" 0.6 0.0 1.0 0.02
#pragma parameter zoomx "Zoom Image X" 0.0 -1.0 1.0 0.005
#pragma parameter zoomy "Zoom Image Y" 0.0 -1.0 1.0 0.005
#pragma parameter centerx "Image Center X" 0.0 -5.0 5.0 0.05 
#pragma parameter centery "Image Center Y" 0.0 -5.0 5.0 0.05
#pragma parameter WARPX "Curvature Horizontal" 0.02 0.00 0.25 0.01
#pragma parameter WARPY "Curvature Vertical" 0.01 0.00 0.25 0.01
#pragma parameter vig "Vignette On/Off" 1.0 0.0 1.0 1.0
#pragma parameter bogus_col " [ COLOR SETTINGS ] " 0.0 0.0 0.0 0.0
#pragma parameter BR_DEP "Scan/Mask Brightness Dependence" 0.2 0.0 0.333 0.01
#pragma parameter c_space "Color Space: sRGB,PAL,NTSC-U,NTSC-J" 0.0 0.0 3.0 1.0
#pragma parameter SATURATION "Saturation" 1.0 0.0 2.0 0.05
#pragma parameter BRIGHTNESS_ "Brightness, Sega fix:1.06" 1.0 0.0 2.0 0.01
#pragma parameter BLACK  "Black Level" 0.0 -0.20 0.20 0.01 
#pragma parameter RG "Green <-to-> Red Hue" 0.0 -0.25 0.25 0.01
#pragma parameter RB "Blue <-to-> Red Hue"  0.0 -0.25 0.25 0.01
#pragma parameter GB "Blue <-to-> Green Hue" 0.0 -0.25 0.25 0.01
#pragma parameter bogus_con " [ CONVERGENCE SETTINGS ] " 0.0 0.0 0.0 0.0
#pragma parameter CONV_R "Convergence Red X-Axis" 0.0 -1.0 1.0 0.05
#pragma parameter CONV_G "Convergence Green X-axis" 0.0 -1.0 1.0 0.05
#pragma parameter CONV_B "Convergence Blue X-Axis" 0.0 -1.0 1.0 0.05
#pragma parameter POTATO "Potato Boost(Simple Gamma, adjust Mask)" 0.0 0.0 1.0 1.0
#ifdef VERTEX

uniform mat4 MVPMatrix;
uniform vec2 OrigTextureSize;
uniform vec2 TextureSize;
struct UBO
{
    mat4 MVP;
    vec4 SourceSize;
    vec4 OriginalSize;
};



in vec4 VertexCoord;
out vec2 RA_VARYING_0;
in vec2 TexCoord;
out vec2 RA_VARYING_1;

void main()
{
    gl_Position = (MVPMatrix) * VertexCoord;
    RA_VARYING_0 = TexCoord * 1.00010001659393310546875;
    RA_VARYING_1 = (vec4(TextureSize, 1.0 / TextureSize)).xy / (vec4(OrigTextureSize, 1.0 / OrigTextureSize)).xy;
}


#endif
#ifdef FRAGMENT

uniform float BGR;
uniform float BLACK;
uniform float BRIGHTNESS_;
uniform float BR_DEP;
uniform float CONV_B;
uniform float CONV_G;
uniform float CONV_R;
uniform int FrameCount;
uniform float GB;
uniform float INTERLACE;
uniform float MSIZE;
uniform float M_TYPE;
uniform float Maskh;
uniform float Maskl;
uniform vec2 OrigTextureSize;
uniform vec2 OutputSize;
uniform float POTATO;
uniform float RB;
uniform float REFLECT;
uniform float RG;
uniform float SATURATION;
uniform float SCANLINE;
uniform float SLOT;
uniform float SLOTW;
uniform vec2 TextureSize;
uniform float WARPX;
uniform float WARPY;
uniform float ambient;
uniform float bzl;
uniform float c_space;
uniform float centerx;
uniform float centery;
uniform float vig;
uniform float zoomx;
uniform float zoomy;
vec3 _1102;

struct UBO
{
    float BLACK;
    float RG;
    float RB;
    float GB;
    float POTATO;
    float SATURATION;
    float BRIGHTNESS_;
    float bzl;
    float zoomx;
    float zoomy;
    float centerx;
    float centery;
    float vig;
    float ambient;
    vec4 SourceSize;
    vec4 OriginalSize;
    vec4 OutputSize;
    uint FrameCount;
};



struct Push
{
    float SCANLINE;
    float INTERLACE;
    float M_TYPE;
    float MSIZE;
    float SLOT;
    float SLOTW;
    float BGR;
    float Maskl;
    float Maskh;
    float CONV_R;
    float CONV_G;
    float CONV_B;
    float WARPX;
    float WARPY;
    float BR_DEP;
    float c_space;
    float REFLECT;
};



uniform sampler2D bezel;
uniform sampler2D Pass1Texture;
uniform sampler2D Pass2Texture;

in vec2 RA_VARYING_0;
in vec2 RA_VARYING_1;
out vec4 FragColor;

void main()
{
    vec2 _861 = (((RA_VARYING_0 * vec2(1.0 - (zoomx), 1.0 - (zoomy))) - (vec2((centerx), (centery)) * vec2(0.00999999977648258209228515625))) * 2.0) - vec2(1.0);
    float _863 = _861.y;
    float _872 = _861.x;
    vec2 _886 = ((_861 * vec2(1.0 + ((_863 * _863) * (WARPX)), 1.0 + ((_872 * _872) * (WARPY)))) * 0.5) + vec2(0.5);
    vec4 _1313;
    if ((bzl) == 1.0)
    {
        _1313 = texture(bezel, (((RA_VARYING_0 * (vec4(TextureSize, 1.0 / TextureSize)).xy) / (vec4(OrigTextureSize, 1.0 / OrigTextureSize)).xy) * 0.9700000286102294921875) + vec2(0.014999999664723873138427734375));
    }
    else
    {
        _1313 = vec4(0.0);
    }
    vec2 _447 = vec2((vec4(TextureSize, 1.0 / TextureSize)).z, 0.0);
    vec2 _453 = _886 * (vec4(TextureSize, 1.0 / TextureSize)).xy;
    vec2 _462 = floor(_453) + vec2(0.5);
    float _467 = _462.y;
    float _468 = _453.y - _467;
    vec2 _1334 = vec2(mix(_886.x, _462.x * (vec4(TextureSize, 1.0 / TextureSize)).z, 0.20000000298023223876953125), (_467 + (((4.0 * _468) * _468) * _468)) * (vec4(TextureSize, 1.0 / TextureSize)).w);
    vec4 _497 = texture(Pass1Texture, _1334);
    vec3 _548 = vec3(0.5 * (_497.x + texture(Pass1Texture, _1334 + (_447 * (CONV_R))).x), 0.5 * (_497.y + texture(Pass1Texture, _1334 + (_447 * (CONV_G))).y), 0.5 * (_497.z + texture(Pass1Texture, _1334 + (_447 * (CONV_B))).z));
    vec3 _567 = mix(_1313.xyz, vec3((ambient)) + (texture(Pass2Texture, _1334).xyz * (REFLECT)), vec3(0.5));
    vec4 _1265 = _1313;
    _1265.x = _567.x;
    _1265.y = _567.y;
    _1265.z = _567.z;
    float _1145;
    if ((vig) == 1.0)
    {
        float _587 = (RA_VARYING_0.x * RA_VARYING_1.x) - 0.5;
        _1145 = _587 * _587;
    }
    else
    {
        _1145 = 0.0;
    }
    float _596 = dot(vec3((BR_DEP)), _548);
    vec3 _1140;
    if ((c_space) != 0.0)
    {
        vec3 _1129;
        if ((c_space) == 1.0)
        {
            _1129 = _548 * mat3(vec3(1.07400000095367431640625, -0.0573999993503093719482421875, -0.011900000274181365966796875), vec3(0.038400001823902130126953125, 0.96990001201629638671875, -0.005900000222027301788330078125), vec3(-0.0078999996185302734375, 0.02040000073611736297607421875, 0.988399982452392578125));
        }
        else
        {
            _1129 = _548;
        }
        vec3 _1134;
        if ((c_space) == 2.0)
        {
            _1134 = _1129 * mat3(vec3(0.93180000782012939453125, 0.0412000007927417755126953125, 0.02170000039041042327880859375), vec3(0.013500000350177288055419921875, 0.97109997272491455078125, 0.014800000004470348358154296875), vec3(0.0054999999701976776123046875, -0.0142999999225139617919921875, 1.00849997997283935546875));
        }
        else
        {
            _1134 = _1129;
        }
        vec3 _1135;
        if ((c_space) == 3.0)
        {
            _1135 = _1134 * mat3(vec3(0.950100004673004150390625, -0.04309999942779541015625, 0.085699997842311859130859375), vec3(0.02649999968707561492919921875, 0.927799999713897705078125, 0.04320000112056732177734375), vec3(0.0010999999940395355224609375, -0.02060000039637088775634765625, 1.31529998779296875));
        }
        else
        {
            _1135 = _1134;
        }
        _1140 = clamp(_1135 * vec3(1.20833337306976318359375, 0.8695652484893798828125, 1.5714285373687744140625), vec3(0.0), vec3(1.0));
    }
    else
    {
        _1140 = _548;
    }
    float _648 = _886.y * (vec4(TextureSize, 1.0 / TextureSize)).y;
    float _1137;
    if ((vec4(OrigTextureSize, 1.0 / OrigTextureSize)).y > 400.0)
    {
        float _664 = fract((_648 * 0.5) - 0.5);
        float _1138;
        if ((INTERLACE) == 1.0)
        {
            float _1136;
            if (mod(float((uint(FrameCount))), 2.0) < 1.0)
            {
                _1136 = _664;
            }
            else
            {
                _1136 = _664 + 0.5;
            }
            _1138 = _1136;
        }
        else
        {
            _1138 = _664;
        }
        _1137 = _1138;
    }
    else
    {
        _1137 = fract(_648 - 0.5);
    }
    vec3 _949;
    float _901 = (SCANLINE) + (0.1500000059604644775390625 * dot(_1140, vec3(0.25 - (0.800000011920928955078125 * _1145))));
    float _904 = _1137 / _901;
    float _929 = (1.0 - _1137) / _901;
    vec2 _720 = ((RA_VARYING_0 * (vec4(OutputSize, 1.0 / OutputSize)).xy) * RA_VARYING_1) / vec2((MSIZE));
    float _728 = mix((Maskl), (Maskh), _596);
    vec3 _1160;
    do
    {
        _949 = vec3(_728);
        if ((M_TYPE) == 0.0)
        {
            if ((POTATO) == 1.0)
            {
                _1160 = vec3(((1.0 - _728) * sin(_720.x * 3.1415927410125732421875)) + _728);
                break;
            }
            else
            {
                vec3 _1316;
                if (fract(_720.x * 0.5) < 0.5)
                {
                    vec3 _1276 = _949;
                    _1276.x = 1.0;
                    _1276.z = 1.0;
                    _1316 = _1276;
                }
                else
                {
                    vec3 _1274 = _949;
                    _1274.y = 1.0;
                    _1316 = _1274;
                }
                _1160 = _1316;
                break;
            }
            break; // unreachable workaround
        }
        if ((M_TYPE) == 1.0)
        {
            if ((POTATO) == 1.0)
            {
                _1160 = vec3(((1.0 - _728) * sin(_720.x * 2.0944998264312744140625)) + _728);
                break;
            }
            else
            {
                float _1009 = fract(_720.x * 0.33329999446868896484375);
                vec3 _1314;
                if (_1009 < 0.33329999446868896484375)
                {
                    vec3 _1159;
                    if ((BGR) == 0.0)
                    {
                        _1159 = vec3(_728, _728, 1.0);
                    }
                    else
                    {
                        _1159 = vec3(1.0, _728, _728);
                    }
                    _1314 = _1159;
                }
                else
                {
                    vec3 _1315;
                    if (_1009 < 0.6665999889373779296875)
                    {
                        vec3 _1286 = _949;
                        _1286.y = 1.0;
                        _1315 = _1286;
                    }
                    else
                    {
                        vec3 _1158;
                        if ((BGR) == 0.0)
                        {
                            _1158 = vec3(1.0, _728, _728);
                        }
                        else
                        {
                            _1158 = vec3(_728, _728, 1.0);
                        }
                        _1315 = _1158;
                    }
                    _1314 = _1315;
                }
                _1160 = _1314;
                break;
            }
            break; // unreachable workaround
        }
        else
        {
            _1160 = vec3(1.0);
            break;
        }
        break; // unreachable workaround
    } while(false);
    vec3 _735 = (_1140 * (((0.4000000059604644775390625 * exp((-_904) * _904)) / _901) + ((0.4000000059604644775390625 * exp((-_929) * _929)) / _901))) * _1160;
    vec3 _1186;
    if ((SLOT) == 1.0)
    {
        vec2 _743 = _720 * vec2(0.5);
        vec3 _1175;
        do
        {
            float _1074 = fract(_743.x / (SLOTW));
            bool _1079 = fract(_743.y) < 0.5;
            if (_1079)
            {
                if (_1074 < 0.5)
                {
                    _1175 = vec3(0.5);
                    break;
                }
                else
                {
                    _1175 = vec3(1.5);
                    break;
                }
                break; // unreachable workaround
            }
            else
            {
                if (!_1079)
                {
                    if (_1074 < 0.5)
                    {
                        _1175 = vec3(1.5);
                        break;
                    }
                    else
                    {
                        _1175 = vec3(0.5);
                        break;
                    }
                    break; // unreachable workaround
                }
            }
            _1175 = _1102;
            break;
        } while(false);
        _1186 = _735 * mix(_1175, vec3(1.0), _949);
    }
    else
    {
        _1186 = _735;
    }
    vec3 _1197;
    if ((POTATO) == 0.0)
    {
        vec3 _1110 = _1186 - vec3(1.0);
        _1197 = mix(sqrt(_1186), sqrt(vec3(1.0) - (_1110 * _1110)), vec3((1.0 / ((((-1.0) * (SCANLINE)) + 1.0) * (((-0.800000011920928955078125) * _728) + 1.0))) - 1.2000000476837158203125));
    }
    else
    {
        _1197 = sqrt(_1186) * mix(1.2999999523162841796875, 1.10000002384185791015625, _596);
    }
    vec3 _810 = (((mix(vec3(dot(vec3(0.2899999916553497314453125, 0.60000002384185791015625, 0.10999999940395355224609375), _1197)), _1197, vec3((SATURATION))) * (BRIGHTNESS_)) * mat3(vec3(1.0, -(RG), -(RB)), vec3((RG), 1.0, -(GB)), vec3((RB), (GB), 1.0))) - vec3((BLACK))) * (1.0 / (1.0 - (BLACK)));
    vec3 _1217;
    if ((bzl) > 0.0)
    {
        _1217 = mix(max(_810, vec3(0.0)), pow(abs(_1265.xyz), vec3(1.39999997615814208984375)), vec3(_1313.w * _1313.w));
    }
    else
    {
        _1217 = _810;
    }
    FragColor = vec4(_1217, 1.0);
}


#endif
