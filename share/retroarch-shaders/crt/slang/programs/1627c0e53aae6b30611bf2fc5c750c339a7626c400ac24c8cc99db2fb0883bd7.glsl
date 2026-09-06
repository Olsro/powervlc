// Generated from crt/shaders/newpixie/blur_vert.slang. See slang/upstream for licence/source.
#version 120
#pragma parameter blur_y "Vertical Blur" 1.0 0.0 5.0 0.25
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

uniform vec2 OutputSize;
uniform float blur_y;
struct Push
{
    vec4 OutputSize;
    float blur_y;
};



uniform sampler2D Texture;

varying vec2 RA_VARYING_0;

void main()
{
    vec2 _27 = vec2(0.0, (blur_y)) * (vec4(OutputSize, 1.0 / OutputSize)).zw;
    float _52 = _27.x;
    float _53 = 4.0 * _52;
    float _59 = _27.y;
    float _60 = 4.0 * _59;
    float _74 = 3.0 * _52;
    float _80 = 3.0 * _59;
    float _94 = 2.0 * _52;
    float _100 = 2.0 * _59;
    gl_FragData[0] = ((((((((texture2D(Texture, RA_VARYING_0) * 0.2270270287990570068359375) + (texture2D(Texture, vec2(RA_VARYING_0.x - _53, RA_VARYING_0.y - _60)) * 0.01621621660888195037841796875)) + (texture2D(Texture, vec2(RA_VARYING_0.x - _74, RA_VARYING_0.y - _80)) * 0.0540540553629398345947265625)) + (texture2D(Texture, vec2(RA_VARYING_0.x - _94, RA_VARYING_0.y - _100)) * 0.12162162363529205322265625)) + (texture2D(Texture, vec2(RA_VARYING_0.x - _52, RA_VARYING_0.y - _59)) * 0.1945945918560028076171875)) + (texture2D(Texture, vec2(RA_VARYING_0.x + _52, RA_VARYING_0.y + _59)) * 0.1945945918560028076171875)) + (texture2D(Texture, vec2(RA_VARYING_0.x + _94, RA_VARYING_0.y + _100)) * 0.12162162363529205322265625)) + (texture2D(Texture, vec2(RA_VARYING_0.x + _74, RA_VARYING_0.y + _80)) * 0.0540540553629398345947265625)) + (texture2D(Texture, vec2(RA_VARYING_0.x + _53, RA_VARYING_0.y + _60)) * 0.01621621660888195037841796875);
}


#endif
