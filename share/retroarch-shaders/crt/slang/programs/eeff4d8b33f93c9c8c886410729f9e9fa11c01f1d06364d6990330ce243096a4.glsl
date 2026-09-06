// Generated from crt/shaders/CreativeForce/crt-CreativeForce-SharpSmooth.slang. See slang/upstream for licence/source.
#version 130
#pragma parameter GBA_MODE_GAMMA     "GBA Mode Gamma"                       0.00 0.00 1.00 1.00
#pragma parameter V_BLACKS_PER       "Vertical Lines"                       1.00 0.00 5.00 1.00
#pragma parameter V_STRENGTH         "Vertical Lines Strength"              1.00 0.00 1.00 0.01
#pragma parameter V_PHASE            "Vertical Phase"                       0.00 -256.00 256.00 1.00
#pragma parameter AUTO_PHASE         "Auto-Phase (lock to active content)"   1.00 0.00 1.00 1.00
#ifdef VERTEX

uniform mat4 MVPMatrix;
struct UBO
{
    mat4 MVP;
};



in vec4 VertexCoord;
out vec2 RA_VARYING_0;
in vec2 TexCoord;

void main()
{
    gl_Position = (MVPMatrix) * VertexCoord;
    RA_VARYING_0 = TexCoord;
}


#endif
#ifdef FRAGMENT

uniform float AUTO_PHASE;
uniform float GBA_MODE_GAMMA;
uniform vec2 OrigTextureSize;
uniform vec2 OutputSize;
uniform float V_BLACKS_PER;
uniform float V_PHASE;
uniform float V_STRENGTH;
struct Push
{
    vec4 OriginalSize;
    vec4 OutputSize;
    float GBA_MODE_GAMMA;
    float V_BLACKS_PER;
    float V_STRENGTH;
    float V_PHASE;
    float AUTO_PHASE;
};



uniform sampler2D Texture;

in vec2 RA_VARYING_0;
out vec4 FragColor;

void main()
{
    vec4 _119 = texture(Texture, RA_VARYING_0);
    int _135 = clamp(int(floor((V_BLACKS_PER) + 0.5)), 0, 17);
    int _138 = _135 + 1;
    int _161 = int(floor((V_PHASE) + 0.5));
    int _346;
    if ((AUTO_PHASE) >= 0.5)
    {
        int _280 = int(floor(((vec4(OutputSize, 1.0 / OutputSize)).x / (vec4(OrigTextureSize, 1.0 / OrigTextureSize)).x) + 9.9999999747524270787835121154785e-07));
        int _347;
        if ((_135 > 0) && (_138 > 0))
        {
            int _207 = ((int((vec4(OutputSize, 1.0 / OutputSize)).x) - (int((vec4(OrigTextureSize, 1.0 / OrigTextureSize)).x) * ((_280 < 1) ? 1 : _280))) / 2) % _138;
            int _340;
            if (_207 < 0)
            {
                _340 = _207 + _138;
            }
            else
            {
                _340 = _207;
            }
            _347 = _161 + (1 - _340);
        }
        else
        {
            _347 = _161;
        }
        _346 = _347;
    }
    else
    {
        _346 = _161;
    }
    float _382;
    if (_135 > 0)
    {
        int _387 = (_138 < 1) ? 1 : _138;
        int _388 = (_135 < 0) ? 0 : _135;
        int _311 = (int(floor(gl_FragCoord.x - 0.5)) + int(floor(float(_346) + 0.5))) % _387;
        int _362;
        if (_311 < 0)
        {
            _362 = _311 + _387;
        }
        else
        {
            _362 = _311;
        }
        _382 = mix(1.0, 1.0 - clamp((V_STRENGTH), 0.0, 1.0), float(_362 < ((_388 > _387) ? _387 : _388)));
    }
    else
    {
        _382 = 1.0;
    }
    FragColor = vec4(pow(max(pow(max(_119.xyz, vec3(0.0)), vec3(((GBA_MODE_GAMMA) >= 0.5) ? 2.7000000476837158203125 : 2.2000000476837158203125)) * vec3(_382), vec3(0.0)), vec3(0.454545438289642333984375)), 1.0);
}


#endif
