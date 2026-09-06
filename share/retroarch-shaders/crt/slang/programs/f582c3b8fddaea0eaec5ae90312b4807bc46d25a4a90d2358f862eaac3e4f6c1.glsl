// Generated from crt/shaders/crt-yo6/crt-yo6-flat-trinitron-tv.slang. See slang/upstream for licence/source.
#version 120
#pragma parameter TVL   "TVL (0:Auto)"      0.0      0.0 16384.0 1.0
#pragma parameter VSIZE "V-Size (0:Auto)"   0.0      0.0 16384.0 1.0
#pragma parameter VOFF  "V-Offset"          0.0 -16384.0 16384.0 1.0
#pragma parameter VOFFC "V-Offset Centered" 1.0      0.0     1.0 1.0
#pragma parameter VZOOM "V-Zoom (2:Auto)"   2.0      2.0    15.0 1.0
#pragma parameter GAMMA "Gamma"             1.8      0.0     4.0 0.1
#ifdef VERTEX

uniform mat4 MVPMatrix;
uniform vec2 OutputSize;
uniform float TVL;
uniform vec2 TextureSize;
uniform float VOFF;
uniform float VOFFC;
uniform float VSIZE;
uniform float VZOOM;
const vec4 _117[13] = vec4[](vec4(2.0, 3.0, 0.0, 0.0), vec4(3.0, 4.0, 1.0, 3.0), vec4(3.0, 5.0, 1.0, 7.0), vec4(4.0, 6.0, 1.0, 12.0), vec4(5.0, 7.0, 1.0, 18.0), vec4(5.0, 8.0, 1.0, 25.0), vec4(6.0, 9.0, 2.0, 33.0), vec4(7.0, 10.0, 2.0, 42.0), vec4(7.0, 11.0, 2.0, 52.0), vec4(8.0, 12.0, 2.0, 63.0), vec4(9.0, 13.0, 3.0, 75.0), vec4(9.0, 14.0, 3.0, 88.0), vec4(10.0, 15.0, 3.0, 102.0));

struct UBO
{
    mat4 MVP;
};



struct Push
{
    vec4 SourceSize;
    vec4 OutputSize;
    float TVL;
    float VSIZE;
    float VZOOM;
    float VOFF;
    float VOFFC;
};



varying vec2 RA_VARYING_0;
attribute vec2 TexCoord;
varying vec4 RA_VARYING_1;
varying vec4 RA_VARYING_2;
varying float RA_VARYING_3;
attribute vec4 VertexCoord;

void main()
{
    float _229;
    if (int((VSIZE)) <= 0)
    {
        _229 = (vec4(TextureSize, 1.0 / TextureSize)).y;
    }
    else
    {
        _229 = (VSIZE);
    }
    float _230;
    if (int((TVL)) <= 0)
    {
        _230 = _229 * 2.0;
    }
    else
    {
        _230 = (TVL);
    }
    vec2 _54 = vec2(_230, _229);
    int _62 = int((VZOOM)) - 3;
    int _234;
    if (_62 < 0)
    {
        int _232_copy;
        int _236;
        _236 = 0;
        for (int _232 = 1; _232 < 13; _232_copy = _232, _232++, _236 = _232_copy)
        {
            vec2 _126 = _117[_232].xy * _54;
            bool _133 = _126.x > (vec4(OutputSize, 1.0 / OutputSize)).x;
            bool _142;
            if (!_133)
            {
                _142 = _126.y > (vec4(OutputSize, 1.0 / OutputSize)).y;
            }
            else
            {
                _142 = _133;
            }
            if (_142)
            {
                break;
            }
        }
        _234 = _236;
    }
    else
    {
        _234 = _62;
    }
    vec2 _156 = _117[_234].xy * _54;
    RA_VARYING_0 = (TexCoord * (vec4(OutputSize, 1.0 / OutputSize)).xy) - floor(((vec4(OutputSize, 1.0 / OutputSize)).xy - _156) * vec2(0.5));
    RA_VARYING_1 = _117[_234];
    RA_VARYING_2 = vec4(_156, _230, _229);
    float _238;
    if (int((VOFFC)) == 1)
    {
        _238 = floor(((vec4(TextureSize, 1.0 / TextureSize)).y - _229) * 0.5);
    }
    else
    {
        _238 = 0.0;
    }
    RA_VARYING_3 = (VOFF) + _238;
    gl_Position = (MVPMatrix) * VertexCoord;
}


#endif
#ifdef FRAGMENT

uniform float GAMMA;
uniform vec2 TextureSize;
struct Push
{
    vec4 SourceSize;
    float GAMMA;
};



uniform sampler2D Texture;
uniform sampler2D TEX;

varying vec2 RA_VARYING_0;
varying vec4 RA_VARYING_1;
varying float RA_VARYING_3;
varying vec4 RA_VARYING_2;

void main()
{
    float _50 = (floor(RA_VARYING_0.y / RA_VARYING_1.y) + RA_VARYING_3) + 0.5;
    vec3 dst = vec3(0.0);
    vec3 src;
    for (int _222 = 0; _222 < 3; )
    {
        vec2 _80 = RA_VARYING_0 + vec2(float(1 - _222) * RA_VARYING_1.z, 0.0);
        src = texture2D(Texture, vec2((floor(_80.x / RA_VARYING_1.x) + 0.5) / RA_VARYING_2.z, _50 / (vec4(TextureSize, 1.0 / TextureSize)).y)).xyz;
        dst[_222] = texture2D(TEX, (vec2(floor(pow(src[_222], (GAMMA)) * 255.0) * RA_VARYING_1.x, RA_VARYING_1.w) + mod(_80, RA_VARYING_1.xy)) * vec2(0.00039062500582076609134674072265625, 0.008547008968889713287353515625)).x;
        _222++;
        continue;
    }
    vec2 _188 = (sign(vec2(_50, (vec4(TextureSize, 1.0 / TextureSize)).y - _50)) + vec2(1.0)) * vec2(0.5);
    vec2 _202 = (sign(RA_VARYING_0) + vec2(1.0)) * vec2(0.5);
    vec2 _216 = (sign(RA_VARYING_2.xy - RA_VARYING_0) + vec2(1.0)) * vec2(0.5);
    gl_FragData[0] = vec4(dst * (((_188.x * _188.y) * (_202.x * _202.y)) * (_216.x * _216.y)), 1.0);
}


#endif
