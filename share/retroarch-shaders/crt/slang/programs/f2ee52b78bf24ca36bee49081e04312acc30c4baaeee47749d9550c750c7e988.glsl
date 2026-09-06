// Generated from crt/shaders/glow/blur_vert.slang. See slang/upstream for licence/source.
#version 120

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
struct UBO
{
    vec4 SourceSize;
};



uniform sampler2D Texture;

varying vec2 RA_VARYING_0;

void main()
{
    vec3 _87;
    float _88;
    _88 = 0.0;
    _87 = vec3(0.0);
    for (int _86 = -4; _86 <= 4; )
    {
        float _42 = float(_86);
        float _47 = exp(((-0.3499999940395355224609375) * _42) * _42);
        _88 += _47;
        _87 += (texture2D(Texture, RA_VARYING_0 + vec2(0.0, _42 * (vec4(TextureSize, 1.0 / TextureSize)).w)).xyz * _47);
        _86++;
        continue;
    }
    gl_FragData[0] = vec4(_87 / vec3(_88), 1.0);
}


#endif
