// Generated from crt/shaders/crt-easymode-halation/crt-easymode-halation.slang. See slang/upstream for licence/source.
#version 130
#pragma parameter GAMMA_OUTPUT "Gamma Output" 2.2 0.1 5.0 0.01
#pragma parameter SHARPNESS_H "Sharpness Horizontal" 0.6 0.0 1.0 0.05
#pragma parameter SHARPNESS_V "Sharpness Vertical" 1.0 0.0 1.0 0.05
#pragma parameter MASK_TYPE "Mask Type" 4.0 0.0 7.0 1.0
#pragma parameter MASK_STRENGTH_MIN "Mask Strength Min." 0.2 0.0 0.5 0.01
#pragma parameter MASK_STRENGTH_MAX "Mask Strength Max." 0.2 0.0 0.5 0.01
#pragma parameter MASK_SIZE "Mask Size" 1.0 1.0 100.0 1.0
#pragma parameter SCANLINE_STRENGTH_MIN "Scanline Strength Min." 0.2 0.0 1.0 0.05
#pragma parameter SCANLINE_STRENGTH_MAX "Scanline Strength Max." 0.4 0.0 1.0 0.05
#pragma parameter SCANLINE_BEAM_MIN "Scanline Beam Min." 1.0 0.25 5.0 0.05
#pragma parameter SCANLINE_BEAM_MAX "Scanline Beam Max." 1.0 0.25 5.0 0.05
#pragma parameter GEOM_CURVATURE "Geom Curvature" 0.0 0.0 0.1 0.01
#pragma parameter GEOM_WARP "Geom Warp" 0.0 0.0 0.1 0.01
#pragma parameter GEOM_CORNER_SIZE "Geom Corner Size" 0.0 0.0 0.1 0.01
#pragma parameter GEOM_CORNER_SMOOTH "Geom Corner Smoothness" 150.0 50.0 1000.0 25.0
#pragma parameter INTERLACING_TOGGLE "Interlacing Toggle" 1.0 0.0 1.0 1.0
#pragma parameter HALATION "Halation" 0.03 0.0 1.0 0.01
#pragma parameter DIFFUSION "Diffusion" 0.0 0.0 1.0 0.01
#pragma parameter BRIGHTNESS "Brightness" 1.0 0.0 2.0 0.05
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

uniform float BRIGHTNESS;
uniform float DIFFUSION;
uniform int FrameCount;
uniform float GAMMA_OUTPUT;
uniform float GEOM_CORNER_SIZE;
uniform float GEOM_CORNER_SMOOTH;
uniform float GEOM_CURVATURE;
uniform float GEOM_WARP;
uniform float HALATION;
uniform float INTERLACING_TOGGLE;
uniform float MASK_SIZE;
uniform float MASK_STRENGTH_MAX;
uniform float MASK_STRENGTH_MIN;
uniform float MASK_TYPE;
uniform vec2 OutputSize;
uniform float SCANLINE_BEAM_MAX;
uniform float SCANLINE_BEAM_MIN;
uniform float SCANLINE_STRENGTH_MAX;
uniform float SCANLINE_STRENGTH_MIN;
uniform float SHARPNESS_H;
uniform float SHARPNESS_V;
uniform vec2 TextureSize;
vec4 _1516;

struct UBO
{
    uint FrameCount;
};



struct Push
{
    vec4 SourceSize;
    vec4 OutputSize;
    float GAMMA_OUTPUT;
    float SHARPNESS_H;
    float SHARPNESS_V;
    float MASK_TYPE;
    float MASK_STRENGTH_MIN;
    float MASK_STRENGTH_MAX;
    float MASK_SIZE;
    float SCANLINE_STRENGTH_MIN;
    float SCANLINE_STRENGTH_MAX;
    float SCANLINE_BEAM_MIN;
    float SCANLINE_BEAM_MAX;
    float GEOM_CURVATURE;
    float GEOM_WARP;
    float GEOM_CORNER_SIZE;
    float GEOM_CORNER_SMOOTH;
    float INTERLACING_TOGGLE;
    float HALATION;
    float DIFFUSION;
    float BRIGHTNESS;
};



uniform sampler2D Pass1Texture;
uniform sampler2D Texture;

in vec2 RA_VARYING_0;
out vec4 FragColor;

