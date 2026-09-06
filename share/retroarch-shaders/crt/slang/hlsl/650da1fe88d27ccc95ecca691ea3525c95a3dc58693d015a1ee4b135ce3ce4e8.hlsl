// Generated from crt/shaders/Advanced_CRT_shader_whkrmrgks0.slang. See slang/upstream for licence/source.
cbuffer UBO : register(b0)
{
    float4 _255_OutputSize : packoffset(c4);
    float4 _255_SourceSize : packoffset(c5);
};

cbuffer Push : register(b1)
{
    float _79_cus : packoffset(c0);
    float _79_vstr : packoffset(c0.y);
    float _79_marginv : packoffset(c0.z);
    float _79_dts : packoffset(c0.w);
    float _79_AAz : packoffset(c1);
    float _79_vex : packoffset(c1.y);
    float _79_capa : packoffset(c1.z);
    float _79_capaiter : packoffset(c1.w);
    float _79_capashape : packoffset(c2);
    float _79_scl : packoffset(c2.y);
    float _79_gma : packoffset(c2.z);
    float _79_sling : packoffset(c2.w);
};

Texture2D<float4> Source : register(t1);
SamplerState _Source_sampler : register(s1);

static float2 vTexCoord;
static float4 FragColor;

struct SPIRV_Cross_Input
{
    float2 vTexCoord : TEXCOORD2;
};

struct SPIRV_Cross_Output
{
    float4 FragColor : SV_Target0;
};

