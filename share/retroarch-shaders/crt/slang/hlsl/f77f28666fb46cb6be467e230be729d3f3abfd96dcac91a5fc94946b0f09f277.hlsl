// Generated from crt/shaders/crt-geom-mini.slang. See slang/upstream for licence/source.
static float2 _489;

cbuffer Push : register(b1)
{
    float4 params_SourceSize : packoffset(c0);
    float4 params_OriginalSize : packoffset(c1);
    uint params_FrameCount : packoffset(c3);
    float params_CURV : packoffset(c3.y);
    float params_scanlines : packoffset(c3.z);
    float params_MASK : packoffset(c3.w);
    float params_INTERL : packoffset(c4);
    float params_SAT : packoffset(c4.y);
};

Texture2D<float4> Source : register(t1);
SamplerState _Source_sampler : register(s1);

static float2 vTexCoord;
static float maskpos;
static float4 FragColor;

struct SPIRV_Cross_Input
{
    float2 vTexCoord : TEXCOORD0;
    float maskpos : TEXCOORD1;
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
    float2 _91 = float2(params_SourceSize.z * 0.5f, 0.0f);
    bool _96 = params_CURV == 1.0f;
    float2 _483;
    float2 _488;
    if (_96)
    {
        float2 _375 = vTexCoord - 0.5f.xx;
        float _377 = _375.x;
        float _382 = _375.y;
        float2 _396 = (_375 + (_375 * (float2(0.119999997317790985107421875f, 0.25f) * ((_377 * _377) + (_382 * _382))))) * float2(0.9700000286102294921875f, 0.944999992847442626953125f);
        bool _400 = abs(_396.x) >= 0.5f;
        bool _408;
        if (!_400)
        {
            _408 = abs(_396.y) >= 0.5f;
        }
        else
        {
            _408 = _400;
        }
        float2 _482;
        if (_408)
        {
            _482 = (-1.0f).xx;
        }
        else
        {
            _482 = _396 + 0.5f.xx;
        }
        float2 _110 = min(_482, 1.0f.xx - _482);
        _110.x = 9.9999997473787516355514526367188e-05f / _110.x;
        _488 = _110;
        _483 = _482;
    }
    else
    {
        _488 = _489;
        _483 = vTexCoord;
    }
    float2 _122 = _91 * 2.0f;
    float2 _124 = _483 - _122;
    float2 _131 = _483 * params_SourceSize.xy;
    float2 _134 = floor(_131) + 0.5f.xx;
    float2 _142 = _131 - _134;
    float _147 = _142.y;
    _124.y = (_134.y + (((((16.0f * _147) * _147) * _147) * _147) * _147)) * params_SourceSize.w;
    float4 _173 = Source.Sample(_Source_sampler, _124);
    float4 _184 = Source.Sample(_Source_sampler, _124 + _122);
    float4 _196 = Source.Sample(_Source_sampler, _124 + (_91 * 3.0f));
    float4 _208 = Source.Sample(_Source_sampler, _124 + (_91 * 4.0f));
    float3 _217 = ((((_173.xyz * (-1.60000002384185791015625f)) + (_184.xyz * 3.2999999523162841796875f)) + (_196.xyz * 5.599999904632568359375f)) + (_208.xyz * (-1.5f))) * 0.17241378128528594970703125f.xxx;
    float _221 = dot(0.25f.xxx, _217);
    float _231 = lerp(params_scanlines, params_scanlines * 0.60000002384185791015625f, _221);
    bool _238 = params_OriginalSize.y > 400.0f;
    bool _244 = params_INTERL == 1.0f;
    bool _250;
    if (_244)
    {
        _250 = _238;
    }
    else
    {
        _250 = _244;
    }
    float _432;
    if (_250)
    {
        _432 = (mod(float(params_FrameCount), 2.0f) < 1.0f) ? 0.75f : 0.25f;
    }
    else
    {
        _432 = 0.25f;
    }
    float3 _309 = (_217 * ((((_231 * sin((((_483.y * params_SourceSize.y) * (_238 ? 0.5f : 1.0f)) - _432) * 6.28318500518798828125f)) + 1.0f) - _231) * (((params_MASK * sin(maskpos)) + 1.0f) - params_MASK))) * lerp(1.4500000476837158203125f, 1.0499999523162841796875f, _221);
    float3 _327 = clamp(lerp(dot(float3(0.2899999916553497314453125f, 0.60000002384185791015625f, 0.10999999940395355224609375f), _309).xxx, _309, params_SAT.xxx), 0.0f.xxx, 1.0f.xxx);
    bool _332 = _488.y <= _488.x;
    bool _338;
    if (_332)
    {
        _338 = _96;
    }
    else
    {
        _338 = _332;
    }
    bool _351;
    if (!_338)
    {
        bool _344 = _488.x < 9.9999997473787516355514526367188e-05f;
        bool _350;
        if (_344)
        {
            _350 = _96;
        }
        else
        {
            _350 = _344;
        }
        _351 = _350;
    }
    else
    {
        _351 = _338;
    }
    bool3 _454 = _351.xxx;
    float3 _357 = sqrt(float3(_454.x ? 0.0f.xxx.x : _327.x, _454.y ? 0.0f.xxx.y : _327.y, _454.z ? 0.0f.xxx.z : _327.z));
    FragColor.x = _357.x;
    FragColor.y = _357.y;
    FragColor.z = _357.z;
}

SPIRV_Cross_Output main(SPIRV_Cross_Input stage_input)
{
    vTexCoord = stage_input.vTexCoord;
    maskpos = stage_input.maskpos;
    frag_main();
    SPIRV_Cross_Output stage_output;
    stage_output.FragColor = FragColor;
    return stage_output;
}
