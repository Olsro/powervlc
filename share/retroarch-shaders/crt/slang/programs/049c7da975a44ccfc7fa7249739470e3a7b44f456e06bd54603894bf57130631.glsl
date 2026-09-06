// Generated from crt/shaders/crt-super-xbr/custom-bicubic-x.slang. See slang/upstream for licence/source.
#version 120

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
varying vec4 RA_VARYING_1;
varying vec4 RA_VARYING_2;

void main()
{
    gl_Position = (MVPMatrix) * VertexCoord;
    RA_VARYING_0 = (TexCoord * 1.00010001659393310546875) - (vec2(0.5, 0.0) * vec2((vec4(TextureSize, 1.0 / TextureSize)).z, (vec4(TextureSize, 1.0 / TextureSize)).w));
    RA_VARYING_1 = RA_VARYING_0.xyxy + vec4(-(vec4(TextureSize, 1.0 / TextureSize)).z, 0.0, 0.0, 0.0);
    RA_VARYING_2 = RA_VARYING_0.xyxy + vec4((vec4(TextureSize, 1.0 / TextureSize)).z, 0.0, 2.0 * (vec4(TextureSize, 1.0 / TextureSize)).z, 0.0);
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
varying vec4 RA_VARYING_1;
varying vec4 RA_VARYING_2;

void main()
{
    vec2 _25 = fract(RA_VARYING_0 * (vec4(TextureSize, 1.0 / TextureSize)).xy);
    float _64 = _25.x;
    float _67 = _64 * _64;
    gl_FragData[0] = vec4(mat4x3(vec3(texture2D(Texture, RA_VARYING_1.xy).xyz), vec3(texture2D(Texture, RA_VARYING_1.zw).xyz), vec3(texture2D(Texture, RA_VARYING_2.xy).xyz), vec3(texture2D(Texture, RA_VARYING_2.zw).xyz)) * (vec4(_67 * _64, _67, _64, 1.0) * mat4(vec4(-1.0, 2.0, -1.0, 0.0), vec4(1.0, -2.0, 0.0, 1.0), vec4(-1.0, 1.0, 1.0, 0.0), vec4(1.0, -1.0, 0.0, 0.0))), 1.0);
}


#endif
