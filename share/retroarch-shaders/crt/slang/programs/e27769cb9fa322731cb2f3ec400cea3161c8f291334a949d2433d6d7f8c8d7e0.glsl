// Generated from crt/shaders/gtu-v050/pass2.slang. See slang/upstream for licence/source.
#version 120
#pragma parameter compositeConnection "Composite Connection Enable" 0.0 0.0 1.0 1.0
#pragma parameter signalResolution "Signal Resolution Y" 256.0 16.0 1024.0 16.0
#pragma parameter signalResolutionI "Signal Resolution I" 83.0 1.0 350.0 2.0
#pragma parameter signalResolutionQ "Signal Resolution Q" 25.0 1.0 350.0 2.0
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

uniform vec2 TextureSize;
uniform float compositeConnection;
uniform float signalResolution;
uniform float signalResolutionI;
uniform float signalResolutionQ;
struct Push
{
    vec4 SourceSize;
    float signalResolution;
    float signalResolutionI;
    float signalResolutionQ;
    float compositeConnection;
};



uniform sampler2D Texture;

varying vec2 RA_VARYING_0;

void main()
{
    float _29 = fract((RA_VARYING_0.x * (vec4(TextureSize, 1.0 / TextureSize)).x) - 0.5);
    bool _39 = (compositeConnection) > 0.0;
    float _550;
    if (_39)
    {
        _550 = ceil(0.5 + ((vec4(TextureSize, 1.0 / TextureSize)).x / min(min((signalResolution), (signalResolutionI)), (signalResolutionQ))));
    }
    else
    {
        _550 = ceil(0.5 + ((vec4(TextureSize, 1.0 / TextureSize)).x / (signalResolution)));
    }
    vec3 _559;
    if (_39)
    {
        float _74 = -_550;
        vec3 _560;
        _560 = vec3(0.0);
        for (float _557 = _74; _557 < (_550 + 2.0); )
        {
            float _88 = _29 - _557;
            vec4 _107 = texture2D(Texture, vec2(RA_VARYING_0.x - (_88 * (vec4(TextureSize, 1.0 / TextureSize)).z), RA_VARYING_0.y));
            float _116 = (signalResolution) / (vec4(TextureSize, 1.0 / TextureSize)).x;
            float _117 = 3.1415927410125732421875 * _116;
            float _119 = abs(_88);
            float _120 = _119 + 0.5;
            float _127 = 1.0 / _116;
            float _129 = _117 * min(_120, _127);
            float _157 = _119 - 0.5;
            float _173 = _117 * min(max(_157, (-1.0) / _116), _127);
            float _210 = (signalResolutionI) / (vec4(TextureSize, 1.0 / TextureSize)).x;
            float _211 = 3.1415927410125732421875 * _210;
            float _220 = 1.0 / _210;
            float _222 = _211 * min(_120, _220);
            float _265 = _211 * min(max(_157, (-1.0) / _210), _220);
            float _301 = (signalResolutionQ) / (vec4(TextureSize, 1.0 / TextureSize)).x;
            float _302 = 3.1415927410125732421875 * _301;
            float _311 = 1.0 / _301;
            float _313 = _302 * min(_120, _311);
            float _356 = _302 * min(max(_157, (-1.0) / _301), _311);
            _560 += vec3(_107.x * ((((_129 + sin(_129)) - _173) - sin(_173)) * 0.15915493667125701904296875), _107.y * ((((_222 + sin(_222)) - _265) - sin(_265)) * 0.15915493667125701904296875), _107.z * ((((_313 + sin(_313)) - _356) - sin(_356)) * 0.15915493667125701904296875));
            _557 += 1.0;
            continue;
        }
        _559 = _560;
    }
    else
    {
        float _393 = -_550;
        vec3 _555;
        _555 = vec3(0.0);
        for (float _551 = _393; _551 < (_550 + 2.0); )
        {
            float _405 = _29 - _551;
            float _424 = (signalResolution) / (vec4(TextureSize, 1.0 / TextureSize)).x;
            float _425 = 3.1415927410125732421875 * _424;
            float _427 = abs(_405);
            float _434 = 1.0 / _424;
            float _436 = _425 * min(_427 + 0.5, _434);
            float _479 = _425 * min(max(_427 - 0.5, (-1.0) / _424), _434);
            _555 += (texture2D(Texture, vec2(RA_VARYING_0.x - (_405 * (vec4(TextureSize, 1.0 / TextureSize)).z), RA_VARYING_0.y)).xyz * ((((_436 + sin(_436)) - _479) - sin(_479)) * 0.15915493667125701904296875));
            _551 += 1.0;
            continue;
        }
        _559 = _555;
    }
    vec3 _561;
    if (_39)
    {
        _561 = clamp(_559 * mat3(vec3(1.0), vec3(0.9563000202178955078125, -0.2721000015735626220703125, -1.10699999332427978515625), vec3(0.620999991893768310546875, -0.64740002155303955078125, 1.70459997653961181640625)), vec3(0.0), vec3(1.0));
    }
    else
    {
        _561 = clamp(_559, vec3(0.0), vec3(1.0));
    }
    gl_FragData[0] = vec4(_561, 1.0);
}


#endif
