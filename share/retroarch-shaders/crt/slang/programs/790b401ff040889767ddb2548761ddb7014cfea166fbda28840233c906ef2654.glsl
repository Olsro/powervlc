// Generated from crt/shaders/geom-deluxe/crt-geom-deluxe.slang. See slang/upstream for licence/source.
#version 430
#pragma parameter mask_type "Mask Pattern" 1.0 1.0 20.0 1.0
#pragma parameter aperture_strength "Shadow mask strength" 0.4 0.0 1.0 0.05
#pragma parameter aperture_brightboost "Shadow mask brightness boost" 0.4 0.0 1.0 0.05
#pragma parameter phosphor_power "Phosphor decay power" 1.2 0.5 3.0 0.05
#pragma parameter phosphor_amplitude "Phosphor persistence amplitude" 0.04 0.0 0.2 0.01
#pragma parameter CRTgamma "Gamma of simulated CRT" 2.4 0.7 4.0 0.05
#pragma parameter rasterbloom "Raster bloom amplitude" 0.1 0.0 1.0 0.01
#pragma parameter halation "Halation amplitude" 0.1 0.0 0.3 0.01
#pragma parameter width "Halation blur width" 2.0 0.1 4.0 0.1
#pragma parameter curvature "Enable Curvature" 1.0 0.0 1.0 1.0
#pragma parameter R "Radius of curvature" 3.5 0.5 10.0 0.1
#pragma parameter d "Distance to screen" 2.0 0.1 10.0 0.1
#pragma parameter angle_x "Tilt X" 0.0 -1.0 1.0 0.01
#pragma parameter angle_y "Tilt Y" 0.0 -1.0 1.0 0.01
#pragma parameter cornersize "Rounded corner size" 0.01 0.00 0.10 0.01
#pragma parameter cornersmooth "Border smoothness" 1000.0 100.0 2000.0 100.0
#pragma parameter overscan_x "Overscan X" 1.0 0.8 1.2 0.005
#pragma parameter overscan_y "Overscan Y" 1.0 0.8 1.2 0.005
#pragma parameter monitorgamma "Gamma of output display" 2.2 0.7 4.0 0.05
#pragma parameter aspect_x "Aspect ratio X" 1.0 0.3 1.0 0.01
#pragma parameter aspect_y "Aspect ratio Y" 0.75 0.3 1.0 0.01
#pragma parameter scanline_weight "CRTGeom Scanline Weight" 0.3 0.1 0.5 0.01
#pragma parameter geom_lum "CRTGeom Luminance" 0.0 0.0 1.0 0.01
#pragma parameter interlace_detect "CRTGeom Interlacing Simulation" 1.0 0.0 1.0 1.0
#ifdef VERTEX

uniform mat4 MVPMatrix;
uniform float R;
uniform vec2 TextureSize;
uniform float angle_x;
uniform float angle_y;
uniform float aspect_x;
uniform float aspect_y;
uniform float d;
uniform float interlace_detect;
struct UBO
{
    vec4 SourceSize;
    mat4 MVP;
};



struct Push
{
    float aspect_x;
    float aspect_y;
    float d;
    float R;
    float angle_x;
    float angle_y;
    float interlace_detect;
};



layout(location = 0) in vec4 VertexCoord;
layout(location = 0) out vec2 RA_VARYING_0;
layout(location = 1) in vec2 TexCoord;
layout(location = 1) out vec2 RA_VARYING_1;
layout(location = 2) out vec2 RA_VARYING_2;
layout(location = 3) out vec3 RA_VARYING_3;
layout(location = 6) out vec2 RA_VARYING_6;
layout(location = 5) out vec2 RA_VARYING_5;
layout(location = 4) out vec2 RA_VARYING_4;

