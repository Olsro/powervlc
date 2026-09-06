// Generated from crt/shaders/glow/blur_horiz.slang. See slang/upstream for licence/source.
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
    float _27 = 4.0 * (vec4(TextureSize, 1.0 / TextureSize)).z;
    vec3 _89;
    float _90;
    _90 = 0.0;
    _89 = vec3(0.0);
    for (int _88 = -4; _88 <= 4; )
    {
        float _44 = float(_88);
        float _49 = exp(((-0.3499999940395355224609375) * _44) * _44);
        _90 += _49;
        _89 += (texture2D(Texture, RA_VARYING_0 + vec2(_44 * _27, 0.0)).xyz * _49);
        _88++;
        continue;
    }
    gl_FragData[0] = vec4(_89 / vec3(_90), 1.0);
}


#endif
