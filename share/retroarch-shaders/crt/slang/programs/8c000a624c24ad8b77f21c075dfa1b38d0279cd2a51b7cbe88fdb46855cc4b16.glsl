// Generated from crt/shaders/fake-crt-geom.slang. See slang/upstream for licence/source.
#version 130
#pragma parameter bogus1 " [ COLORS ] " 0.0 0.0 0.0 0.0
#pragma parameter a_col_temp "Color Temperature (0.01 ~ 200K)" 0.0 -0.15 0.15 0.01
#pragma parameter a_sat "Saturation" 1.0 0.0 2.0 0.05
#pragma parameter a_boostd "Bright Boost Dark" 1.45 1.0 2.0 0.05
#pragma parameter a_boostb "Bright Boost Bright" 1.05 1.0 2.0 0.05
#pragma parameter bogus2 " [ SCANLINES/MASK ] " 0.0 0.0 0.0 0.0
#pragma parameter scanl "Scanlines Low" 0.5 0.0 0.5 0.05
#pragma parameter scanh "Scanlines High" 0.35 0.0 0.5 0.05
#pragma parameter a_interlace "Interlace On/Off" 1.0 0.0 1.0 1.0
#pragma parameter a_MTYPE "Mask Type, Fine/Coarse/LCD" 0.0 0.0 2.0 1.0
#pragma parameter a_MSIZE "Mask Size" 1.0 1.0 2.0 1.0
#pragma parameter a_MASK "Mask Strength" 0.2 0.0 0.5 0.05
#pragma parameter bogus3 " [ GEOMETRY ] " 0.0 0.0 0.0 0.0
#pragma parameter warpx "Curvature Horizontal" 0.03 0.0 0.2 0.01
#pragma parameter warpy "Curvature Vertical" 0.04 0.0 0.2 0.01
#pragma parameter a_corner "Corner Roundness" 0.03 0.0 0.2 0.01
#pragma parameter bsmooth "Border Smoothness" 250.0 100.0 1000.0 25.0
#pragma parameter a_vignette "Vignette On/Off" 1.0 0.0 1.0 1.0
#pragma parameter a_vigstr "Vignette Strength" 0.5 0.0 1.0 0.05
#ifdef VERTEX

uniform mat4 MVPMatrix;
uniform vec2 OrigTextureSize;
uniform vec2 OutputSize;
uniform vec2 TextureSize;
uniform float a_MSIZE;
struct UBO
{
    mat4 MVP;
};



struct Push
{
    vec4 SourceSize;
    vec4 OriginalSize;
    vec4 OutputSize;
    float a_MSIZE;
};



in vec4 VertexCoord;
out vec2 RA_VARYING_0;
in vec2 TexCoord;
out vec2 RA_VARYING_1;
out float RA_VARYING_2;

void main()
{
    gl_Position = (MVPMatrix) * VertexCoord;
    RA_VARYING_0 = TexCoord * 1.00010001659393310546875;
    RA_VARYING_1 = vec2(1.0) / (vec4(TextureSize, 1.0 / TextureSize)).xy;
    RA_VARYING_2 = (((RA_VARYING_0.x * (vec4(OutputSize, 1.0 / OutputSize)).x) / (a_MSIZE)) * ((vec4(TextureSize, 1.0 / TextureSize)).xy / (vec4(OrigTextureSize, 1.0 / OrigTextureSize)).xy).x) * 3.1415920257568359375;
}


#endif
#ifdef FRAGMENT

uniform int FrameCount;
uniform vec2 OrigTextureSize;
uniform vec2 TextureSize;
uniform float a_MASK;
uniform float a_MTYPE;
uniform float a_boostb;
uniform float a_boostd;
uniform float a_col_temp;
uniform float a_corner;
uniform float a_interlace;
uniform float a_sat;
uniform float a_vignette;
uniform float a_vigstr;
uniform float bsmooth;
uniform float scanh;
uniform float scanl;
uniform float warpx;
uniform float warpy;
struct Push
{
    vec4 SourceSize;
    vec4 OriginalSize;
    uint FrameCount;
    float warpx;
    float warpy;
    float a_vignette;
    float a_vigstr;
    float a_col_temp;
    float a_sat;
    float a_boostd;
    float a_boostb;
    float a_interlace;
    float scanl;
    float scanh;
    float a_MASK;
    float a_MTYPE;
    float a_corner;
    float bsmooth;
};



uniform sampler2D Texture;

