// Generated from crt/shaders/crt-consumer/reflect_blur.slang. See slang/upstream for licence/source.
#version 120
#pragma parameter dummy1 "[ NTSC ]" 0.0 0.0 0.0 0.0
#ifdef VERTEX

uniform mat4 MVPMatrix;
uniform vec2 TextureSize;
struct UBO
{
    mat4 MVP;
};



struct Push
{
    vec4 SourceSize;
};



attribute vec4 VertexCoord;
varying vec2 RA_VARYING_0;
attribute vec2 TexCoord;
varying vec2 RA_VARYING_1;
varying vec2 RA_VARYING_2;

void main()
{
    gl_Position = (MVPMatrix) * VertexCoord;
    RA_VARYING_0 = TexCoord;
    RA_VARYING_1 = RA_VARYING_0 * (vec4(TextureSize, 1.0 / TextureSize)).xy;
    RA_VARYING_2 = vec2(1.0) / (vec4(TextureSize, 1.0 / TextureSize)).xy;
}


#endif
#ifdef FRAGMENT


uniform sampler2D Texture;

varying vec2 RA_VARYING_0;
varying vec2 RA_VARYING_2;

void main()
{
    vec2 _307 = (RA_VARYING_0 * 2.0) - vec2(1.0);
    float _309 = _307.y;
    float _316 = _307.x;
    vec2 _328 = ((_307 * vec2(1.0 + ((_309 * _309) * (-0.02999999932944774627685546875)), 1.0 + ((_316 * _316) * 0.02999999932944774627685546875))) * 0.5) + vec2(0.5);
    float _167 = _328.x;
    float _169 = (_167 * 2.0) - 1.0;
    float _172 = _169 * _169;
    float _175 = _328.y;
    float _177 = (_175 * 2.0) - 1.0;
    float _180 = _177 * _177;
    float _183 = mix(0.0, 0.0199999995529651641845703125, _172);
    float _186 = mix(0.0, 0.0199999995529651641845703125, _180);
    float _191 = mix(1.0, 0.980000019073486328125, _172);
    float _194 = mix(1.0, 0.980000019073486328125, _180);
    vec2 _201 = vec2(RA_VARYING_2.x, 0.0);
    vec2 _205 = vec2(0.0, RA_VARYING_2.y);
    float _501;
    do
    {
        float _367 = _191 - _183;
        if (_167 < _183)
        {
            float _378 = mod(_183 - _167, _367 * 2.0);
            float _500;
            if (_378 <= _367)
            {
                _500 = _183 + _378;
            }
            else
            {
                _500 = _191 - (_378 - _367);
            }
            _501 = _500;
            break;
        }
        else
        {
            if (_167 > _191)
            {
                float _405 = mod(_167 - _191, _367 * 2.0);
                float _499;
                if (_405 <= _367)
                {
                    _499 = _191 - _405;
                }
                else
                {
                    _499 = _183 + (_405 - _367);
                }
                _501 = _499;
                break;
            }
        }
        _501 = _167;
        break;
    } while(false);
    float _504;
    do
    {
        float _440 = _194 - _186;
        if (_175 < _186)
        {
            float _451 = mod(_186 - _175, _440 * 2.0);
            float _503;
            if (_451 <= _440)
            {
                _503 = _186 + _451;
            }
            else
            {
                _503 = _194 - (_451 - _440);
            }
            _504 = _503;
            break;
        }
        else
        {
            if (_175 > _194)
            {
                float _478 = mod(_175 - _194, _440 * 2.0);
                float _502;
                if (_478 <= _440)
                {
                    _502 = _194 - _478;
                }
                else
                {
                    _502 = _186 + (_478 - _440);
                }
                _504 = _502;
                break;
            }
        }
        _504 = _175;
        break;
    } while(false);
    vec2 _352 = vec2(_501, _504);
    int _505;
    float _506;
    vec4 _513;
    _513 = vec4(0.0);
    _506 = 0.0;
    _505 = -2;
    vec4 _540;
    float _541;
    for (; _505 < 3; _513 = _540, _506 = _541, _505++)
    {
        _541 = _506;
        _540 = _513;
        for (int _520 = -2; _520 < 3; )
        {
            float _241 = float(_505);
            float _248 = exp(((-0.100000001490116119384765625) * _241) * _241);
            _541 += _248;
            _540 += (texture2D(Texture, (_352 + (_201 * _241)) + (_205 * float(_520))) * _248);
            _520++;
            continue;
        }
    }
    gl_FragData[0] = (_513 / vec4(_506)) * 1.25;
}


#endif