void frag_main()
{
    float _262 = ((1.0f - min(_79_scl, 1.0f)) * _255_SourceSize.y) + _79_scl;
    float2 _272 = vTexCoord * _255_OutputSize.xy;
    float _282 = _255_OutputSize.x / _255_OutputSize.y;
    float2 _628 = ((vTexCoord * 2.0f.xx) - 1.0f.xx) * float2(1.0f + _79_marginv, 1.0f + (_79_marginv * _282));
    float _630 = _628.x;
    float _632 = _628.y;
    float2 _655 = float2(_630 / cos(abs(_632 * _79_cus) * 1.57079637050628662109375f), _632 / cos(abs((_630 * _79_cus) * _282) * 1.57079637050628662109375f));
    float2 _658 = abs(_655) - 1.0f.xx;
    float _660 = _658.x;
    float _662 = _658.y;
    float2 _672 = (_655 + 1.0f.xx) * 0.5f.xx;
    float _302 = _672.y * _262;
    float _306 = floor(_302 - 1.0f) / _262;
    float _314 = floor(_302 + 1.0f) / _262;
    float _320 = floor(_302);
    float _322 = _320 / _262;
    float _333 = _79_capaiter * (-0.5f);
    float _1136;
    float _1137;
    float3 _1138;
    float3 _1139;
    float3 _1140;
    _1140 = 0.0f.xxx;
    _1139 = 0.0f.xxx;
    _1138 = 0.0f.xxx;
    _1137 = 0.0f;
    _1136 = _333;
    float _342;
    for (;;)
    {
        _342 = _79_capaiter * 0.5f;
        if (_1136 <= _342)
        {
            float _681 = sin(pow((_1136 + _342) / _79_capaiter, _79_capashape) * 6.283185482025146484375f) + 1.0f;
            float _377 = _672.x - (((_79_capa / _262) * _1136) / _342);
            float _687 = _377 - floor(_377);
            _1140 += (Source.Sample(_Source_sampler, float2(_687, _314)).xyz * _681);
            _1139 += (Source.Sample(_Source_sampler, float2(_687, _322)).xyz * _681);
            _1138 += (Source.Sample(_Source_sampler, float2(_687, _306)).xyz * _681);
            _1137 += _681;
            _1136 += 1.0f;
            continue;
        }
        else
        {
            break;
        }
    }
    float3 _443 = _1137.xxx;
    float3 _444 = _1138 / _443;
    float3 _448 = _1139 / _443;
    float3 _452 = _1140 / _443;
    float _460 = _79_AAz * (-0.5f);
    float _1141;
    float _1142;
    float3 _1143;
    _1143 = 0.0f.xxx;
    _1142 = 0.0f;
    _1141 = _460;
    float _469;
    for (;;)
    {
        _469 = _79_AAz * 0.5f;
        if (_1141 <= _469)
        {
            float _481 = ((_469 - abs(_1141)) / _79_AAz) * 0.5f;
            float _764 = ((_302 - _320) + (((((_1141 / _79_AAz) * 2.0f) * _79_vex) / _255_OutputSize.y) * _262)) + 0.5f;
            _1143 += ((((max(((abs((_764 - floor(_764)) - 0.5f) * 2.0f) - 1.0f).xxx + (_448 * _79_sling), 0.0f.xxx) + max((-1.0f).xxx + (_452 * _79_sling), 0.0f.xxx)) + max((-1.0f).xxx + (_444 * _79_sling), 0.0f.xxx)) / (_79_sling * 0.5f).xxx) * _481);
            _1142 += _481;
            _1141 += 1.0f;
            continue;
        }
        else
        {
            break;
        }
    }
    float2 _792 = _79_dts.xx;
    float2 _793 = (_272 + (float2(4.0f, 0.0f) * _79_dts)) / _792;
    float _806 = _793.x * 0.16666667163372039794921875f;
    float _823 = _793.y * 0.5f;
    float2 _853 = _272 / _792;
    float _866 = _853.x * 0.16666667163372039794921875f;
    float _883 = _853.y * 0.5f;
    float2 _913 = (_272 + (float2(2.0f, 0.0f) * _79_dts)) / _792;
    float _926 = _913.x * 0.16666667163372039794921875f;
    float _943 = _913.y * 0.5f;
    float2 _973 = (_272 + (float2(7.0f, 1.0f) * _79_dts)) / _792;
    float _986 = _973.x * 0.16666667163372039794921875f;
    float _1003 = _973.y * 0.5f;
    float2 _1033 = (_272 + (float2(3.0f, 1.0f) * _79_dts)) / _792;
    float _1046 = _1033.x * 0.16666667163372039794921875f;
    float _1063 = _1033.y * 0.5f;
    float2 _1093 = (_272 + (float2(5.0f, 1.0f) * _79_dts)) / _792;
    float _1106 = _1093.x * 0.16666667163372039794921875f;
    float _1123 = _1093.y * 0.5f;
    float3 _592 = pow(pow(pow((_1143 / _1142.xxx) / _79_sling.xxx, 0.5f.xxx), 1.33333337306976318359375f.xxx), _79_gma.xxx);
    float3 _606 = min(lerp((_592 * (float3(step(_806 - floor(_806), 0.3333333432674407958984375f) * step(_823 - floor(_823), 0.5f), step(_866 - floor(_866), 0.3333333432674407958984375f) * step(_883 - floor(_883), 0.5f), step(_926 - floor(_926), 0.3333333432674407958984375f) * step(_943 - floor(_943), 0.5f)) + float3(step(_986 - floor(_986), 0.3333333432674407958984375f) * step(_1003 - floor(_1003), 0.5f), step(_1046 - floor(_1046), 0.3333333432674407958984375f) * step(_1063 - floor(_1063), 0.5f), step(_1106 - floor(_1106), 0.3333333432674407958984375f) * step(_1123 - floor(_1123), 0.5f)))) * 3.0f, _592, _592), 1.0f.xxx) * (step(max(_660, _662), 0.0f) * pow(max(_660 * _662, 0.0f), _79_vstr));
    FragColor = float4(_606, 1.0f);
}

SPIRV_Cross_Output main(SPIRV_Cross_Input stage_input)
{
    vTexCoord = stage_input.vTexCoord;
    frag_main();
    SPIRV_Cross_Output stage_output;
    stage_output.FragColor = FragColor;
    return stage_output;
}