void main()
{
    vec2 _45 = vec2((aspect_x), (aspect_y));
    vec2 _53 = vec2((angle_x), (angle_y));
    gl_Position = (MVPMatrix) * VertexCoord;
    RA_VARYING_0 = TexCoord;
    RA_VARYING_1 = sin(_53);
    RA_VARYING_2 = cos(_53);
    float _503 = -(R);
    vec2 _519 = (RA_VARYING_1 * _503) / vec2(1.0 + ((((R) / (d)) * RA_VARYING_2.x) * RA_VARYING_2.y));
    float _694 = (d) * (d);
    float _695 = dot(_519, _519) + _694;
    float _716 = ((R) * (dot(_519, RA_VARYING_1) - (((d) * RA_VARYING_2.x) * RA_VARYING_2.y))) - _694;
    vec2 _624 = ((vec2(((_716 * (-2.0)) - sqrt((4.0 * (_716 * _716)) - ((4.0 * _695) * (_694 + ((((2.0 * (R)) * (d)) * RA_VARYING_2.x) * RA_VARYING_2.y))))) / (2.0 * _695)) * _519) - (vec2(_503) * RA_VARYING_1)) / vec2((R));
    vec2 _627 = RA_VARYING_1 / RA_VARYING_2;
    vec2 _630 = _624 / RA_VARYING_2;
    float _634 = dot(_627, _627) + 1.0;
    float _637 = dot(_630, _627);
    float _657 = ((_637 * 2.0) + sqrt((4.0 * (_637 * _637)) - ((4.0 * _634) * (dot(_630, _630) - 1.0)))) / (2.0 * _634);
    float _671 = max(abs((R) * acos(_657)), 9.9999997473787516355514526367188e-06);
    vec2 _681 = (((_624 - (RA_VARYING_1 * _657)) / RA_VARYING_2) * _671) / vec2(sin(_671 / (R)));
    vec2 _524 = vec2(0.5) * _45;
    float _526 = _524.x;
    float _529 = _681.y;
    vec2 _530 = vec2(-_526, _529);
    float _761 = max(abs(sqrt(dot(_530, _530))), 9.9999997473787516355514526367188e-06);
    float _765 = _761 / (R);
    vec2 _770 = _530 * (sin(_765) / _761);
    float _776 = 1.0 - cos(_765);
    float _781 = (d) / (R);
    float _536 = _681.x;
    float _538 = _524.y;
    vec2 _540 = vec2(_536, -_538);
    float _817 = max(abs(sqrt(dot(_540, _540))), 9.9999997473787516355514526367188e-06);
    float _821 = _817 / (R);
    vec2 _826 = _540 * (sin(_821) / _817);
    float _832 = 1.0 - cos(_821);
    vec2 _547 = vec2(((((_770 * RA_VARYING_2) - (RA_VARYING_1 * _776)) * (d)) / vec2((_781 + ((_776 * RA_VARYING_2.x) * RA_VARYING_2.y)) + dot(_770, RA_VARYING_1))).x, ((((_826 * RA_VARYING_2) - (RA_VARYING_1 * _832)) * (d)) / vec2((_781 + ((_832 * RA_VARYING_2.x) * RA_VARYING_2.y)) + dot(_826, RA_VARYING_1))).y) / _45;
    vec2 _552 = vec2(_526, _529);
    float _873 = max(abs(sqrt(dot(_552, _552))), 9.9999997473787516355514526367188e-06);
    float _877 = _873 / (R);
    vec2 _882 = _552 * (sin(_877) / _873);
    float _888 = 1.0 - cos(_877);
    vec2 _561 = vec2(_536, _538);
    float _929 = max(abs(sqrt(dot(_561, _561))), 9.9999997473787516355514526367188e-06);
    float _933 = _929 / (R);
    vec2 _938 = _561 * (sin(_933) / _929);
    float _944 = 1.0 - cos(_933);
    vec2 _568 = vec2(((((_882 * RA_VARYING_2) - (RA_VARYING_1 * _888)) * (d)) / vec2((_781 + ((_888 * RA_VARYING_2.x) * RA_VARYING_2.y)) + dot(_882, RA_VARYING_1))).x, ((((_938 * RA_VARYING_2) - (RA_VARYING_1 * _944)) * (d)) / vec2((_781 + ((_944 * RA_VARYING_2.x) * RA_VARYING_2.y)) + dot(_938, RA_VARYING_1))).y) / _45;
    RA_VARYING_3 = vec3(((_568 + _547) * _45) * 0.5, max(_568.x - _547.x, _568.y - _547.y));
    RA_VARYING_6 = (vec4(TextureSize, 1.0 / TextureSize)).xy;
    RA_VARYING_5 = vec2(1.0, clamp(floor((vec4(TextureSize, 1.0 / TextureSize)).y / (((interlace_detect) == 1.0) ? 200.0 : 1000.0)), 1.0, 2.0));
    RA_VARYING_4 = RA_VARYING_5 / RA_VARYING_6;
}


#endif
#ifdef FRAGMENT

