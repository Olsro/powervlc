// Generated from crt/shaders/hyllian/support/ntsc/shaders/ntsc-adaptive-lite/ntsc-lite-pass1.slang. See slang/upstream for licence/source.
#version 130
#pragma parameter ntsc_nonono              "NTSC-ADAPTIVE-LITE:"                  0.0 0.0 0.0 1.0
#pragma parameter quality                  "    Preset (Svideo=0 Composite=1 RF=2 Custom=-1)" 1.0 -1.0 2.0 1.0
#pragma parameter ntsc_fields              "    Merge Fields"                                  0.0 0.0 1.0 1.0
#pragma parameter ntsc_phase               "    Phase: Auto | 2 phase | 3 phase"               1.0 1.0 3.0 1.0
#pragma parameter ntsc_scale               "    Resolution Scaling"                            1.0 0.20 3.0 0.05
#pragma parameter ntsc_sat                 "    Color Saturation"                              1.0 0.0 2.0 0.01
#pragma parameter ntsc_bright              "    Brightness"                                    1.0 0.0 1.5 0.01
#pragma parameter cust_fringing            "    Custom Fringing Value"                         0.0 0.0 5.0 0.1
#pragma parameter cust_artifacting         "    Custom Artifacting Value"                      0.0 0.0 5.0 0.1
#pragma parameter ntsc_artifacting_rainbow "    Artifacting Rainbow Effect"                    0.0 -1.0 1.0 0.1
#ifdef VERTEX

uniform mat4 MVPMatrix;
uniform vec2 OrigTextureSize;
uniform vec2 OutputSize;
uniform vec2 TextureSize;
uniform float cust_artifacting;
uniform float cust_fringing;
uniform float ntsc_bright;
uniform float ntsc_fields;
uniform float ntsc_phase;
uniform float ntsc_sat;
uniform float ntsc_scale;
uniform float quality;
struct UBO
{
    mat4 MVP;
    vec4 OutputSize;
    vec4 OriginalSize;
    vec4 SourceSize;
    float quality;
    float ntsc_sat;
    float cust_fringing;
    float cust_artifacting;
    float ntsc_bright;
    float ntsc_scale;
    float ntsc_fields;
    float ntsc_phase;
};



in vec4 VertexCoord;
out vec2 RA_VARYING_0;
in vec2 TexCoord;
out vec2 RA_VARYING_1;
out float RA_VARYING_2;
out float RA_VARYING_7;
out float RA_VARYING_6;
out float RA_VARYING_5;
out float RA_VARYING_4;
out float RA_VARYING_3;
out float RA_VARYING_8;

void main()
{
    gl_Position = (MVPMatrix) * VertexCoord;
    RA_VARYING_0 = TexCoord;
    if ((ntsc_scale) < 1.0)
    {
        RA_VARYING_1 = (TexCoord * (vec4(TextureSize, 1.0 / TextureSize)).xy) * (((vec4(OutputSize, 1.0 / OutputSize)).xy * (ntsc_scale)) / (vec4(TextureSize, 1.0 / TextureSize)).xy);
    }
    else
    {
        RA_VARYING_1 = (TexCoord * (vec4(TextureSize, 1.0 / TextureSize)).xy) * ((vec4(OutputSize, 1.0 / OutputSize)).xy / (vec4(TextureSize, 1.0 / TextureSize)).xy);
    }
    float _192;
    if ((ntsc_phase) < 1.5)
    {
        _192 = ((vec4(OrigTextureSize, 1.0 / OrigTextureSize)).x > 300.0) ? 2.0 : 3.0;
    }
    else
    {
        _192 = ((ntsc_phase) > 2.5) ? 3.0 : 2.0;
    }
    RA_VARYING_2 = _192;
    float _109 = max((ntsc_scale), 1.0);
    RA_VARYING_7 = (RA_VARYING_2 < 2.5) ? 0.83775806427001953125 : 1.0471975803375244140625;
    bool _121 = (quality) > (-0.5);
    float _195;
    if (_121)
    {
        _195 = ((quality) * 0.5) * (_109 + 1.0);
    }
    else
    {
        _195 = (cust_artifacting);
    }
    RA_VARYING_6 = _195;
    float _196;
    if (_121)
    {
        _196 = (quality);
    }
    else
    {
        _196 = (cust_fringing);
    }
    RA_VARYING_5 = _196;
    RA_VARYING_4 = (ntsc_sat);
    RA_VARYING_3 = (ntsc_bright);
    RA_VARYING_1.x *= _109;
    int _167 = int((quality));
    bool _168 = _167 == 2;
    bool _174;
    if (!_168)
    {
        _174 = RA_VARYING_2 < 2.5;
    }
    else
    {
        _174 = _168;
    }
    RA_VARYING_8 = _174 ? 0.0 : 1.0;
    float _199;
    if (_167 == (-1))
    {
        _199 = (ntsc_fields);
    }
    else
    {
        _199 = RA_VARYING_8;
    }
    RA_VARYING_8 = _199;
}


