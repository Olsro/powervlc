// Generated from crt/shaders/zfast_crt/zfast_crt_composite.slang. See slang/upstream for licence/source.
#version 130
#pragma parameter WARP "Curvature" 0.03 0.0 0.3 0.01
#pragma parameter BLURSCALEX "Blur Amount X-Axis" 0.5 0.0 1.0 0.05
#pragma parameter sharp "NTSC Sharpness" 5.0 2.0 10.0 0.1
#pragma parameter chroma_gain "NTSC Chroma Gain" 1.0 0.0 3.0 0.05
#pragma parameter LOWLUMSCAN "Scanline Darkness - Low" 6.0 0.0 10.0 0.5
#pragma parameter HILUMSCAN "Scanline Darkness - High" 8.0 0.0 50.0 1.0
#pragma parameter BRIGHTBOOST "Dark Pixel Brightness Boost" 1.25 0.5 1.5 0.05
#pragma parameter MASK_DARK "Mask Effect Amount" 0.25 0.0 1.0 0.05
#pragma parameter MASK_FADE "Mask/Scanline Fade" 0.8 0.0 1.0 0.05
#pragma parameter FINEMASK "Mask Fine/Coarse" 0.0 0.0 1.0 1.0
#ifdef VERTEX

uniform float MASK_FADE;
uniform mat4 MVPMatrix;
uniform vec2 OutputSize;
uniform vec2 TextureSize;
struct UBO
{
    mat4 MVP;
};



struct Push
{
    vec4 SourceSize;
    vec4 OutputSize;
    float MASK_FADE;
};



in vec4 VertexCoord;
out vec2 RA_VARYING_0;
in vec2 TexCoord;
out float RA_VARYING_1;
out vec2 RA_VARYING_2;
out vec2 RA_VARYING_3;

void main()
{
    gl_Position = (MVPMatrix) * VertexCoord;
    RA_VARYING_0 = TexCoord;
    RA_VARYING_1 = 0.33329999446868896484375 * (MASK_FADE);
    RA_VARYING_2 = vec2(1.0) / (vec4(TextureSize, 1.0 / TextureSize)).xy;
    RA_VARYING_3 = RA_VARYING_0 * (vec4(OutputSize, 1.0 / OutputSize)).xy;
}


#endif
#ifdef FRAGMENT

uniform float BLURSCALEX;
uniform float BRIGHTBOOST;
uniform float FINEMASK;
uniform int FrameCount;
uniform float HILUMSCAN;
uniform float LOWLUMSCAN;
uniform float MASK_DARK;
uniform vec2 OrigTextureSize;
uniform vec2 TextureSize;
uniform float WARP;
uniform float chroma_gain;
uniform float sharp;
struct Push
{
    vec4 SourceSize;
    vec4 OriginalSize;
    uint FrameCount;
    float BLURSCALEX;
    float LOWLUMSCAN;
    float HILUMSCAN;
    float BRIGHTBOOST;
    float MASK_DARK;
    float FINEMASK;
    float WARP;
    float sharp;
    float chroma_gain;
};



uniform sampler2D Texture;

in vec2 RA_VARYING_2;
in vec2 RA_VARYING_0;
in vec2 RA_VARYING_3;
in float RA_VARYING_1;
out vec4 FragColor;