uniform float CRTgamma;
uniform int FrameCount;
uniform vec2 OutputSize;
uniform float R;
uniform vec2 TextureSize;
uniform float aperture_brightboost;
uniform float aperture_strength;
uniform float aspect_x;
uniform float aspect_y;
uniform float cornersize;
uniform float cornersmooth;
uniform float curvature;
uniform float d;
uniform float geom_lum;
uniform float halation;
uniform float interlace_detect;
uniform float mask_type;
uniform float monitorgamma;
uniform float overscan_x;
uniform float overscan_y;
uniform float rasterbloom;
uniform float scanline_weight;
uniform float width;
const vec3 _3509[3][4] = vec3[][](vec3[](vec3(1.0, 0.0, 1.0), vec3(0.0, 1.0, 0.0), vec3(0.0), vec3(0.0)), vec3[](vec3(1.0, 0.0, 1.0), vec3(0.0, 1.0, 0.0), vec3(1.0, 0.0, 1.0), vec3(0.0, 1.0, 0.0)), vec3[](vec3(0.0), vec3(0.0), vec3(1.0, 0.0, 1.0), vec3(0.0, 1.0, 0.0)));
const vec3 _3510[4] = vec3[](vec3(1.0, 0.0, 0.0), vec3(0.0, 1.0, 0.0), vec3(0.0, 0.0, 1.0), vec3(0.0));
const vec3 _3511[5] = vec3[](vec3(1.0, 0.0, 0.0), vec3(1.0, 0.0, 1.0), vec3(0.0, 0.0, 1.0), vec3(0.0, 1.0, 0.0), vec3(0.0, 1.0, 0.0));
const vec3 _3512[7] = vec3[](vec3(1.0, 0.0, 0.0), vec3(1.0, 0.0, 0.0), vec3(1.0, 1.0, 0.0), vec3(0.0, 1.0, 0.0), vec3(0.0, 1.0, 1.0), vec3(0.0, 0.0, 1.0), vec3(0.0, 0.0, 1.0));
const vec3 _3513[4] = vec3[](vec3(1.0, 0.0, 0.0), vec3(1.0, 1.0, 0.0), vec3(0.0, 1.0, 1.0), vec3(0.0, 0.0, 1.0));
const vec3 _3514[4] = vec3[](vec3(1.0, 0.0, 0.0), vec3(1.0, 0.0, 1.0), vec3(0.0, 1.0, 1.0), vec3(0.0, 1.0, 0.0));
const vec3 _3516[2][4] = vec3[][](vec3[](vec3(1.0, 0.0, 0.0), vec3(0.0, 1.0, 0.0), vec3(0.0, 0.0, 1.0), vec3(0.0)), vec3[](vec3(0.0, 0.0, 1.0), vec3(0.0), vec3(1.0, 0.0, 0.0), vec3(0.0, 1.0, 0.0)));
const vec3 _3518[2][4] = vec3[][](vec3[](vec3(1.0, 0.0, 0.0), vec3(1.0, 1.0, 0.0), vec3(0.0, 1.0, 1.0), vec3(0.0, 0.0, 1.0)), vec3[](vec3(0.0, 1.0, 1.0), vec3(0.0, 0.0, 1.0), vec3(1.0, 0.0, 0.0), vec3(1.0, 1.0, 0.0)));
const vec3 _3519[4][4] = vec3[][](vec3[](vec3(1.0, 0.0, 0.0), vec3(1.0, 1.0, 0.0), vec3(0.0, 1.0, 1.0), vec3(0.0, 0.0, 1.0)), vec3[](vec3(1.0, 0.0, 0.0), vec3(1.0, 1.0, 0.0), vec3(0.0, 1.0, 1.0), vec3(0.0, 0.0, 1.0)), vec3[](vec3(0.0, 1.0, 1.0), vec3(0.0, 0.0, 1.0), vec3(1.0, 0.0, 0.0), vec3(1.0, 1.0, 0.0)), vec3[](vec3(0.0, 1.0, 1.0), vec3(0.0, 0.0, 1.0), vec3(1.0, 0.0, 0.0), vec3(1.0, 1.0, 0.0)));
const vec3 _3523[3][6] = vec3[][](vec3[](vec3(1.0, 0.0, 1.0), vec3(0.0, 1.0, 0.0), vec3(0.0), vec3(0.0), vec3(0.0), vec3(0.0)), vec3[](vec3(1.0, 0.0, 1.0), vec3(0.0, 1.0, 0.0), vec3(0.0), vec3(1.0, 0.0, 1.0), vec3(0.0, 1.0, 0.0), vec3(0.0)), vec3[](vec3(0.0), vec3(0.0), vec3(0.0), vec3(1.0, 0.0, 1.0), vec3(0.0, 1.0, 0.0), vec3(0.0)));
const vec3 _3527[4][8] = vec3[][](vec3[](vec3(1.0, 0.0, 0.0), vec3(1.0, 1.0, 0.0), vec3(0.0, 1.0, 1.0), vec3(0.0, 0.0, 1.0), vec3(1.0, 0.0, 0.0), vec3(1.0, 1.0, 0.0), vec3(0.0, 1.0, 1.0), vec3(0.0, 0.0, 1.0)), vec3[](vec3(1.0, 0.0, 0.0), vec3(1.0, 1.0, 0.0), vec3(0.0, 1.0, 1.0), vec3(0.0, 0.0, 1.0), vec3(0.0), vec3(0.0), vec3(0.0), vec3(0.0)), vec3[](vec3(1.0, 0.0, 0.0), vec3(1.0, 1.0, 0.0), vec3(0.0, 1.0, 1.0), vec3(0.0, 0.0, 1.0), vec3(1.0, 0.0, 0.0), vec3(1.0, 1.0, 0.0), vec3(0.0, 1.0, 1.0), vec3(0.0, 0.0, 1.0)), vec3[](vec3(0.0), vec3(0.0), vec3(0.0), vec3(0.0), vec3(1.0, 0.0, 0.0), vec3(1.0, 1.0, 0.0), vec3(0.0, 1.0, 1.0), vec3(0.0, 0.0, 1.0)));
const vec3 _3531[3][4] = vec3[][](vec3[](vec3(1.0, 1.0, 0.0), vec3(0.0, 0.0, 1.0), vec3(0.0), vec3(0.0)), vec3[](vec3(1.0, 1.0, 0.0), vec3(0.0, 0.0, 1.0), vec3(1.0, 1.0, 0.0), vec3(0.0, 0.0, 1.0)), vec3[](vec3(0.0), vec3(0.0), vec3(1.0, 1.0, 0.0), vec3(0.0, 0.0, 1.0)));
const vec3 _3535[4][10] = vec3[][](vec3[](vec3(1.0, 0.0, 0.0), vec3(1.0, 0.0, 1.0), vec3(0.0, 0.0, 1.0), vec3(0.0, 1.0, 0.0), vec3(0.0, 1.0, 0.0), vec3(1.0, 0.0, 0.0), vec3(1.0, 0.0, 1.0), vec3(0.0, 0.0, 1.0), vec3(0.0, 1.0, 0.0), vec3(0.0, 1.0, 0.0)), vec3[](vec3(0.0), vec3(0.0, 0.0, 1.0), vec3(0.0, 0.0, 1.0), vec3(0.0, 1.0, 0.0), vec3(0.0, 1.0, 0.0), vec3(1.0, 0.0, 0.0), vec3(1.0, 0.0, 0.0), vec3(0.0), vec3(0.0), vec3(0.0)), vec3[](vec3(1.0, 0.0, 0.0), vec3(1.0, 0.0, 1.0), vec3(0.0, 0.0, 1.0), vec3(0.0, 1.0, 0.0), vec3(0.0, 1.0, 0.0), vec3(1.0, 0.0, 0.0), vec3(1.0, 0.0, 1.0), vec3(0.0, 0.0, 1.0), vec3(0.0, 1.0, 0.0), vec3(0.0, 1.0, 0.0)), vec3[](vec3(1.0, 0.0, 0.0), vec3(1.0, 0.0, 0.0), vec3(0.0), vec3(0.0), vec3(0.0), vec3(0.0), vec3(0.0, 0.0, 1.0), vec3(0.0, 0.0, 1.0), vec3(0.0, 1.0, 0.0), vec3(0.0, 1.0, 0.0)));
const vec3 _3539[4][10] = vec3[][](vec3[](vec3(1.0, 0.0, 0.0), vec3(1.0, 1.0, 0.0), vec3(0.0, 1.0, 0.0), vec3(0.0, 0.0, 1.0), vec3(0.0, 0.0, 1.0), vec3(1.0, 0.0, 0.0), vec3(1.0, 1.0, 0.0), vec3(0.0, 1.0, 0.0), vec3(0.0, 0.0, 1.0), vec3(0.0, 0.0, 1.0)), vec3[](vec3(0.0), vec3(0.0, 1.0, 0.0), vec3(0.0, 1.0, 0.0), vec3(0.0, 0.0, 1.0), vec3(0.0, 0.0, 1.0), vec3(1.0, 0.0, 0.0), vec3(1.0, 0.0, 0.0), vec3(0.0), vec3(0.0), vec3(0.0)), vec3[](vec3(1.0, 0.0, 0.0), vec3(1.0, 1.0, 0.0), vec3(0.0, 1.0, 0.0), vec3(0.0, 0.0, 1.0), vec3(0.0, 0.0, 1.0), vec3(1.0, 0.0, 0.0), vec3(1.0, 1.0, 0.0), vec3(0.0, 1.0, 0.0), vec3(0.0, 0.0, 1.0), vec3(0.0, 0.0, 1.0)), vec3[](vec3(1.0, 0.0, 0.0), vec3(1.0, 0.0, 0.0), vec3(0.0), vec3(0.0), vec3(0.0), vec3(0.0), vec3(0.0, 1.0, 0.0), vec3(0.0, 1.0, 0.0), vec3(0.0, 0.0, 1.0), vec3(0.0, 0.0, 1.0)));
const vec3 _3543[6][14] = vec3[][](vec3[](vec3(1.0, 0.0, 0.0), vec3(1.0, 0.0, 0.0), vec3(1.0, 1.0, 0.0), vec3(0.0, 1.0, 0.0), vec3(0.0, 1.0, 1.0), vec3(0.0, 0.0, 1.0), vec3(0.0, 0.0, 1.0), vec3(1.0, 0.0, 0.0), vec3(1.0, 0.0, 0.0), vec3(1.0, 1.0, 0.0), vec3(0.0, 1.0, 0.0), vec3(0.0, 1.0, 1.0), vec3(0.0, 0.0, 1.0), vec3(0.0, 0.0, 1.0)), vec3[](vec3(1.0, 0.0, 0.0), vec3(1.0, 0.0, 0.0), vec3(1.0, 1.0, 0.0), vec3(0.0, 1.0, 0.0), vec3(0.0, 1.0, 1.0), vec3(0.0, 0.0, 1.0), vec3(0.0, 0.0, 1.0), vec3(1.0, 0.0, 0.0), vec3(1.0, 0.0, 0.0), vec3(1.0, 1.0, 0.0), vec3(0.0, 1.0, 0.0), vec3(0.0, 1.0, 1.0), vec3(0.0, 0.0, 1.0), vec3(0.0, 0.0, 1.0)), vec3[](vec3(1.0, 0.0, 0.0), vec3(1.0, 0.0, 0.0), vec3(1.0, 1.0, 0.0), vec3(0.0, 1.0, 0.0), vec3(0.0, 1.0, 1.0), vec3(0.0, 0.0, 1.0), vec3(0.0, 0.0, 1.0), vec3(0.0), vec3(0.0), vec3(0.0), vec3(0.0), vec3(0.0), vec3(0.0), vec3(0.0)), vec3[](vec3(1.0, 0.0, 0.0), vec3(1.0, 0.0, 0.0), vec3(1.0, 1.0, 0.0), vec3(0.0, 1.0, 0.0), vec3(0.0, 1.0, 1.0), vec3(0.0, 0.0, 1.0), vec3(0.0, 0.0, 1.0), vec3(1.0, 0.0, 0.0), vec3(1.0, 0.0, 0.0), vec3(1.0, 1.0, 0.0), vec3(0.0, 1.0, 0.0), vec3(0.0, 1.0, 1.0), vec3(0.0, 0.0, 1.0), vec3(0.0, 0.0, 1.0)), vec3[](vec3(1.0, 0.0, 0.0), vec3(1.0, 0.0, 0.0), vec3(1.0, 1.0, 0.0), vec3(0.0, 1.0, 0.0), vec3(0.0, 1.0, 1.0), vec3(0.0, 0.0, 1.0), vec3(0.0, 0.0, 1.0), vec3(1.0, 0.0, 0.0), vec3(1.0, 0.0, 0.0), vec3(1.0, 1.0, 0.0), vec3(0.0, 1.0, 0.0), vec3(0.0, 1.0, 1.0), vec3(0.0, 0.0, 1.0), vec3(0.0, 0.0, 1.0)), vec3[](vec3(0.0), vec3(0.0), vec3(0.0), vec3(0.0), vec3(0.0), vec3(0.0), vec3(0.0), vec3(0.0), vec3(1.0, 0.0, 0.0), vec3(1.0, 0.0, 0.0), vec3(1.0, 1.0, 0.0), vec3(0.0, 1.0, 0.0), vec3(0.0, 1.0, 1.0), vec3(0.0, 0.0, 1.0)));
const vec3 _3547[4][4] = vec3[][](vec3[](vec3(0.0, 1.0, 0.0), vec3(1.0, 0.0, 1.0), vec3(0.0, 1.0, 0.0), vec3(1.0, 0.0, 1.0)), vec3[](vec3(0.0), vec3(0.0, 0.0, 1.0), vec3(0.0, 1.0, 0.0), vec3(1.0, 0.0, 0.0)), vec3[](vec3(0.0, 1.0, 0.0), vec3(1.0, 0.0, 1.0), vec3(0.0, 1.0, 0.0), vec3(1.0, 0.0, 1.0)), vec3[](vec3(0.0, 1.0, 0.0), vec3(1.0, 0.0, 0.0), vec3(0.0), vec3(0.0, 0.0, 1.0)));
const vec3 _3551[4][8] = vec3[][](vec3[](vec3(1.0, 0.0, 0.0), vec3(0.0, 1.0, 0.0), vec3(0.0, 0.0, 1.0), vec3(0.0), vec3(1.0, 0.0, 0.0), vec3(0.0, 1.0, 0.0), vec3(0.0, 0.0, 1.0), vec3(0.0)), vec3[](vec3(1.0, 0.0, 0.0), vec3(0.0, 1.0, 0.0), vec3(0.0, 0.0, 1.0), vec3(0.0), vec3(0.0), vec3(0.0), vec3(0.0), vec3(0.0)), vec3[](vec3(1.0, 0.0, 0.0), vec3(0.0, 1.0, 0.0), vec3(0.0, 0.0, 1.0), vec3(0.0), vec3(1.0, 0.0, 0.0), vec3(0.0, 1.0, 0.0), vec3(0.0, 0.0, 1.0), vec3(0.0)), vec3[](vec3(0.0), vec3(0.0), vec3(0.0), vec3(0.0), vec3(1.0, 0.0, 0.0), vec3(0.0, 1.0, 0.0), vec3(0.0, 0.0, 1.0), vec3(0.0)));
const vec3 _3552[3] = vec3[](vec3(0.0), vec3(1.0), vec3(1.0));
const vec3 _3553[4] = vec3[](vec3(0.0), vec3(0.0), vec3(1.0), vec3(1.0));
const vec3 _3556[6][10] = vec3[][](vec3[](vec3(0.0, 1.0, 0.0), vec3(0.0, 1.0, 1.0), vec3(0.0, 0.0, 1.0), vec3(0.0, 0.0, 1.0), vec3(0.0, 0.0, 1.0), vec3(1.0, 0.0, 0.0), vec3(1.0, 0.0, 0.0), vec3(1.0, 0.0, 0.0), vec3(1.0, 1.0, 0.0), vec3(0.0, 1.0, 0.0)), vec3[](vec3(0.0, 1.0, 0.0), vec3(0.0, 1.0, 1.0), vec3(0.0, 0.0, 1.0), vec3(0.0, 0.0, 1.0), vec3(0.0, 0.0, 1.0), vec3(1.0, 0.0, 0.0), vec3(1.0, 0.0, 0.0), vec3(1.0, 0.0, 0.0), vec3(1.0, 1.0, 0.0), vec3(0.0, 1.0, 0.0)), vec3[](vec3(0.0, 1.0, 0.0), vec3(0.0, 1.0, 1.0), vec3(0.0, 0.0, 1.0), vec3(0.0, 0.0, 1.0), vec3(0.0, 0.0, 1.0), vec3(1.0, 0.0, 0.0), vec3(1.0, 0.0, 0.0), vec3(1.0, 0.0, 0.0), vec3(1.0, 1.0, 0.0), vec3(0.0, 1.0, 0.0)), vec3[](vec3(1.0, 0.0, 0.0), vec3(1.0, 0.0, 0.0), vec3(1.0, 0.0, 0.0), vec3(1.0, 1.0, 0.0), vec3(0.0, 1.0, 0.0), vec3(0.0, 1.0, 0.0), vec3(0.0, 1.0, 1.0), vec3(0.0, 0.0, 1.0), vec3(0.0, 0.0, 1.0), vec3(0.0, 0.0, 1.0)), vec3[](vec3(1.0, 0.0, 0.0), vec3(1.0, 0.0, 0.0), vec3(1.0, 0.0, 0.0), vec3(1.0, 1.0, 0.0), vec3(0.0, 1.0, 0.0), vec3(0.0, 1.0, 0.0), vec3(0.0, 1.0, 1.0), vec3(0.0, 0.0, 1.0), vec3(0.0, 0.0, 1.0), vec3(0.0, 0.0, 1.0)), vec3[](vec3(1.0, 0.0, 0.0), vec3(1.0, 0.0, 0.0), vec3(1.0, 0.0, 0.0), vec3(1.0, 1.0, 0.0), vec3(0.0, 1.0, 0.0), vec3(0.0, 1.0, 0.0), vec3(0.0, 1.0, 1.0), vec3(0.0, 0.0, 1.0), vec3(0.0, 0.0, 1.0), vec3(0.0, 0.0, 1.0)));

