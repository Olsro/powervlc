// Generated from crt/shaders/crt-geom.slang. See slang/upstream for licence/source.
#version 430
#pragma parameter CRTgamma "CRTGeom Target Gamma" 2.4 0.1 5.0 0.1
#pragma parameter monitorgamma "CRTGeom Monitor Gamma" 2.2 0.1 5.0 0.1
#pragma parameter d "CRTGeom Distance" 1.5 0.1 3.0 0.1
#pragma parameter CURVATURE "CRTGeom Curvature Toggle" 1.0 0.0 1.0 1.0
#pragma parameter invert_aspect "CRTGeom Curvature Aspect Inversion" 0.0 0.0 1.0 1.0
#pragma parameter R "CRTGeom Curvature Radius" 2.0 0.1 10.0 0.1
#pragma parameter cornersize "CRTGeom Corner Size" 0.03 0.001 1.0 0.005
#pragma parameter cornersmooth "CRTGeom Corner Smoothness" 1000.0 80.0 2000.0 100.0
#pragma parameter x_tilt "CRTGeom Horizontal Tilt" 0.0 -0.5 0.5 0.05
#pragma parameter y_tilt "CRTGeom Vertical Tilt" 0.0 -0.5 0.5 0.05
#pragma parameter overscan_x "CRTGeom Horiz. Overscan %" 100.0 -125.0 125.0 0.5
#pragma parameter overscan_y "CRTGeom Vert. Overscan %" 100.0 -125.0 125.0 0.5
#pragma parameter mask_type "CRTGeom Mask Pattern" 1.0 1.0 20.0 1.0
#pragma parameter DOTMASK "CRTGeom Mask strength" 0.3 0.0 1.0 0.05
#pragma parameter DOTMASK_brightboost "CRTGeom Mask brightness boost" 0.0 0.0 1.0 0.05
#pragma parameter SHARPER "CRTGeom Sharpness" 1.0 1.0 3.0 1.0
#pragma parameter scanline_weight "CRTGeom Scanline Weight" 0.3 0.1 0.5 0.05
#pragma parameter vertical_scanlines "CRTGeom Vertical Scanlines" 0.0 0.0 1.0 1.0
#pragma parameter lum "CRTGeom Luminance" 0.0 0.0 1.0 0.01
#pragma parameter interlace_detect "CRTGeom Interlacing Simulation" 1.0 0.0 1.0 1.0
#pragma parameter xsize "Simulated Width (0==Auto)" 0.0 0.0 1920.0 16.0
#pragma parameter ysize "Simulated Height (0==Auto)" 0.0 0.0 1080.0 16.0
#ifdef VERTEX

uniform mat4 MVPMatrix;
uniform vec2 OutputSize;
uniform float R;
uniform float SHARPER;
uniform vec2 TextureSize;
uniform float d;
uniform float interlace_detect;
uniform float invert_aspect;
uniform float vertical_scanlines;
uniform float x_tilt;
uniform float xsize;
uniform float y_tilt;
uniform float ysize;
struct UBO
{
    mat4 MVP;
    vec4 OutputSize;
    vec4 SourceSize;
};



struct Push
{
    float d;
    float R;
    float x_tilt;
    float y_tilt;
    float SHARPER;
    float interlace_detect;
    float invert_aspect;
    float vertical_scanlines;
    float xsize;
    float ysize;
};



layout(location = 1) out vec2 RA_VARYING_1;
layout(location = 2) out vec2 RA_VARYING_2;
layout(location = 0) in vec4 VertexCoord;
layout(location = 0) out vec2 RA_VARYING_0;
layout(location = 1) in vec2 TexCoord;
layout(location = 3) out vec3 RA_VARYING_3;
layout(location = 7) out vec2 RA_VARYING_7;
layout(location = 4) out vec2 RA_VARYING_4;
layout(location = 5) out vec2 RA_VARYING_5;
layout(location = 6) out float RA_VARYING_6;

void main()
{
    vec2 _1022;
    if ((ysize) > 0.001000000047497451305389404296875)
    {
        _1022 = vec2((ysize), 1.0 / (ysize));
    }
    else
    {
        _1022 = (vec4(TextureSize, 1.0 / TextureSize)).yw;
    }
    vec2 _1023;
    if ((xsize) > 0.001000000047497451305389404296875)
    {
        _1023 = vec2((xsize), 1.0 / (xsize));
    }
    else
    {
        _1023 = (vec4(TextureSize, 1.0 / TextureSize)).xz;
    }
    vec2 _106 = vec2(((invert_aspect) > 0.5) ? 1.0 : 0.75);
    gl_Position = (MVPMatrix) * VertexCoord;
    RA_VARYING_0 = TexCoord * vec2(1.000010013580322265625);
    vec2 _454 = vec2((x_tilt), (y_tilt));
    RA_VARYING_1 = sin(_454);
    RA_VARYING_2 = cos(_454);
    float _560 = -(R);
    vec2 _576 = (RA_VARYING_1 * _560) / vec2(1.0 + ((((R) / (d)) * RA_VARYING_2.x) * RA_VARYING_2.y));
    float _740 = (d) * (d);
    float _741 = dot(_576, _576) + _740;
    float _762 = ((R) * (dot(_576, RA_VARYING_1) - (((d) * RA_VARYING_2.x) * RA_VARYING_2.y))) - _740;
    vec2 _670 = ((vec2(((_762 * (-2.0)) - sqrt((4.0 * (_762 * _762)) - ((4.0 * _741) * (_740 + ((((2.0 * (R)) * (d)) * RA_VARYING_2.x) * RA_VARYING_2.y))))) / (2.0 * _741)) * _576) - (vec2(_560) * RA_VARYING_1)) / vec2((R));
    vec2 _673 = _670 / RA_VARYING_2;
    vec2 _676 = RA_VARYING_1 / RA_VARYING_2;
    float _680 = dot(_676, _676) + 1.0;
    float _683 = dot(_673, _676);
    float _703 = ((_683 * 2.0) + sqrt((4.0 * (_683 * _683)) - ((4.0 * _680) * (dot(_673, _673) - 1.0)))) / (2.0 * _680);
    float _717 = max(abs((R) * acos(_703)), 9.9999997473787516355514526367188e-06);
    vec2 _727 = (((_670 - (RA_VARYING_1 * _703)) / RA_VARYING_2) * _717) / vec2(sin(_717 / (R)));
    vec2 _579 = vec2(0.5) * _106;
    float _581 = _579.x;
    vec2 _585 = vec2(-_581, _727.y);
    float _807 = max(abs(sqrt(dot(_585, _585))), 9.9999997473787516355514526367188e-06);
    float _811 = _807 / (R);
    vec2 _816 = _585 * (sin(_811) / _807);
    float _822 = 1.0 - cos(_811);
    float _827 = (d) / (R);
    float _591 = _579.y;
    vec2 _593 = vec2(_727.x, -_591);
    float _863 = max(abs(sqrt(dot(_593, _593))), 9.9999997473787516355514526367188e-06);
    float _867 = _863 / (R);
    vec2 _872 = _593 * (sin(_867) / _863);
    float _878 = 1.0 - cos(_867);
    vec2 _598 = vec2(((((_816 * RA_VARYING_2) - (RA_VARYING_1 * _822)) * (d)) / vec2((_827 + ((_822 * RA_VARYING_2.x) * RA_VARYING_2.y)) + dot(_816, RA_VARYING_1))).x, ((((_872 * RA_VARYING_2) - (RA_VARYING_1 * _878)) * (d)) / vec2((_827 + ((_878 * RA_VARYING_2.x) * RA_VARYING_2.y)) + dot(_872, RA_VARYING_1))).y) / _106;
    vec2 _603 = vec2(_581, _727.y);
    float _919 = max(abs(sqrt(dot(_603, _603))), 9.9999997473787516355514526367188e-06);
    float _923 = _919 / (R);
    vec2 _928 = _603 * (sin(_923) / _919);
    float _934 = 1.0 - cos(_923);
    vec2 _610 = vec2(_727.x, _591);
    float _975 = max(abs(sqrt(dot(_610, _610))), 9.9999997473787516355514526367188e-06);
    float _979 = _975 / (R);
    vec2 _984 = _610 * (sin(_979) / _975);
    float _990 = 1.0 - cos(_979);
    vec2 _615 = vec2(((((_928 * RA_VARYING_2) - (RA_VARYING_1 * _934)) * (d)) / vec2((_827 + ((_934 * RA_VARYING_2.x) * RA_VARYING_2.y)) + dot(_928, RA_VARYING_1))).x, ((((_984 * RA_VARYING_2) - (RA_VARYING_1 * _990)) * (d)) / vec2((_827 + ((_990 * RA_VARYING_2.x) * RA_VARYING_2.y)) + dot(_984, RA_VARYING_1))).y) / _106;
    RA_VARYING_3 = vec3(((_615 + _598) * _106) * 0.5, max(_615.x - _598.x, _615.y - _598.y));
    if ((vertical_scanlines) < 0.5)
    {
        RA_VARYING_7 = vec2((SHARPER) * _1023.x, _1022.x);
        RA_VARYING_4 = vec2(1.0, clamp(floor(_1022.x / (((interlace_detect) > 0.5) ? 200.0 : 1000.0)), 1.0, 2.0));
        RA_VARYING_5 = RA_VARYING_4 / RA_VARYING_7;
        RA_VARYING_6 = ((RA_VARYING_0.x * _1023.x) * (vec4(OutputSize, 1.0 / OutputSize)).x) / _1023.x;
    }
    else
    {
        RA_VARYING_7 = vec2(_1023.x, (SHARPER) * _1022.x);
        RA_VARYING_4 = vec2(clamp(floor(_1023.x / (((interlace_detect) > 0.5) ? 200.0 : 1000.0)), 1.0, 2.0), 1.0);
        RA_VARYING_5 = RA_VARYING_4 / RA_VARYING_7;
        RA_VARYING_6 = ((RA_VARYING_0.y * _1022.x) * (vec4(OutputSize, 1.0 / OutputSize)).y) / _1022.x;
    }
}


