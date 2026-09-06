// Generated from crt/shaders/crt-easymode-halation/blur_vert.slang. See slang/upstream for licence/source.
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
struct Push
{
    vec4 SourceSize;
};



uniform sampler2D Texture;

varying vec2 RA_VARYING_0;

void main()
{
    vec3 _90;
    float _91;
    _91 = 0.0;
    _90 = vec3(0.0);
    for (int _89 = -4; _89 <= 4; )
    {
        float _41 = float(_89);
        float _46 = exp(((-0.3499999940395355224609375) * _41) * _41);
        _91 += _46;
        _90 += (texture2D(Texture, RA_VARYING_0 + vec2(0.0, _41 * (vec4(TextureSize, 1.0 / TextureSize)).w)).xyz * _46);
        _89++;
        continue;
    }
    gl_FragData[0] = vec4(_90 / vec3(_91), 1.0);
}


#endif
