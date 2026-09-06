// Generated from crt/shaders/crt-beans/linearize.slang. See slang/upstream for licence/source.
#version 130

#ifdef VERTEX

uniform mat4 MVPMatrix;
struct UBO
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
struct Push
{
    vec4 SourceSize;
};



uniform sampler2D Texture;

in vec2 RA_VARYING_0;
out vec4 FragColor;

void main()
{
    vec3 _89 = pow(clamp(texelFetch(Texture, ivec2(int(floor(RA_VARYING_0.x * (vec4(TextureSize, 1.0 / TextureSize)).x)), int(floor(RA_VARYING_0.y * (vec4(TextureSize, 1.0 / TextureSize)).y))), 0).xyz, vec3(0.0), vec3(1.0)), vec3(2.400000095367431640625));
    FragColor.x = _89.x;
    FragColor.y = _89.y;
    FragColor.z = _89.z;
}


#endif
