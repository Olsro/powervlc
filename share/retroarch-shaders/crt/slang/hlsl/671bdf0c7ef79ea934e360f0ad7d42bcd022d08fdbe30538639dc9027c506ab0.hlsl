// Generated from crt/shaders/crt-easymode-halation/crt-easymode-halation.slang. See slang/upstream for licence/source.
static float4 _1516;

cbuffer UBO : register(b0)
{
    uint global_FrameCount : packoffset(c4);
};

cbuffer Push : register(b1)
{
    float4 params_SourceSize : packoffset(c0);
    float4 params_OutputSize : packoffset(c1);
    float params_GAMMA_OUTPUT : packoffset(c2);
    float params_SHARPNESS_H : packoffset(c2.y);
    float params_SHARPNESS_V : packoffset(c2.z);
    float params_MASK_TYPE : packoffset(c2.w);
    float params_MASK_STRENGTH_MIN : packoffset(c3);
    float params_MASK_STRENGTH_MAX : packoffset(c3.y);
    float params_MASK_SIZE : packoffset(c3.z);
    float params_SCANLINE_STRENGTH_MIN : packoffset(c3.w);
    float params_SCANLINE_STRENGTH_MAX : packoffset(c4);
    float params_SCANLINE_BEAM_MIN : packoffset(c4.y);
    float params_SCANLINE_BEAM_MAX : packoffset(c4.z);
    float params_GEOM_CURVATURE : packoffset(c4.w);
    float params_GEOM_WARP : packoffset(c5);
    float params_GEOM_CORNER_SIZE : packoffset(c5.y);
    float params_GEOM_CORNER_SMOOTH : packoffset(c5.z);
    float params_INTERLACING_TOGGLE : packoffset(c5.w);
    float params_HALATION : packoffset(c6);
    float params_DIFFUSION : packoffset(c6.y);
    float params_BRIGHTNESS : packoffset(c6.z);
};