struct UBO
{
    vec4 SourceSize;
    vec4 OutputSize;
    uint FrameCount;
};



struct Push
{
    float CRTgamma;
    float width;
    float aspect_x;
    float aspect_y;
    float d;
    float R;
    float aperture_strength;
    float aperture_brightboost;
    float halation;
    float curvature;
    float cornersize;
    float cornersmooth;
    float overscan_x;
    float overscan_y;
    float monitorgamma;
    float mask_type;
    float scanline_weight;
    float geom_lum;
    float interlace_detect;
    float rasterbloom;
};



layout(binding = 3) uniform sampler2D Pass1Texture;
layout(binding = 2) uniform sampler2D Pass4Texture;

layout(location = 0) in vec2 RA_VARYING_0;
layout(location = 3) in vec3 RA_VARYING_3;
layout(location = 1) in vec2 RA_VARYING_1;
layout(location = 2) in vec2 RA_VARYING_2;
layout(location = 5) in vec2 RA_VARYING_5;
layout(location = 6) in vec2 RA_VARYING_6;
layout(location = 4) in vec2 RA_VARYING_4;
layout(location = 0) out vec4 FragColor;

void main()
{
    vec2 _71 = vec2((aspect_x), (aspect_y));
    vec2 _87 = vec2((overscan_x), (overscan_y));
    int _93 = int((mask_type));
    vec2 _3477;
    if ((curvature) > 0.5)
    {
        vec2 _1926 = (((RA_VARYING_0 - vec2(0.5)) * _71) * RA_VARYING_3.z) + RA_VARYING_3.xy;
        float _2041 = (d) * (d);
        float _2042 = dot(_1926, _1926) + _2041;
        float _2063 = ((R) * (dot(_1926, RA_VARYING_1) - (((d) * RA_VARYING_2.x) * RA_VARYING_2.y))) - _2041;
        vec2 _1971 = ((vec2(((_2063 * (-2.0)) - sqrt((4.0 * (_2063 * _2063)) - ((4.0 * _2042) * (_2041 + ((((2.0 * (R)) * (d)) * RA_VARYING_2.x) * RA_VARYING_2.y))))) / (2.0 * _2042)) * _1926) - (vec2(-(R)) * RA_VARYING_1)) / vec2((R));
        vec2 _1974 = RA_VARYING_1 / RA_VARYING_2;
        vec2 _1977 = _1971 / RA_VARYING_2;
        float _1981 = dot(_1974, _1974) + 1.0;
        float _1984 = dot(_1977, _1974);
        float _2004 = ((_1984 * 2.0) + sqrt((4.0 * (_1984 * _1984)) - ((4.0 * _1981) * (dot(_1977, _1977) - 1.0)))) / (2.0 * _1981);
        float _2018 = max(abs((R) * acos(_2004)), 9.9999997473787516355514526367188e-06);
        _3477 = ((((((_1971 - (RA_VARYING_1 * _2004)) / RA_VARYING_2) * _2018) / vec2(sin(_2018 / (R)))) / _87) / _71) + vec2(0.5);
    }
    else
    {
        _3477 = ((RA_VARYING_0 - vec2(0.5)) / _87) + vec2(0.5);
    }
    vec2 _2103 = _3477 - vec2(0.5);
    vec2 _2105 = _2103 * _87;
    vec2 _2115 = vec2((cornersize));
    vec2 _2120 = _2115 - min(min(_2105 + vec2(0.5), vec2(0.5) - _2105) * _71, _2115);
    float _2133 = clamp((max((cornersize), 0.001000000047497451305389404296875) - sqrt(dot(_2120, _2120))) * (cornersmooth), 0.0, 1.0);
    float _1475 = 1.0 - (((rasterbloom) * 0.100000001490116119384765625) * ((dot(textureLod(Pass4Texture, vec2(1.0), 9.0).xyz, vec3(1.0)) * 0.3333333432674407958984375) - 0.5));
    vec2 _1479 = _2103 * _1475;
    vec2 _1480 = _1479 + vec2(0.5);
    float _3480;
    if ((RA_VARYING_5.y * (interlace_detect)) > 1.5)
    {
        _3480 = mod(float((uint(FrameCount))), 2.0);
    }
    else
    {
        _3480 = 0.0;
    }
    vec2 _1507 = vec2(0.0, _3480);
    vec2 _1517 = (((_1480 * RA_VARYING_6) - vec2(0.5)) + _1507) / RA_VARYING_5;
    float _1521 = fwidth(_1517.y);
    vec2 _1524 = fract(_1517);
    vec2 _1533 = (((floor(_1517) * RA_VARYING_5) + vec2(0.5)) - _1507) / RA_VARYING_6;
    float _1537 = _1524.x;
    vec4 _1552 = max(abs(vec4(1.0 + _1537, _1537, 1.0 - _1537, 2.0 - _1537) * 3.1415927410125732421875), vec4(9.9999997473787516355514526367188e-06));
    vec4 _1564 = ((sin(_1552) * 2.0) * sin(_1552 * vec4(0.5))) / (_1552 * _1552);
    vec4 _1570 = _1564 / vec4(dot(_1564, vec4(1.0)));
    float _1576 = -RA_VARYING_4.x;
    vec2 _1578 = _1533 + vec2(_1576, 0.0);
    vec2 _2145 = step(vec2(0.0), _1578) * step(vec2(0.0), vec2(1.0) - _1578);
    vec4 _2159 = vec4((CRTgamma));
    float _1582 = _1570.x;
    vec2 _2173 = step(vec2(0.0), _1533) * step(vec2(0.0), vec2(1.0) - _1533);
    float _1588 = _1570.y;
    vec2 _1595 = _1533 + vec2(RA_VARYING_4.x, 0.0);
    vec2 _2201 = step(vec2(0.0), _1595) * step(vec2(0.0), vec2(1.0) - _1595);
    float _1599 = _1570.z;
    float _1605 = 2.0 * RA_VARYING_4.x;
    vec2 _1607 = _1533 + vec2(_1605, 0.0);
    vec2 _2229 = step(vec2(0.0), _1607) * step(vec2(0.0), vec2(1.0) - _1607);
    float _1611 = _1570.w;
    vec4 _1616 = clamp((((pow(texture(Pass1Texture, _1578) * vec4(_2145.x * _2145.y), _2159) * _1582) + (pow(texture(Pass1Texture, _1533) * vec4(_2173.x * _2173.y), _2159) * _1588)) + (pow(texture(Pass1Texture, _1595) * vec4(_2201.x * _2201.y), _2159) * _1599)) + (pow(texture(Pass1Texture, _1607) * vec4(_2229.x * _2229.y), _2159) * _1611), vec4(0.0), vec4(1.0));
    vec2 _1625 = _1533 + vec2(_1576, RA_VARYING_4.y);
    vec2 _2257 = step(vec2(0.0), _1625) * step(vec2(0.0), vec2(1.0) - _1625);
    vec2 _1635 = _1533 + vec2(0.0, RA_VARYING_4.y);
    vec2 _2285 = step(vec2(0.0), _1635) * step(vec2(0.0), vec2(1.0) - _1635);
    vec2 _1644 = _1533 + RA_VARYING_4;
    vec2 _2313 = step(vec2(0.0), _1644) * step(vec2(0.0), vec2(1.0) - _1644);
    vec2 _1658 = _1533 + vec2(_1605, RA_VARYING_4.y);
    vec2 _2341 = step(vec2(0.0), _1658) * step(vec2(0.0), vec2(1.0) - _1658);
    vec4 _1667 = clamp((((pow(texture(Pass1Texture, _1625) * vec4(_2257.x * _2257.y), _2159) * _1582) + (pow(texture(Pass1Texture, _1635) * vec4(_2285.x * _2285.y), _2159) * _1588)) + (pow(texture(Pass1Texture, _1644) * vec4(_2313.x * _2313.y), _2159) * _1599)) + (pow(texture(Pass1Texture, _1658) * vec4(_2341.x * _2341.y), _2159) * _1611), vec4(0.0), vec4(1.0));
    float _1671 = _1524.y;
    vec4 _2366 = vec4(2.0) + (pow(_1616, vec4(4.0)) * 2.0);
    float _2374 = (geom_lum) + 1.39999997615814208984375;
    vec4 _2378 = inversesqrt(_2366 * 0.5);
    vec4 _2388 = vec4(0.60000002384185791015625) + (_2366 * 0.20000000298023223876953125);
    vec4 _2398 = vec4(2.0) + (pow(_1667, vec4(4.0)) * 2.0);
    vec4 _2410 = inversesqrt(_2398 * 0.5);
    vec4 _2420 = vec4(0.60000002384185791015625) + (_2398 * 0.20000000298023223876953125);
    float _1687 = _1671 + (0.3333333432674407958984375 * _1521);
    float _1715 = _1687 - (0.666666686534881591796875 * _1521);
    vec3 _1748 = ((_1616 * (vec4(0.3333333432674407958984375) * ((((exp(-pow(vec4(_1671 / (scanline_weight)) * _2378, _2366)) * _2374) / _2388) + ((exp(-pow(vec4(_1687 / (scanline_weight)) * _2378, _2366)) * _2374) / _2388)) + ((exp(-pow(vec4(abs(_1715) / (scanline_weight)) * _2378, _2366)) * _2374) / _2388)))) + (_1667 * (vec4(0.3333333432674407958984375) * ((((exp(-pow(vec4((1.0 - _1671) / (scanline_weight)) * _2410, _2398)) * _2374) / _2420) + ((exp(-pow(vec4(abs(1.0 - _1687) / (scanline_weight)) * _2410, _2398)) * _2374) / _2420)) + ((exp(-pow(vec4(abs(1.0 - _1715) / (scanline_weight)) * _2410, _2398)) * _2374) / _2420))))).xyz;
    vec2 _2575 = (min(_1480, vec2(0.5) - _1479) * _71) * vec2(320.0 / (width));
    vec2 _2580 = exp((-_2575) * _2575);
    vec2 _2593 = (((step(vec2(0.0), _2575) - vec2(0.5)) * sqrt(vec2(1.0) - _2580)) * (vec2(1.0) + (vec2(0.174899995326995849609375) * _2580))) + vec2(0.5);
    vec3 _2601 = pow(texture(Pass4Texture, _1480).xyz, vec3((CRTgamma))) * vec3(_2593.x * _2593.y);
    vec3 _1757 = vec3((halation));
    vec3 _1772 = mix(mix(_1748, _2601, _1757) * vec3(_2133), _2601, _1757) * vec3(_2133 * _1475);
    vec2 _1793 = RA_VARYING_0 * (vec4(OutputSize, 1.0 / OutputSize)).xy;
    vec3 _3488;
    float _3489;
    do
    {
        float _2672 = _1793.x;
        vec3 _2675 = vec3(floor(mod(_2672, 2.0)));
        vec3 _2676 = mix(vec3(1.0, 0.0, 1.0), vec3(0.0, 1.0, 0.0), _2675);
        if (_93 == 0)
        {
            _3489 = 1.0;
            _3488 = vec3(1.0);
            break;
        }
        else
        {
            if (_93 == 1)
            {
                _3489 = 0.5;
                _3488 = _2676;
                break;
            }
            else
            {
                if (_93 == 2)
                {
                    _3489 = 0.5;
                    _3488 = mix(_2676, mix(vec3(0.0, 1.0, 0.0), vec3(1.0, 0.0, 1.0), _2675), vec3(floor(mod(_1793.y, 2.0))));
                    break;
                }
                else
                {
                    if (_93 == 3)
                    {
                        _3489 = 0.3333333432674407958984375;
                        _3488 = _3509[int(floor(mod(_1793.y, 3.0)))][int(floor(mod(_2672, 4.0)))];
                        break;
                    }
                    else
                    {
                        if (_93 == 4)
                        {
                            _3489 = 0.5;
                            _3488 = mix(vec3(1.0, 1.0, 0.0), vec3(0.0, 0.0, 1.0), _2675);
                            break;
                        }
                        else
                        {
                            if (_93 == 5)
                            {
                                _3489 = 0.5;
                                _3488 = mix(mix(vec3(1.0, 1.0, 0.0), vec3(0.0, 0.0, 1.0), _2675), mix(vec3(0.0, 0.0, 1.0), vec3(1.0, 1.0, 0.0), _2675), vec3(floor(mod(_1793.y, 2.0))));
                                break;
                            }
                            else
                            {
                                if (_93 == 6)
                                {
                                    _3489 = 0.25;
                                    _3488 = _3510[int(floor(mod(_2672, 4.0)))];
                                    break;
                                }
                                else
                                {
                                    if (_93 == 7)
                                    {
                                        _3489 = 0.4000000059604644775390625;
                                        _3488 = _3511[int(floor(mod(_2672, 5.0)))];
                                        break;
                                    }
                                    else
                                    {
                                        if (_93 == 8)
                                        {
                                            _3489 = 0.4444444477558135986328125;
                                            _3488 = _3512[int(floor(mod(_2672, 7.0)))];
                                            break;
                                        }
                                        else
                                        {
                                            if (_93 == 9)
                                            {
                                                _3489 = 0.5;
                                                _3488 = _3513[int(floor(mod(_2672, 4.0)))];
                                                break;
                                            }
                                            else
                                            {
                                                if (_93 == 10)
                                                {
                                                    _3489 = 0.5;
                                                    _3488 = _3514[int(floor(mod(_2672, 4.0)))];
                                                    break;
                                                }
                                                else
                                                {
                                                    if (_93 == 11)
                                                    {
                                                        _3489 = 0.25;
                                                        _3488 = _3516[int(floor(mod(_1793.y, 2.0)))][int(floor(mod(_2672, 4.0)))];
                                                        break;
                                                    }
                                                    else
                                                    {
                                                        if (_93 == 12)
                                                        {
                                                            _3489 = 0.5;
                                                            _3488 = _3518[int(floor(mod(_1793.y, 2.0)))][int(floor(mod(_2672, 4.0)))];
                                                            break;
                                                        }
                                                        else
                                                        {
                                                            if (_93 == 13)
                                                            {
                                                                _3489 = 0.5;
                                                                _3488 = _3519[int(floor(mod(_1793.y, 4.0)))][int(floor(mod(_2672, 4.0)))];
                                                                break;
                                                            }
                                                            else
                                                            {
                                                                if (_93 == 14)
                                                                {
                                                                    _3489 = 0.22222222387790679931640625;
                                                                    _3488 = _3523[int(floor(mod(_1793.y, 3.0)))][int(floor(mod(_2672, 6.0)))];
                                                                    break;
                                                                }
                                                                else
                                                                {
                                                                    if (_93 == 15)
                                                                    {
                                                                        _3489 = 0.375;
                                                                        _3488 = _3527[int(floor(mod(_1793.y, 4.0)))][int(floor(mod(_2672, 8.0)))];
                                                                        break;
                                                                    }
                                                                    else
                                                                    {
                                                                        if (_93 == 16)
                                                                        {
                                                                            _3489 = 0.388888895511627197265625;
                                                                            _3488 = _3531[int(floor(mod(_1793.y, 3.0)))][int(floor(mod(_2672, 4.0)))];
                                                                            break;
                                                                        }
                                                                        else
                                                                        {
                                                                            if (_93 == 17)
                                                                            {
                                                                                _3489 = 0.300000011920928955078125;
                                                                                _3488 = _3535[int(floor(mod(_1793.y, 4.0)))][int(floor(mod(_2672, 10.0)))];
                                                                                break;
                                                                            }
                                                                            else
                                                                            {
                                                                                if (_93 == 18)
                                                                                {
                                                                                    _3489 = 0.300000011920928955078125;
                                                                                    _3488 = _3539[int(floor(mod(_1793.y, 4.0)))][int(floor(mod(_2672, 10.0)))];
                                                                                    break;
                                                                                }
                                                                                else
                                                                                {
                                                                                    if (_93 == 19)
                                                                                    {
                                                                                        _3489 = 0.3531745970249176025390625;
                                                                                        _3488 = _3543[int(floor(mod(_1793.y, 6.0)))][int(floor(mod(_2672, 14.0)))];
                                                                                        break;
                                                                                    }
                                                                                    else
                                                                                    {
                                                                                        if (_93 == 20)
                                                                                        {
                                                                                            _3489 = 0.375;
                                                                                            _3488 = _3547[int(floor(mod(_1793.y, 4.0)))][int(floor(mod(_2672, 4.0)))];
                                                                                            break;
                                                                                        }
                                                                                        else
                                                                                        {
                                                                                            if (_93 == 21)
                                                                                            {
                                                                                                _3489 = 0.21875;
                                                                                                _3488 = _3551[int(floor(mod(_1793.y, 4.0)))][int(floor(mod(_2672, 8.0)))];
                                                                                                break;
                                                                                            }
                                                                                            else
                                                                                            {
                                                                                                if (_93 == 22)
                                                                                                {
                                                                                                    _3489 = 0.666666686534881591796875;
                                                                                                    _3488 = _3552[int(floor(mod(_2672, 3.0)))];
                                                                                                    break;
                                                                                                }
                                                                                                else
                                                                                                {
                                                                                                    if (_93 == 23)
                                                                                                    {
                                                                                                        _3489 = 0.5;
                                                                                                        _3488 = _3553[int(floor(mod(_2672, 4.0)))];
                                                                                                        break;
                                                                                                    }
                                                                                                    else
                                                                                                    {
                                                                                                        if (_93 == 24)
                                                                                                        {
                                                                                                            _3489 = 0.4000000059604644775390625;
                                                                                                            _3488 = _3556[int(floor(mod(_1793.y, 6.0)))][int(floor(mod(_2672, 10.0)))];
                                                                                                            break;
                                                                                                        }
                                                                                                        else
                                                                                                        {
                                                                                                            _3489 = 1.0;
                                                                                                            _3488 = vec3(1.0);
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
        }
        break; // unreachable workaround
    } while(false);
    vec4 _1805 = vec4(_3488, 1.0);
    _1805.w = _3489;
    vec2 _1822 = (vec4(OutputSize, 1.0 / OutputSize)).xy * (vec4(TextureSize, 1.0 / TextureSize)).zw;
    float _1833 = (255.0 - (255.0 * _3489)) / (_1822.x * _1822.y);
    vec3 _1861 = _1772 * (vec3(1.0 - (aperture_strength)) + (vec3((aperture_strength) * (aperture_brightboost)) * _1772));
    float _1864 = 1.0 / _1833;
    FragColor = vec4(pow(mix(_1861, (vec3(_1864 * mix(1.0 - ((aperture_strength) * (1.0 - (aperture_brightboost))), 1.0, _1833)) * _1772) - (vec3(_1864 - 1.0) * _1861), _1805.xyz), vec3(1.0 / (monitorgamma))), _1616.w);
}


#endif
