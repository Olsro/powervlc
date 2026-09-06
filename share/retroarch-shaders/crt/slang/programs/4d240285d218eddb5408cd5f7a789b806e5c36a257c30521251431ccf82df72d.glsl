// Generated from crt/shaders/guest/advanced/ntsc/ntsc-pass2.slang. See slang/upstream for licence/source.
#version 130
#pragma parameter auto_res "          SNES/Amiga Hi-Res Auto Mode" 0.0 0.0 1.0 1.0
#pragma parameter speedup  "          Speedup w. higher Internal Res." 1.0 1.0 4.0 1.0
#pragma parameter ntsc_scale   "NTSC Resolution Scaling" 1.0 0.20 2.5 0.025
#pragma parameter nscale       "NTSC Filter Scaling" 1.0 0.20 2.5 0.025
#pragma parameter ntsc_phase   "NTSC Phase: Auto | 2 phase | 3 phase | Mixed | PCE" 1.0 1.0 5.0 1.0
#pragma parameter ntsc_taps    "NTSC # of Taps (Filter Width)" 32.0 6.0 48.0 1.0
#pragma parameter ntsc_cscale  "NTSC Chroma Scaling / Bleeding (2-phase)" 1.0 0.50 4.00 0.05
#pragma parameter ntsc_cscale1 "NTSC Chroma Scaling / Bleeding (3-phase)" 1.0 0.20 2.25 0.05
#pragma parameter ntsc_charp   "NTSC Preserve 'Edge' Colors 2-phase" 0.0 0.0 10.0 0.50
#pragma parameter ntsc_charp3  "NTSC Preserve 'Edge' Colors 3-phase" 0.0 0.0 10.0 0.50
#pragma parameter ntsc_ring    "NTSC Anti-Ringing" 0.5 0.0 1.0 0.10
#ifdef VERTEX

uniform mat4 MVPMatrix;
uniform vec2 OrigTextureSize;
uniform float auto_res;
uniform float speedup;
struct UBO
{
    mat4 MVP;
};



struct Push
{
    vec4 OriginalSize;
    float auto_res;
    float speedup;
};



in vec4 VertexCoord;
out vec2 RA_VARYING_0;
in vec2 TexCoord;

void main()
{
    gl_Position = (MVPMatrix) * VertexCoord;
    RA_VARYING_0 = TexCoord + vec2(((0.5 / (speedup)) * ((vec4(OrigTextureSize, 1.0 / OrigTextureSize)).z / mix(1.0, 0.5, clamp(((auto_res) * round((vec4(OrigTextureSize, 1.0 / OrigTextureSize)).x * 0.0033333334140479564666748046875)) - 1.0, 0.0, 1.0)))) * 0.25, 0.0);
}


#endif
#ifdef FRAGMENT

uniform vec2 OrigTextureSize;
uniform float auto_res;
uniform float nscale;
uniform float ntsc_charp;
uniform float ntsc_cscale;
uniform float ntsc_cscale1;
uniform float ntsc_phase;
uniform float ntsc_ring;
uniform float ntsc_scale;
uniform float ntsc_taps;
uniform float speedup;
const float _262[33] = float[](-0.0001748439972288906574249267578125, -0.0002058440004475414752960205078125, -0.0001494530006311833858489990234375, -5.16930012963712215423583984375e-05, 0.0, -6.6171000071335583925247192382812e-05, -0.00024505800683982670307159423828125, -0.00043292800546623766422271728515625, -0.000472643994726240634918212890625, -0.00025223600096069276332855224609375, 0.00019892900309059768915176391601562, 0.0006870580255053937435150146484375, 0.0009441120200790464878082275390625, 0.000803467002697288990020751953125, 0.00036319901118986308574676513671875, 1.3421999938145745545625686645508e-05, 0.0002534019877202808856964111328125, 0.00133946095593273639678955078125, 0.00293297204189002513885498046875, 0.0039834850467741489410400390625, 0.00302668311633169651031494140625, -0.001102056005038321018218994140625, -0.0083730258047580718994140625, -0.016897700726985931396484375, -0.0229144804179668426513671875, -0.02164234779775142669677734375, -0.028863273561000823974609375, 0.0272719562053680419921875, 0.0549219213426113128662109375, 0.09834258258342742919921875, 0.139044284820556640625, 0.168055832386016845703125, 0.1785714328289031982421875);
const float _499[33] = float[](0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, -0.00011884699779329821467399597167969, -0.00027130599482916295528411865234375, -0.00050264201126992702484130859375, -0.0009308329899795353412628173828125, -0.001451013027690351009368896484375, -0.00206474401056766510009765625, -0.00270043197087943553924560546875, -0.0032412759028375148773193359375, -0.0035249479115009307861328125, -0.0033502839505672454833984375, -0.00249172910116612911224365234375, -0.0007211489719338715076446533203125, 0.002164659090340137481689453125, 0.00631363503634929656982421875, 0.011789103038609027862548828125, 0.01854565925896167755126953125, 0.02641439624130725860595703125, 0.0351007096469402313232421875, 0.044196568429470062255859375, 0.05320720374584197998046875, 0.061590276658535003662109375, 0.068803600966930389404296875, 0.074356190860271453857421875, 0.077856563031673431396484375, 0.079052396118640899658203125);