Texture2D<float4> ORIG_LINEARIZED : register(t3);
SamplerState _ORIG_LINEARIZED_sampler : register(s3);
Texture2D<float4> Source : register(t2);
SamplerState _Source_sampler : register(s2);

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
    float2 _246 = params_SourceSize.xy;
    bool _268 = params_INTERLACING_TOGGLE > 0.5f;
    bool _275;
    if (_268)
    {
        _275 = params_SourceSize.y >= 400.0f;
    }
    else
    {
        _275 = _268;
    }
    float _1344;
    float2 _1499;
    float2 _1501;
    if (_275)
    {
        float2 _1439 = _246;
        _1439.y = params_SourceSize.y * 0.5f;
        bool _284 = mod(float(global_FrameCount), 2.0f) > 0.0f;
        float2 _1502;
        if (_284)
        {
            _1502 = float2(0.5f, 0.75f);
        }
        else
        {
            _1502 = float2(0.5f, 0.25f);
        }
        _1501 = _1502;
        _1499 = _1439;
        _1344 = _284 ? 0.5f : 0.0f;
    }
    else
    {
        _1501 = 0.5f.xx;
        _1499 = _246;
        _1344 = 0.0f;
    }
    float2 _299 = (vTexCoord * _1499) * params_SourceSize.zw;
    float2 _862 = float2(params_GEOM_WARP, params_GEOM_WARP * 0.75f);
    float2 _879 = (float2(_299.yx) * 2.0f) - 1.0f.xx;
    float2 _884 = _879 * _879;
    float2 _895 = float2(params_GEOM_CURVATURE, params_GEOM_CURVATURE * 0.75f);
    float2 _918 = lerp(_299, (_299 + (_299 * _895)) - (_895 * 0.5f.xx), _884);
    float2 _319 = params_GEOM_CORNER_SIZE.xx;
    float2 _932 = _319 - min(min(_918, 1.0f.xx - _918) * float2(1.0f, 0.75f), _319);
    float2 _333 = lerp(_299, (_299 + (_299 * _862)) - (_862 * 0.5f.xx), _884) * (_246 / _1499);
    float2 _338 = float2(1.0f / _1499.x, 0.0f);
    float2 _343 = float2(0.0f, 1.0f / _1499.y);
    float2 _349 = (_333 * _1499) - _1501;
    float2 _356 = (floor(_349) + _1501) / _1499;
    float2 _359 = frac(_349);
    float _369 = _359.x;
    float _957 = _369 - step(0.5f, _369);
    float _972 = lerp(_369, 0.5f - (sqrt(0.25f - (_957 * _957)) * sign(0.5f - _369)), params_SHARPNESS_H * params_SHARPNESS_H);
    float _381 = _359.y;
    float _981 = _381 - step(0.5f, _381);
    float _996 = lerp(_381, 0.5f - (sqrt(0.25f - (_981 * _981)) * sign(0.5f - _381)), params_SHARPNESS_V * params_SHARPNESS_V);
    float4 _408 = max(abs(float4(1.0f + _972, _972, 1.0f - _972, 2.0f - _972) * 3.1415927410125732421875f), 9.9999997473787516355514526367188e-06f.xxxx);
    float4 _420 = ((sin(_408) * 2.0f) * sin(_408 * 0.5f.xxxx)) / (_408 * _408);
    float4 _426 = _420 / dot(_420, 1.0f.xxxx).xxxx;
    float4 _430 = max(abs(float4(1.0f + _996, _996, 1.0f - _996, 2.0f - _996) * 3.1415927410125732421875f), 9.9999997473787516355514526367188e-06f.xxxx);
    float4 _442 = ((sin(_430) * 2.0f) * sin(_430 * 0.5f.xxxx)) / (_430 * _430);
    float2 _452 = _356 - _343;
    float4 _1006 = ORIG_LINEARIZED.Sample(_ORIG_LINEARIZED_sampler, _452);
    float4 _1011 = ORIG_LINEARIZED.Sample(_ORIG_LINEARIZED_sampler, _452 + _338);
    float2 _1015 = _338 * 2.0f;
    float4 _1071 = ORIG_LINEARIZED.Sample(_ORIG_LINEARIZED_sampler, _356);
    float4 _1076 = ORIG_LINEARIZED.Sample(_ORIG_LINEARIZED_sampler, _356 + _338);
    float4 _1125 = clamp(mul(_426, float4x4(ORIG_LINEARIZED.Sample(_ORIG_LINEARIZED_sampler, _356 - _338), _1071, _1076, ORIG_LINEARIZED.Sample(_ORIG_LINEARIZED_sampler, _356 + _1015))), min(_1071, _1076), max(_1071, _1076));
    float2 _474 = _356 + _343;
    float4 _1136 = ORIG_LINEARIZED.Sample(_ORIG_LINEARIZED_sampler, _474);
    float4 _1141 = ORIG_LINEARIZED.Sample(_ORIG_LINEARIZED_sampler, _474 + _338);
    float4 _1190 = clamp(mul(_426, float4x4(ORIG_LINEARIZED.Sample(_ORIG_LINEARIZED_sampler, _474 - _338), _1136, _1141, ORIG_LINEARIZED.Sample(_ORIG_LINEARIZED_sampler, _474 + _1015))), min(_1136, _1141), max(_1136, _1141));
    float2 _487 = _356 + (_343 * 2.0f);
    float4 _1201 = ORIG_LINEARIZED.Sample(_ORIG_LINEARIZED_sampler, _487);
    float4 _1206 = ORIG_LINEARIZED.Sample(_ORIG_LINEARIZED_sampler, _487 + _338);
    float4 _1278 = clamp(mul(_442 / dot(_442, 1.0f.xxxx).xxxx, float4x4(clamp(mul(_426, float4x4(ORIG_LINEARIZED.Sample(_ORIG_LINEARIZED_sampler, _452 - _338), _1006, _1011, ORIG_LINEARIZED.Sample(_ORIG_LINEARIZED_sampler, _452 + _1015))), min(_1006, _1011), max(_1006, _1011)), _1125, _1190, clamp(mul(_426, float4x4(ORIG_LINEARIZED.Sample(_ORIG_LINEARIZED_sampler, _487 - _338), _1201, _1206, ORIG_LINEARIZED.Sample(_ORIG_LINEARIZED_sampler, _487 + _1015))), min(_1201, _1206), max(_1201, _1206)))), min(_1125, _1190), max(_1125, _1190));
    float4 _509 = Source.Sample(_Source_sampler, _333);
    float3 _510 = _509.xyz;
    float _520 = max(_1278.x, max(_1278.y, _1278.z));
    float _528 = (params_SourceSize.y * params_OutputSize.w) * 0.5f;
    float _536 = (_333.y * _1499.y) + _1344;
    float _545 = lerp(params_SCANLINE_STRENGTH_MAX, params_SCANLINE_STRENGTH_MIN, _520);
    float _557 = clamp(_520 * params_SCANLINE_BEAM_MAX, params_SCANLINE_BEAM_MIN, params_SCANLINE_BEAM_MAX);
    float4 _1507;
    if (params_MASK_TYPE == 1.0f)
    {
        _1507 = float4(2.0f, 1.0f, 1.0f, 0.0f);
    }
    else
    {
        float4 _1508;
        if (params_MASK_TYPE == 2.0f)
        {
            _1508 = float4(3.0f, 1.0f, 1.0f, 0.0f);
        }
        else
        {
            float4 _1509;
            if (params_MASK_TYPE == 3.0f)
            {
                _1509 = float4(2.099999904632568359375f, 1.0f, 1.0f, 0.0f);
            }
            else
            {
                float4 _1510;
                if (params_MASK_TYPE == 4.0f)
                {
                    _1510 = float4(3.099999904632568359375f, 1.0f, 1.0f, 0.0f);
                }
                else
                {
                    float4 _1511;
                    if (params_MASK_TYPE == 5.0f)
                    {
                        _1511 = float4(2.0f, 1.0f, 1.0f, 1.0f);
                    }
                    else
                    {
                        float4 _1512;
                        if (params_MASK_TYPE == 6.0f)
                        {
                            _1512 = float4(3.0f, 2.0f, 1.0f, 3.0f);
                        }
                        else
                        {
                            float4 _1513;
                            if (params_MASK_TYPE == 7.0f)
                            {
                                _1513 = float4(3.0f, 2.0f, 2.0f, 3.0f);
                            }
                            else
                            {
                                _1513 = _1516;
                            }
                            _1512 = _1513;
                        }
                        _1511 = _1512;
                    }
                    _1510 = _1511;
                }
                _1509 = _1510;
            }
            _1508 = _1509;
        }
        _1507 = _1508;
    }
    float _620 = floor(_1507.x);
    float2 _659 = floor(((vTexCoord * params_OutputSize.xy) * _246) / (_246 * float2(params_MASK_SIZE, _1507.z * params_MASK_SIZE)));
    float _663 = _659.x;
    float _665 = _659.y;
    int _674 = int(mod((_663 + (mod(_665, 2.0f) * _1507.w)) / _1507.y, _620));
    float _694 = lerp(params_MASK_STRENGTH_MAX, params_MASK_STRENGTH_MIN, _520);
    float _697 = 1.0f - _694;
    float _701 = 1.0f + (_694 * 2.0f);
    float3 _1365;
    if (_674 == 0)
    {
        _1365 = lerp(_701.xxx, float3(_701, _697, _697), (_620 - 2.0f).xxx);
    }
    else
    {
        float3 _1366;
        if (_674 == 1)
        {
            _1366 = lerp(_697.xxx, float3(_697, _701, _697), (_620 - 2.0f).xxx);
        }
        else
        {
            _1366 = float3(_697, _697, _701);
        }
        _1365 = _1366;
    }
    float3 _755 = lerp(1.0f.xxx, _1365 * lerp(1.0f, (mod(_665 + mod(floor(_663 / _620), 2.0f), 2.0f) > 0.89999997615814208984375f) ? _697 : _701, frac(_1507.x) * 10.0f), clamp(params_MASK_TYPE, 0.0f, 1.0f).xxx);
    float3 _764 = (_1278.xyz * _755) * params_BRIGHTNESS;
    float _1297 = 1.0f - _545;
    float3 _846 = pow(lerp(1.0f, clamp((params_GEOM_CORNER_SIZE - sqrt(dot(_932, _932))) * params_GEOM_CORNER_SMOOTH, 0.0f, 1.0f), ceil(params_GEOM_CORNER_SIZE)).xxx * (((((clamp(_764 * ((((1.0f - pow((cos((_536 - _528) * 6.283185482025146484375f) * 0.5f) + 0.5f, _557)) * _545) * 2.0f) + _1297).xxx, 0.0f.xxx, 1.0f.xxx) + clamp(_764 * ((((1.0f - pow((cos(_536 * 6.283185482025146484375f) * 0.5f) + 0.5f, _557)) * _545) * 2.0f) + _1297).xxx, 0.0f.xxx, 1.0f.xxx)) + clamp(_764 * ((((1.0f - pow((cos((_536 + _528) * 6.283185482025146484375f) * 0.5f) + 0.5f, _557)) * _545) * 2.0f) + _1297).xxx, 0.0f.xxx, 1.0f.xxx)) * 0.3333333432674407958984375f.xxx) + ((_510 * _755) * params_HALATION)) + (_510 * params_DIFFUSION)), (1.0f / params_GAMMA_OUTPUT).xxx);
    FragColor = float4(_846, 1.0f);
}

SPIRV_Cross_Output main(SPIRV_Cross_Input stage_input)
{
    vTexCoord = stage_input.vTexCoord;
    frag_main();
    SPIRV_Cross_Output stage_output;
    stage_output.FragColor = FragColor;
    return stage_output;
}
