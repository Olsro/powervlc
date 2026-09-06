// Generated from crt/shaders/hyllian/support/multiLUT-linear-fast.slang. See slang/upstream for licence/source.
#version 120
#pragma parameter crt_nonono        "** CRT-HYLLIAN **"             0.0 0.0 0.0 1.0
#pragma parameter non_nonono        " "                             0.0 0.0 0.0 1.0
#pragma parameter col_nonono        "COLOR SETTINGS:"               0.0 0.0 0.0 1.0
#pragma parameter LUT_selector_param "    LUT [ OFF, DARK BLUE, DARK BLUE (cool) ]" 1.0 0.0 2.0 1.0
#pragma parameter H_InputGamma       "    Input Gamma"     2.4 1.0 3.0 0.05
#pragma parameter H_OUTPUT_GAMMA     "    Output Gamma"    2.2 1.0 3.0 0.05
#pragma parameter BRIGHTBOOST        "    Brightboost"     1.0 0.5 2.0 0.01
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

uniform float H_InputGamma;
uniform float LUT_selector_param;
struct Push
{
    float LUT_selector_param;
    float H_InputGamma;
};



uniform sampler2D Texture;
uniform sampler2D SamplerLUT1;
uniform sampler2D SamplerLUT2;

varying vec2 RA_VARYING_0;

void main()
{
    vec4 _47 = texture2D(Texture, RA_VARYING_0);
    vec3 _193;
    if ((LUT_selector_param) < 0.5)
    {
        _193 = _47.xyz;
    }
    else
    {
        float _77 = ((_47.x * 31.0) + 0.4999000132083892822265625) * 0.0009765625;
        float _85 = ((_47.y * 31.0) + 0.4999000132083892822265625) * 0.03125;
        float _88 = _47.z;
        float _89 = _88 * 31.0;
        float _93 = (floor(_89) * 0.03125) + _77;
        float _101 = (ceil(_89) * 0.03125) + _77;
        vec3 _189;
        vec3 _190;
        if ((LUT_selector_param) < 1.5)
        {
            _190 = texture2D(SamplerLUT1, vec2(_101, _85)).xyz;
            _189 = texture2D(SamplerLUT1, vec2(_93, _85)).xyz;
        }
        else
        {
            _190 = texture2D(SamplerLUT2, vec2(_101, _85)).xyz;
            _189 = texture2D(SamplerLUT2, vec2(_93, _85)).xyz;
        }
        vec3 _192;
        if (_189.z < 1.0)
        {
            _192 = mix(_189, _190, vec3(clamp(max((_88 - _93) / (_101 - _93), 0.0), 0.0, 32.0)));
        }
        else
        {
            _192 = _189;
        }
        _193 = _192;
    }
    gl_FragData[0] = vec4(pow(_193, vec3((H_InputGamma))), 1.0);
}


#endif
