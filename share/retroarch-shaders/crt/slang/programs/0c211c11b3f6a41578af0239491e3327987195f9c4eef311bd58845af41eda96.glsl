// Generated from crt/shaders/torridgristle/ScanlineSimple.slang. See slang/upstream for licence/source.
#version 120
#pragma parameter ScanlineSize "Scanline Size" 3.0 2.0 32.0 1.0
#pragma parameter YIQAmount "YIQ Amount" 1.0 0.0 1.0 0.05
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
uniform float ScanlineSize;
uniform float YIQAmount;
struct Push
{
    vec4 OutputSize;
    float ScanlineSize;
    float YIQAmount;
};



uniform sampler2D Texture;

varying vec2 RA_VARYING_0;

void main()
{
    vec4 _20 = texture2D(Texture, RA_VARYING_0);
    vec3 _21 = _20.xyz;
    float _27 = _20.x;
    float _30 = _20.y;
    float _36 = _20.z;
    float _38 = max(max(_27, _30), max(_30, _36));
    float _58 = mix(_38, ((0.2989999949932098388671875 * _27) + (0.58700001239776611328125 * _30)) + (0.114000000059604644775390625 * _36), _38);
    float _100 = clamp(sqrt(1.0 - pow(abs((mod(RA_VARYING_0.y * (vec4(OutputSize, 1.0 / OutputSize)).y, (ScanlineSize)) / (ScanlineSize)) - 0.5) * 2.0, 2.0)) - (1.0 - _58), 0.0, 1.0) / _58;
    vec3 _114 = _21 * mat3(vec3(0.2989999949932098388671875, 0.595715999603271484375, 0.211456000804901123046875), vec3(0.58700001239776611328125, -0.2744530141353607177734375, -0.52259099483489990234375), vec3(0.114000000059604644775390625, -0.3212629854679107666015625, 0.311134994029998779296875));
    _114.x = _114.x * _100;
    gl_FragData[0] = vec4(mix(_21 * _100, (_114 * mat3(vec3(1.0), vec3(0.9563000202178955078125, -0.2721000015735626220703125, -1.10699999332427978515625), vec3(0.620999991893768310546875, -0.64740002155303955078125, 1.70459997653961181640625))) * mix(_100, 1.0, 0.75), vec3((YIQAmount))), 1.0);
}


#endif
