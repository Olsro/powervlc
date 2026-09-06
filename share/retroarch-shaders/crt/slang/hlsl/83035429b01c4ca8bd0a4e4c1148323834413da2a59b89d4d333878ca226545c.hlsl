// Generated from crt/shaders/crt-aperture.slang. See slang/upstream for licence/source.
cbuffer Push : register(b1)
{
    float4 params_SourceSize : packoffset(c0);
    float4 params_OutputSize : packoffset(c1);
    float params_SHARPNESS_IMAGE : packoffset(c2.y);
    float params_SHARPNESS_EDGES : packoffset(c2.z);
    float params_GLOW_WIDTH : packoffset(c2.w);
    float params_GLOW_HEIGHT : packoffset(c3);
    float params_GLOW_HALATION : packoffset(c3.y);
    float params_GLOW_DIFFUSION : packoffset(c3.z);
    float params_MASK_COLORS : packoffset(c3.w);
    float params_MASK_STRENGTH : packoffset(c4);
    float params_MASK_SIZE : packoffset(c4.y);
    float params_SCANLINE_SIZE_MIN : packoffset(c4.z);
    float params_SCANLINE_SIZE_MAX : packoffset(c4.w);
    float params_SCANLINE_SHAPE : packoffset(c5);
    float params_SCANLINE_OFFSET : packoffset(c5.y);
    float params_GAMMA_INPUT : packoffset(c5.z);
    float params_GAMMA_OUTPUT : packoffset(c5.w);
    float params_BRIGHTNESS : packoffset(c6);
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
    float _1318;
    float _474 = floor(params_OutputSize.y * params_SourceSize.w);
    float2 _491 = params_SourceSize.xy;
    float2 _503 = ((vTexCoord * _491) - float2(0.0f, ((mod(_474, 2.0f) != 0.0f) ? 0.0f : (0.5f / _474)) * params_SCANLINE_OFFSET)) * params_SourceSize.zw;
    float2 _653 = float2(1.0f / params_SourceSize.x, 0.0f);
    float2 _657 = float2(0.0f, 1.0f / params_SourceSize.y);
    float2 _660 = _503 * _491;
    float2 _666 = (floor(_660) + 0.5f.xx) / _491;
    float2 _671 = (frac(_660) - 0.5f.xx) * (-1.0f);
    float2 _674 = _666 - _657;
    float3 _732 = params_GAMMA_INPUT.xxx;
    float2 _682 = _666 + _657;
    float _687 = _671.x;
    float3 _863 = float3(_687 - 1.0f, _687, _687 + 1.0f) / params_GLOW_WIDTH.xxx;
    float3 _868 = exp2((_863 * _863) * (-1.0f));
    float _872 = _868.x;
    float _877 = _868.y;
    float _883 = _868.z;
    float3 _894 = ((_872 + _877) + _883).xxx;
    float _718 = _671.y;
    float3 _998 = float3(_718 - 1.0f, _718, _718 + 1.0f) / params_GLOW_HEIGHT.xxx;
    float3 _1003 = exp2((_998 * _998) * (-1.0f));
    float _1007 = _1003.x;
    float _1012 = _1003.y;
    float _1018 = _1003.z;
    float3 _1030 = (((((((pow(Source.Sample(_Source_sampler, _674 - _653).xyz, _732) * _872) + (pow(Source.Sample(_Source_sampler, _674).xyz, _732) * _877)) + (pow(Source.Sample(_Source_sampler, _674 + _653).xyz, _732) * _883)) / _894) * _1007) + (((((pow(Source.Sample(_Source_sampler, _666 - _653).xyz, _732) * _872) + (pow(Source.Sample(_Source_sampler, _666).xyz, _732) * _877)) + (pow(Source.Sample(_Source_sampler, _666 + _653).xyz, _732) * _883)) / _894) * _1012)) + (((((pow(Source.Sample(_Source_sampler, _682 - _653).xyz, _732) * _872) + (pow(Source.Sample(_Source_sampler, _682).xyz, _732) * _877)) + (pow(Source.Sample(_Source_sampler, _682 + _653).xyz, _732) * _883)) / _894) * _1018)) / ((_1007 + _1012) + _1018).xxx;
    float _1043 = params_SourceSize.x * params_SHARPNESS_IMAGE;
    float2 _1393 = _491;
    _1393.x = _1043;
    float2 _1052 = (_503 * _1393) - float2(0.5f, 0.0f);
    float2 _1057 = (floor(_1052) + float2(0.5f, 0.001000000047497451305389404296875f)) / _1393;
    float2 _1059 = frac(_1052);
    float _1061 = _1059.x;
    float4 _1076 = max(abs(float4(_1061 + 1.0f, _1061, _1061 - 1.0f, _1061 - 2.0f) * 3.1415927410125732421875f), 9.9999997473787516355514526367188e-06f.xxxx);
    float4 _1088 = ((sin(_1076) * 2.0f) * sin(_1076 * 0.5f.xxxx)) / (_1076 * _1076);
    float4 _1138 = float4(pow(Source.Sample(_Source_sampler, _1057).xyz, _732), 1.0f);
    float4 _1140 = float4(pow(Source.Sample(_Source_sampler, _1057 + float2(1.0f / _1043, 0.0f)).xyz, _732), 1.0f);
    float3 _1145 = mul(_1088 / dot(_1088, 1.0f.xxxx).xxxx, float4x4(_1138, _1138, _1140, _1140)).xyz;
    float _1158 = params_SourceSize.x * params_SHARPNESS_EDGES;
    float2 _1401 = _491;
    _1401.x = _1158;
    float2 _1167 = (_503 * _1401) - float2(0.5f, 0.0f);
    float2 _1172 = (floor(_1167) + float2(0.5f, 0.001000000047497451305389404296875f)) / _1401;
    float2 _1174 = frac(_1167);
    float _1176 = _1174.x;
    float4 _1191 = max(abs(float4(_1176 + 1.0f, _1176, _1176 - 1.0f, _1176 - 2.0f) * 3.1415927410125732421875f), 9.9999997473787516355514526367188e-06f.xxxx);
    float4 _1203 = ((sin(_1191) * 2.0f) * sin(_1191 * 0.5f.xxxx)) / (_1191 * _1191);
    float4 _1253 = float4(pow(Source.Sample(_Source_sampler, _1172).xyz, _732), 1.0f);
    float4 _1255 = float4(pow(Source.Sample(_Source_sampler, _1172 + float2(1.0f / _1158, 0.0f)).xyz, _732), 1.0f);
    float3 _1281 = 2.0f.xxx / lerp(params_SCANLINE_SIZE_MIN.xxx, params_SCANLINE_SIZE_MAX.xxx, pow(_1145, (1.0f / params_SCANLINE_SHAPE).xxx));
    float3 _1283 = _1281 * 0.5f;
    float3 _553 = sqrt(mul(_1203 / dot(_1203, 1.0f.xxxx).xxxx, float4x4(_1253, _1253, _1255, _1255)).xyz * _1145) * (smoothstep(0.0f.xxx, 1.0f.xxx, 1.0f.xxx - abs((_1281 * frac(_503.y * params_SourceSize.y)) - _1283)) * _1283);
    float3 _559 = clamp(_1030 - _553, 0.0f.xxx, 1.0f.xxx);
    float3 _568 = _553 + ((_559 * _559) * params_GLOW_HALATION);
    float3 _1338;
    do
    {
        _1318 = params_MASK_COLORS;
        float _1319 = mod(floor(((vTexCoord.x * params_OutputSize.x) * params_SourceSize.x) / (params_SourceSize.x * params_MASK_SIZE)), _1318);
        if (_1319 == 0.0f)
        {
            _1338 = lerp(float3(1.0f, 0.0f, 1.0f), float3(1.0f, 0.0f, 0.0f), (_1318 - 2.0f).xxx);
            break;
        }
        else
        {
            if (_1319 == 1.0f)
            {
                _1338 = float3(0.0f, 1.0f, 0.0f);
                break;
            }
            else
            {
                _1338 = float3(0.0f, 0.0f, 1.0f);
                break;
            }
            break; // unreachable workaround
        }
        break; // unreachable workaround
    } while(false);
    FragColor = float4(pow((lerp(_568, (_568 * _1338) * _1318, params_MASK_STRENGTH.xxx) + (_559 * params_GLOW_DIFFUSION)) * params_BRIGHTNESS, (1.0f / params_GAMMA_OUTPUT).xxx), 1.0f);
}

SPIRV_Cross_Output main(SPIRV_Cross_Input stage_input)
{
    vTexCoord = stage_input.vTexCoord;
    frag_main();
    SPIRV_Cross_Output stage_output;
    stage_output.FragColor = FragColor;
    return stage_output;
}
