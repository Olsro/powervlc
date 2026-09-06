// Generated from crt/shaders/hyllian/crt-hyllian-fast.slang. See slang/upstream for licence/source.
#version 120
#pragma parameter MASK_INTENSITY "MASK INTENSITY" 0.5 0.0 1.0 0.1
#pragma parameter InputGamma "INPUT GAMMA" 2.4 0.0 5.0 0.1
#pragma parameter OutputGamma "OUTPUT GAMMA" 2.2 0.0 5.0 0.1
#pragma parameter BRIGHTBOOST "BRIGHT BOOST" 1.5 0.0 2.0 0.1
#pragma parameter SCANLINES "SCANLINES STRENGTH" 0.72 0.0 1.0 0.02
#pragma parameter SHARPER "SHARPER" 0.0 0.0 1.0 1.0
#ifdef VERTEX

uniform mat4 MVPMatrix;
uniform vec2 TextureSize;
struct UBO
{
    mat4 MVP;
    vec4 SourceSize;
};



attribute vec4 VertexCoord;
varying vec2 RA_VARYING_1;
varying vec2 RA_VARYING_0;
attribute vec2 TexCoord;

void main()
{
    gl_Position = (MVPMatrix) * VertexCoord;
    RA_VARYING_1 = vec2(1.0) / vec2((vec4(TextureSize, 1.0 / TextureSize)).x, (vec4(TextureSize, 1.0 / TextureSize)).y);
    RA_VARYING_0 = TexCoord + (RA_VARYING_1 * vec2(-0.499989986419677734375, 0.0));
}


#endif
#ifdef FRAGMENT

uniform float BRIGHTBOOST;
uniform float InputGamma;
uniform float MASK_INTENSITY;
uniform float OutputGamma;
uniform vec2 OutputSize;
uniform float SCANLINES;
uniform float SHARPER;
uniform vec2 TextureSize;
struct UBO
{
    vec4 SourceSize;
    vec4 OutputSize;
};



struct Push
{
    float MASK_INTENSITY;
    float InputGamma;
    float OutputGamma;
    float BRIGHTBOOST;
    float SCANLINES;
    float SHARPER;
};



uniform sampler2D Texture;

varying vec2 RA_VARYING_1;
varying vec2 RA_VARYING_0;

void main()
{
    vec2 _18 = vec2(RA_VARYING_1.x, 0.0);
    vec2 _38 = RA_VARYING_0 * (vec4(TextureSize, 1.0 / TextureSize)).xy;
    vec2 _46 = (floor(_38) + vec2(0.499989986419677734375)) / (vec4(TextureSize, 1.0 / TextureSize)).xy;
    vec2 _53 = fract(_38);
    vec4 _65 = texture2D(Texture, _46 - _18);
    vec4 _70 = texture2D(Texture, _46);
    vec4 _77 = texture2D(Texture, _46 + _18);
    vec4 _86 = texture2D(Texture, _46 + (_18 * 2.0));
    float _92 = _53.x;
    float _95 = _92 * _92;
    vec4 _107 = vec4(_95 * _92, _95, _92, 1.0);
    vec4 _326;
    if ((SHARPER) == 0.0)
    {
        _326 = vec4(dot(vec4(-0.5, 1.0, -0.5, 0.0), _107), dot(vec4(1.5, -2.5, 0.0, 1.0), _107), dot(vec4(-1.5, 2.0, 0.5, 0.0), _107), dot(vec4(0.5, -0.5, 0.0, 0.0), _107));
    }
    else
    {
        vec4 _327;
        if ((SHARPER) == 1.0)
        {
            vec4 _309 = vec4(0.0);
            _309.y = dot(vec4(2.0, -3.0, 0.0, 1.0), _107);
            _309.z = dot(vec4(-2.0, 3.0, 0.0, 0.0), _107);
            _309.w = 0.0;
            _327 = _309;
        }
        else
        {
            _327 = vec4(0.0);
        }
        _326 = _327;
    }
    float _212 = max(0.0, min(1.0, (1.5 - (SCANLINES)) - abs(_53.y - 0.5)));
    float _239 = 1.0 - (MASK_INTENSITY);
    gl_FragData[0] = vec4(pow((pow((((_65.xyz * _326.x) + (_70.xyz * _326.y)) + (_77.xyz * _326.z)) + (_86.xyz * _326.w), vec3((InputGamma))) * ((_212 * _212) * ((3.0 + (BRIGHTBOOST)) - (2.0 * _212)))) * vec3(mix(vec4(1.0, _239, 1.0, 1.0), vec4(_239, 1.0, _239, 1.0), vec4(floor(mod(RA_VARYING_0.x * (vec4(OutputSize, 1.0 / OutputSize)).x, 2.0)))).xyz), vec3(1.0 / (OutputGamma))), 1.0);
}


#endif
