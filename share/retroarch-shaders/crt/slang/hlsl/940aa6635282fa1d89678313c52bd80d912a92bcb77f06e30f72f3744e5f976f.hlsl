// Generated from crt/shaders/guest/advanced/ntsc/ntsc-pass2.slang. See slang/upstream for licence/source.
static const float _171[33] = { 0.0f, 0.0f, 0.0f, 0.0f, 0.0f, 0.0f, 0.0f, 0.0f, -1.2020000212942250072956085205078e-05f, -2.2145999537315219640731811523438e-05f, -1.315499957854626700282096862793e-05f, -1.2020000212942250072956085205078e-05f, -4.9979000323219224810600280761719e-05f, -0.00011393999739084392786026000976562f, -0.0001221499987877905368804931640625f, -5.6120002227544318884611129760742e-06f, 0.00017051599570550024509429931640625f, 0.00023719899763818830251693725585938f, 0.0001696399995125830173492431640625f, 0.00028568800189532339572906494140625f, 0.00098457396961748600006103515625f, 0.00201868289150297641754150390625f, 0.0020022750832140445709228515625f, -0.0059098820202052593231201171875f, -0.01204908080399036407470703125f, -0.01822285912930965423583984375f, -0.022606931626796722412109375f, 0.00246085994876921176910400390625f, 0.0358682237565517425537109375f, 0.084016449749469757080078125f, 0.13556349277496337890625f, 0.17526127398014068603515625f, 0.2201765477657318115234375f };
static const float _262[33] = { -0.0001748439972288906574249267578125f, -0.0002058440004475414752960205078125f, -0.0001494530006311833858489990234375f, -5.16930012963712215423583984375e-05f, 0.0f, -6.6171000071335583925247192382812e-05f, -0.00024505800683982670307159423828125f, -0.00043292800546623766422271728515625f, -0.000472643994726240634918212890625f, -0.00025223600096069276332855224609375f, 0.00019892900309059768915176391601562f, 0.0006870580255053937435150146484375f, 0.0009441120200790464878082275390625f, 0.000803467002697288990020751953125f, 0.00036319901118986308574676513671875f, 1.3421999938145745545625686645508e-05f, 0.0002534019877202808856964111328125f, 0.00133946095593273639678955078125f, 0.00293297204189002513885498046875f, 0.0039834850467741489410400390625f, 0.00302668311633169651031494140625f, -0.001102056005038321018218994140625f, -0.0083730258047580718994140625f, -0.016897700726985931396484375f, -0.0229144804179668426513671875f, -0.02164234779775142669677734375f, -0.028863273561000823974609375f, 0.0272719562053680419921875f, 0.0549219213426113128662109375f, 0.09834258258342742919921875f, 0.139044284820556640625f, 0.168055832386016845703125f, 0.1785714328289031982421875f };
static const float _499[33] = { 0.0f, 0.0f, 0.0f, 0.0f, 0.0f, 0.0f, 0.0f, 0.0f, -0.00011884699779329821467399597167969f, -0.00027130599482916295528411865234375f, -0.00050264201126992702484130859375f, -0.0009308329899795353412628173828125f, -0.001451013027690351009368896484375f, -0.00206474401056766510009765625f, -0.00270043197087943553924560546875f, -0.0032412759028375148773193359375f, -0.0035249479115009307861328125f, -0.0033502839505672454833984375f, -0.00249172910116612911224365234375f, -0.0007211489719338715076446533203125f, 0.002164659090340137481689453125f, 0.00631363503634929656982421875f, 0.011789103038609027862548828125f, 0.01854565925896167755126953125f, 0.02641439624130725860595703125f, 0.0351007096469402313232421875f, 0.044196568429470062255859375f, 0.05320720374584197998046875f, 0.061590276658535003662109375f, 0.068803600966930389404296875f, 0.074356190860271453857421875f, 0.077856563031673431396484375f, 0.079052396118640899658203125f };

cbuffer Push : register(b1)
{
    float4 params_OriginalSize : packoffset(c1);
    float params_ntsc_scale : packoffset(c3);
    float params_ntsc_phase : packoffset(c3.y);
    float params_ntsc_ring : packoffset(c3.z);
    float params_ntsc_cscale : packoffset(c3.w);
    float params_ntsc_cscale1 : packoffset(c4);
    float params_ntsc_taps : packoffset(c4.y);
    float params_auto_res : packoffset(c4.z);
    float params_ntsc_charp : packoffset(c4.w);
    float params_speedup : packoffset(c5.y);
    float params_nscale : packoffset(c5.z);
};

Texture2D<float4> Source : register(t2);
SamplerState _Source_sampler : register(s2);
Texture2D<float4> PrePass0 : register(t3);
SamplerState _PrePass0_sampler : register(s3);

static float2 vTexCoord;
static float4 FragColor;

struct SPIRV_Cross_Input
{
    float2 vTexCoord : TEXCOORD0;
};

struct SPIRV_Cross_Output
{
    float4 FragColor : SV_Target0;
};

