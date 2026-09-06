// Generated from crt/shaders/crt-interlaced-halation/crt-interlaced-halation-pass1.slang. See slang/upstream for licence/source.
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
varying vec4 RA_VARYING_3;

void main()
{
    gl_Position = (MVPMatrix) * VertexCoord;
    RA_VARYING_0 = TexCoord;
    RA_VARYING_1 = RA_VARYING_0.xxxy + vec4((-4.0) * (vec4(TextureSize, 1.0 / TextureSize)).z, (-3.0) * (vec4(TextureSize, 1.0 / TextureSize)).z, (-2.0) * (vec4(TextureSize, 1.0 / TextureSize)).z, 0.0);
    RA_VARYING_2 = RA_VARYING_0.xxxy + vec4(-(vec4(TextureSize, 1.0 / TextureSize)).z, 0.0, (vec4(TextureSize, 1.0 / TextureSize)).z, 0.0);
    RA_VARYING_3 = RA_VARYING_0.xxxy + vec4(2.0 * (vec4(TextureSize, 1.0 / TextureSize)).z, 3.0 * (vec4(TextureSize, 1.0 / TextureSize)).z, 4.0 * (vec4(TextureSize, 1.0 / TextureSize)).z, 0.0);
}


#endif
#ifdef FRAGMENT


uniform sampler2D Texture;

varying vec4 RA_VARYING_1;
varying vec4 RA_VARYING_2;
varying vec2 RA_VARYING_0;
varying vec4 RA_VARYING_3;

void main()
{
    gl_FragData[0] = pow((((((((((pow(texture2D(Texture, RA_VARYING_1.xw), vec4(2.2000000476837158203125)) * vec4(0.0183156393468379974365234375)) + (pow(texture2D(Texture, RA_VARYING_1.yw), vec4(2.2000000476837158203125)) * vec4(0.1053992211818695068359375))) + (pow(texture2D(Texture, RA_VARYING_1.zw), vec4(2.2000000476837158203125)) * vec4(0.367879450321197509765625))) + (pow(texture2D(Texture, RA_VARYING_2.xw), vec4(2.2000000476837158203125)) * vec4(0.778800785541534423828125))) + pow(texture2D(Texture, RA_VARYING_0), vec4(2.2000000476837158203125))) + (pow(texture2D(Texture, RA_VARYING_2.zw), vec4(2.2000000476837158203125)) * vec4(0.778800785541534423828125))) + (pow(texture2D(Texture, RA_VARYING_3.xw), vec4(2.2000000476837158203125)) * vec4(0.367879450321197509765625))) + (pow(texture2D(Texture, RA_VARYING_3.yw), vec4(2.2000000476837158203125)) * vec4(0.1053992211818695068359375))) + (pow(texture2D(Texture, RA_VARYING_3.zw), vec4(2.2000000476837158203125)) * vec4(0.0183156393468379974365234375))) * vec4(0.2824228107929229736328125), vec4(0.4545454680919647216796875));
}


#endif
