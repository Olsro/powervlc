// Generated from crt/shaders/crt-slangtest/sinc.slang. See slang/upstream for licence/source.
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
    float _57 = (RA_VARYING_0.x * (vec4(TextureSize, 1.0 / TextureSize)).x) - 0.5;
    float _60 = fract(_57);
    vec2 _73 = vec2((floor(_57) + 0.5) * (vec4(TextureSize, 1.0 / TextureSize)).z, RA_VARYING_0.y);
    float _148 = max(abs(_60 + 1.0) * 3.1415927410125732421875, 9.9999997473787516355514526367188e-05);
    float _152 = 0.5 * _148;
    float _174 = max(abs(_60) * 3.1415927410125732421875, 9.9999997473787516355514526367188e-05);
    float _178 = 0.5 * _174;
    float _200 = max(abs(_60 - 1.0) * 3.1415927410125732421875, 9.9999997473787516355514526367188e-05);
    float _204 = 0.5 * _200;
    float _226 = max(abs(_60 - 2.0) * 3.1415927410125732421875, 9.9999997473787516355514526367188e-05);
    float _230 = 0.5 * _226;
    vec3 _129 = (((textureLodOffset(Texture, _73, 0.0, ivec2(-1, 0)).xyz * ((sin(_148) / _148) * (sin(_152) / _152))) + (textureLodOffset(Texture, _73, 0.0, ivec2(0)).xyz * ((sin(_174) / _174) * (sin(_178) / _178)))) + (textureLodOffset(Texture, _73, 0.0, ivec2(1, 0)).xyz * ((sin(_200) / _200) * (sin(_204) / _204)))) + (textureLodOffset(Texture, _73, 0.0, ivec2(2, 0)).xyz * ((sin(_226) / _226) * (sin(_230) / _230)));
    FragColor = vec4(_129, 1.0);
}


#endif
