// Generated from crt/shaders/zfast_crt/zfast_crt_composite.slang. See slang/upstream for licence/source.
cbuffer Push : register(b1)
{
    float4 params_SourceSize : packoffset(c0);
    float4 params_OriginalSize : packoffset(c1);
    uint params_FrameCount : packoffset(c3);
    float params_BLURSCALEX : packoffset(c3.y);
    float params_LOWLUMSCAN : packoffset(c3.z);
    float params_HILUMSCAN : packoffset(c3.w);
    float params_BRIGHTBOOST : packoffset(c4);
    float params_MASK_DARK : packoffset(c4.y);
    float params_FINEMASK : packoffset(c4.w);
    float params_WARP : packoffset(c5);
    float params_sharp : packoffset(c5.y);
    float params_chroma_gain : packoffset(c5.z);
};

Texture2D<float4> Source : register(t2);
SamplerState _Source_sampler : register(s2);

static float2 invDims;
static float2 vTexCoord;
static float2 maskpos;
static float maskFade;
static float4 FragColor;

struct SPIRV_Cross_Input
{
    float2 vTexCoord : TEXCOORD0;
    float maskFade : TEXCOORD1;
    float2 invDims : TEXCOORD2;
    float2 maskpos : TEXCOORD3;
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
    float2 _177 = float2(invDims.x, 0.0f);
    bool _184 = params_OriginalSize.y > 300.0f;
    float2 _826;
    if (_184)
    {
        _826 = vTexCoord + (float2(0.0f, params_SourceSize.w) * mod(float(params_FrameCount), 2.0f));
    }
    else
    {
        _826 = vTexCoord;
    }
    float2 _530 = (_826 * 2.0f) - 1.0f.xx;
    float _532 = _530.y;
    float _541 = _530.x;
    float2 _554 = (_530 * float2(1.0f + ((_532 * _532) * params_WARP), 1.0f + (((_541 * _541) * params_WARP) * 1.5f))) * 0.5f;
    float2 _556 = _554 + 0.5f.xx;
    float2 _215 = min(_556, 0.5f.xx - _554);
    float _219 = 9.9999997473787516355514526367188e-06f / _215.x;
    float2 _227 = _556 * params_SourceSize.xy;
    float2 _232 = floor(_227) + 0.5f.xx;
    float2 _236 = _227 - _232;
    float2 _247 = (_232 + (((_236 * 4.0f) * _236) * _236)) * invDims;
    _247.x = lerp(_247.x, _556.x, params_BLURSCALEX);
    float _827;
    if (_184)
    {
        float _269 = (_556.y * params_SourceSize.y) * 0.5f;
        _827 = _269 - (floor(_269) + 0.5f);
    }
    else
    {
        _827 = _236.y;
    }
    float _286 = _827 * _827;
    float _290 = _286 * _286;
    float _833;
    if (params_FINEMASK == 0.0f)
    {
        _833 = 1.0f + (float(frac(floor(maskpos.x) * (-0.4999000132083892822265625f)) < 0.5f) * (-params_MASK_DARK));
    }
    else
    {
        _833 = 1.0f + (float(frac(floor(maskpos.x) * (-0.33329999446868896484375f)) <= 0.3333300054073333740234375f) * (-params_MASK_DARK));
    }
    float4 _339 = Source.Sample(_Source_sampler, _247);
    float _568 = _339.x;
    float _570 = _339.y;
    float _572 = _339.z;
    float4 _348 = Source.Sample(_Source_sampler, _247 - _177);
    float _614 = _348.x;
    float _616 = _348.y;
    float _618 = _348.z;
    float2 _356 = _177 * 2.0f;
    float4 _358 = Source.Sample(_Source_sampler, _247 - _356);
    float4 _367 = Source.Sample(_Source_sampler, _247 + _177);
    float _706 = _367.x;
    float _708 = _367.y;
    float _710 = _367.z;
    float4 _377 = Source.Sample(_Source_sampler, _247 + _356);
    float _398 = (((params_sharp * (((0.2989999949932098388671875f * _568) + (0.58700001239776611328125f * _570)) + (0.114000000059604644775390625f * _572))) + (((0.2989999949932098388671875f * _614) + (0.58700001239776611328125f * _616)) + (0.114000000059604644775390625f * _618))) + (((0.2989999949932098388671875f * _706) + (0.58700001239776611328125f * _708)) + (0.114000000059604644775390625f * _710))) * (1.0f / (params_sharp + 2.0f));
    float _437 = (((((0.596000015735626220703125f * _568) + (((-0.273999989032745361328125f) * _570) - (0.3219999969005584716796875f * _572))) + ((0.596000015735626220703125f * _614) + (((-0.273999989032745361328125f) * _616) - (0.3219999969005584716796875f * _618)))) + ((0.596000015735626220703125f * _706) + (((-0.273999989032745361328125f) * _708) - (0.3219999969005584716796875f * _710)))) * 0.3999600112438201904296875f) * params_chroma_gain;
    float _441 = (((((((0.2109999954700469970703125f * _568) + (((-0.5230000019073486328125f) * _570) + (0.3120000064373016357421875f * _572))) + ((0.2109999954700469970703125f * _614) + (((-0.5230000019073486328125f) * _616) + (0.3120000064373016357421875f * _618)))) + ((0.2109999954700469970703125f * _706) + (((-0.5230000019073486328125f) * _708) + (0.3120000064373016357421875f * _710)))) + ((0.2109999954700469970703125f * _358.x) + (((-0.5230000019073486328125f) * _358.y) + (0.3120000064373016357421875f * _358.z)))) + ((0.2109999954700469970703125f * _377.x) + (((-0.5230000019073486328125f) * _377.y) + (0.3120000064373016357421875f * _377.z)))) * 0.16000001132488250732421875f) * params_chroma_gain;
    float3 _825 = float3((_398 + (0.95599997043609619140625f * _437)) + (0.620999991893768310546875f * _441), (_398 - (0.272000014781951904296875f * _437)) - (0.647000014781951904296875f * _441), (_398 - (1.10599994659423828125f * _437)) + (1.70299994945526123046875f * _441));
    float3 _483 = _825 * lerp((params_BRIGHTBOOST - (params_LOWLUMSCAN * (_286 - (2.0499999523162841796875f * _290)))) * _833, 1.0f - (params_HILUMSCAN * (_290 - ((2.7999999523162841796875f * _290) * _286))), dot(_825, maskFade.xxx));
    bool _486 = params_WARP != 0.0f;
    bool _494;
    if (_486)
    {
        _494 = _215.y < _219;
    }
    else
    {
        _494 = _486;
    }
    bool _507;
    if (!_494)
    {
        bool _506;
        if (_486)
        {
            _506 = _219 < 9.9999997473787516355514526367188e-06f;
        }
        else
        {
            _506 = _486;
        }
        _507 = _506;
    }
    else
    {
        _507 = _494;
    }
    bool3 _842 = _507.xxx;
    float3 _843 = float3(_842.x ? 0.0f.xxx.x : _483.x, _842.y ? 0.0f.xxx.y : _483.y, _842.z ? 0.0f.xxx.z : _483.z);
    FragColor.x = _843.x;
    FragColor.y = _843.y;
    FragColor.z = _843.z;
}

SPIRV_Cross_Output main(SPIRV_Cross_Input stage_input)
{
    invDims = stage_input.invDims;
    vTexCoord = stage_input.vTexCoord;
    maskpos = stage_input.maskpos;
    maskFade = stage_input.maskFade;
    frag_main();
    SPIRV_Cross_Output stage_output;
    stage_output.FragColor = FragColor;
    return stage_output;
}
