// Generated from crt/shaders/gizmo-slotmask-crt.slang. See slang/upstream for licence/source.
cbuffer Push : register(b1)
{
    float4 params_OutputSize : packoffset(c2);
    uint params_FrameCount : packoffset(c3);
    float params_CURVATURE_X : packoffset(c3.y);
    float params_CURVATURE_Y : packoffset(c3.z);
    float params_BRIGHTNESS : packoffset(c3.w);
    float params_HORIZONTAL_BLUR : packoffset(c4);
    float params_VERTICAL_BLUR : packoffset(c4.y);
    float params_BLUR_OFFSET : packoffset(c4.z);
    float params_BGR_LCD_PATTERN : packoffset(c4.w);
    float params_SHRINK : packoffset(c5);
    float params_SNR : packoffset(c5.y);
    float params_COLOUR_BLEEDING : packoffset(c5.z);
    float params_GRID : packoffset(c5.w);
    float params_SLOTMASK : packoffset(c6);
};

Texture2D<float4> Source : register(t2);
SamplerState _Source_sampler : register(s2);

static float4 gl_FragCoord;
static float2 vTexCoord;
static float4 FragColor;

struct SPIRV_Cross_Input
{
    float2 vTexCoord : TEXCOORD0;
    float4 gl_FragCoord : SV_Position;
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

uint2 spvTextureSize(Texture2D<float4> Tex, uint Level, out uint Param)
{
    uint2 ret;
    Tex.GetDimensions(Level, ret.x, ret.y, Param);
    return ret;
}

void frag_main()
{
    do
    {
        float2 _90 = float2(params_CURVATURE_X, params_CURVATURE_Y);
        uint _622_dummy_parameter;
        float2 _623 = float2(int2(spvTextureSize(Source, uint(0), _622_dummy_parameter)));
        float2 _627 = vTexCoord;
        float2 _1739;
        if (params_SHRINK > 0.0f)
        {
            float _636 = _627.x - 0.5f;
            float2 _1680 = _627;
            _1680.x = _636;
            float _643 = _636 * (1.0f + params_SHRINK);
            _1680.x = _643;
            _1680.x = _643 + 0.5f;
            _1739 = _1680;
        }
        else
        {
            _1739 = _627;
        }
        float2 _767 = _1739 - 0.5f.xx;
        float _769 = _767.x;
        float _774 = _767.y;
        float2 _788 = (_767 + (_767 * (_90 * ((_769 * _769) + (_774 * _774))))) * (1.0f.xx - (_90 * 0.23000000417232513427734375f));
        bool _792 = abs(_788.x) >= 0.5f;
        bool _800;
        if (!_792)
        {
            _800 = abs(_788.y) >= 0.5f;
        }
        else
        {
            _800 = _792;
        }
        float2 _1741;
        if (_800)
        {
            _1741 = (-1.0f).xx;
        }
        else
        {
            _1741 = _788 + 0.5f.xx;
        }
        if (_1741.x < 0.0f)
        {
            FragColor = 0.0f.xxxx;
            break;
        }
        float2 _667 = _1741 * params_OutputSize.xy;
        float2 _673 = _623 / params_OutputSize.xy;
        float _812 = float(params_FrameCount);
        float _820 = _667.y + (sin(_812 * 5.502500057220458984375f) * 0.100000001490116119384765625f);
        float2 _1696 = _667;
        _1696.y = _820;
        float _827 = _820 * _673.y;
        float _688 = _667.x;
        float _839 = 0.3333333432674407958984375f + params_COLOUR_BLEEDING;
        float3 _841 = _688.xxx;
        float3 _1742;
        if (params_BGR_LCD_PATTERN == 1.0f)
        {
            float3 _1706 = _841;
            _1706.x = _688 + (_839 * 2.0f);
            _1742 = _1706;
        }
        else
        {
            float3 _1703 = _841;
            _1703.z = _688 + (_839 * 2.0f);
            _1742 = _1703;
        }
        bool _922;
        float3 _1709 = _1742;
        _1709.y = _1742.y + _839;
        float3 _867 = _1709 * _673.x;
        float2 _701 = float2(_867.x / _623.x, _1741.y);
        float2 _708 = float2(_867.y, _827) / _623;
        float2 _715 = float2(_867.z, _827) / _623;
        float4 _1613;
        do
        {
            uint _905_dummy_parameter;
            float2 _906 = float2(int2(spvTextureSize(Source, uint(0), _905_dummy_parameter)));
            float2 _1001 = _701 * _906;
            float2 _1005 = fwidth(_1001);
            float2 _1011 = clamp(frac(_1001) / clamp(_1005, 0.0f.xx, 1.0f.xx), 0.0f.xx, 1.0f.xx) + floor(_1001);
            _922 = params_HORIZONTAL_BLUR == 1.0f;
            if (_922)
            {
                float _931 = (-0.5f) - params_BLUR_OFFSET;
                float4 _938 = Source.Sample(_Source_sampler, (_1011 + (-0.5f).xx) / _906);
                float4 _941 = Source.Sample(_Source_sampler, (_1011 + float2(_931, -0.5f)) / _906);
                float4 _945 = (_938 + _941) * 0.5f.xxxx;
                float4 _1612;
                if (params_VERTICAL_BLUR == 1.0f)
                {
                    _1612 = (((Source.Sample(_Source_sampler, (_1011 + float2(-0.5f, _931)) / _906) + Source.Sample(_Source_sampler, (_1011 + _931.xx) / _906)) * 0.5f.xxxx) + _945) * 0.5f.xxxx;
                }
                else
                {
                    _1612 = _945;
                }
                _1613 = _1612;
                break;
            }
            else
            {
                _1613 = Source.Sample(_Source_sampler, (_1011 + (-0.5f).xx) / _906);
                break;
            }
            break; // unreachable workaround
        } while(false);
        float4 _1617;
        do
        {
            uint _1049_dummy_parameter;
            float2 _1050 = float2(int2(spvTextureSize(Source, uint(0), _1049_dummy_parameter)));
            float2 _1145 = _708 * _1050;
            float2 _1149 = fwidth(_1145);
            float2 _1155 = clamp(frac(_1145) / clamp(_1149, 0.0f.xx, 1.0f.xx), 0.0f.xx, 1.0f.xx) + floor(_1145);
            if (_922)
            {
                float _1075 = (-0.5f) - params_BLUR_OFFSET;
                float4 _1082 = Source.Sample(_Source_sampler, (_1155 + (-0.5f).xx) / _1050);
                float4 _1085 = Source.Sample(_Source_sampler, (_1155 + float2(_1075, -0.5f)) / _1050);
                float4 _1089 = (_1082 + _1085) * 0.5f.xxxx;
                float4 _1616;
                if (params_VERTICAL_BLUR == 1.0f)
                {
                    _1616 = (((Source.Sample(_Source_sampler, (_1155 + float2(-0.5f, _1075)) / _1050) + Source.Sample(_Source_sampler, (_1155 + _1075.xx) / _1050)) * 0.5f.xxxx) + _1089) * 0.5f.xxxx;
                }
                else
                {
                    _1616 = _1089;
                }
                _1617 = _1616;
                break;
            }
            else
            {
                _1617 = Source.Sample(_Source_sampler, (_1155 + (-0.5f).xx) / _1050);
                break;
            }
            break; // unreachable workaround
        } while(false);
        float4 _1623;
        do
        {
            uint _1193_dummy_parameter;
            float2 _1194 = float2(int2(spvTextureSize(Source, uint(0), _1193_dummy_parameter)));
            float2 _1289 = _715 * _1194;
            float2 _1293 = fwidth(_1289);
            float2 _1299 = clamp(frac(_1289) / clamp(_1293, 0.0f.xx, 1.0f.xx), 0.0f.xx, 1.0f.xx) + floor(_1289);
            if (_922)
            {
                float _1219 = (-0.5f) - params_BLUR_OFFSET;
                float4 _1226 = Source.Sample(_Source_sampler, (_1299 + (-0.5f).xx) / _1194);
                float4 _1229 = Source.Sample(_Source_sampler, (_1299 + float2(_1219, -0.5f)) / _1194);
                float4 _1233 = (_1226 + _1229) * 0.5f.xxxx;
                float4 _1622;
                if (params_VERTICAL_BLUR == 1.0f)
                {
                    _1622 = (((Source.Sample(_Source_sampler, (_1299 + float2(-0.5f, _1219)) / _1194) + Source.Sample(_Source_sampler, (_1299 + _1219.xx) / _1194)) * 0.5f.xxxx) + _1233) * 0.5f.xxxx;
                }
                else
                {
                    _1622 = _1233;
                }
                _1623 = _1622;
                break;
            }
            else
            {
                _1623 = Source.Sample(_Source_sampler, (_1299 + (-0.5f).xx) / _1194);
                break;
            }
            break; // unreachable workaround
        } while(false);
        FragColor = float4(_1613.x, _1617.y, _1623.z, 1.0f);
        FragColor = clamp((FragColor + (frac(tan(distance(_1696 * 1.61803400516510009765625f, _1696) * sin(_812 * 0.02500000037252902984619140625f)) * _688) * (params_SNR * 0.03125f)).xxxx) - (params_SNR * 0.015625f).xxxx, 0.0f.xxxx, 1.0f.xxxx);
        float4 _729 = FragColor;
        uint _1370_dummy_parameter;
        uint _1420_dummy_parameter;
        float2 _1426 = (_701 * float2(int2(spvTextureSize(Source, uint(0), _1420_dummy_parameter)))) + 0.5f.xx;
        float2 _1431 = _1426 - floor(_1426);
        uint _1456_dummy_parameter;
        float2 _1462 = (_708 * float2(int2(spvTextureSize(Source, uint(0), _1456_dummy_parameter)))) + 0.5f.xx;
        float2 _1467 = _1462 - floor(_1462);
        uint _1492_dummy_parameter;
        float2 _1498 = (_715 * float2(int2(spvTextureSize(Source, uint(0), _1492_dummy_parameter)))) + 0.5f.xx;
        float2 _1503 = _1498 - floor(_1498);
        float3 _1405 = _729.xyz - (abs(((1.0f.xxx - _729.xyz) * 1.5f) * (0.5f.xxx - float3(abs((((_1431 * _1431) * _1431) * ((_1431 * ((_1431 * 6.0f) - 15.0f.xx)) + 10.0f.xx)).y - 0.5f), abs((((_1467 * _1467) * _1467) * ((_1467 * ((_1467 * 6.0f) - 15.0f.xx)) + 10.0f.xx)).y - 0.5f), abs((((_1503 * _1503) * _1503) * ((_1503 * ((_1503 * 6.0f) - 15.0f.xx)) + 10.0f.xx)).y - 0.5f)))) * (0.02500000037252902984619140625f * ((params_OutputSize.y / float2(int2(spvTextureSize(Source, uint(0), _1370_dummy_parameter))).y) / params_BRIGHTNESS)));
        float4 _1718 = _729;
        _1718.x = _1405.x;
        _1718.y = _1405.y;
        _1718.z = _1405.z;
        FragColor = _1718;
        uint _1528_dummy_parameter;
        float _1534 = params_OutputSize.x / float2(int2(spvTextureSize(Source, uint(0), _1528_dummy_parameter))).y;
        float4 _1659;
        if (mod(floor(gl_FragCoord.x), 3.0f) == 0.0f)
        {
            _1659 = lerp(FragColor, float4(0.0f, 0.0f, 0.0f, _1534 * 0.125f), params_GRID.xxxx);
        }
        else
        {
            float4 _1660;
            if (params_SLOTMASK == 1.0f)
            {
                float _1559 = frac(gl_FragCoord.x * 0.16666667163372039794921875f);
                bool _1564 = (_1559 >= 0.16599999368190765380859375f) && (_1559 <= 0.5f);
                bool _1574;
                if (_1564)
                {
                    _1574 = mod(floor(gl_FragCoord.y + 1.0f), 3.0f) == 0.0f;
                }
                else
                {
                    _1574 = _1564;
                }
                bool _1592;
                if (!_1574)
                {
                    bool _1581 = (_1559 >= 0.66600000858306884765625f) && (_1559 <= 1.0f);
                    bool _1590;
                    if (_1581)
                    {
                        _1590 = mod(floor(gl_FragCoord.y), 3.0f) == 0.0f;
                    }
                    else
                    {
                        _1590 = _1581;
                    }
                    _1592 = _1590;
                }
                else
                {
                    _1592 = _1574;
                }
                float4 _1661;
                if (_1592)
                {
                    _1661 = lerp(FragColor, float4(0.0f, 0.0f, 0.0f, _1534 * 0.125f), (params_GRID * 0.300000011920928955078125f).xxxx);
                }
                else
                {
                    _1661 = FragColor;
                }
                _1660 = _1661;
            }
            else
            {
                _1660 = FragColor;
            }
            _1659 = _1660;
        }
        FragColor = _1659;
        FragColor.w = 1.0f;
        break;
    } while(false);
}

SPIRV_Cross_Output main(SPIRV_Cross_Input stage_input)
{
    gl_FragCoord = stage_input.gl_FragCoord;
    gl_FragCoord.w = 1.0 / gl_FragCoord.w;
    vTexCoord = stage_input.vTexCoord;
    frag_main();
    SPIRV_Cross_Output stage_output;
    stage_output.FragColor = FragColor;
    return stage_output;
}