void main()
{
    vec2 _177 = vec2(RA_VARYING_2.x, 0.0);
    bool _184 = (vec4(OrigTextureSize, 1.0 / OrigTextureSize)).y > 300.0;
    vec2 _826;
    if (_184)
    {
        _826 = RA_VARYING_0 + (vec2(0.0, (vec4(TextureSize, 1.0 / TextureSize)).w) * mod(float((uint(FrameCount))), 2.0));
    }
    else
    {
        _826 = RA_VARYING_0;
    }
    vec2 _530 = (_826 * 2.0) - vec2(1.0);
    float _532 = _530.y;
    float _541 = _530.x;
    vec2 _554 = (_530 * vec2(1.0 + ((_532 * _532) * (WARP)), 1.0 + (((_541 * _541) * (WARP)) * 1.5))) * 0.5;
    vec2 _556 = _554 + vec2(0.5);
    vec2 _215 = min(_556, vec2(0.5) - _554);
    float _219 = 9.9999997473787516355514526367188e-06 / _215.x;
    vec2 _227 = _556 * (vec4(TextureSize, 1.0 / TextureSize)).xy;
    vec2 _232 = floor(_227) + vec2(0.5);
    vec2 _236 = _227 - _232;
    vec2 _247 = (_232 + (((_236 * 4.0) * _236) * _236)) * RA_VARYING_2;
    _247.x = mix(_247.x, _556.x, (BLURSCALEX));
    float _827;
    if (_184)
    {
        float _269 = (_556.y * (vec4(TextureSize, 1.0 / TextureSize)).y) * 0.5;
        _827 = _269 - (floor(_269) + 0.5);
    }
    else
    {
        _827 = _236.y;
    }
    float _286 = _827 * _827;
    float _290 = _286 * _286;
    float _833;
    if ((FINEMASK) == 0.0)
    {
        _833 = 1.0 + (float(fract(floor(RA_VARYING_3.x) * (-0.4999000132083892822265625)) < 0.5) * (-(MASK_DARK)));
    }
    else
    {
        _833 = 1.0 + (float(fract(floor(RA_VARYING_3.x) * (-0.33329999446868896484375)) <= 0.3333300054073333740234375) * (-(MASK_DARK)));
    }
    vec4 _339 = texture(Texture, _247);
    float _568 = _339.x;
    float _570 = _339.y;
    float _572 = _339.z;
    vec4 _348 = texture(Texture, _247 - _177);
    float _614 = _348.x;
    float _616 = _348.y;
    float _618 = _348.z;
    vec2 _356 = _177 * 2.0;
    vec4 _358 = texture(Texture, _247 - _356);
    vec4 _367 = texture(Texture, _247 + _177);
    float _706 = _367.x;
    float _708 = _367.y;
    float _710 = _367.z;
    vec4 _377 = texture(Texture, _247 + _356);
    float _398 = ((((sharp) * (((0.2989999949932098388671875 * _568) + (0.58700001239776611328125 * _570)) + (0.114000000059604644775390625 * _572))) + (((0.2989999949932098388671875 * _614) + (0.58700001239776611328125 * _616)) + (0.114000000059604644775390625 * _618))) + (((0.2989999949932098388671875 * _706) + (0.58700001239776611328125 * _708)) + (0.114000000059604644775390625 * _710))) * (1.0 / ((sharp) + 2.0));
    float _437 = (((((0.596000015735626220703125 * _568) + (((-0.273999989032745361328125) * _570) - (0.3219999969005584716796875 * _572))) + ((0.596000015735626220703125 * _614) + (((-0.273999989032745361328125) * _616) - (0.3219999969005584716796875 * _618)))) + ((0.596000015735626220703125 * _706) + (((-0.273999989032745361328125) * _708) - (0.3219999969005584716796875 * _710)))) * 0.3999600112438201904296875) * (chroma_gain);
    float _441 = (((((((0.2109999954700469970703125 * _568) + (((-0.5230000019073486328125) * _570) + (0.3120000064373016357421875 * _572))) + ((0.2109999954700469970703125 * _614) + (((-0.5230000019073486328125) * _616) + (0.3120000064373016357421875 * _618)))) + ((0.2109999954700469970703125 * _706) + (((-0.5230000019073486328125) * _708) + (0.3120000064373016357421875 * _710)))) + ((0.2109999954700469970703125 * _358.x) + (((-0.5230000019073486328125) * _358.y) + (0.3120000064373016357421875 * _358.z)))) + ((0.2109999954700469970703125 * _377.x) + (((-0.5230000019073486328125) * _377.y) + (0.3120000064373016357421875 * _377.z)))) * 0.16000001132488250732421875) * (chroma_gain);
    vec3 _825 = vec3((_398 + (0.95599997043609619140625 * _437)) + (0.620999991893768310546875 * _441), (_398 - (0.272000014781951904296875 * _437)) - (0.647000014781951904296875 * _441), (_398 - (1.10599994659423828125 * _437)) + (1.70299994945526123046875 * _441));
    vec3 _483 = _825 * mix(((BRIGHTBOOST) - ((LOWLUMSCAN) * (_286 - (2.0499999523162841796875 * _290)))) * _833, 1.0 - ((HILUMSCAN) * (_290 - ((2.7999999523162841796875 * _290) * _286))), dot(_825, vec3(RA_VARYING_1)));
    bool _486 = (WARP) != 0.0;
    bool _494;
    if (_486)
    {
        _494 = _215.y < _219;
    }
    else
    {
        _494 = _486;
    }
    bool _507;
    if (!_494)
    {
        bool _506;
        if (_486)
        {
            _506 = _219 < 9.9999997473787516355514526367188e-06;
        }
        else
        {
            _506 = _486;
        }
        _507 = _506;
    }
    else
    {
        _507 = _494;
    }
    bvec3 _842 = bvec3(_507);
    vec3 _843 = vec3(_842.x ? vec3(0.0).x : _483.x, _842.y ? vec3(0.0).y : _483.y, _842.z ? vec3(0.0).z : _483.z);
    FragColor.x = _843.x;
    FragColor.y = _843.y;
    FragColor.z = _843.z;
}


#endif
