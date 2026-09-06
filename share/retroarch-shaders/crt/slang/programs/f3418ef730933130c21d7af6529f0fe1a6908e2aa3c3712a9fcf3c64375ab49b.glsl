// Generated from crt/shaders/guest/advanced/ntsc/ntsc-pass1.slang. See slang/upstream for licence/source.
#version 130
#pragma parameter auto_res     "          SNES/Amiga Hi-Res Auto Mode" 0.0 0.0 1.0 1.0
#pragma parameter filter_res   "          Horizontal Filtering Resolution" 1.0 0.5 8.0 0.10
#pragma parameter speedup      "          Speedup w. higher Internal Res." 1.0 1.0 4.0 1.0
#pragma parameter quality "INFO --> A&F Values: Svideo = 0.0 | Composite = 1.0 | RF = 2.0" 0.0 0.0 0.0 1.0
#pragma parameter cust_artifacting "NTSC Artifacting Value" 1.0 0.0 5.0 0.1
#pragma parameter cust_fringing "NTSC Fringing Value" 1.0 0.0 5.0 0.1
#pragma parameter ntsc_fields "NTSC Merge Fields: Auto | NO | YES" -1.0 -1.0 1.0 1.0
#pragma parameter ntsc_phase  "NTSC Phase: Auto | 2 phase | 3 phase | Mixed | PCE" 1.0 1.0 5.0 1.0
#pragma parameter ntsc_scale  "NTSC Resolution Scaling" 1.0 0.20 2.5 0.025
#pragma parameter nscale      "NTSC Filter Scaling" 1.0 0.20 2.5 0.025
#pragma parameter ntsc_sat    "NTSC Color Saturation" 1.0 0.0 2.0 0.01
#pragma parameter ntsc_bright "NTSC Brightness" 1.0 0.0 1.5 0.01
#pragma parameter ntsc_gamma  "NTSC Filtering Gamma Correction" 1.0 0.25 2.5 0.025
#pragma parameter ntsc_rainbow1 "NTSC Coloring/Rainbow Effect (2-phase)" 0.0 0.0 3.0 1.0
#pragma parameter ntsc_taps   "NTSC # of Taps (Filter Width)" 32.0 6.0 48.0 1.0
#pragma parameter ntsc_charp  "NTSC Preserve 'Edge' Colors 2-phase" 0.0 0.0 10.0 0.50
#pragma parameter ntsc_charp3 "NTSC Preserve 'Edge' Colors 3-phase" 0.0 0.0 10.0 0.50
#ifdef VERTEX

uniform mat4 MVPMatrix;
uniform vec2 OrigTextureSize;
uniform float auto_res;
uniform float cust_artifacting;
uniform float cust_fringing;
uniform float ntsc_bright;
uniform float ntsc_fields;
uniform float ntsc_phase;
uniform float ntsc_sat;
uniform float ntsc_scale;
uniform float speedup;
struct UBO
{
    mat4 MVP;
};



struct Push
{
    vec4 OriginalSize;
    float ntsc_sat;
    float cust_fringing;
    float cust_artifacting;
    float ntsc_bright;
    float ntsc_scale;
    float ntsc_fields;
    float ntsc_phase;
    float auto_res;
    float speedup;
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
    float _38 = mix(1.0, 0.5, clamp(((auto_res) * round((vec4(OrigTextureSize, 1.0 / OrigTextureSize)).x * 0.0033333334140479564666748046875)) - 1.0, 0.0, 1.0));
    float _46 = min((ntsc_scale) * _38, 1.0);
    float _51 = (vec4(OrigTextureSize, 1.0 / OrigTextureSize)).x * _38;
    gl_Position = (MVPMatrix) * VertexCoord;
    RA_VARYING_0 = TexCoord * vec2((speedup), 1.0);
    RA_VARYING_1 = ((RA_VARYING_0 * (vec4(OrigTextureSize, 1.0 / OrigTextureSize)).xy) * vec2(_46, _46 / _38)) * vec2(4.0, 1.0);
    float _200;
    if ((ntsc_phase) < 1.5)
    {
        _200 = (_51 > 300.0) ? 2.0 : 3.0;
    }
    else
    {
        _200 = ((ntsc_phase) > 2.5) ? 3.0 : 2.0;
    }
    RA_VARYING_2 = _200;
    if ((ntsc_phase) == 4.0)
    {
        RA_VARYING_2 = 3.0;
    }
    else
    {
        if ((ntsc_phase) == 5.0)
        {
            RA_VARYING_2 = 2.0;
        }
    }
    bool _135 = RA_VARYING_2 == 2.0;
    bool _141;
    if (_135)
    {
        _141 = (ntsc_phase) != 5.0;
    }
    else
    {
        _141 = _135;
    }
    float _205;
    if (_141)
    {
        _205 = 0.83775806427001953125;
    }
    else
    {
        bool _148 = _51 <= 300.0;
        bool _154;
        if (!_148)
        {
            _154 = RA_VARYING_2 == 3.0;
        }
        else
        {
            _154 = _148;
        }
        _205 = _154 ? 1.0471975803375244140625 : 1.57079637050628662109375;
    }
    RA_VARYING_7 = _205;
    RA_VARYING_6 = (cust_artifacting);
    RA_VARYING_5 = (cust_fringing);
    RA_VARYING_4 = (ntsc_sat);
    RA_VARYING_3 = (ntsc_bright);
    RA_VARYING_8 = 0.0;
    bool _180 = (ntsc_fields) == (-1.0);
    bool _185;
    if (_180)
    {
        _185 = RA_VARYING_2 == 3.0;
    }
    else
    {
        _185 = _180;
    }
    if (_185)
    {
        RA_VARYING_8 = 1.0;
    }
    else
    {
        if ((ntsc_fields) == 0.0)
        {
            RA_VARYING_8 = 0.0;
        }
        else
        {
            if ((ntsc_fields) == 1.0)
            {
                RA_VARYING_8 = 1.0;
            }
        }
    }
}


