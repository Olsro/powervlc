// Generated from crt/shaders/crt-blurPi.slang. See slang/upstream for licence/source.
#version 120
#pragma parameter scanlineGain "scanlineGain" 	0.30 	0.0 	1.0 	0.05
#pragma parameter rgbExtraGain "rgbExtraGain" 	0.10 	0.0 	1.0 	0.05
#pragma parameter blurGain "blurGain" 			0.15 	0.0 	1.0 	0.05
#pragma parameter blurRadius "blurRadius" 		1.5 	0.1 	3.0 	0.1
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
varying vec2 RA_VARYING_1;

void main()
{
    gl_Position = (MVPMatrix) * VertexCoord;
    RA_VARYING_0 = TexCoord;
    RA_VARYING_1 = (vec4(TextureSize, 1.0 / TextureSize)).zw;
}


#endif
#ifdef FRAGMENT

uniform vec2 OutputSize;
uniform float blurGain;
uniform float blurRadius;
uniform float rgbExtraGain;
uniform float scanlineGain;
struct Push
{
    vec4 OutputSize;
    float scanlineGain;
    float rgbExtraGain;
    float blurGain;
    float blurRadius;
};



uniform sampler2D Texture;

varying vec2 RA_VARYING_1;
varying vec2 RA_VARYING_0;

void main()
{
    vec2 _23 = RA_VARYING_1 * (blurRadius);
    float _53 = 0.25 * (blurGain);
    float _58 = _23.x;
    float _102 = mod(float(int(RA_VARYING_0.y * (vec4(OutputSize, 1.0 / OutputSize)).y)), 2.0);
    gl_FragData[0] = ((((texture2D(Texture, RA_VARYING_0) * ((1.0 - (0.75 * (blurGain))) * (1.0 + (rgbExtraGain)))) + (texture2D(Texture, RA_VARYING_0 + vec2(-_58, 0.0)) * _53)) + (texture2D(Texture, RA_VARYING_0 + vec2(_58, 0.0)) * _53)) + (texture2D(Texture, RA_VARYING_0 + vec2(0.0, _23.y)) * _53)) * mix(1.0, _102 * _102, (scanlineGain));
}


#endif
