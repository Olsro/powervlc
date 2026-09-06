// Generated from crt/shaders/crt-aperture.slang. See slang/upstream for licence/source.
#version 120
#pragma parameter SHARPNESS_IMAGE "Sharpness Image" 1.0 1.0 5.0 1.0
#pragma parameter SHARPNESS_EDGES "Sharpness Edges" 3.0 1.0 5.0 1.0
#pragma parameter GLOW_WIDTH "Glow Width" 0.5 0.05 0.65 0.05
#pragma parameter GLOW_HEIGHT "Glow Height" 0.5 0.05 0.65 0.05
#pragma parameter GLOW_HALATION "Glow Halation" 0.1 0.0 1.0 0.01
#pragma parameter GLOW_DIFFUSION "Glow Diffusion" 0.05 0.0 1.0 0.01
#pragma parameter MASK_COLORS "Mask Colors" 2.0 2.0 3.0 1.0
#pragma parameter MASK_STRENGTH "Mask Strength" 0.3 0.0 1.0 0.05
#pragma parameter MASK_SIZE "Mask Size" 1.0 1.0 9.0 1.0
#pragma parameter SCANLINE_SIZE_MIN "Scanline Size Min." 0.5 0.5 1.5 0.05
#pragma parameter SCANLINE_SIZE_MAX "Scanline Size Max." 1.5 0.5 1.5 0.05
#pragma parameter SCANLINE_SHAPE "Scanline Shape" 2.5 1.0 100.0 0.1
#pragma parameter SCANLINE_OFFSET "Scanline Offset" 1.0 0.0 1.0 1.0
#pragma parameter GAMMA_INPUT "Gamma Input" 2.4 1.0 5.0 0.1
#pragma parameter GAMMA_OUTPUT "Gamma Output" 2.4 1.0 5.0 0.1
#pragma parameter BRIGHTNESS "Brightness" 1.5 0.0 2.0 0.05
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

uniform float BRIGHTNESS;
uniform float GAMMA_INPUT;
uniform float GAMMA_OUTPUT;
uniform float GLOW_DIFFUSION;
uniform float GLOW_HALATION;
uniform float GLOW_HEIGHT;
uniform float GLOW_WIDTH;
uniform float MASK_COLORS;
uniform float MASK_SIZE;
uniform float MASK_STRENGTH;
uniform vec2 OutputSize;
uniform float SCANLINE_OFFSET;
uniform float SCANLINE_SHAPE;
uniform float SCANLINE_SIZE_MAX;
uniform float SCANLINE_SIZE_MIN;
uniform float SHARPNESS_EDGES;
uniform float SHARPNESS_IMAGE;
uniform vec2 TextureSize;
struct Push
{
    vec4 SourceSize;
    vec4 OutputSize;
    float SHARPNESS_IMAGE;
    float SHARPNESS_EDGES;
    float GLOW_WIDTH;
    float GLOW_HEIGHT;
    float GLOW_HALATION;
    float GLOW_DIFFUSION;
    float MASK_COLORS;
    float MASK_STRENGTH;
    float MASK_SIZE;
    float SCANLINE_SIZE_MIN;
    float SCANLINE_SIZE_MAX;
    float SCANLINE_SHAPE;
    float SCANLINE_OFFSET;
    float GAMMA_INPUT;
    float GAMMA_OUTPUT;
    float BRIGHTNESS;
};



uniform sampler2D Texture;

varying vec2 RA_VARYING_0;

