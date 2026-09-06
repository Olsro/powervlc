// Generated from crt/shaders/crt-beans/bilinear_upsample.slang. See slang/upstream for licence/source.
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


uniform sampler2D Texture;

varying vec2 RA_VARYING_0;

void main()
{
    vec4 _19 = texture2D(Texture, RA_VARYING_0);
    gl_FragData[0].x = _19.x;
    gl_FragData[0].y = _19.y;
    gl_FragData[0].z = _19.z;
}


#endif
