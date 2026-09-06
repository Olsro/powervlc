// Generated from crt/shaders/guest/advanced/ntsc/ntsc-pass1.slang. See slang/upstream for licence/source.
cbuffer Push : register(b1)
{
    float4 params_OriginalSize : packoffset(c1);
    uint params_FrameCount : packoffset(c3);
    float params_ntsc_scale : packoffset(c4.z);
    float params_ntsc_phase : packoffset(c5);
    float params_ntsc_gamma : packoffset(c5.y);
    float params_ntsc_rainbow1 : packoffset(c5.z);
    float params_ntsc_taps : packoffset(c5.w);
    float params_auto_res : packoffset(c6);
    float params_ntsc_charp : packoffset(c6.y);
};

Texture2D<float4> Source : register(t2);
SamplerState _Source_sampler : register(s2);

static float BRIGHTNESS;
static float FRINGING;
static float ARTIFACTING;
static float SATURATION;
static float2 vTexCoord;
static float4 FragColor;
static float phase;
static float MERGE;
static float2 pix_no;
static float CHROMA_MOD_FREQ;

struct SPIRV_Cross_Input
{
    float2 vTexCoord : TEXCOORD0;
    float2 pix_no : TEXCOORD1;
    float phase : TEXCOORD2;
    float BRIGHTNESS : TEXCOORD3;
    float SATURATION : TEXCOORD4;
    float FRINGING : TEXCOORD5;
    float ARTIFACTING : TEXCOORD6;
    float CHROMA_MOD_FREQ : TEXCOORD7;
    float MERGE : TEXCOORD8;
};

struct SPIRV_Cross_Output
{
    float4 FragColor : SV_Target0;
};

float mod(float x, float y)
{
    return x - y * floor(x / y);
}

float2 mod(float2 x, float2 y)
{
    return x - y * floor(x / y);
}

float3 mod(float3 x, float3 y)
{
    return x - y * floor(x / y);
}

float4 mod(float4 x, float4 y)
{
    return x - y * floor(x / y);
}