#endif
#ifdef FRAGMENT

uniform float CRTgamma;
uniform float CURVATURE;
uniform float DOTMASK;
uniform float DOTMASK_brightboost;
uniform int FrameCount;
uniform vec2 OutputSize;
uniform float R;
uniform vec2 TextureSize;
uniform float cornersize;
uniform float cornersmooth;
uniform float d;
uniform float interlace_detect;
uniform float invert_aspect;
uniform float lum;
uniform float mask_type;
uniform float monitorgamma;
uniform float overscan_x;
uniform float overscan_y;
uniform float scanline_weight;
uniform float vertical_scanlines;
const vec3 _4686[3][4] = vec3[][](vec3[](vec3(1.0, 0.0, 1.0), vec3(0.0, 1.0, 0.0), vec3(0.0), vec3(0.0)), vec3[](vec3(1.0, 0.0, 1.0), vec3(0.0, 1.0, 0.0), vec3(1.0, 0.0, 1.0), vec3(0.0, 1.0, 0.0)), vec3[](vec3(0.0), vec3(0.0), vec3(1.0, 0.0, 1.0), vec3(0.0, 1.0, 0.0)));
const vec3 _4687[4] = vec3[](vec3(1.0, 0.0, 0.0), vec3(0.0, 1.0, 0.0), vec3(0.0, 0.0, 1.0), vec3(0.0));
const vec3 _4688[5] = vec3[](vec3(1.0, 0.0, 0.0), vec3(1.0, 0.0, 1.0), vec3(0.0, 0.0, 1.0), vec3(0.0, 1.0, 0.0), vec3(0.0, 1.0, 0.0));
const vec3 _4689[7] = vec3[](vec3(1.0, 0.0, 0.0), vec3(1.0, 0.0, 0.0), vec3(1.0, 1.0, 0.0), vec3(0.0, 1.0, 0.0), vec3(0.0, 1.0, 1.0), vec3(0.0, 0.0, 1.0), vec3(0.0, 0.0, 1.0));
const vec3 _4690[4] = vec3[](vec3(1.0, 0.0, 0.0), vec3(1.0, 1.0, 0.0), vec3(0.0, 1.0, 1.0), vec3(0.0, 0.0, 1.0));
const vec3 _4691[4] = vec3[](vec3(1.0, 0.0, 0.0), vec3(1.0, 0.0, 1.0), vec3(0.0, 1.0, 1.0), vec3(0.0, 1.0, 0.0));
const vec3 _4693[2][4] = vec3[][](vec3[](vec3(1.0, 0.0, 0.0), vec3(0.0, 1.0, 0.0), vec3(0.0, 0.0, 1.0), vec3(0.0)), vec3[](vec3(0.0, 0.0, 1.0), vec3(0.0), vec3(1.0, 0.0, 0.0), vec3(0.0, 1.0, 0.0)));
const vec3 _4695[2][4] = vec3[][](vec3[](vec3(1.0, 0.0, 0.0), vec3(1.0, 1.0, 0.0), vec3(0.0, 1.0, 1.0), vec3(0.0, 0.0, 1.0)), vec3[](vec3(0.0, 1.0, 1.0), vec3(0.0, 0.0, 1.0), vec3(1.0, 0.0, 0.0), vec3(1.0, 1.0, 0.0)));
const vec3 _4696[4][4] = vec3[][](vec3[](vec3(1.0, 0.0, 0.0), vec3(1.0, 1.0, 0.0), vec3(0.0, 1.0, 1.0), vec3(0.0, 0.0, 1.0)), vec3[](vec3(1.0, 0.0, 0.0), vec3(1.0, 1.0, 0.0), vec3(0.0, 1.0, 1.0), vec3(0.0, 0.0, 1.0)), vec3[](vec3(0.0, 1.0, 1.0), vec3(0.0, 0.0, 1.0), vec3(1.0, 0.0, 0.0), vec3(1.0, 1.0, 0.0)), vec3[](vec3(0.0, 1.0, 1.0), vec3(0.0, 0.0, 1.0), vec3(1.0, 0.0, 0.0), vec3(1.0, 1.0, 0.0)));
const vec3 _4700[3][6] = vec3[][](vec3[](vec3(1.0, 0.0, 1.0), vec3(0.0, 1.0, 0.0), vec3(0.0), vec3(0.0), vec3(0.0), vec3(0.0)), vec3[](vec3(1.0, 0.0, 1.0), vec3(0.0, 1.0, 0.0), vec3(0.0), vec3(1.0, 0.0, 1.0), vec3(0.0, 1.0, 0.0), vec3(0.0)), vec3[](vec3(0.0), vec3(0.0), vec3(0.0), vec3(1.0, 0.0, 1.0), vec3(0.0, 1.0, 0.0), vec3(0.0)));
const vec3 _4704[4][8] = vec3[][](vec3[](vec3(1.0, 0.0, 0.0), vec3(1.0, 1.0, 0.0), vec3(0.0, 1.0, 1.0), vec3(0.0, 0.0, 1.0), vec3(1.0, 0.0, 0.0), vec3(1.0, 1.0, 0.0), vec3(0.0, 1.0, 1.0), vec3(0.0, 0.0, 1.0)), vec3[](vec3(1.0, 0.0, 0.0), vec3(1.0, 1.0, 0.0), vec3(0.0, 1.0, 1.0), vec3(0.0, 0.0, 1.0), vec3(0.0), vec3(0.0), vec3(0.0), vec3(0.0)), vec3[](vec3(1.0, 0.0, 0.0), vec3(1.0, 1.0, 0.0), vec3(0.0, 1.0, 1.0), vec3(0.0, 0.0, 1.0), vec3(1.0, 0.0, 0.0), vec3(1.0, 1.0, 0.0), vec3(0.0, 1.0, 1.0), vec3(0.0, 0.0, 1.0)), vec3[](vec3(0.0), vec3(0.0), vec3(0.0), vec3(0.0), vec3(1.0, 0.0, 0.0), vec3(1.0, 1.0, 0.0), vec3(0.0, 1.0, 1.0), vec3(0.0, 0.0, 1.0)));
const vec3 _4708[3][4] = vec3[][](vec3[](vec3(1.0, 1.0, 0.0), vec3(0.0, 0.0, 1.0), vec3(0.0), vec3(0.0)), vec3[](vec3(1.0, 1.0, 0.0), vec3(0.0, 0.0, 1.0), vec3(1.0, 1.0, 0.0), vec3(0.0, 0.0, 1.0)), vec3[](vec3(0.0), vec3(0.0), vec3(1.0, 1.0, 0.0), vec3(0.0, 0.0, 1.0)));
const vec3 _4712[4][10] = vec3[][](vec3[](vec3(1.0, 0.0, 0.0), vec3(1.0, 0.0, 1.0), vec3(0.0, 0.0, 1.0), vec3(0.0, 1.0, 0.0), vec3(0.0, 1.0, 0.0), vec3(1.0, 0.0, 0.0), vec3(1.0, 0.0, 1.0), vec3(0.0, 0.0, 1.0), vec3(0.0, 1.0, 0.0), vec3(0.0, 1.0, 0.0)), vec3[](vec3(0.0), vec3(0.0, 0.0, 1.0), vec3(0.0, 0.0, 1.0), vec3(0.0, 1.0, 0.0), vec3(0.0, 1.0, 0.0), vec3(1.0, 0.0, 0.0), vec3(1.0, 0.0, 0.0), vec3(0.0), vec3(0.0), vec3(0.0)), vec3[](vec3(1.0, 0.0, 0.0), vec3(1.0, 0.0, 1.0), vec3(0.0, 0.0, 1.0), vec3(0.0, 1.0, 0.0), vec3(0.0, 1.0, 0.0), vec3(1.0, 0.0, 0.0), vec3(1.0, 0.0, 1.0), vec3(0.0, 0.0, 1.0), vec3(0.0, 1.0, 0.0), vec3(0.0, 1.0, 0.0)), vec3[](vec3(1.0, 0.0, 0.0), vec3(1.0, 0.0, 0.0), vec3(0.0), vec3(0.0), vec3(0.0), vec3(0.0), vec3(0.0, 0.0, 1.0), vec3(0.0, 0.0, 1.0), vec3(0.0, 1.0, 0.0), vec3(0.0, 1.0, 0.0)));
const vec3 _4716[4][10] = vec3[][](vec3[](vec3(1.0, 0.0, 0.0), vec3(1.0, 1.0, 0.0), vec3(0.0, 1.0, 0.0), vec3(0.0, 0.0, 1.0), vec3(0.0, 0.0, 1.0), vec3(1.0, 0.0, 0.0), vec3(1.0, 1.0, 0.0), vec3(0.0, 1.0, 0.0), vec3(0.0, 0.0, 1.0), vec3(0.0, 0.0, 1.0)), vec3[](vec3(0.0), vec3(0.0, 1.0, 0.0), vec3(0.0, 1.0, 0.0), vec3(0.0, 0.0, 1.0), vec3(0.0, 0.0, 1.0), vec3(1.0, 0.0, 0.0), vec3(1.0, 0.0, 0.0), vec3(0.0), vec3(0.0), vec3(0.0)), vec3[](vec3(1.0, 0.0, 0.0), vec3(1.0, 1.0, 0.0), vec3(0.0, 1.0, 0.0), vec3(0.0, 0.0, 1.0), vec3(0.0, 0.0, 1.0), vec3(1.0, 0.0, 0.0), vec3(1.0, 1.0, 0.0), vec3(0.0, 1.0, 0.0), vec3(0.0, 0.0, 1.0), vec3(0.0, 0.0, 1.0)), vec3[](vec3(1.0, 0.0, 0.0), vec3(1.0, 0.0, 0.0), vec3(0.0), vec3(0.0), vec3(0.0), vec3(0.0), vec3(0.0, 1.0, 0.0), vec3(0.0, 1.0, 0.0), vec3(0.0, 0.0, 1.0), vec3(0.0, 0.0, 1.0)));
const vec3 _4720[6][14] = vec3[][](vec3[](vec3(1.0, 0.0, 0.0), vec3(1.0, 0.0, 0.0), vec3(1.0, 1.0, 0.0), vec3(0.0, 1.0, 0.0), vec3(0.0, 1.0, 1.0), vec3(0.0, 0.0, 1.0), vec3(0.0, 0.0, 1.0), vec3(1.0, 0.0, 0.0), vec3(1.0, 0.0, 0.0), vec3(1.0, 1.0, 0.0), vec3(0.0, 1.0, 0.0), vec3(0.0, 1.0, 1.0), vec3(0.0, 0.0, 1.0), vec3(0.0, 0.0, 1.0)), vec3[](vec3(1.0, 0.0, 0.0), vec3(1.0, 0.0, 0.0), vec3(1.0, 1.0, 0.0), vec3(0.0, 1.0, 0.0), vec3(0.0, 1.0, 1.0), vec3(0.0, 0.0, 1.0), vec3(0.0, 0.0, 1.0), vec3(1.0, 0.0, 0.0), vec3(1.0, 0.0, 0.0), vec3(1.0, 1.0, 0.0), vec3(0.0, 1.0, 0.0), vec3(0.0, 1.0, 1.0), vec3(0.0, 0.0, 1.0), vec3(0.0, 0.0, 1.0)), vec3[](vec3(1.0, 0.0, 0.0), vec3(1.0, 0.0, 0.0), vec3(1.0, 1.0, 0.0), vec3(0.0, 1.0, 0.0), vec3(0.0, 1.0, 1.0), vec3(0.0, 0.0, 1.0), vec3(0.0, 0.0, 1.0), vec3(0.0), vec3(0.0), vec3(0.0), vec3(0.0), vec3(0.0), vec3(0.0), vec3(0.0)), vec3[](vec3(1.0, 0.0, 0.0), vec3(1.0, 0.0, 0.0), vec3(1.0, 1.0, 0.0), vec3(0.0, 1.0, 0.0), vec3(0.0, 1.0, 1.0), vec3(0.0, 0.0, 1.0), vec3(0.0, 0.0, 1.0), vec3(1.0, 0.0, 0.0), vec3(1.0, 0.0, 0.0), vec3(1.0, 1.0, 0.0), vec3(0.0, 1.0, 0.0), vec3(0.0, 1.0, 1.0), vec3(0.0, 0.0, 1.0), vec3(0.0, 0.0, 1.0)), vec3[](vec3(1.0, 0.0, 0.0), vec3(1.0, 0.0, 0.0), vec3(1.0, 1.0, 0.0), vec3(0.0, 1.0, 0.0), vec3(0.0, 1.0, 1.0), vec3(0.0, 0.0, 1.0), vec3(0.0, 0.0, 1.0), vec3(1.0, 0.0, 0.0), vec3(1.0, 0.0, 0.0), vec3(1.0, 1.0, 0.0), vec3(0.0, 1.0, 0.0), vec3(0.0, 1.0, 1.0), vec3(0.0, 0.0, 1.0), vec3(0.0, 0.0, 1.0)), vec3[](vec3(0.0), vec3(0.0), vec3(0.0), vec3(0.0), vec3(0.0), vec3(0.0), vec3(0.0), vec3(0.0), vec3(1.0, 0.0, 0.0), vec3(1.0, 0.0, 0.0), vec3(1.0, 1.0, 0.0), vec3(0.0, 1.0, 0.0), vec3(0.0, 1.0, 1.0), vec3(0.0, 0.0, 1.0)));
const vec3 _4724[4][4] = vec3[][](vec3[](vec3(0.0, 1.0, 0.0), vec3(1.0, 0.0, 1.0), vec3(0.0, 1.0, 0.0), vec3(1.0, 0.0, 1.0)), vec3[](vec3(0.0), vec3(0.0, 0.0, 1.0), vec3(0.0, 1.0, 0.0), vec3(1.0, 0.0, 0.0)), vec3[](vec3(0.0, 1.0, 0.0), vec3(1.0, 0.0, 1.0), vec3(0.0, 1.0, 0.0), vec3(1.0, 0.0, 1.0)), vec3[](vec3(0.0, 1.0, 0.0), vec3(1.0, 0.0, 0.0), vec3(0.0), vec3(0.0, 0.0, 1.0)));
const vec3 _4728[4][8] = vec3[][](vec3[](vec3(1.0, 0.0, 0.0), vec3(0.0, 1.0, 0.0), vec3(0.0, 0.0, 1.0), vec3(0.0), vec3(1.0, 0.0, 0.0), vec3(0.0, 1.0, 0.0), vec3(0.0, 0.0, 1.0), vec3(0.0)), vec3[](vec3(1.0, 0.0, 0.0), vec3(0.0, 1.0, 0.0), vec3(0.0, 0.0, 1.0), vec3(0.0), vec3(0.0), vec3(0.0), vec3(0.0), vec3(0.0)), vec3[](vec3(1.0, 0.0, 0.0), vec3(0.0, 1.0, 0.0), vec3(0.0, 0.0, 1.0), vec3(0.0), vec3(1.0, 0.0, 0.0), vec3(0.0, 1.0, 0.0), vec3(0.0, 0.0, 1.0), vec3(0.0)), vec3[](vec3(0.0), vec3(0.0), vec3(0.0), vec3(0.0), vec3(1.0, 0.0, 0.0), vec3(0.0, 1.0, 0.0), vec3(0.0, 0.0, 1.0), vec3(0.0)));
const vec3 _4729[3] = vec3[](vec3(0.0), vec3(1.0), vec3(1.0));
const vec3 _4730[4] = vec3[](vec3(0.0), vec3(0.0), vec3(1.0), vec3(1.0));
const vec3 _4733[6][10] = vec3[][](vec3[](vec3(0.0, 1.0, 0.0), vec3(0.0, 1.0, 1.0), vec3(0.0, 0.0, 1.0), vec3(0.0, 0.0, 1.0), vec3(0.0, 0.0, 1.0), vec3(1.0, 0.0, 0.0), vec3(1.0, 0.0, 0.0), vec3(1.0, 0.0, 0.0), vec3(1.0, 1.0, 0.0), vec3(0.0, 1.0, 0.0)), vec3[](vec3(0.0, 1.0, 0.0), vec3(0.0, 1.0, 1.0), vec3(0.0, 0.0, 1.0), vec3(0.0, 0.0, 1.0), vec3(0.0, 0.0, 1.0), vec3(1.0, 0.0, 0.0), vec3(1.0, 0.0, 0.0), vec3(1.0, 0.0, 0.0), vec3(1.0, 1.0, 0.0), vec3(0.0, 1.0, 0.0)), vec3[](vec3(0.0, 1.0, 0.0), vec3(0.0, 1.0, 1.0), vec3(0.0, 0.0, 1.0), vec3(0.0, 0.0, 1.0), vec3(0.0, 0.0, 1.0), vec3(1.0, 0.0, 0.0), vec3(1.0, 0.0, 0.0), vec3(1.0, 0.0, 0.0), vec3(1.0, 1.0, 0.0), vec3(0.0, 1.0, 0.0)), vec3[](vec3(1.0, 0.0, 0.0), vec3(1.0, 0.0, 0.0), vec3(1.0, 0.0, 0.0), vec3(1.0, 1.0, 0.0), vec3(0.0, 1.0, 0.0), vec3(0.0, 1.0, 0.0), vec3(0.0, 1.0, 1.0), vec3(0.0, 0.0, 1.0), vec3(0.0, 0.0, 1.0), vec3(0.0, 0.0, 1.0)), vec3[](vec3(1.0, 0.0, 0.0), vec3(1.0, 0.0, 0.0), vec3(1.0, 0.0, 0.0), vec3(1.0, 1.0, 0.0), vec3(0.0, 1.0, 0.0), vec3(0.0, 1.0, 0.0), vec3(0.0, 1.0, 1.0), vec3(0.0, 0.0, 1.0), vec3(0.0, 0.0, 1.0), vec3(0.0, 0.0, 1.0)), vec3[](vec3(1.0, 0.0, 0.0), vec3(1.0, 0.0, 0.0), vec3(1.0, 0.0, 0.0), vec3(1.0, 1.0, 0.0), vec3(0.0, 1.0, 0.0), vec3(0.0, 1.0, 0.0), vec3(0.0, 1.0, 1.0), vec3(0.0, 0.0, 1.0), vec3(0.0, 0.0, 1.0), vec3(0.0, 0.0, 1.0)));

