// Generated from crt/shaders/crt-geom-mini.slang. See slang/upstream for licence/source.
#version 130
#pragma parameter CURV "CRT-Geom Curvature" 1.0 0.0 1.0 1.0
#pragma parameter scanlines "CRT-Geom Scanline Weight" 0.5 0.0 0.5 0.05
#pragma parameter MASK "CRT-Geom Dotmask Strength" 0.2 0.0 0.5 0.05
#pragma parameter INTERL "CRT-Geom Interlacing Simulation" 1.0 0.0 1.0 1.0
#pragma parameter SAT "CRT-Geom Saturation" 1.0 0.0 2.0 0.05
#ifdef VERTEX

uniform mat4 MVPMatrix;
uniform vec2 OutputSize;
struct UBO
{
    mat4 MVP;
};



struct Push
{
    vec4 OutputSize;
};



in vec4 VertexCoord;
out vec2 RA_VARYING_0;
in vec2 TexCoord;
out float RA_VARYING_1;

void main()
{
    gl_Position = (MVPMatrix) * VertexCoord;
    RA_VARYING_0 = TexCoord * 1.00010001659393310546875;
    RA_VARYING_1 = (RA_VARYING_0.x * (vec4(OutputSize, 1.0 / OutputSize)).x) * 3.1415927410125732421875;
}


#endif
#ifdef FRAGMENT

uniform float CURV;
uniform int FrameCount;
uniform float INTERL;
uniform float MASK;
uniform vec2 OrigTextureSize;
uniform float SAT;
uniform vec2 TextureSize;
uniform float scanlines;
vec2 _489;

struct Push
{
    vec4 SourceSize;
    vec4 OriginalSize;
    uint FrameCount;
    float CURV;
    float scanlines;
    float MASK;
    float INTERL;
    float SAT;
};



uniform sampler2D Texture;

in vec2 RA_VARYING_0;
in float RA_VARYING_1;
out vec4 FragColor;

void main()
{
    vec2 _91 = vec2((vec4(TextureSize, 1.0 / TextureSize)).z * 0.5, 0.0);
    bool _96 = (CURV) == 1.0;
    vec2 _483;
    vec2 _488;
    if (_96)
    {
        vec2 _375 = RA_VARYING_0 - vec2(0.5);
        float _377 = _375.x;
        float _382 = _375.y;
        vec2 _396 = (_375 + (_375 * (vec2(0.119999997317790985107421875, 0.25) * ((_377 * _377) + (_382 * _382))))) * vec2(0.9700000286102294921875, 0.944999992847442626953125);
        bool _400 = abs(_396.x) >= 0.5;
        bool _408;
        if (!_400)
        {
            _408 = abs(_396.y) >= 0.5;
        }
        else
        {
            _408 = _400;
        }
        vec2 _482;
        if (_408)
        {
            _482 = vec2(-1.0);
        }
        else
        {
            _482 = _396 + vec2(0.5);
        }
        vec2 _110 = min(_482, vec2(1.0) - _482);
        _110.x = 9.9999997473787516355514526367188e-05 / _110.x;
        _488 = _110;
        _483 = _482;
    }
    else
    {
        _488 = _489;
        _483 = RA_VARYING_0;
    }
    vec2 _122 = _91 * 2.0;
    vec2 _124 = _483 - _122;
    vec2 _131 = _483 * (vec4(TextureSize, 1.0 / TextureSize)).xy;
    vec2 _134 = floor(_131) + vec2(0.5);
    vec2 _142 = _131 - _134;
    float _147 = _142.y;
    _124.y = (_134.y + (((((16.0 * _147) * _147) * _147) * _147) * _147)) * (vec4(TextureSize, 1.0 / TextureSize)).w;
    vec4 _173 = texture(Texture, _124);
    vec4 _184 = texture(Texture, _124 + _122);
    vec4 _196 = texture(Texture, _124 + (_91 * 3.0));
    vec4 _208 = texture(Texture, _124 + (_91 * 4.0));
    vec3 _217 = ((((_173.xyz * (-1.60000002384185791015625)) + (_184.xyz * 3.2999999523162841796875)) + (_196.xyz * 5.599999904632568359375)) + (_208.xyz * (-1.5))) * vec3(0.17241378128528594970703125);
    float _221 = dot(vec3(0.25), _217);
    float _231 = mix((scanlines), (scanlines) * 0.60000002384185791015625, _221);
    bool _238 = (vec4(OrigTextureSize, 1.0 / OrigTextureSize)).y > 400.0;
    bool _244 = (INTERL) == 1.0;
    bool _250;
    if (_244)
    {
        _250 = _238;
    }
    else
    {
        _250 = _244;
    }
    float _432;
    if (_250)
    {
        _432 = (mod(float((uint(FrameCount))), 2.0) < 1.0) ? 0.75 : 0.25;
    }
    else
    {
        _432 = 0.25;
    }
    vec3 _309 = (_217 * ((((_231 * sin((((_483.y * (vec4(TextureSize, 1.0 / TextureSize)).y) * (_238 ? 0.5 : 1.0)) - _432) * 6.28318500518798828125)) + 1.0) - _231) * ((((MASK) * sin(RA_VARYING_1)) + 1.0) - (MASK)))) * mix(1.4500000476837158203125, 1.0499999523162841796875, _221);
    vec3 _327 = clamp(mix(vec3(dot(vec3(0.2899999916553497314453125, 0.60000002384185791015625, 0.10999999940395355224609375), _309)), _309, vec3((SAT))), vec3(0.0), vec3(1.0));
    bool _332 = _488.y <= _488.x;
    bool _338;
    if (_332)
    {
        _338 = _96;
    }
    else
    {
        _338 = _332;
    }
    bool _351;
    if (!_338)
    {
        bool _344 = _488.x < 9.9999997473787516355514526367188e-05;
        bool _350;
        if (_344)
        {
            _350 = _96;
        }
        else
        {
            _350 = _344;
        }
        _351 = _350;
    }
    else
    {
        _351 = _338;
    }
    bvec3 _454 = bvec3(_351);
    vec3 _357 = sqrt(vec3(_454.x ? vec3(0.0).x : _327.x, _454.y ? vec3(0.0).y : _327.y, _454.z ? vec3(0.0).z : _327.z));
    FragColor.x = _357.x;
    FragColor.y = _357.y;
    FragColor.z = _357.z;
}


#endif