void frag_main()
{
    float _36 = float(params_FrameCount);
    float _55 = lerp(1.0f, 0.5f, clamp((params_auto_res * round(params_OriginalSize.x * 0.0033333334140479564666748046875f)) - 1.0f, 0.0f, 1.0f));
    float _69 = 2.0f * SATURATION;
    float3 _73 = float3(BRIGHTNESS, FRINGING, FRINGING);
    float3x3 _76 = float3x3(_73, float3(ARTIFACTING, _69, 0.0f), float3(ARTIFACTING, 0.0f, _69));
    if (vTexCoord.x > 1.0f)
    {
        FragColor = 0.0f.xxxx;
    }
    else
    {
        float _126 = params_ntsc_scale * _55;
        bool _135 = params_ntsc_charp > 0.25f;
        bool _141;
        if (_135)
        {
            _141 = phase == 2.0f;
        }
        else
        {
            _141 = _135;
        }
        float _556;
        if (_141)
        {
            _556 = clamp(params_ntsc_taps, 8.0f, min(params_ntsc_taps, 14.0f));
        }
        else
        {
            _556 = params_ntsc_taps;
        }
        float _158 = clamp((_556 - 16.0f) * (-0.125f), 0.0f, 1.0f) * 0.324999988079071044921875f;
        float4 _166 = Source.Sample(_Source_sampler, vTexCoord);
        float3 _545 = mul(float3x3(float3(0.29890000820159912109375f, 0.58700001239776611328125f, 0.114000000059604644775390625f), float3(0.595899999141693115234375f, -0.2743999958038330078125f, -0.3215999901294708251953125f), float3(0.21150000393390655517578125f, -0.52289998531341552734375f, 0.311399996280670166015625f)), _166.xyz);
        float _177 = pow(_545.x, params_ntsc_gamma);
        float3 _598 = _545;
        _598.x = _177;
        bool _186 = params_ntsc_phase == 4.0f;
        float3 _657;
        if (_186)
        {
            float2 _196 = float2(params_OriginalSize.z / _55, 0.0f);
            float _549 = dot(Source.Sample(_Source_sampler, vTexCoord - _196).xyz, float3(0.29890000820159912109375f, 0.58700001239776611328125f, 0.114000000059604644775390625f));
            float _553 = dot(Source.Sample(_Source_sampler, vTexCoord + _196).xyz, float3(0.29890000820159912109375f, 0.58700001239776611328125f, 0.114000000059604644775390625f));
            float _226 = pow(_549, params_ntsc_gamma);
            float _230 = pow(_553, params_ntsc_gamma);
            float3 _604 = _598;
            _604.x = lerp(min(0.5f * (_177 + max(_226, _230)), max(_177, min(_226, _230))), _177, min(5.0f * abs(_549 - _553), 1.0f));
            _657 = _604;
        }
        else
        {
            _657 = _598;
        }
        bool _260 = MERGE > 0.5f;
        float3 _671;
        if (_260)
        {
            float _562;
            if (phase < 2.5f)
            {
                _562 = 3.1415927410125732421875f * (mod(pix_no.y, 2.0f) + mod(_36 + 1.0f, 2.0f));
            }
            else
            {
                _562 = 2.0944998264312744140625f * (mod(pix_no.y, 3.0f) + mod(_36 + 1.0f, 2.0f));
            }
            float _299 = pix_no.x * CHROMA_MOD_FREQ;
            float _300 = _562 + _299;
            float2 _309 = float2(cos(_300), sin(_300));
            float2 _312 = _657.yz * _309;
            float3 _606 = _657;
            _606.y = _312.x;
            _606.z = _312.y;
            float3 _319 = mul(_76, _606);
            float2 _325 = _319.yz * _309;
            float3 _610 = _319;
            _610.y = _325.x;
            _610.z = _325.y;
            float2 _336 = lerp(_610.yz, _657.yz, _158.xx);
            float _338 = _336.x;
            float3 _614 = _610;
            _614.y = _338;
            _614.z = _336.y;
            float3 _672;
            if (_126 > 1.02499997615814208984375f)
            {
                float _353 = _562 + (_299 * _126);
                float2 _363 = _657.yz * float2(cos(_353), sin(_353));
                float3 _618 = _657;
                _618.y = _363.x;
                _618.z = _363.y;
                _672 = float3(dot(_618, _73), _338, _336.y);
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
        if (phase < 2.5f)
        {
            _573 = 3.1415927410125732421875f * (mod(pix_no.y, 2.0f) + mod(_36, 2.0f));
        }
        else
        {
            _573 = 2.0944998264312744140625f * (mod(pix_no.y, 3.0f) + mod(_36, 2.0f));
        }
        float _402 = pix_no.x * CHROMA_MOD_FREQ;
        float _403 = _573 + _402;
        float2 _412 = float2(cos(_403), sin(_403));
        float2 _415 = _657.yz * _412;
        float3 _625 = _657;
        _625.y = _415.x;
        _625.z = _415.y;
        float3 _422 = mul(_76, _625);
        float2 _428 = _422.yz * _412;
        float3 _629 = _422;
        _629.y = _428.x;
        _629.z = _428.y;
        float2 _439 = lerp(_629.yz, _657.yz, _158.xx);
        float _441 = _439.x;
        float3 _633 = _629;
        _633.y = _441;
        _633.z = _439.y;
        float3 _668;
        if (_126 > 1.02499997615814208984375f)
        {
            float _455 = _573 + (_402 * _126);
            float2 _465 = _657.yz * float2(cos(_455), sin(_455));
            float3 _637 = _657;
            _637.y = _465.x;
            _637.z = _465.y;
            _668 = float3(dot(_637, _73), _441, _439.y);
        }
        else
        {
            _668 = _633;
        }
        float3 _674;
        float3 _676;
        if (_186)
        {
            float3 _644 = _668;
            _644.x = _177;
            float3 _646 = _671;
            _646.x = _177;
            _676 = _646;
            _674 = _644;
        }
        else
        {
            _676 = _671;
            _674 = _668;
        }
        float3 _677;
        if (_260)
        {
            bool _491 = params_ntsc_rainbow1 < 0.5f;
            bool _497;
            if (!_491)
            {
                _497 = phase > 2.5f;
            }
            else
            {
                _497 = _491;
            }
            float3 _678;
            if (_497)
            {
                _678 = (_674 + _676) * 0.5f;
            }
            else
            {
                float3 _650 = _674;
                _650.x = 0.5f * (_674.x + _676.x);
                _678 = _650;
            }
            _677 = _678;
        }
        else
        {
            _677 = _674;
        }
        FragColor = float4(_677, _177);
    }
}

SPIRV_Cross_Output main(SPIRV_Cross_Input stage_input)
{
    BRIGHTNESS = stage_input.BRIGHTNESS;
    FRINGING = stage_input.FRINGING;
    ARTIFACTING = stage_input.ARTIFACTING;
    SATURATION = stage_input.SATURATION;
    vTexCoord = stage_input.vTexCoord;
    phase = stage_input.phase;
    MERGE = stage_input.MERGE;
    pix_no = stage_input.pix_no;
    CHROMA_MOD_FREQ = stage_input.CHROMA_MOD_FREQ;
    frag_main();
    SPIRV_Cross_Output stage_output;
    stage_output.FragColor = FragColor;
    return stage_output;
}