#endif
#ifdef FRAGMENT

uniform int FrameCount;
uniform float ntsc_artifacting_rainbow;
struct UBO
{
    uint FrameCount;
    float ntsc_artifacting_rainbow;
};



uniform sampler2D Texture;

in vec2 RA_VARYING_0;
in float RA_VARYING_8;
in float RA_VARYING_2;
in vec2 RA_VARYING_1;
in float RA_VARYING_7;
in float RA_VARYING_3;
in float RA_VARYING_5;
in float RA_VARYING_6;
in float RA_VARYING_4;
out vec4 FragColor;

void main()
{
    vec4 _42 = texture(Texture, RA_VARYING_0);
    vec3 _280 = _42.xyz * mat3(vec3(0.29890000820159912109375, 0.58700001239776611328125, 0.114000000059604644775390625), vec3(0.595899999141693115234375, -0.2743999958038330078125, -0.3215999901294708251953125), vec3(0.21150000393390655517578125, -0.52289998531341552734375, 0.311399996280670166015625));
    vec3 _309;
    if (RA_VARYING_8 > 0.5)
    {
        float _281;
        if (RA_VARYING_2 < 2.5)
        {
            _281 = 3.1415927410125732421875 * (mod(RA_VARYING_1.y, 2.0) + mod(float((uint(FrameCount)) + 1u), 2.0));
        }
        else
        {
            _281 = 2.0944998264312744140625 * (mod(RA_VARYING_1.y, 3.0) + mod(float((uint(FrameCount)) + 1u), 2.0));
        }
        float _122 = (((ntsc_artifacting_rainbow) + 1.0) * _281) + (RA_VARYING_1.x * RA_VARYING_7);
        vec2 _131 = vec2(cos(_122), sin(_122));
        vec2 _134 = _280.yz * _131;
        vec3 _289 = _280;
        _289.y = _134.x;
        _289.z = _134.y;
        float _148 = 2.0 * RA_VARYING_4;
        vec3 _158 = _289 * mat3(vec3(RA_VARYING_3, RA_VARYING_5, RA_VARYING_5), vec3(RA_VARYING_6, _148, 0.0), vec3(RA_VARYING_6, 0.0, _148));
        vec2 _164 = _158.yz * _131;
        vec3 _293 = _158;
        _293.y = _164.x;
        _293.z = _164.y;
        _309 = _293;
    }
    else
    {
        _309 = _280;
    }
    float _286;
    if (RA_VARYING_2 < 2.5)
    {
        _286 = 3.1415927410125732421875 * (mod(RA_VARYING_1.y, 2.0) + mod(float((uint(FrameCount))), 2.0));
    }
    else
    {
        _286 = 2.0944998264312744140625 * (mod(RA_VARYING_1.y, 3.0) + mod(float((uint(FrameCount))), 2.0));
    }
    float _207 = (((ntsc_artifacting_rainbow) + 1.0) * _286) + (RA_VARYING_1.x * RA_VARYING_7);
    vec2 _216 = vec2(cos(_207), sin(_207));
    vec2 _219 = _280.yz * _216;
    vec3 _297 = _280;
    _297.y = _219.x;
    _297.z = _219.y;
    float _228 = 2.0 * RA_VARYING_4;
    vec3 _237 = _297 * mat3(vec3(RA_VARYING_3, RA_VARYING_5, RA_VARYING_5), vec3(RA_VARYING_6, _228, 0.0), vec3(RA_VARYING_6, 0.0, _228));
    vec2 _243 = _237.yz * _216;
    vec3 _301 = _237;
    _301.y = _243.x;
    _301.z = _243.y;
    vec3 _287;
    if (RA_VARYING_8 < 0.5)
    {
        _287 = _301;
    }
    else
    {
        _287 = (_301 + _309) * 0.5;
    }
    FragColor = vec4(_287, 1.0);
}


#endif