struct Push
{
    vec4 OriginalSize;
    float ntsc_scale;
    float ntsc_phase;
    float ntsc_ring;
    float ntsc_cscale;
    float ntsc_cscale1;
    float ntsc_taps;
    float auto_res;
    float ntsc_charp;
    float speedup;
    float nscale;
};



uniform sampler2D Texture;
uniform sampler2D Pass2Texture;

in vec2 RA_VARYING_0;
out vec4 FragColor;

void main()
{
    float _55 = mix(1.0, 0.5, clamp(((auto_res) * round((vec4(OrigTextureSize, 1.0 / OrigTextureSize)).x * 0.0033333334140479564666748046875)) - 1.0, 0.0, 1.0));
    if ((RA_VARYING_0.x * (speedup)) > 1.00325000286102294921875)
    {
        discard;
    }
    float luma_filter_3_phase[33] = float[](0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, -1.2020000212942250072956085205078e-05, -2.2145999537315219640731811523438e-05, -1.315499957854626700282096862793e-05, -1.2020000212942250072956085205078e-05, -4.9979000323219224810600280761719e-05, -0.00011393999739084392786026000976562, -0.0001221499987877905368804931640625, -5.6120002227544318884611129760742e-06, 0.00017051599570550024509429931640625, 0.00023719899763818830251693725585938, 0.0001696399995125830173492431640625, 0.00028568800189532339572906494140625, 0.00098457396961748600006103515625, 0.00201868289150297641754150390625, 0.0020022750832140445709228515625, -0.0059098820202052593231201171875, -0.01204908080399036407470703125, -0.01822285912930965423583984375, -0.022606931626796722412109375, 0.00246085994876921176910400390625, 0.0358682237565517425537109375, 0.084016449749469757080078125, 0.13556349277496337890625, 0.17526127398014068603515625, 0.2201765477657318115234375);
    float _181 = ((ntsc_scale) * _55) * (nscale);
    vec2 _200 = (((vec4(OrigTextureSize, 1.0 / OrigTextureSize)).zz * 0.25) / vec2(_181)) / vec2((speedup));
    float _741;
    if ((ntsc_phase) < 1.5)
    {
        _741 = (((vec4(OrigTextureSize, 1.0 / OrigTextureSize)).x * _55) > 300.0) ? 2.0 : 3.0;
    }
    else
    {
        _741 = ((ntsc_phase) > 2.5) ? 3.0 : 2.0;
    }
    bool _227 = (ntsc_phase) > 3.5;
    if (_227)
    {
        luma_filter_3_phase = _262;
    }
    vec3 _811;
    if ((_227 ? 3.0 : _741) < 2.5)
    {
        float _282 = max((ntsc_taps), 8.0);
        float _750;
        if ((ntsc_charp) > 0.25)
        {
            _750 = min(_282, 14.0);
        }
        else
        {
            _750 = _282;
        }
        int _296 = int(32.0 - _750);
        float _307 = _750 - (_750 / (ntsc_cscale));
        vec2 _325 = vec2(_200.x * (1.0 + (0.039999999105930328369140625 * pow(clamp((_750 - 16.0) * (-0.125), 0.0, 1.0), 0.5))), 0.0);
        vec3 _754;
        vec3 _809;
        _809 = vec3(0.0);
        _754 = vec3(0.0);
        for (int _751 = _296; _751 < 32; )
        {
            float _340 = float(_751 - _296);
            vec2 _347 = _325 * (_340 - _750);
            float _354 = max((_340 + 1.0) - _307, 0.0);
            vec3 _364 = vec3(_262[max(_751, 0)], _354, _354);
            _809 += ((texture(Texture, RA_VARYING_0 + _347).xyz + texture(Texture, RA_VARYING_0 - _347).xyz) * _364);
            _754 += _364;
            _751++;
            continue;
        }
        float _377 = (_750 + 1.0) - _307;
        vec3 _382 = vec3(0.1785714328289031982421875, _377, _377);
        _811 = (_809 + (texture(Texture, RA_VARYING_0).xyz * _382)) / ((_754 + _754) + _382);
    }
    else
    {
        float _410 = _200.x;
        vec3 _413 = vec3(_410, _200.y / (ntsc_cscale1), 0.0);
        float _419 = min((ntsc_taps), 24.0);
        float _743;
        float _744;
        if (_227)
        {
            float _426 = max(_419, 8.0);
            _744 = _426;
            _743 = 1.0 + (0.039999999105930328369140625 * pow(clamp((_426 - 16.0) * (-0.125), 0.0, 1.0), 0.5));
        }
        else
        {
            _744 = _419;
            _743 = 1.0;
        }
        vec3 _778 = _413;
        _778.x = _410 * _743;
        int _445 = int(32.0 - _744);
        vec3 _746;
        vec3 _802;
        vec3 _807;
        _807 = _413;
        _802 = vec3(0.0);
        _746 = vec3(0.0);
        for (int _745 = _445; _745 < 32; )
        {
            vec2 _463 = _778.xy * (float(_745 - _445) - _744);
            vec3 _780 = _807;
            _780.x = _463.x;
            _780.y = _463.y;
            vec3 _507 = vec3(luma_filter_3_phase[_745], _499[_745], _499[_745]);
            _807 = _780;
            _802 += (vec3(texture(Texture, RA_VARYING_0 + _780.xz).x + texture(Texture, RA_VARYING_0 - _780.xz).x, texture(Texture, RA_VARYING_0 + _780.yz).yz + texture(Texture, RA_VARYING_0 - _780.yz).yz) * _507);
            _746 += _507;
            _745++;
            continue;
        }
        vec3 _520 = vec3(luma_filter_3_phase[32], 0.079052396118640899658203125, 0.079052396118640899658203125);
        _811 = (_802 + (texture(Texture, RA_VARYING_0).xyz * _520)) / ((_746 + _746) + _520);
    }
    float _539 = clamp(_811.x, 0.0, 1.0);
    vec3 _785 = _811;
    _785.x = _539;
    vec3 _812;
    if ((ntsc_ring) > 0.0500000007450580596923828125)
    {
        vec2 _558 = vec2(((vec4(OrigTextureSize, 1.0 / OrigTextureSize)).z / min(_181, 1.0)) / (speedup), 0.0);
        vec2 _563 = _558 * 2.0;
        vec4 _565 = texture(Texture, RA_VARYING_0 - _563);
        float _567 = _565.w;
        vec4 _573 = texture(Texture, RA_VARYING_0 - _558);
        float _574 = _573.w;
        vec4 _581 = texture(Texture, RA_VARYING_0 + _563);
        float _582 = _581.w;
        vec4 _588 = texture(Texture, RA_VARYING_0 + _558);
        float _589 = _588.w;
        vec4 _593 = texture(Texture, RA_VARYING_0);
        float _594 = _593.w;
        vec3 _789 = _785;
        _789.x = mix(_539, clamp(_539, min(min(min(_567, _574), min(_582, _589)), _594), max(max(max(_567, _574), max(_582, _589)), _594)), (ntsc_ring));
        _812 = _789;
    }
    else
    {
        _812 = _785;
    }
    FragColor = vec4(_812, dot(texture(Pass2Texture, RA_VARYING_0 * vec2((speedup), 1.0)).xyz, vec3(0.29890000820159912109375, 0.58700001239776611328125, 0.114000000059604644775390625)));
}


#endif