struct UBO
{
    vec4 OutputSize;
    vec4 SourceSize;
};



struct Push
{
    uint FrameCount;
    float CRTgamma;
    float monitorgamma;
    float d;
    float R;
    float cornersize;
    float cornersmooth;
    float overscan_x;
    float overscan_y;
    float mask_type;
    float DOTMASK;
    float DOTMASK_brightboost;
    float scanline_weight;
    float CURVATURE;
    float interlace_detect;
    float lum;
    float invert_aspect;
    float vertical_scanlines;
};



layout(binding = 2) uniform sampler2D Texture;

layout(location = 1) in vec2 RA_VARYING_1;
layout(location = 2) in vec2 RA_VARYING_2;
layout(location = 3) in vec3 RA_VARYING_3;
layout(location = 0) in vec2 RA_VARYING_0;
layout(location = 4) in vec2 RA_VARYING_4;
layout(location = 7) in vec2 RA_VARYING_7;
layout(location = 5) in vec2 RA_VARYING_5;
layout(location = 0) out vec4 FragColor;

void main()
{
    vec2 _120 = vec2(((invert_aspect) > 0.5) ? 1.0 : 0.75);
    vec2 _4636;
    if ((CURVATURE) > 0.5)
    {
        vec2 _2213 = (((RA_VARYING_0 - vec2(0.5)) * _120) * RA_VARYING_3.z) + RA_VARYING_3.xy;
        float _2331 = (d) * (d);
        float _2332 = dot(_2213, _2213) + _2331;
        float _4631;
        float _4633;
        if ((vertical_scanlines) < 0.5)
        {
            _4633 = _2331 + ((((2.0 * (R)) * (d)) * RA_VARYING_2.x) * RA_VARYING_2.y);
            _4631 = 2.0 * (((R) * (dot(_2213, RA_VARYING_1) - (((d) * RA_VARYING_2.x) * RA_VARYING_2.y))) - _2331);
        }
        else
        {
            _4633 = _2331 + ((((2.0 * (R)) * (d)) * RA_VARYING_2.y) * RA_VARYING_2.x);
            _4631 = 2.0 * (((R) * (dot(_2213, RA_VARYING_1) - (((d) * RA_VARYING_2.y) * RA_VARYING_2.x))) - _2331);
        }
        vec2 _2261 = ((vec2(((-_4631) - sqrt((_4631 * _4631) - ((4.0 * _2332) * _4633))) / (2.0 * _2332)) * _2213) - (vec2(-(R)) * RA_VARYING_1)) / vec2((R));
        vec2 _2264 = _2261 / RA_VARYING_2;
        vec2 _2267 = RA_VARYING_1 / RA_VARYING_2;
        float _2271 = dot(_2267, _2267) + 1.0;
        float _2274 = dot(_2264, _2267);
        float _2294 = ((_2274 * 2.0) + sqrt((4.0 * (_2274 * _2274)) - ((4.0 * _2271) * (dot(_2264, _2264) - 1.0)))) / (2.0 * _2271);
        float _2308 = max(abs((R) * acos(_2294)), 9.9999997473787516355514526367188e-06);
        _4636 = ((((((_2261 - (RA_VARYING_1 * _2294)) / RA_VARYING_2) * _2308) / vec2(sin(_2308 / (R)))) / vec2((overscan_x) * 0.00999999977648258209228515625, (overscan_y) * 0.00999999977648258209228515625)) / _120) + vec2(0.5);
    }
    else
    {
        _4636 = RA_VARYING_0;
    }
    bool _2472;
    float _4638;
    do
    {
        vec2 _2450 = (_4636 - vec2(0.5)) * vec2((overscan_x) * 0.00999999977648258209228515625, (overscan_y) * 0.00999999977648258209228515625);
        vec2 _2460 = vec2((cornersize));
        vec2 _2465 = _2460 - min(min(_2450 + vec2(0.5), vec2(0.5) - _2450) * _120, _2460);
        float _2469 = sqrt(dot(_2465, _2465));
        _2472 = (vertical_scanlines) < 0.5;
        if (_2472)
        {
            _4638 = clamp(((cornersize) - _2469) * (cornersmooth), 0.0, 1.0);
            break;
        }
        else
        {
            _4638 = clamp(((cornersize) - _2469) * (cornersmooth), 0.0, 1.0);
            break;
        }
        break; // unreachable workaround
    } while(false);
    vec2 _4645;
    if (_2472)
    {
        float _4640;
        if ((RA_VARYING_4.y * (interlace_detect)) > 1.5)
        {
            _4640 = mod(float((uint(FrameCount))), 2.0);
        }
        else
        {
            _4640 = 0.0;
        }
        _4645 = vec2(0.0, _4640);
    }
    else
    {
        float _4639;
        if ((RA_VARYING_4.x * (interlace_detect)) > 1.5)
        {
            _4639 = mod(float((uint(FrameCount))), 2.0);
        }
        else
        {
            _4639 = 0.0;
        }
        _4645 = vec2(_4639, 0.0);
    }
    vec2 _1503 = (((_4636 * RA_VARYING_7) - vec2(0.5)) + _4645) / RA_VARYING_4;
    vec2 _1506 = fract(_1503);
    vec2 _1515 = (((floor(_1503) * RA_VARYING_4) + vec2(0.5)) - _4645) / RA_VARYING_7;
    vec4 _4646;
    if (_2472)
    {
        float _1524 = _1506.x;
        _4646 = vec4(1.0 + _1524, _1524, 1.0 - _1524, 2.0 - _1524) * 3.1415927410125732421875;
    }
    else
    {
        float _1538 = _1506.y;
        _4646 = vec4(1.0 + _1538, _1538, 1.0 - _1538, 2.0 - _1538) * 3.1415927410125732421875;
    }
    vec4 _1553 = max(abs(_4646), vec4(9.9999997473787516355514526367188e-06));
    vec4 _1565 = ((sin(_1553) * 2.0) * sin(_1553 * vec4(0.5))) / (_1553 * _1553);
    vec4 _1571 = _1565 / vec4(dot(_1565, vec4(1.0)));
    vec4 _4648;
    vec4 _4649;
    if (_2472)
    {
        float _1587 = -RA_VARYING_5.x;
        vec4 _1593 = vec4((CRTgamma));
        float _1617 = 2.0 * RA_VARYING_5.x;
        _4649 = clamp(mat4(pow(texture(Texture, _1515 + vec2(_1587, RA_VARYING_5.y)), _1593), pow(texture(Texture, _1515 + vec2(0.0, RA_VARYING_5.y)), _1593), pow(texture(Texture, _1515 + RA_VARYING_5), _1593), pow(texture(Texture, _1515 + vec2(_1617, RA_VARYING_5.y)), _1593)) * _1571, vec4(0.0), vec4(1.0));
        _4648 = clamp(mat4(pow(texture(Texture, _1515 + vec2(_1587, 0.0)), _1593), pow(texture(Texture, _1515), _1593), pow(texture(Texture, _1515 + vec2(RA_VARYING_5.x, 0.0)), _1593), pow(texture(Texture, _1515 + vec2(_1617, 0.0)), _1593)) * _1571, vec4(0.0), vec4(1.0));
    }
    else
    {
        float _1731 = -RA_VARYING_5.y;
        vec4 _1737 = vec4((CRTgamma));
        float _1761 = 2.0 * RA_VARYING_5.y;
        _4649 = clamp(mat4(pow(texture(Texture, _1515 + vec2(RA_VARYING_5.x, _1731)), _1737), pow(texture(Texture, _1515 + vec2(RA_VARYING_5.x, 0.0)), _1737), pow(texture(Texture, _1515 + RA_VARYING_5), _1737), pow(texture(Texture, _1515 + vec2(RA_VARYING_5.x, _1761)), _1737)) * _1571, vec4(0.0), vec4(1.0));
        _4648 = clamp(mat4(pow(texture(Texture, _1515 + vec2(0.0, _1731)), _1737), pow(texture(Texture, _1515), _1737), pow(texture(Texture, _1515 + vec2(0.0, RA_VARYING_5.y)), _1737), pow(texture(Texture, _1515 + vec2(0.0, _1761)), _1737)) * _1571, vec4(0.0), vec4(1.0));
    }
    vec4 _4651;
    vec4 _4653;
    if (_2472)
    {
        float _1877 = _1506.y;
        vec4 _2502 = vec4(2.0) + (pow(_4648, vec4(4.0)) * 2.0);
        float _2510 = (lum) + 1.39999997615814208984375;
        vec4 _2514 = inversesqrt(_2502 * 0.5);
        vec4 _2524 = vec4(0.60000002384185791015625) + (_2502 * 0.20000000298023223876953125);
        vec4 _2534 = vec4(2.0) + (pow(_4649, vec4(4.0)) * 2.0);
        vec4 _2546 = inversesqrt(_2534 * 0.5);
        vec4 _2556 = vec4(0.60000002384185791015625) + (_2534 * 0.20000000298023223876953125);
        float _1892 = fwidth(_1503.y);
        float _1897 = _1877 + (0.3333333432674407958984375 * _1892);
        float _1925 = _1897 - (0.666666686534881591796875 * _1892);
        _4653 = vec4(0.3333333432674407958984375) * ((((exp(-pow(vec4((1.0 - _1877) / (scanline_weight)) * _2546, _2534)) * _2510) / _2556) + ((exp(-pow(vec4(abs(1.0 - _1897) / (scanline_weight)) * _2546, _2534)) * _2510) / _2556)) + ((exp(-pow(vec4(abs(1.0 - _1925) / (scanline_weight)) * _2546, _2534)) * _2510) / _2556));
        _4651 = vec4(0.3333333432674407958984375) * ((((exp(-pow(vec4(_1877 / (scanline_weight)) * _2514, _2502)) * _2510) / _2524) + ((exp(-pow(vec4(_1897 / (scanline_weight)) * _2514, _2502)) * _2510) / _2524)) + ((exp(-pow(vec4(abs(_1925) / (scanline_weight)) * _2514, _2502)) * _2510) / _2524));
    }
    else
    {
        float _1953 = _1506.x;
        vec4 _2694 = vec4(2.0) + (pow(_4648, vec4(4.0)) * 2.0);
        float _2702 = (lum) + 1.39999997615814208984375;
        vec4 _2706 = inversesqrt(_2694 * 0.5);
        vec4 _2716 = vec4(0.60000002384185791015625) + (_2694 * 0.20000000298023223876953125);
        vec4 _2726 = vec4(2.0) + (pow(_4649, vec4(4.0)) * 2.0);
        vec4 _2738 = inversesqrt(_2726 * 0.5);
        vec4 _2748 = vec4(0.60000002384185791015625) + (_2726 * 0.20000000298023223876953125);
        float _1967 = fwidth(_1503.x);
        float _1972 = _1953 + (0.3333333432674407958984375 * _1967);
        float _2000 = _1972 - (0.666666686534881591796875 * _1967);
        _4653 = vec4(0.3333333432674407958984375) * ((((exp(-pow(vec4((1.0 - _1953) / (scanline_weight)) * _2738, _2726)) * _2702) / _2748) + ((exp(-pow(vec4(abs(1.0 - _1972) / (scanline_weight)) * _2738, _2726)) * _2702) / _2748)) + ((exp(-pow(vec4(abs(1.0 - _2000) / (scanline_weight)) * _2738, _2726)) * _2702) / _2748));
        _4651 = vec4(0.3333333432674407958984375) * ((((exp(-pow(vec4(_1953 / (scanline_weight)) * _2706, _2694)) * _2702) / _2716) + ((exp(-pow(vec4(_1972 / (scanline_weight)) * _2706, _2694)) * _2702) / _2716)) + ((exp(-pow(vec4(abs(_2000) / (scanline_weight)) * _2706, _2694)) * _2702) / _2716));
    }
    vec3 _2036 = ((_4648 * _4651) + (_4649 * _4653)).xyz * vec3(_4638);
    float _4664;
    vec4 _4868;
    if (_2472)
    {
        vec2 _2061 = RA_VARYING_0 * (vec4(OutputSize, 1.0 / OutputSize)).xy;
        int _2064 = int((mask_type));
        vec3 _4662;
        float _4663;
        do
        {
            float _2948 = _2061.x;
            vec3 _2951 = vec3(floor(mod(_2948, 2.0)));
            vec3 _2952 = mix(vec3(1.0, 0.0, 1.0), vec3(0.0, 1.0, 0.0), _2951);
            if (_2064 == 0)
            {
                _4663 = 1.0;
                _4662 = vec3(1.0);
                break;
            }
            else
            {
                if (_2064 == 1)
                {
                    _4663 = 0.5;
                    _4662 = _2952;
                    break;
                }
                else
                {
                    if (_2064 == 2)
                    {
                        _4663 = 0.5;
                        _4662 = mix(_2952, mix(vec3(0.0, 1.0, 0.0), vec3(1.0, 0.0, 1.0), _2951), vec3(floor(mod(_2061.y, 2.0))));
                        break;
                    }
                    else
                    {
                        if (_2064 == 3)
                        {
                            _4663 = 0.3333333432674407958984375;
                            _4662 = _4686[int(floor(mod(_2061.y, 3.0)))][int(floor(mod(_2948, 4.0)))];
                            break;
                        }
                        else
                        {
                            if (_2064 == 4)
                            {
                                _4663 = 0.5;
                                _4662 = mix(vec3(1.0, 1.0, 0.0), vec3(0.0, 0.0, 1.0), _2951);
                                break;
                            }
                            else
                            {
                                if (_2064 == 5)
                                {
                                    _4663 = 0.5;
                                    _4662 = mix(mix(vec3(1.0, 1.0, 0.0), vec3(0.0, 0.0, 1.0), _2951), mix(vec3(0.0, 0.0, 1.0), vec3(1.0, 1.0, 0.0), _2951), vec3(floor(mod(_2061.y, 2.0))));
                                    break;
                                }
                                else
                                {
                                    if (_2064 == 6)
                                    {
                                        _4663 = 0.25;
                                        _4662 = _4687[int(floor(mod(_2948, 4.0)))];
                                        break;
                                    }
                                    else
                                    {
                                        if (_2064 == 7)
                                        {
                                            _4663 = 0.4000000059604644775390625;
                                            _4662 = _4688[int(floor(mod(_2948, 5.0)))];
                                            break;
                                        }
                                        else
                                        {
                                            if (_2064 == 8)
                                            {
                                                _4663 = 0.4444444477558135986328125;
                                                _4662 = _4689[int(floor(mod(_2948, 7.0)))];
                                                break;
                                            }
                                            else
                                            {
                                                if (_2064 == 9)
                                                {
                                                    _4663 = 0.5;
                                                    _4662 = _4690[int(floor(mod(_2948, 4.0)))];
                                                    break;
                                                }
                                                else
                                                {
                                                    if (_2064 == 10)
                                                    {
                                                        _4663 = 0.5;
                                                        _4662 = _4691[int(floor(mod(_2948, 4.0)))];
                                                        break;
                                                    }
                                                    else
                                                    {
                                                        if (_2064 == 11)
                                                        {
                                                            _4663 = 0.25;
                                                            _4662 = _4693[int(floor(mod(_2061.y, 2.0)))][int(floor(mod(_2948, 4.0)))];
                                                            break;
                                                        }
                                                        else
                                                        {
                                                            if (_2064 == 12)
                                                            {
                                                                _4663 = 0.5;
                                                                _4662 = _4695[int(floor(mod(_2061.y, 2.0)))][int(floor(mod(_2948, 4.0)))];
                                                                break;
                                                            }
                                                            else
                                                            {
                                                                if (_2064 == 13)
                                                                {
                                                                    _4663 = 0.5;
                                                                    _4662 = _4696[int(floor(mod(_2061.y, 4.0)))][int(floor(mod(_2948, 4.0)))];
                                                                    break;
                                                                }
                                                                else
                                                                {
                                                                    if (_2064 == 14)
                                                                    {
                                                                        _4663 = 0.22222222387790679931640625;
                                                                        _4662 = _4700[int(floor(mod(_2061.y, 3.0)))][int(floor(mod(_2948, 6.0)))];
                                                                        break;
                                                                    }
                                                                    else
                                                                    {
                                                                        if (_2064 == 15)
                                                                        {
                                                                            _4663 = 0.375;
                                                                            _4662 = _4704[int(floor(mod(_2061.y, 4.0)))][int(floor(mod(_2948, 8.0)))];
                                                                            break;
                                                                        }
                                                                        else
                                                                        {
                                                                            if (_2064 == 16)
                                                                            {
                                                                                _4663 = 0.388888895511627197265625;
                                                                                _4662 = _4708[int(floor(mod(_2061.y, 3.0)))][int(floor(mod(_2948, 4.0)))];
                                                                                break;
                                                                            }
                                                                            else
                                                                            {
                                                                                if (_2064 == 17)
                                                                                {
                                                                                    _4663 = 0.300000011920928955078125;
                                                                                    _4662 = _4712[int(floor(mod(_2061.y, 4.0)))][int(floor(mod(_2948, 10.0)))];
                                                                                    break;
                                                                                }
                                                                                else
                                                                                {
                                                                                    if (_2064 == 18)
                                                                                    {
                                                                                        _4663 = 0.300000011920928955078125;
                                                                                        _4662 = _4716[int(floor(mod(_2061.y, 4.0)))][int(floor(mod(_2948, 10.0)))];
                                                                                        break;
                                                                                    }
                                                                                    else
                                                                                    {
                                                                                        if (_2064 == 19)
                                                                                        {
                                                                                            _4663 = 0.3531745970249176025390625;
                                                                                            _4662 = _4720[int(floor(mod(_2061.y, 6.0)))][int(floor(mod(_2948, 14.0)))];
                                                                                            break;
                                                                                        }
                                                                                        else
                                                                                        {
                                                                                            if (_2064 == 20)
                                                                                            {
                                                                                                _4663 = 0.375;
                                                                                                _4662 = _4724[int(floor(mod(_2061.y, 4.0)))][int(floor(mod(_2948, 4.0)))];
                                                                                                break;
                                                                                            }
                                                                                            else
                                                                                            {
                                                                                                if (_2064 == 21)
                                                                                                {
                                                                                                    _4663 = 0.21875;
                                                                                                    _4662 = _4728[int(floor(mod(_2061.y, 4.0)))][int(floor(mod(_2948, 8.0)))];
                                                                                                    break;
                                                                                                }
                                                                                                else
                                                                                                {
                                                                                                    if (_2064 == 22)
                                                                                                    {
                                                                                                        _4663 = 0.666666686534881591796875;
                                                                                                        _4662 = _4729[int(floor(mod(_2948, 3.0)))];
                                                                                                        break;
                                                                                                    }
                                                                                                    else
                                                                                                    {
                                                                                                        if (_2064 == 23)
                                                                                                        {
                                                                                                            _4663 = 0.5;
                                                                                                            _4662 = _4730[int(floor(mod(_2948, 4.0)))];
                                                                                                            break;
                                                                                                        }
                                                                                                        else
                                                                                                        {
                                                                                                            if (_2064 == 24)
                                                                                                            {
                                                                                                                _4663 = 0.4000000059604644775390625;
                                                                                                                _4662 = _4733[int(floor(mod(_2061.y, 6.0)))][int(floor(mod(_2948, 10.0)))];
                                                                                                                break;
                                                                                                            }
                                                                                                            else
                                                                                                            {
                                                                                                                _4663 = 1.0;
                                                                                                                _4662 = vec3(1.0);
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
        _4868 = vec4(_4662, 1.0);
        _4664 = _4663;
    }
    else
    {
        vec2 _2082 = RA_VARYING_0.yx * (vec4(OutputSize, 1.0 / OutputSize)).yx;
        int _2085 = int((mask_type));
        vec3 _4660;
        float _4661;
        do
        {
            float _3823 = _2082.x;
            vec3 _3826 = vec3(floor(mod(_3823, 2.0)));
            vec3 _3827 = mix(vec3(1.0, 0.0, 1.0), vec3(0.0, 1.0, 0.0), _3826);
            if (_2085 == 0)
            {
                _4661 = 1.0;
                _4660 = vec3(1.0);
                break;
            }
            else
            {
                if (_2085 == 1)
                {
                    _4661 = 0.5;
                    _4660 = _3827;
                    break;
                }
                else
                {
                    if (_2085 == 2)
                    {
                        _4661 = 0.5;
                        _4660 = mix(_3827, mix(vec3(0.0, 1.0, 0.0), vec3(1.0, 0.0, 1.0), _3826), vec3(floor(mod(_2082.y, 2.0))));
                        break;
                    }
                    else
                    {
                        if (_2085 == 3)
                        {
                            _4661 = 0.3333333432674407958984375;
                            _4660 = _4686[int(floor(mod(_2082.y, 3.0)))][int(floor(mod(_3823, 4.0)))];
                            break;
                        }
                        else
                        {
                            if (_2085 == 4)
                            {
                                _4661 = 0.5;
                                _4660 = mix(vec3(1.0, 1.0, 0.0), vec3(0.0, 0.0, 1.0), _3826);
                                break;
                            }
                            else
                            {
                                if (_2085 == 5)
                                {
                                    _4661 = 0.5;
                                    _4660 = mix(mix(vec3(1.0, 1.0, 0.0), vec3(0.0, 0.0, 1.0), _3826), mix(vec3(0.0, 0.0, 1.0), vec3(1.0, 1.0, 0.0), _3826), vec3(floor(mod(_2082.y, 2.0))));
                                    break;
                                }
                                else
                                {
                                    if (_2085 == 6)
                                    {
                                        _4661 = 0.25;
                                        _4660 = _4687[int(floor(mod(_3823, 4.0)))];
                                        break;
                                    }
                                    else
                                    {
                                        if (_2085 == 7)
                                        {
                                            _4661 = 0.4000000059604644775390625;
                                            _4660 = _4688[int(floor(mod(_3823, 5.0)))];
                                            break;
                                        }
                                        else
                                        {
                                            if (_2085 == 8)
                                            {
                                                _4661 = 0.4444444477558135986328125;
                                                _4660 = _4689[int(floor(mod(_3823, 7.0)))];
                                                break;
                                            }
                                            else
                                            {
                                                if (_2085 == 9)
                                                {
                                                    _4661 = 0.5;
                                                    _4660 = _4690[int(floor(mod(_3823, 4.0)))];
                                                    break;
                                                }
                                                else
                                                {
                                                    if (_2085 == 10)
                                                    {
                                                        _4661 = 0.5;
                                                        _4660 = _4691[int(floor(mod(_3823, 4.0)))];
                                                        break;
                                                    }
                                                    else
                                                    {
                                                        if (_2085 == 11)
                                                        {
                                                            _4661 = 0.25;
                                                            _4660 = _4693[int(floor(mod(_2082.y, 2.0)))][int(floor(mod(_3823, 4.0)))];
                                                            break;
                                                        }
                                                        else
                                                        {
                                                            if (_2085 == 12)
                                                            {
                                                                _4661 = 0.5;
                                                                _4660 = _4695[int(floor(mod(_2082.y, 2.0)))][int(floor(mod(_3823, 4.0)))];
                                                                break;
                                                            }
                                                            else
                                                            {
                                                                if (_2085 == 13)
                                                                {
                                                                    _4661 = 0.5;
                                                                    _4660 = _4696[int(floor(mod(_2082.y, 4.0)))][int(floor(mod(_3823, 4.0)))];
                                                                    break;
                                                                }
                                                                else
                                                                {
                                                                    if (_2085 == 14)
                                                                    {
                                                                        _4661 = 0.22222222387790679931640625;
                                                                        _4660 = _4700[int(floor(mod(_2082.y, 3.0)))][int(floor(mod(_3823, 6.0)))];
                                                                        break;
                                                                    }
                                                                    else
                                                                    {
                                                                        if (_2085 == 15)
                                                                        {
                                                                            _4661 = 0.375;
                                                                            _4660 = _4704[int(floor(mod(_2082.y, 4.0)))][int(floor(mod(_3823, 8.0)))];
                                                                            break;
                                                                        }
                                                                        else
                                                                        {
                                                                            if (_2085 == 16)
                                                                            {
                                                                                _4661 = 0.388888895511627197265625;
                                                                                _4660 = _4708[int(floor(mod(_2082.y, 3.0)))][int(floor(mod(_3823, 4.0)))];
                                                                                break;
                                                                            }
                                                                            else
                                                                            {
                                                                                if (_2085 == 17)
                                                                                {
                                                                                    _4661 = 0.300000011920928955078125;
                                                                                    _4660 = _4712[int(floor(mod(_2082.y, 4.0)))][int(floor(mod(_3823, 10.0)))];
                                                                                    break;
                                                                                }
                                                                                else
                                                                                {
                                                                                    if (_2085 == 18)
                                                                                    {
                                                                                        _4661 = 0.300000011920928955078125;
                                                                                        _4660 = _4716[int(floor(mod(_2082.y, 4.0)))][int(floor(mod(_3823, 10.0)))];
                                                                                        break;
                                                                                    }
                                                                                    else
                                                                                    {
                                                                                        if (_2085 == 19)
                                                                                        {
                                                                                            _4661 = 0.3531745970249176025390625;
                                                                                            _4660 = _4720[int(floor(mod(_2082.y, 6.0)))][int(floor(mod(_3823, 14.0)))];
                                                                                            break;
                                                                                        }
                                                                                        else
                                                                                        {
                                                                                            if (_2085 == 20)
                                                                                            {
                                                                                                _4661 = 0.375;
                                                                                                _4660 = _4724[int(floor(mod(_2082.y, 4.0)))][int(floor(mod(_3823, 4.0)))];
                                                                                                break;
                                                                                            }
                                                                                            else
                                                                                            {
                                                                                                if (_2085 == 21)
                                                                                                {
                                                                                                    _4661 = 0.21875;
                                                                                                    _4660 = _4728[int(floor(mod(_2082.y, 4.0)))][int(floor(mod(_3823, 8.0)))];
                                                                                                    break;
                                                                                                }
                                                                                                else
                                                                                                {
                                                                                                    if (_2085 == 22)
                                                                                                    {
                                                                                                        _4661 = 0.666666686534881591796875;
                                                                                                        _4660 = _4729[int(floor(mod(_3823, 3.0)))];
                                                                                                        break;
                                                                                                    }
                                                                                                    else
                                                                                                    {
                                                                                                        if (_2085 == 23)
                                                                                                        {
                                                                                                            _4661 = 0.5;
                                                                                                            _4660 = _4730[int(floor(mod(_3823, 4.0)))];
                                                                                                            break;
                                                                                                        }
                                                                                                        else
                                                                                                        {
                                                                                                            if (_2085 == 24)
                                                                                                            {
                                                                                                                _4661 = 0.4000000059604644775390625;
                                                                                                                _4660 = _4733[int(floor(mod(_2082.y, 6.0)))][int(floor(mod(_3823, 10.0)))];
                                                                                                                break;
                                                                                                            }
                                                                                                            else
                                                                                                            {
                                                                                                                _4661 = 1.0;
                                                                                                                _4660 = vec3(1.0);
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
        _4868 = vec4(_4660, 1.0);
        _4664 = _4661;
    }
    vec4 _4857 = _4868;
    _4857.w = _4664;
    vec2 _2112 = (vec4(OutputSize, 1.0 / OutputSize)).xy * (vec4(TextureSize, 1.0 / TextureSize)).zw;
    float _2123 = (255.0 - (255.0 * _4664)) / (_2112.x * _2112.y);
    vec3 _2151 = _2036 * (vec3(1.0 - (DOTMASK)) + (vec3((DOTMASK) * (DOTMASK_brightboost)) * _2036));
    float _2154 = 1.0 / _2123;
    FragColor = vec4(pow(mix(_2151, (vec3(_2154 * mix(1.0 - ((DOTMASK) * (1.0 - (DOTMASK_brightboost))), 1.0, _2123)) * _2036) - (vec3(_2154 - 1.0) * _2151), _4857.xyz), vec3(1.0 / (monitorgamma))), 1.0);
}


#endif
