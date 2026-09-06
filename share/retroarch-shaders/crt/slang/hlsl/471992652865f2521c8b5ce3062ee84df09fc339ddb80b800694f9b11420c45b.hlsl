// Generated from crt/shaders/gizmo-crt.slang. See slang/upstream for licence/source.
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
};

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
        float2 _80 = float2(params_CURVATURE_X, params_CURVATURE_Y);
        uint _485_dummy_parameter;
        float2 _486 = float2(int2(spvTextureSize(Source, uint(0), _485_dummy_parameter)));
        float2 _490 = vTexCoord;
        float2 _1361;
        if (params_SHRINK > 0.0f)
        {
            float _499 = _490.y - 0.5f;
            float2 _1314 = _490;
            _1314.y = _499;
            float _506 = _499 * (1.0f + params_SHRINK);
            _1314.y = _506;
            _1314.y = _506 + 0.5f;
            _1361 = _1314;
        }
        else
        {
            _1361 = _490;
        }
        float2 _615 = _1361 - 0.5f.xx;
        float _617 = _615.x;
        float _622 = _615.y;
        float2 _636 = (_615 + (_615 * (_80 * ((_617 * _617) + (_622 * _622))))) * (1.0f.xx - (_80 * 0.23000000417232513427734375f));
        bool _640 = abs(_636.x) >= 0.5f;
        bool _648;
        if (!_640)
        {
            _648 = abs(_636.y) >= 0.5f;
        }
        else
        {
            _648 = _640;
        }
        float2 _1363;
        if (_648)
        {
            _1363 = (-1.0f).xx;
        }
        else
        {
            _1363 = _636 + 0.5f.xx;
        }
        if (_1363.x < 0.0f)
        {
            FragColor = 0.0f.xxxx;
            break;
        }
        float2 _530 = _1363 * params_OutputSize.xy;
        float2 _536 = _486 / params_OutputSize.xy;
        float _659 = _530.y * _536.y;
        float _548 = _530.x;
        float3 _670 = _548.xxx;
        float3 _1364;
        if (params_BGR_LCD_PATTERN == 1.0f)
        {
            float3 _1337 = _670;
            _1337.x = _548 + 0.66600000858306884765625f;
            _1364 = _1337;
        }
        else
        {
            float3 _1334 = _670;
            _1334.z = _548 + 0.66600000858306884765625f;
            _1364 = _1334;
        }
        bool _751;
        float3 _1340 = _1364;
        _1340.y = _1364.y + 0.333000004291534423828125f;
        float3 _696 = _1340 * _536.x;
        float2 _561 = float2(_696.x / _486.x, _1363.y);
        float4 _1271;
        do
        {
            uint _734_dummy_parameter;
            float2 _735 = float2(int2(spvTextureSize(Source, uint(0), _734_dummy_parameter)));
            float2 _830 = _561 * _735;
            float2 _834 = fwidth(_830);
            float2 _840 = clamp(frac(_830) / clamp(_834, 0.0f.xx, 1.0f.xx), 0.0f.xx, 1.0f.xx) + floor(_830);
            _751 = params_HORIZONTAL_BLUR == 1.0f;
            if (_751)
            {
                float _760 = (-0.5f) + params_BLUR_OFFSET;
                float4 _767 = Source.Sample(_Source_sampler, (_840 + (-0.5f).xx) / _735);
                float4 _770 = Source.Sample(_Source_sampler, (_840 + float2(_760, -0.5f)) / _735);
                float4 _774 = (_767 + _770) * 0.5f.xxxx;
                float4 _1270;
                if (params_VERTICAL_BLUR == 1.0f)
                {
                    _1270 = (((Source.Sample(_Source_sampler, (_840 + float2(-0.5f, _760)) / _735) + Source.Sample(_Source_sampler, (_840 + _760.xx) / _735)) * 0.5f.xxxx) + _774) * 0.5f.xxxx;
                }
                else
                {
                    _1270 = _774;
                }
                _1271 = _1270;
                break;
            }
            else
            {
                _1271 = Source.Sample(_Source_sampler, (_840 + (-0.5f).xx) / _735);
                break;
            }
            break; // unreachable workaround
        } while(false);
        float4 _1275;
        do
        {
            uint _878_dummy_parameter;
            float2 _879 = float2(int2(spvTextureSize(Source, uint(0), _878_dummy_parameter)));
            float2 _974 = (float2(_696.y, _659) / _486) * _879;
            float2 _978 = fwidth(_974);
            float2 _984 = clamp(frac(_974) / clamp(_978, 0.0f.xx, 1.0f.xx), 0.0f.xx, 1.0f.xx) + floor(_974);
            if (_751)
            {
                float _904 = (-0.5f) + params_BLUR_OFFSET;
                float4 _911 = Source.Sample(_Source_sampler, (_984 + (-0.5f).xx) / _879);
                float4 _914 = Source.Sample(_Source_sampler, (_984 + float2(_904, -0.5f)) / _879);
                float4 _918 = (_911 + _914) * 0.5f.xxxx;
                float4 _1274;
                if (params_VERTICAL_BLUR == 1.0f)
                {
                    _1274 = (((Source.Sample(_Source_sampler, (_984 + float2(-0.5f, _904)) / _879) + Source.Sample(_Source_sampler, (_984 + _904.xx) / _879)) * 0.5f.xxxx) + _918) * 0.5f.xxxx;
                }
                else
                {
                    _1274 = _918;
                }
                _1275 = _1274;
                break;
            }
            else
            {
                _1275 = Source.Sample(_Source_sampler, (_984 + (-0.5f).xx) / _879);
                break;
            }
            break; // unreachable workaround
        } while(false);
        float4 _1281;
        do
        {
            uint _1022_dummy_parameter;
            float2 _1023 = float2(int2(spvTextureSize(Source, uint(0), _1022_dummy_parameter)));
            float2 _1118 = (float2(_696.z, _659) / _486) * _1023;
            float2 _1122 = fwidth(_1118);
            float2 _1128 = clamp(frac(_1118) / clamp(_1122, 0.0f.xx, 1.0f.xx), 0.0f.xx, 1.0f.xx) + floor(_1118);
            if (_751)
            {
                float _1048 = (-0.5f) + params_BLUR_OFFSET;
                float4 _1055 = Source.Sample(_Source_sampler, (_1128 + (-0.5f).xx) / _1023);
                float4 _1058 = Source.Sample(_Source_sampler, (_1128 + float2(_1048, -0.5f)) / _1023);
                float4 _1062 = (_1055 + _1058) * 0.5f.xxxx;
                float4 _1280;
                if (params_VERTICAL_BLUR == 1.0f)
                {
                    _1280 = (((Source.Sample(_Source_sampler, (_1128 + float2(-0.5f, _1048)) / _1023) + Source.Sample(_Source_sampler, (_1128 + _1048.xx) / _1023)) * 0.5f.xxxx) + _1062) * 0.5f.xxxx;
                }
                else
                {
                    _1280 = _1062;
                }
                _1281 = _1280;
                break;
            }
            else
            {
                _1281 = Source.Sample(_Source_sampler, (_1128 + (-0.5f).xx) / _1023);
                break;
            }
            break; // unreachable workaround
        } while(false);
        FragColor = float4(_1271.x, _1275.y, _1281.z, 255.0f);
        FragColor = clamp((FragColor + (frac(tan(distance(_530 * 1.61803400516510009765625f, _530) * sin(float(params_FrameCount) * 0.02500000037252902984619140625f)) * _548) * 0.03125f).xxxx) - 0.015625f.xxxx, 0.0f.xxxx, 1.0f.xxxx);
        float4 _589 = FragColor;
        uint _1190_dummy_parameter;
        uint _1236_dummy_parameter;
        float2 _1242 = (_561 * float2(int2(spvTextureSize(Source, uint(0), _1236_dummy_parameter)))) + 0.5f.xx;
        float2 _1247 = _1242 - floor(_1242);
        float3 _1221 = _589.xyz - (abs(((1.0f.xxx - _589.xyz) * 1.5f) * abs(abs(abs((((_1247 * _1247) * _1247) * ((_1247 * ((_1247 * 6.0f) - 15.0f.xx)) + 10.0f.xx)).y - 0.5f) - 0.5f))) * (0.02500000037252902984619140625f * ((params_OutputSize.y / float2(int2(spvTextureSize(Source, uint(0), _1190_dummy_parameter))).y) / params_BRIGHTNESS)));
        float4 _1349 = _589;
        _1349.x = _1221.x;
        _1349.y = _1221.y;
        _1349.z = _1221.z;
        FragColor = _1349;
        FragColor.w = 1.0f;
        break;
    } while(false);
}

SPIRV_Cross_Output main(SPIRV_Cross_Input stage_input)
{
    vTexCoord = stage_input.vTexCoord;
    frag_main();
    SPIRV_Cross_Output stage_output;
    stage_output.FragColor = FragColor;
    return stage_output;
}
