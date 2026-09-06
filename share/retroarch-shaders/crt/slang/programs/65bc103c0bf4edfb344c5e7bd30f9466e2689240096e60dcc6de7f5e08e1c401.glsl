// Generated from crt/shaders/glow/lanczos_horiz.slang. See slang/upstream for licence/source.
#version 120

#ifdef VERTEX

uniform mat4 MVPMatrix;
uniform vec2 TextureSize;
struct UBO
{
    mat4 MVP;
    vec4 SourceSize;
};



attribute vec4 VertexCoord;
varying vec2 RA_VARYING_0;
attribute vec2 TexCoord;
varying float RA_VARYING_1;
varying float RA_VARYING_2;

void main()
{
    gl_Position = (MVPMatrix) * VertexCoord;
    RA_VARYING_0 = TexCoord;
    RA_VARYING_1 = RA_VARYING_0.x * (vec4(TextureSize, 1.0 / TextureSize)).x;
    RA_VARYING_2 = (vec4(TextureSize, 1.0 / TextureSize)).z;
}


#endif
#ifdef FRAGMENT

uniform vec2 TextureSize;
struct UBO
{
    vec4 SourceSize;
};



uniform sampler2D Texture;

varying float RA_VARYING_1;
varying vec2 RA_VARYING_0;
varying float RA_VARYING_2;

void main()
{
    float _34 = floor(RA_VARYING_1);
    float _42 = (RA_VARYING_1 - _34) - 0.5;
    vec2 _66 = vec2((_34 + 0.5) * (vec4(TextureSize, 1.0 / TextureSize)).z, RA_VARYING_0.y);
    vec3 _179;
    _179 = vec3(0.0);
    vec3 _192;
    for (int _178 = -2; _178 <= 2; _179 = _192, _178++)
    {
        float _86 = float(_178);
        float _87 = _42 - _86;
        float _89 = abs(_87);
        if (_89 < 2.0)
        {
            float _181;
            do
            {
                if (_89 < 0.001000000047497451305389404296875)
                {
                    _181 = 1.0;
                    break;
                }
                float _153 = _87 * 3.1415927410125732421875;
                _181 = sin(_153) / _153;
                break;
            } while(false);
            float _183;
            do
            {
                if (abs(0.5 * _87) < 0.001000000047497451305389404296875)
                {
                    _183 = 1.0;
                    break;
                }
                float _171 = _87 * 1.57079637050628662109375;
                _183 = sin(_171) / _171;
                break;
            } while(false);
            _192 = _179 + (texture2D(Texture, _66 + vec2(_86 * RA_VARYING_2, 0.0)).xyz * (_181 * _183));
        }
        else
        {
            _192 = _179;
        }
    }
    gl_FragData[0] = vec4(_179, 1.0);
}


#endif