in vec2 RA_VARYING_0;
in vec2 RA_VARYING_1;
in float RA_VARYING_2;
out vec4 FragColor;

void main()
{
    vec2 _109 = (vec4(TextureSize, 1.0 / TextureSize)).xy / (vec4(OrigTextureSize, 1.0 / OrigTextureSize)).xy;
    vec2 _445 = ((RA_VARYING_0 * _109) * 2.0) - vec2(1.0);
    float _447 = _445.y;
    float _456 = _445.x;
    vec2 _468 = (_445 * vec2(1.0 + ((_447 * _447) * (warpx)), 1.0 + ((_456 * _456) * (warpy)))) * 0.5;
    vec2 _470 = _468 + vec2(0.5);
    vec2 _129 = (_470 / _109) * (vec4(TextureSize, 1.0 / TextureSize)).xy;
    vec2 _133 = _129 - vec2(0.5);
    vec2 _136 = fract(_133);
    vec2 _143 = (floor(_133) + vec2(0.5)) * RA_VARYING_1;
    float _148 = _136.x;
    vec4 _164 = max(abs(vec4(1.0 + _148, _148, 1.0 - _148, 2.0 - _148) * 3.1415920257568359375), vec4(9.9999997473787516355514526367188e-06));
    vec4 _175 = ((sin(_164) * 2.0) * sin(_164 * 0.5)) / (_164 * _164);
    vec4 _250 = clamp(mat4(texture(Texture, _143 + vec2(-RA_VARYING_1.x, 0.0)), texture(Texture, _143), texture(Texture, _143 + vec2(RA_VARYING_1.x, 0.0)), texture(Texture, _143 + vec2(2.0 * RA_VARYING_1.x, 0.0))) * (_175 / vec4(dot(_175, vec4(1.0)))), vec4(0.0), vec4(1.0));
    vec3 _273 = _250.xyz * vec3(1.0 + (a_col_temp), 1.0 - ((a_col_temp) * 0.20000000298023223876953125), 1.0 - (a_col_temp));
    vec4 _528 = _250;
    _528.x = _273.x;
    _528.y = _273.y;
    _528.z = _273.z;
    float _289 = mix((scanl), (scanh), dot(vec3(0.3300000131130218505859375), _250.xyz));
    float _500;
    if ((a_MTYPE) == 2.0)
    {
        _500 = _129.x * 6.283184051513671875;
    }
    else
    {
        _500 = RA_VARYING_2;
    }
    float _511;
    if ((a_vignette) == 1.0)
    {
        float _334 = _470.x - 0.5;
        _511 = (_334 * _334) * (a_vigstr);
    }
    else
    {
        _511 = 0.0;
    }
    vec2 _562;
    if ((vec4(OrigTextureSize, 1.0 / OrigTextureSize)).y > 400.0)
    {
        vec2 _350 = _129 * vec2(0.5);
        bool _357 = mod(float((uint(FrameCount))), 2.0) > 0.0;
        bool _364;
        if (_357)
        {
            _364 = (a_interlace) == 1.0;
        }
        else
        {
            _364 = _357;
        }
        vec2 _563;
        if (_364)
        {
            _563 = _350 + vec2(0.5);
        }
        else
        {
            _563 = _350;
        }
        _562 = _563;
    }
    else
    {
        _562 = _129;
    }
    vec4 _387 = (_528 * ((((a_MASK) * sin(_500 * (((a_MTYPE) == 1.0) ? 0.6665999889373779296875 : 1.0))) + 1.0) - (a_MASK))) * (((_289 + _511) * sin((_562.y + 0.25) * 6.283184051513671875)) + ((1.0 - _289) - _511));
    vec3 _390 = _387.xyz;
    float _395 = dot(_390, vec3(0.300000011920928955078125, 0.60000002384185791015625, 0.100000001490116119384765625));
    vec3 _404 = mix(vec3(_395), _390, vec3((a_sat)));
    vec4 _537 = _387;
    _537.x = _404.x;
    _537.y = _404.y;
    _537.z = _404.z;
    vec2 _482 = vec2((a_corner));
    vec2 _487 = _482 - min(min(_470, vec2(0.5) - _468), _482);
    vec3 _429 = sqrt((_537 * mix((a_boostd), (a_boostb), _395)).xyz) * clamp(((a_corner) - sqrt(dot(_487, _487))) * (bsmooth), 0.0, 1.0);
    FragColor.x = _429.x;
    FragColor.y = _429.y;
    FragColor.z = _429.z;
}


#endif