void frag_main()
{
    float _55 = lerp(1.0f, 0.5f, clamp((params_auto_res * round(params_OriginalSize.x * 0.0033333334140479564666748046875f)) - 1.0f, 0.0f, 1.0f));
    if ((vTexCoord.x * params_speedup) > 1.00325000286102294921875f)
    {
        discard;
    }
    float luma_filter_3_phase[33] = _171;
    float _181 = (params_ntsc_scale * _55) * params_nscale;
    float2 _200 = ((params_OriginalSize.zz * 0.25f) / _181.xx) / params_speedup.xx;
    float _741;
    if (params_ntsc_phase < 1.5f)
    {
        _741 = ((params_OriginalSize.x * _55) > 300.0f) ? 2.0f : 3.0f;
    }
    else
    {
        _741 = (params_ntsc_phase > 2.5f) ? 3.0f : 2.0f;
    }
    bool _227 = params_ntsc_phase > 3.5f;
    if (_227)
    {
        luma_filter_3_phase = _262;
    }
    float3 _811;
    if ((_227 ? 3.0f : _741) < 2.5f)
    {
        float _282 = max(params_ntsc_taps, 8.0f);
        float _750;
        if (params_ntsc_charp > 0.25f)
        {
            _750 = min(_282, 14.0f);
        }
        else
        {
            _750 = _282;
        }
        int _296 = int(32.0f - _750);
        float _307 = _750 - (_750 / params_ntsc_cscale);
        float2 _325 = float2(_200.x * (1.0f + (0.039999999105930328369140625f * pow(clamp((_750 - 16.0f) * (-0.125f), 0.0f, 1.0f), 0.5f))), 0.0f);
        float3 _754;
        float3 _809;
        _809 = 0.0f.xxx;
        _754 = 0.0f.xxx;
        for (int _751 = _296; _751 < 32; )
        {
            float _340 = float(_751 - _296);
            float2 _347 = _325 * (_340 - _750);
            float _354 = max((_340 + 1.0f) - _307, 0.0f);
            float3 _364 = float3(_262[max(_751, 0)], _354, _354);
            _809 += ((Source.Sample(_Source_sampler, vTexCoord + _347).xyz + Source.Sample(_Source_sampler, vTexCoord - _347).xyz) * _364);
            _754 += _364;
            _751++;
            continue;
        }
        float _377 = (_750 + 1.0f) - _307;
        float3 _382 = float3(0.1785714328289031982421875f, _377, _377);
        _811 = (_809 + (Source.Sample(_Source_sampler, vTexCoord).xyz * _382)) / ((_754 + _754) + _382);
    }
    else
    {
        float _410 = _200.x;
        float3 _413 = float3(_410, _200.y / params_ntsc_cscale1, 0.0f);
        float _419 = min(params_ntsc_taps, 24.0f);
        float _743;
        float _744;
        if (_227)
        {
            float _426 = max(_419, 8.0f);
            _744 = _426;
            _743 = 1.0f + (0.039999999105930328369140625f * pow(clamp((_426 - 16.0f) * (-0.125f), 0.0f, 1.0f), 0.5f));
        }
        else
        {
            _744 = _419;
            _743 = 1.0f;
        }
        float3 _778 = _413;
        _778.x = _410 * _743;
        int _445 = int(32.0f - _744);
        float3 _746;
        float3 _802;
        float3 _807;
        _807 = _413;
        _802 = 0.0f.xxx;
        _746 = 0.0f.xxx;
        for (int _745 = _445; _745 < 32; )
        {
            float2 _463 = _778.xy * (float(_745 - _445) - _744);
            float3 _780 = _807;
            _780.x = _463.x;
            _780.y = _463.y;
            float3 _507 = float3(luma_filter_3_phase[_745], _499[_745], _499[_745]);
            _807 = _780;
            _802 += (float3(Source.Sample(_Source_sampler, vTexCoord + _780.xz).x + Source.Sample(_Source_sampler, vTexCoord - _780.xz).x, Source.Sample(_Source_sampler, vTexCoord + _780.yz).yz + Source.Sample(_Source_sampler, vTexCoord - _780.yz).yz) * _507);
            _746 += _507;
            _745++;
            continue;
        }
        float3 _520 = float3(luma_filter_3_phase[32], 0.079052396118640899658203125f, 0.079052396118640899658203125f);
        _811 = (_802 + (Source.Sample(_Source_sampler, vTexCoord).xyz * _520)) / ((_746 + _746) + _520);
    }
    float _539 = clamp(_811.x, 0.0f, 1.0f);
    float3 _785 = _811;
    _785.x = _539;
    float3 _812;
    if (params_ntsc_ring > 0.0500000007450580596923828125f)
    {
        float2 _558 = float2((params_OriginalSize.z / min(_181, 1.0f)) / params_speedup, 0.0f);
        float2 _563 = _558 * 2.0f;
        float4 _565 = Source.Sample(_Source_sampler, vTexCoord - _563);
        float _567 = _565.w;
        float4 _573 = Source.Sample(_Source_sampler, vTexCoord - _558);
        float _574 = _573.w;
        float4 _581 = Source.Sample(_Source_sampler, vTexCoord + _563);
        float _582 = _581.w;
        float4 _588 = Source.Sample(_Source_sampler, vTexCoord + _558);
        float _589 = _588.w;
        float4 _593 = Source.Sample(_Source_sampler, vTexCoord);
        float _594 = _593.w;
        float3 _789 = _785;
        _789.x = lerp(_539, clamp(_539, min(min(min(_567, _574), min(_582, _589)), _594), max(max(max(_567, _574), max(_582, _589)), _594)), params_ntsc_ring);
        _812 = _789;
    }
    else
    {
        _812 = _785;
    }
    FragColor = float4(_812, dot(PrePass0.Sample(_PrePass0_sampler, vTexCoord * float2(params_speedup, 1.0f)).xyz, float3(0.29890000820159912109375f, 0.58700001239776611328125f, 0.114000000059604644775390625f)));
}

SPIRV_Cross_Output main(SPIRV_Cross_Input stage_input)
{
    vTexCoord = stage_input.vTexCoord;
    frag_main();
    SPIRV_Cross_Output stage_output;
    stage_output.FragColor = FragColor;
    return stage_output;
}
