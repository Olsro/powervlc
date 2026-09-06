// Generated from crt/shaders/crt-slangtest/cubic.slang. See slang/upstream for licence/source.
#version 130

#ifdef VERTEX

uniform mat4 MVPMatrix;
struct UBO1
{
    mat4 MVP;
};



in vec4 VertexCoord;
out vec2 RA_VARYING_0;
in vec2 TexCoord;

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

in vec2 RA_VARYING_0;
out vec4 FragColor;

void main()
{
    float _28 = (RA_VARYING_0.x * (vec4(TextureSize, 1.0 / TextureSize)).x) - 0.5;
    float _31 = fract(_28);
    vec2 _44 = vec2((floor(_28) + 0.5) * (vec4(TextureSize, 1.0 / TextureSize)).z, RA_VARYING_0.y);
    vec3 _59 = textureLodOffset(Texture, _44, 0.0, ivec2(-1, 0)).xyz;
    vec3 _65 = textureLodOffset(Texture, _44, 0.0, ivec2(0)).xyz;
    vec3 _72 = textureLodOffset(Texture, _44, 0.0, ivec2(1, 0)).xyz;
    vec3 _79 = textureLodOffset(Texture, _44, 0.0, ivec2(2, 0)).xyz;
    float _83 = _31 * _31;
    FragColor = vec4(((_65 + (((_72 - _59) * 0.5) * _31)) + ((((_59 - (_65 * 2.5)) + (_72 * 2.0)) - (_79 * 0.5)) * _83)) + ((((_79 - _59) + ((_65 - _72) * 3.0)) * 0.5) * (_83 * _31)), 1.0);
}


#endif
