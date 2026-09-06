// Generated from interpolation/shaders/EWA-Cubics.slang. See slang/upstream for licence/source.
#version 120
#pragma parameter CubicMode "Cubic (0=Robidoux/Smooth; 1=Mitchell/Medium; 2=RobidouxSharp)" 0.00 0.00 2.00 1.00
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

uniform float CubicMode;
uniform vec2 TextureSize;
struct Push
{
    vec4 SourceSize;
    float CubicMode;
};



uniform sampler2D Texture;

varying vec2 RA_VARYING_0;

void main()
{
    float _384;
    if ((CubicMode) < 0.5)
    {
        _384 = 0.3782157599925994873046875;
    }
    else
    {
        _384 = ((CubicMode) < 1.5) ? 0.3333333432674407958984375 : 0.26201450824737548828125;
    }
    float _293 = 1.0 - _384;
    vec2 _175 = RA_VARYING_0 * (vec4(TextureSize, 1.0 / TextureSize)).xy;
    vec2 _181 = floor(_175 - vec2(0.5)) + vec2(0.5);
    float _387;
    vec3 _388;
    _388 = vec3(0.0);
    _387 = 0.0;
    vec3 _403;
    float _405;
    for (int _386 = -1; _386 <= 2; _388 = _403, _387 = _405, _386++)
    {
        _405 = _387;
        _403 = _388;
        vec3 _418;
        float _419;
        for (int _390 = -1; _390 <= 2; _405 = _419, _403 = _418, _390++)
        {
            vec2 _212 = _181 + vec2(float(_390), float(_386));
            float _219 = length(_175 - _212);
            if (_219 >= 2.0)
            {
                _419 = _405;
                _418 = _403;
                continue;
            }
            float _400;
            do
            {
                float _304 = abs(_219);
                float _307 = _304 * _304;
                float _310 = _307 * _304;
                if (_304 < 1.0)
                {
                    float _318 = _293 * 3.0;
                    _400 = (((((12.0 - (9.0 * _384)) - _318) * _310) + ((((-18.0) + (12.0 * _384)) + _318) * _307)) + (6.0 - (2.0 * _384))) * 0.16666667163372039794921875;
                    break;
                }
                else
                {
                    if (_304 < 2.0)
                    {
                        _400 = ((((((-_384) - (_293 * 3.0)) * _310) + (((6.0 * _384) + (_293 * 15.0)) * _307)) + ((((-12.0) * _384) - (_293 * 24.0)) * _304)) + ((8.0 * _384) + (_293 * 12.0))) * 0.16666667163372039794921875;
                        break;
                    }
                }
                _400 = 0.0;
                break;
            } while(false);
            if (_400 == 0.0)
            {
                _419 = _405;
                _418 = _403;
                continue;
            }
            _419 = _405 + _400;
            _418 = _403 + (texture2D(Texture, _212 * (vec4(TextureSize, 1.0 / TextureSize)).zw).xyz * _400);
        }
    }
    vec3 _389;
    if (_387 > 0.0)
    {
        _389 = _388 / vec3(_387);
    }
    else
    {
        _389 = _388;
    }
    gl_FragData[0] = vec4(_389, 1.0);
}


#endif
