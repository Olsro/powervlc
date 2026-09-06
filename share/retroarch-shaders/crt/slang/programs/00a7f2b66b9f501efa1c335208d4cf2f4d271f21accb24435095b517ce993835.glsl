// Generated from crt/shaders/newpixie-mini/newpixie-mini.slang. See slang/upstream for licence/source.
#version 120
#pragma parameter curvature "Curvature" 2.0 0.0001 4.0 0.25
#pragma parameter vignette "Vignette" 1.0 0.0 1.0 0.05
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
    gl_Position = (MVPMatrix) * vec4(VertexCoord.x, 1.0 - VertexCoord.y, VertexCoord.z, VertexCoord.w);
    RA_VARYING_0 = TexCoord;
}


#endif
#ifdef FRAGMENT

uniform vec2 OutputSize;
uniform float curvature;
uniform float vignette;
struct Push
{
    vec4 OutputSize;
    float curvature;
    float vignette;
};



uniform sampler2D Texture;

varying vec2 RA_VARYING_0;

void main()
{
    vec2 _377 = ((RA_VARYING_0 - vec2(0.5)) * vec2(0.925000011920928955078125, 1.0950000286102294921875)) * (curvature);
    float _386 = _377.x * (1.0 + pow(abs(_377.y) * 0.25, 2.0));
    vec2 _160 = mix((((vec2(_386, _377.y * (1.0 + pow(abs(_386) * 0.3333333432674407958984375, 2.0))) / vec2((curvature))) + vec2(0.5)) * 0.920000016689300537109375) + vec2(0.039999999105930328369140625), RA_VARYING_0, vec2(0.4000000059604644775390625));
    vec2 _175 = (_160 * 1.10099995136260986328125) + vec2(-0.0475000031292438507080078125, -0.051500000059604644775390625);
    vec2 _184 = RA_VARYING_0 * (vec4(OutputSize, 1.0 / OutputSize)).xy;
    float _201 = ((sin(_184.y * 1.5) / (vec4(OutputSize, 1.0 / OutputSize)).x) * 0.25) + _175.x;
    float _205 = _175.y;
    vec2 _416 = (vec2(_201 + 0.000899999984540045261383056640625, _205 + 0.000899999984540045261383056640625) * vec2(1.02499997615814208984375, 0.920000016689300537109375)) + vec2(-0.012500000186264514923095703125, 0.039999999105930328369140625);
    vec2 _435 = (vec2(_201, _205 - 0.0010999999940395355224609375) * vec2(1.02499997615814208984375, 0.920000016689300537109375)) + vec2(-0.012500000186264514923095703125, 0.039999999105930328369140625);
    vec2 _454 = (vec2(_201 - 0.00150000001303851604461669921875, _205) * vec2(1.02499997615814208984375, 0.920000016689300537109375)) + vec2(-0.012500000186264514923095703125, 0.039999999105930328369140625);
    vec3 _537 = vec3((pow(abs(texture2D(Texture, vec2(_416.x, 1.0 - _416.y)).xyz), vec3(2.2000000476837158203125)) * vec3(1.25)).x + 0.0199999995529651641845703125, (pow(abs(texture2D(Texture, vec2(_435.x, 1.0 - _435.y)).xyz), vec3(2.2000000476837158203125)) * vec3(1.25)).y + 0.0199999995529651641845703125, (pow(abs(texture2D(Texture, vec2(_454.x, 1.0 - _454.y)).xyz), vec3(2.2000000476837158203125)) * vec3(1.25)).z + 0.0199999995529651641845703125);
    vec3 _273 = _537 * _537;
    float _296 = _160.x;
    float _299 = _160.y;
    vec3 _473 = max(vec3(0.0), (((clamp((_537 + _273) + (((_273 * _537) * _537) * _537), vec3(0.0), vec3(10.0)) * (1.2999999523162841796875 * pow((1.0 - (0.9900000095367431640625 * (vignette))) + ((((4.0 * _296) * _299) * (1.0 - _296)) * (1.0 - _299)), 0.5))) * vec3(pow(clamp(0.3499999940395355224609375 + (0.180000007152557373046875 * sin((_299 * (vec4(OutputSize, 1.0 / OutputSize)).y) * 1.5)), 0.0, 1.0), 0.89999997615814208984375))) * (1.0 - (0.23000000417232513427734375 * clamp(mod(_184.x, 3.0) * 0.5, 0.0, 1.0)))) - vec3(0.0040000001899898052215576171875));
    vec3 _476 = _473 * 6.19999980926513671875;
    gl_FragData[0] = vec4((_473 * (_476 + vec3(0.5))) / ((_473 * (_476 + vec3(1.7000000476837158203125))) + vec3(0.0599999986588954925537109375)), 1.0);
}


#endif
