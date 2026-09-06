// Generated from crt/shaders/glow/gauss_horiz.slang. See slang/upstream for licence/source.
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
    float _12 = floor(RA_VARYING_1);
    float _20 = (RA_VARYING_1 - _12) - 0.5;
    vec2 _44 = vec2((_12 + 0.5) * (vec4(TextureSize, 1.0 / TextureSize)).z, RA_VARYING_0.y);
    vec3 _110;
    _110 = vec3(0.0);
    for (int _109 = -2; _109 <= 2; )
    {
        float _65 = float(_109);
        float _66 = _20 - _65;
        _110 += (texture2D(Texture, _44 + vec2(_65 * RA_VARYING_2, 0.0)).xyz * (exp((((-0.5) * _66) * _66) * 4.0) * 0.7599999904632568359375));
        _109++;
        continue;
    }
    gl_FragData[0] = vec4(_110, 1.0);
}


#endif
