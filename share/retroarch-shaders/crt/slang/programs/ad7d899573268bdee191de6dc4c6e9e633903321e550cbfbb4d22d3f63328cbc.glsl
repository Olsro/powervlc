// Generated from crt/shaders/crt-beans/cubic_downsample.slang. See slang/upstream for licence/source.
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
#extension GL_ARB_shader_texture_lod : require

uniform vec2 TextureSize;
struct Push
{
    vec4 SourceSize;
};



uniform sampler2D Texture;

varying vec2 RA_VARYING_0;

void main()
{
    vec2 _23 = RA_VARYING_0 * (vec4(TextureSize, 1.0 / TextureSize)).xy;
    vec2 _29 = floor(_23 - vec2(0.5));
    vec2 _35 = _23 - (_29 + vec2(0.5));
    vec2 _38 = _35 + vec2(1.0);
    vec2 _65 = (_35 * _35) * ((abs(_35) * 0.25) - vec2(0.75));
    vec2 _72 = _35 - vec2(1.0);
    vec2 _90 = _35 - vec2(2.0);
    vec2 _100 = (_90 * _90) * ((abs(_90) * 0.25) - vec2(0.75));
    vec2 _227 = ((_38 * _38) * ((abs(_38) * 0.25) - vec2(0.75))) + _65;
    vec2 _106 = vec2(2.0) + _227;
    vec2 _228 = ((_72 * _72) * ((abs(_72) * 0.25) - vec2(0.75))) + _100;
    vec2 _110 = vec2(2.0) + _228;
    vec2 _122 = ((_29 + vec2(-0.5)) + ((_65 + vec2(1.0)) / _106)) * (vec4(TextureSize, 1.0 / TextureSize)).zw;
    vec2 _134 = ((_29 + vec2(1.5)) + ((_100 + vec2(1.0)) / _110)) * (vec4(TextureSize, 1.0 / TextureSize)).zw;
    float _156 = _106.x;
    float _167 = _110.x;
    vec2 _203 = vec2(4.0) + (_227 + _228);
    gl_FragData[0] = vec4(((((texture2DLod(Texture, _122, 0.0).xyz * _156) + (texture2DLod(Texture, vec2(_134.x, _122.y), 0.0).xyz * _167)) * _106.y) + (((texture2DLod(Texture, vec2(_122.x, _134.y), 0.0).xyz * _156) + (texture2DLod(Texture, _134, 0.0).xyz * _167)) * _110.y)) / vec3(_203.x * _203.y), 1.0);
}


#endif