void main()
{
    float _1318;
    float _474 = floor((vec4(OutputSize, 1.0 / OutputSize)).y * (vec4(TextureSize, 1.0 / TextureSize)).w);
    vec2 _491 = (vec4(TextureSize, 1.0 / TextureSize)).xy;
    vec2 _503 = ((RA_VARYING_0 * _491) - vec2(0.0, ((mod(_474, 2.0) != 0.0) ? 0.0 : (0.5 / _474)) * (SCANLINE_OFFSET))) * (vec4(TextureSize, 1.0 / TextureSize)).zw;
    vec2 _653 = vec2(1.0 / (vec4(TextureSize, 1.0 / TextureSize)).x, 0.0);
    vec2 _657 = vec2(0.0, 1.0 / (vec4(TextureSize, 1.0 / TextureSize)).y);
    vec2 _660 = _503 * _491;
    vec2 _666 = (floor(_660) + vec2(0.5)) / _491;
    vec2 _671 = (fract(_660) - vec2(0.5)) * (-1.0);
    vec2 _674 = _666 - _657;
    vec3 _732 = vec3((GAMMA_INPUT));
    vec2 _682 = _666 + _657;
    float _687 = _671.x;
    vec3 _863 = vec3(_687 - 1.0, _687, _687 + 1.0) / vec3((GLOW_WIDTH));
    vec3 _868 = exp2((_863 * _863) * (-1.0));
    float _872 = _868.x;
    float _877 = _868.y;
    float _883 = _868.z;
    vec3 _894 = vec3((_872 + _877) + _883);
    float _718 = _671.y;
    vec3 _998 = vec3(_718 - 1.0, _718, _718 + 1.0) / vec3((GLOW_HEIGHT));
    vec3 _1003 = exp2((_998 * _998) * (-1.0));
    float _1007 = _1003.x;
    float _1012 = _1003.y;
    float _1018 = _1003.z;
    vec3 _1030 = (((((((pow(texture2D(Texture, _674 - _653).xyz, _732) * _872) + (pow(texture2D(Texture, _674).xyz, _732) * _877)) + (pow(texture2D(Texture, _674 + _653).xyz, _732) * _883)) / _894) * _1007) + (((((pow(texture2D(Texture, _666 - _653).xyz, _732) * _872) + (pow(texture2D(Texture, _666).xyz, _732) * _877)) + (pow(texture2D(Texture, _666 + _653).xyz, _732) * _883)) / _894) * _1012)) + (((((pow(texture2D(Texture, _682 - _653).xyz, _732) * _872) + (pow(texture2D(Texture, _682).xyz, _732) * _877)) + (pow(texture2D(Texture, _682 + _653).xyz, _732) * _883)) / _894) * _1018)) / vec3((_1007 + _1012) + _1018);
    float _1043 = (vec4(TextureSize, 1.0 / TextureSize)).x * (SHARPNESS_IMAGE);
    vec2 _1393 = _491;
    _1393.x = _1043;
    vec2 _1052 = (_503 * _1393) - vec2(0.5, 0.0);
    vec2 _1057 = (floor(_1052) + vec2(0.5, 0.001000000047497451305389404296875)) / _1393;
    vec2 _1059 = fract(_1052);
    float _1061 = _1059.x;
    vec4 _1076 = max(abs(vec4(_1061 + 1.0, _1061, _1061 - 1.0, _1061 - 2.0) * 3.1415927410125732421875), vec4(9.9999997473787516355514526367188e-06));
    vec4 _1088 = ((sin(_1076) * 2.0) * sin(_1076 * vec4(0.5))) / (_1076 * _1076);
    vec4 _1138 = vec4(pow(texture2D(Texture, _1057).xyz, _732), 1.0);
    vec4 _1140 = vec4(pow(texture2D(Texture, _1057 + vec2(1.0 / _1043, 0.0)).xyz, _732), 1.0);
    vec3 _1145 = (mat4(_1138, _1138, _1140, _1140) * (_1088 / vec4(dot(_1088, vec4(1.0))))).xyz;
    float _1158 = (vec4(TextureSize, 1.0 / TextureSize)).x * (SHARPNESS_EDGES);
    vec2 _1401 = _491;
    _1401.x = _1158;
    vec2 _1167 = (_503 * _1401) - vec2(0.5, 0.0);
    vec2 _1172 = (floor(_1167) + vec2(0.5, 0.001000000047497451305389404296875)) / _1401;
    vec2 _1174 = fract(_1167);
    float _1176 = _1174.x;
    vec4 _1191 = max(abs(vec4(_1176 + 1.0, _1176, _1176 - 1.0, _1176 - 2.0) * 3.1415927410125732421875), vec4(9.9999997473787516355514526367188e-06));
    vec4 _1203 = ((sin(_1191) * 2.0) * sin(_1191 * vec4(0.5))) / (_1191 * _1191);
    vec4 _1253 = vec4(pow(texture2D(Texture, _1172).xyz, _732), 1.0);
    vec4 _1255 = vec4(pow(texture2D(Texture, _1172 + vec2(1.0 / _1158, 0.0)).xyz, _732), 1.0);
    vec3 _1281 = vec3(2.0) / mix(vec3((SCANLINE_SIZE_MIN)), vec3((SCANLINE_SIZE_MAX)), pow(_1145, vec3(1.0 / (SCANLINE_SHAPE))));
    vec3 _1283 = _1281 * 0.5;
    vec3 _553 = sqrt((mat4(_1253, _1253, _1255, _1255) * (_1203 / vec4(dot(_1203, vec4(1.0))))).xyz * _1145) * (smoothstep(vec3(0.0), vec3(1.0), vec3(1.0) - abs((_1281 * fract(_503.y * (vec4(TextureSize, 1.0 / TextureSize)).y)) - _1283)) * _1283);
    vec3 _559 = clamp(_1030 - _553, vec3(0.0), vec3(1.0));
    vec3 _568 = _553 + ((_559 * _559) * (GLOW_HALATION));
    vec3 _1338;
    do
    {
        _1318 = (MASK_COLORS);
        float _1319 = mod(floor(((RA_VARYING_0.x * (vec4(OutputSize, 1.0 / OutputSize)).x) * (vec4(TextureSize, 1.0 / TextureSize)).x) / ((vec4(TextureSize, 1.0 / TextureSize)).x * (MASK_SIZE))), _1318);
        if (_1319 == 0.0)
        {
            _1338 = mix(vec3(1.0, 0.0, 1.0), vec3(1.0, 0.0, 0.0), vec3(_1318 - 2.0));
            break;
        }
        else
        {
            if (_1319 == 1.0)
            {
                _1338 = vec3(0.0, 1.0, 0.0);
                break;
            }
            else
            {
                _1338 = vec3(0.0, 0.0, 1.0);
                break;
            }
            break; // unreachable workaround
        }
        break; // unreachable workaround
    } while(false);
    gl_FragData[0] = vec4(pow((mix(_568, (_568 * _1338) * _1318, vec3((MASK_STRENGTH))) + (_559 * (GLOW_DIFFUSION))) * (BRIGHTNESS), vec3(1.0 / (GAMMA_OUTPUT))), 1.0);
}


#endif