void main()
{
    vec2 _246 = (vec4(TextureSize, 1.0 / TextureSize)).xy;
    bool _268 = (INTERLACING_TOGGLE) > 0.5;
    bool _275;
    if (_268)
    {
        _275 = (vec4(TextureSize, 1.0 / TextureSize)).y >= 400.0;
    }
    else
    {
        _275 = _268;
    }
    float _1344;
    vec2 _1499;
    vec2 _1501;
    if (_275)
    {
        vec2 _1439 = _246;
        _1439.y = (vec4(TextureSize, 1.0 / TextureSize)).y * 0.5;
        bool _284 = mod(float((uint(FrameCount))), 2.0) > 0.0;
        vec2 _1502;
        if (_284)
        {
            _1502 = vec2(0.5, 0.75);
        }
        else
        {
            _1502 = vec2(0.5, 0.25);
        }
        _1501 = _1502;
        _1499 = _1439;
        _1344 = _284 ? 0.5 : 0.0;
    }
    else
    {
        _1501 = vec2(0.5);
        _1499 = _246;
        _1344 = 0.0;
    }
    vec2 _299 = (RA_VARYING_0 * _1499) * (vec4(TextureSize, 1.0 / TextureSize)).zw;
    vec2 _862 = vec2((GEOM_WARP), (GEOM_WARP) * 0.75);
    vec2 _879 = (vec2(_299.yx) * 2.0) - vec2(1.0);
    vec2 _884 = _879 * _879;
    vec2 _895 = vec2((GEOM_CURVATURE), (GEOM_CURVATURE) * 0.75);
    vec2 _918 = mix(_299, (_299 + (_299 * _895)) - (_895 * vec2(0.5)), _884);
    vec2 _319 = vec2((GEOM_CORNER_SIZE));
    vec2 _932 = _319 - min(min(_918, vec2(1.0) - _918) * vec2(1.0, 0.75), _319);
    vec2 _333 = mix(_299, (_299 + (_299 * _862)) - (_862 * vec2(0.5)), _884) * (_246 / _1499);
    vec2 _338 = vec2(1.0 / _1499.x, 0.0);
    vec2 _343 = vec2(0.0, 1.0 / _1499.y);
    vec2 _349 = (_333 * _1499) - _1501;
    vec2 _356 = (floor(_349) + _1501) / _1499;
    vec2 _359 = fract(_349);
    float _369 = _359.x;
    float _957 = _369 - step(0.5, _369);
    float _972 = mix(_369, 0.5 - (sqrt(0.25 - (_957 * _957)) * sign(0.5 - _369)), (SHARPNESS_H) * (SHARPNESS_H));
    float _381 = _359.y;
    float _981 = _381 - step(0.5, _381);
    float _996 = mix(_381, 0.5 - (sqrt(0.25 - (_981 * _981)) * sign(0.5 - _381)), (SHARPNESS_V) * (SHARPNESS_V));
    vec4 _408 = max(abs(vec4(1.0 + _972, _972, 1.0 - _972, 2.0 - _972) * 3.1415927410125732421875), vec4(9.9999997473787516355514526367188e-06));
    vec4 _420 = ((sin(_408) * 2.0) * sin(_408 * vec4(0.5))) / (_408 * _408);
    vec4 _426 = _420 / vec4(dot(_420, vec4(1.0)));
    vec4 _430 = max(abs(vec4(1.0 + _996, _996, 1.0 - _996, 2.0 - _996) * 3.1415927410125732421875), vec4(9.9999997473787516355514526367188e-06));
    vec4 _442 = ((sin(_430) * 2.0) * sin(_430 * vec4(0.5))) / (_430 * _430);
    vec2 _452 = _356 - _343;
    vec4 _1006 = texture(Pass1Texture, _452);
    vec4 _1011 = texture(Pass1Texture, _452 + _338);
    vec2 _1015 = _338 * 2.0;
    vec4 _1071 = texture(Pass1Texture, _356);
    vec4 _1076 = texture(Pass1Texture, _356 + _338);
    vec4 _1125 = clamp(mat4(texture(Pass1Texture, _356 - _338), _1071, _1076, texture(Pass1Texture, _356 + _1015)) * _426, min(_1071, _1076), max(_1071, _1076));
    vec2 _474 = _356 + _343;
    vec4 _1136 = texture(Pass1Texture, _474);
    vec4 _1141 = texture(Pass1Texture, _474 + _338);
    vec4 _1190 = clamp(mat4(texture(Pass1Texture, _474 - _338), _1136, _1141, texture(Pass1Texture, _474 + _1015)) * _426, min(_1136, _1141), max(_1136, _1141));
    vec2 _487 = _356 + (_343 * 2.0);
    vec4 _1201 = texture(Pass1Texture, _487);
    vec4 _1206 = texture(Pass1Texture, _487 + _338);
    vec4 _1278 = clamp(mat4(clamp(mat4(texture(Pass1Texture, _452 - _338), _1006, _1011, texture(Pass1Texture, _452 + _1015)) * _426, min(_1006, _1011), max(_1006, _1011)), _1125, _1190, clamp(mat4(texture(Pass1Texture, _487 - _338), _1201, _1206, texture(Pass1Texture, _487 + _1015)) * _426, min(_1201, _1206), max(_1201, _1206))) * (_442 / vec4(dot(_442, vec4(1.0)))), min(_1125, _1190), max(_1125, _1190));
    vec4 _509 = texture(Texture, _333);
    vec3 _510 = _509.xyz;
    float _520 = max(_1278.x, max(_1278.y, _1278.z));
    float _528 = ((vec4(TextureSize, 1.0 / TextureSize)).y * (vec4(OutputSize, 1.0 / OutputSize)).w) * 0.5;
    float _536 = (_333.y * _1499.y) + _1344;
    float _545 = mix((SCANLINE_STRENGTH_MAX), (SCANLINE_STRENGTH_MIN), _520);
    float _557 = clamp(_520 * (SCANLINE_BEAM_MAX), (SCANLINE_BEAM_MIN), (SCANLINE_BEAM_MAX));
    vec4 _1507;
    if ((MASK_TYPE) == 1.0)
    {
        _1507 = vec4(2.0, 1.0, 1.0, 0.0);
    }
    else
    {
        vec4 _1508;
        if ((MASK_TYPE) == 2.0)
        {
            _1508 = vec4(3.0, 1.0, 1.0, 0.0);
        }
        else
        {
            vec4 _1509;
            if ((MASK_TYPE) == 3.0)
            {
                _1509 = vec4(2.099999904632568359375, 1.0, 1.0, 0.0);
            }
            else
            {
                vec4 _1510;
                if ((MASK_TYPE) == 4.0)
                {
                    _1510 = vec4(3.099999904632568359375, 1.0, 1.0, 0.0);
                }
                else
                {
                    vec4 _1511;
                    if ((MASK_TYPE) == 5.0)
                    {
                        _1511 = vec4(2.0, 1.0, 1.0, 1.0);
                    }
                    else
                    {
                        vec4 _1512;
                        if ((MASK_TYPE) == 6.0)
                        {
                            _1512 = vec4(3.0, 2.0, 1.0, 3.0);
                        }
                        else
                        {
                            vec4 _1513;
                            if ((MASK_TYPE) == 7.0)
                            {
                                _1513 = vec4(3.0, 2.0, 2.0, 3.0);
                            }
                            else
                            {
                                _1513 = _1516;
                            }
                            _1512 = _1513;
                        }
                        _1511 = _1512;
                    }
                    _1510 = _1511;
                }
                _1509 = _1510;
            }
            _1508 = _1509;
        }
        _1507 = _1508;
    }
    float _620 = floor(_1507.x);
    vec2 _659 = floor(((RA_VARYING_0 * (vec4(OutputSize, 1.0 / OutputSize)).xy) * _246) / (_246 * vec2((MASK_SIZE), _1507.z * (MASK_SIZE))));
    float _663 = _659.x;
    float _665 = _659.y;
    int _674 = int(mod((_663 + (mod(_665, 2.0) * _1507.w)) / _1507.y, _620));
    float _694 = mix((MASK_STRENGTH_MAX), (MASK_STRENGTH_MIN), _520);
    float _697 = 1.0 - _694;
    float _701 = 1.0 + (_694 * 2.0);
    vec3 _1365;
    if (_674 == 0)
    {
        _1365 = mix(vec3(_701), vec3(_701, _697, _697), vec3(_620 - 2.0));
    }
    else
    {
        vec3 _1366;
        if (_674 == 1)
        {
            _1366 = mix(vec3(_697), vec3(_697, _701, _697), vec3(_620 - 2.0));
        }
        else
        {
            _1366 = vec3(_697, _697, _701);
        }
        _1365 = _1366;
    }
    vec3 _755 = mix(vec3(1.0), _1365 * mix(1.0, (mod(_665 + mod(floor(_663 / _620), 2.0), 2.0) > 0.89999997615814208984375) ? _697 : _701, fract(_1507.x) * 10.0), vec3(clamp((MASK_TYPE), 0.0, 1.0)));
    vec3 _764 = (_1278.xyz * _755) * (BRIGHTNESS);
    float _1297 = 1.0 - _545;
    vec3 _846 = pow(vec3(mix(1.0, clamp(((GEOM_CORNER_SIZE) - sqrt(dot(_932, _932))) * (GEOM_CORNER_SMOOTH), 0.0, 1.0), ceil((GEOM_CORNER_SIZE)))) * (((((clamp(_764 * vec3((((1.0 - pow((cos((_536 - _528) * 6.283185482025146484375) * 0.5) + 0.5, _557)) * _545) * 2.0) + _1297), vec3(0.0), vec3(1.0)) + clamp(_764 * vec3((((1.0 - pow((cos(_536 * 6.283185482025146484375) * 0.5) + 0.5, _557)) * _545) * 2.0) + _1297), vec3(0.0), vec3(1.0))) + clamp(_764 * vec3((((1.0 - pow((cos((_536 + _528) * 6.283185482025146484375) * 0.5) + 0.5, _557)) * _545) * 2.0) + _1297), vec3(0.0), vec3(1.0))) * vec3(0.3333333432674407958984375)) + ((_510 * _755) * (HALATION))) + (_510 * (DIFFUSION))), vec3(1.0 / (GAMMA_OUTPUT)));
    FragColor = vec4(_846, 1.0);
}


#endif
