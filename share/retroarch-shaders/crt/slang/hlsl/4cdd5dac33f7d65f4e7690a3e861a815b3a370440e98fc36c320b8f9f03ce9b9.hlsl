// Generated from crt/shaders/fake-crt-geom.slang. See slang/upstream for licence/source.
cbuffer Push : register(b1)
{
    float4 params_SourceSize : packoffset(c0);
    float4 params_OriginalSize : packoffset(c1);
    uint params_FrameCount : packoffset(c3);
    float params_warpx : packoffset(c3.y);
    float params_warpy : packoffset(c3.z);
    float params_a_vignette : packoffset(c3.w);
    float params_a_vigstr : packoffset(c4);
    float params_a_col_temp : packoffset(c4.y);
    float params_a_sat : packoffset(c4.z);
    float params_a_boostd : packoffset(c4.w);
    float params_a_boostb : packoffset(c5);
    float params_a_interlace : packoffset(c5.y);
    float params_scanl : packoffset(c5.z);
    float params_scanh : packoffset(c5.w);
    float params_a_MASK : packoffset(c6);
    float params_a_MTYPE : packoffset(c6.z);
    float params_a_corner : packoffset(c6.w);
    float params_bsmooth : packoffset(c7);
};

Texture2D<float4> Source : register(t1);
SamplerState _Source_sampler : register(s1);

static float2 vTexCoord;
static float2 ps;
static float maskpos;
static float4 FragColor;

struct SPIRV_Cross_Input
{
    float2 vTexCoord : TEXCOORD0;
    float2 ps : TEXCOORD1;
    float maskpos : TEXCOORD2;
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
    float2 _109 = params_SourceSize.xy / params_OriginalSize.xy;
    float2 _445 = ((vTexCoord * _109) * 2.0f) - 1.0f.xx;
    float _447 = _445.y;
    float _456 = _445.x;
    float2 _468 = (_445 * float2(1.0f + ((_447 * _447) * params_warpx), 1.0f + ((_456 * _456) * params_warpy))) * 0.5f;
    float2 _470 = _468 + 0.5f.xx;
    float2 _129 = (_470 / _109) * params_SourceSize.xy;
    float2 _133 = _129 - 0.5f.xx;
    float2 _136 = frac(_133);
    float2 _143 = (floor(_133) + 0.5f.xx) * ps;
    float _148 = _136.x;
    float4 _164 = max(abs(float4(1.0f + _148, _148, 1.0f - _148, 2.0f - _148) * 3.1415920257568359375f), 9.9999997473787516355514526367188e-06f.xxxx);
    float4 _175 = ((sin(_164) * 2.0f) * sin(_164 * 0.5f)) / (_164 * _164);
    float4 _250 = clamp(mul(_175 / dot(_175, 1.0f.xxxx).xxxx, float4x4(Source.Sample(_Source_sampler, _143 + float2(-ps.x, 0.0f)), Source.Sample(_Source_sampler, _143), Source.Sample(_Source_sampler, _143 + float2(ps.x, 0.0f)), Source.Sample(_Source_sampler, _143 + float2(2.0f * ps.x, 0.0f)))), 0.0f.xxxx, 1.0f.xxxx);
    float3 _273 = _250.xyz * float3(1.0f + params_a_col_temp, 1.0f - (params_a_col_temp * 0.20000000298023223876953125f), 1.0f - params_a_col_temp);
    float4 _528 = _250;
    _528.x = _273.x;
    _528.y = _273.y;
    _528.z = _273.z;
    float _289 = lerp(params_scanl, params_scanh, dot(0.3300000131130218505859375f.xxx, _250.xyz));
    float _500;
    if (params_a_MTYPE == 2.0f)
    {
        _500 = _129.x * 6.283184051513671875f;
    }
    else
    {
        _500 = maskpos;
    }
    float _511;
    if (params_a_vignette == 1.0f)
    {
        float _334 = _470.x - 0.5f;
        _511 = (_334 * _334) * params_a_vigstr;
    }
    else
    {
        _511 = 0.0f;
    }
    float2 _562;
    if (params_OriginalSize.y > 400.0f)
    {
        float2 _350 = _129 * 0.5f.xx;
        bool _357 = mod(float(params_FrameCount), 2.0f) > 0.0f;
        bool _364;
        if (_357)
        {
            _364 = params_a_interlace == 1.0f;
        }
        else
        {
            _364 = _357;
        }
        float2 _563;
        if (_364)
        {
            _563 = _350 + 0.5f.xx;
        }
        else
        {
            _563 = _350;
        }
        _562 = _563;
    }
    else
    {
        _562 = _129;
    }
    float4 _387 = (_528 * (((params_a_MASK * sin(_500 * ((params_a_MTYPE == 1.0f) ? 0.6665999889373779296875f : 1.0f))) + 1.0f) - params_a_MASK)) * (((_289 + _511) * sin((_562.y + 0.25f) * 6.283184051513671875f)) + ((1.0f - _289) - _511));
    float3 _390 = _387.xyz;
    float _395 = dot(_390, float3(0.300000011920928955078125f, 0.60000002384185791015625f, 0.100000001490116119384765625f));
    float3 _404 = lerp(_395.xxx, _390, params_a_sat.xxx);
    float4 _537 = _387;
    _537.x = _404.x;
    _537.y = _404.y;
    _537.z = _404.z;
    float2 _482 = params_a_corner.xx;
    float2 _487 = _482 - min(min(_470, 0.5f.xx - _468), _482);
    float3 _429 = sqrt((_537 * lerp(params_a_boostd, params_a_boostb, _395)).xyz) * clamp((params_a_corner - sqrt(dot(_487, _487))) * params_bsmooth, 0.0f, 1.0f);
    FragColor.x = _429.x;
    FragColor.y = _429.y;
    FragColor.z = _429.z;
}

SPIRV_Cross_Output main(SPIRV_Cross_Input stage_input)
{
    vTexCoord = stage_input.vTexCoord;
    ps = stage_input.ps;
    maskpos = stage_input.maskpos;
    frag_main();
    SPIRV_Cross_Output stage_output;
    stage_output.FragColor = FragColor;
    return stage_output;
}