#endif
#ifdef FRAGMENT

uniform int FrameCount;
uniform vec2 OrigTextureSize;
uniform float auto_res;
uniform float ntsc_charp;
uniform float ntsc_gamma;
uniform float ntsc_phase;
uniform float ntsc_rainbow1;
uniform float ntsc_scale;
uniform float ntsc_taps;
struct Push
{
    vec4 OriginalSize;
    uint FrameCount;
    float ntsc_scale;
    float ntsc_phase;
    float ntsc_gamma;
    float ntsc_rainbow1;
    float ntsc_taps;
    float auto_res;
    float ntsc_charp;
};



uniform sampler2D Texture;

in float RA_VARYING_3;
in float RA_VARYING_5;
in float RA_VARYING_6;
in float RA_VARYING_4;
in vec2 RA_VARYING_0;
out vec4 FragColor;
in float RA_VARYING_2;
in float RA_VARYING_8;
in vec2 RA_VARYING_1;
in float RA_VARYING_7;

void main()
{
    float _36 = float((uint(FrameCount)));
    float _55 = mix(1.0, 0.5, clamp(((auto_res) * round((vec4(OrigTextureSize, 1.0 / OrigTextureSize)).x * 0.0033333334140479564666748046875)) - 1.0, 0.0, 1.0));
    float _69 = 2.0 * RA_VARYING_4;
    vec3 _73 = vec3(RA_VARYING_3, RA_VARYING_5, RA_VARYING_5);
    mat3 _76 = mat3(_73, vec3(RA_VARYING_6, _69, 0.0), vec3(RA_VARYING_6, 0.0, _69));
    if (RA_VARYING_0.x > 1.0)
    {
        FragColor = vec4(0.0);
    }
    else
    {
        float _126 = (ntsc_scale) * _55;
        bool _135 = (ntsc_charp) > 0.25;
        bool _141;
        if (_135)
        {
            _141 = RA_VARYING_2 == 2.0;
        }
        else
        {
            _141 = _135;
        }
        float _556;
        if (_141)
        {
            _556 = clamp((ntsc_taps), 8.0, min((ntsc_taps), 14.0));
        }
        else
        {
            _556 = (ntsc_taps);
        }
        float _158 = clamp((_556 - 16.0) * (-0.125), 0.0, 1.0) * 0.324999988079071044921875;
        vec4 _166 = texture(Texture, RA_VARYING_0);
        vec3 _545 = _166.xyz * mat3(vec3(0.29890000820159912109375, 0.58700001239776611328125, 0.114000000059604644775390625), vec3(0.595899999141693115234375, -0.2743999958038330078125, -0.3215999901294708251953125), vec3(0.21150000393390655517578125, -0.52289998531341552734375, 0.311399996280670166015625));
        float _177 = pow(_545.x, (ntsc_gamma));
        vec3 _598 = _545;
        _598.x = _177;
        bool _186 = (ntsc_phase) == 4.0;
        vec3 _657;
        if (_186)
        {
            vec2 _196 = vec2((vec4(OrigTextureSize, 1.0 / OrigTextureSize)).z / _55, 0.0);
            float _549 = dot(texture(Texture, RA_VARYING_0 - _196).xyz, vec3(0.29890000820159912109375, 0.58700001239776611328125, 0.114000000059604644775390625));
            float _553 = dot(texture(Texture, RA_VARYING_0 + _196).xyz, vec3(0.29890000820159912109375, 0.58700001239776611328125, 0.114000000059604644775390625));
            float _226 = pow(_549, (ntsc_gamma));
            float _230 = pow(_553, (ntsc_gamma));
            vec3 _604 = _598;
            _604.x = mix(min(0.5 * (_177 + max(_226, _230)), max(_177, min(_226, _230))), _177, min(5.0 * abs(_549 - _553), 1.0));
            _657 = _604;
        }
        else
        {
            _657 = _598;
        }
        bool _260 = RA_VARYING_8 > 0.5;
        vec3 _671;
        if (_260)
        {
            float _562;
            if (RA_VARYING_2 < 2.5)
            {
                _562 = 3.1415927410125732421875 * (mod(RA_VARYING_1.y, 2.0) + mod(_36 + 1.0, 2.0));
            }
            else
            {
                _562 = 2.0944998264312744140625 * (mod(RA_VARYING_1.y, 3.0) + mod(_36 + 1.0, 2.0));
            }
            float _299 = RA_VARYING_1.x * RA_VARYING_7;
            float _300 = _562 + _299;
            vec2 _309 = vec2(cos(_300), sin(_300));
            vec2 _312 = _657.yz * _309;
            vec3 _606 = _657;
            _606.y = _312.x;
            _606.z = _312.y;
            vec3 _319 = _606 * _76;
            vec2 _325 = _319.yz * _309;
            vec3 _610 = _319;
            _610.y = _325.x;
            _610.z = _325.y;
            vec2 _336 = mix(_610.yz, _657.yz, vec2(_158));
            float _338 = _336.x;
            vec3 _614 = _610;
            _614.y = _338;
            _614.z = _336.y;
            vec3 _672;
            if (_126 > 1.02499997615814208984375)
            {
                float _353 = _562 + (_299 * _126);
                vec2 _363 = _657.yz * vec2(cos(_353), sin(_353));
                vec3 _618 = _657;
                _618.y = _363.x;
                _618.z = _363.y;
                _672 = vec3(dot(_618, _73), _338, _336.y);
            }
            else
            {
                _672 = _614;
            }
            _671 = _672;
        }
        else
        {
            _671 = _657;
        }
        float _573;
        if (RA_VARYING_2 < 2.5)
        {
            _573 = 3.1415927410125732421875 * (mod(RA_VARYING_1.y, 2.0) + mod(_36, 2.0));
        }
        else
        {
            _573 = 2.0944998264312744140625 * (mod(RA_VARYING_1.y, 3.0) + mod(_36, 2.0));
        }
        float _402 = RA_VARYING_1.x * RA_VARYING_7;
        float _403 = _573 + _402;
        vec2 _412 = vec2(cos(_403), sin(_403));
        vec2 _415 = _657.yz * _412;
        vec3 _625 = _657;
        _625.y = _415.x;
        _625.z = _415.y;
        vec3 _422 = _625 * _76;
        vec2 _428 = _422.yz * _412;
        vec3 _629 = _422;
        _629.y = _428.x;
        _629.z = _428.y;
        vec2 _439 = mix(_629.yz, _657.yz, vec2(_158));
        float _441 = _439.x;
        vec3 _633 = _629;
        _633.y = _441;
        _633.z = _439.y;
        vec3 _668;
        if (_126 > 1.02499997615814208984375)
        {
            float _455 = _573 + (_402 * _126);
            vec2 _465 = _657.yz * vec2(cos(_455), sin(_455));
            vec3 _637 = _657;
            _637.y = _465.x;
            _637.z = _465.y;
            _668 = vec3(dot(_637, _73), _441, _439.y);
        }
        else
        {
            _668 = _633;
        }
        vec3 _674;
        vec3 _676;
        if (_186)
        {
            vec3 _644 = _668;
            _644.x = _177;
            vec3 _646 = _671;
            _646.x = _177;
            _676 = _646;
            _674 = _644;
        }
        else
        {
            _676 = _671;
            _674 = _668;
        }
        vec3 _677;
        if (_260)
        {
            bool _491 = (ntsc_rainbow1) < 0.5;
            bool _497;
            if (!_491)
            {
                _497 = RA_VARYING_2 > 2.5;
            }
            else
            {
                _497 = _491;
            }
            vec3 _678;
            if (_497)
            {
                _678 = (_674 + _676) * 0.5;
            }
            else
            {
                vec3 _650 = _674;
                _650.x = 0.5 * (_674.x + _676.x);
                _678 = _650;
            }
            _677 = _678;
        }
        else
        {
            _677 = _674;
        }
        FragColor = vec4(_677, _177);
    }
}


#endif
