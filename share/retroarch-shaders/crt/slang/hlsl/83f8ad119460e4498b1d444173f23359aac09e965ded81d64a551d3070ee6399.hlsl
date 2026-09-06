// Generated from crt/shaders/crt-Cyclon.slang. See slang/upstream for licence/source.
static float3 _1102;

cbuffer UBO : register(b0)
{
    float global_BLACK : packoffset(c4);
    float global_RG : packoffset(c4.y);
    float global_RB : packoffset(c4.z);
    float global_GB : packoffset(c4.w);
    float global_POTATO : packoffset(c5);
    float global_SATURATION : packoffset(c5.y);
    float global_BRIGHTNESS_ : packoffset(c5.z);
    float global_bzl : packoffset(c5.w);
    float global_zoomx : packoffset(c6);
    float global_zoomy : packoffset(c6.y);
    float global_centerx : packoffset(c6.z);
    float global_centery : packoffset(c6.w);
    float global_vig : packoffset(c7);
    float global_ambient : packoffset(c7.y);
    float4 global_SourceSize : packoffset(c8);
    float4 global_OriginalSize : packoffset(c9);
    float4 global_OutputSize : packoffset(c10);
    uint global_FrameCount : packoffset(c11);
};

cbuffer Push : register(b1)
{
    float params_SCANLINE : packoffset(c0);
    float params_INTERLACE : packoffset(c0.y);
    float params_M_TYPE : packoffset(c0.z);
    float params_MSIZE : packoffset(c0.w);
    float params_SLOT : packoffset(c1);
    float params_SLOTW : packoffset(c1.y);
    float params_BGR : packoffset(c1.z);
    float params_Maskl : packoffset(c1.w);
    float params_Maskh : packoffset(c2);
    float params_CONV_R : packoffset(c2.y);
    float params_CONV_G : packoffset(c2.z);
    float params_CONV_B : packoffset(c2.w);
    float params_WARPX : packoffset(c3);
    float params_WARPY : packoffset(c3.y);
    float params_BR_DEP : packoffset(c3.z);
    float params_c_space : packoffset(c3.w);
    float params_REFLECT : packoffset(c4);
};

Texture2D<float4> bezel : register(t2);
SamplerState _bezel_sampler : register(s2);
Texture2D<float4> stock : register(t4);
SamplerState _stock_sampler : register(s4);
Texture2D<float4> blur : register(t3);
SamplerState _blur_sampler : register(s3);

static float2 vTexCoord;
static float2 scale;
static float4 FragColor;

struct SPIRV_Cross_Input
{
    float2 vTexCoord : TEXCOORD0;
    float2 scale : TEXCOORD1;
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
    float2 _861 = (((vTexCoord * float2(1.0f - global_zoomx, 1.0f - global_zoomy)) - (float2(global_centerx, global_centery) * 0.00999999977648258209228515625f.xx)) * 2.0f) - 1.0f.xx;
    float _863 = _861.y;
    float _872 = _861.x;
    float2 _886 = ((_861 * float2(1.0f + ((_863 * _863) * params_WARPX), 1.0f + ((_872 * _872) * params_WARPY))) * 0.5f) + 0.5f.xx;
    float4 _1313;
    if (global_bzl == 1.0f)
    {
        _1313 = bezel.Sample(_bezel_sampler, (((vTexCoord * global_SourceSize.xy) / global_OriginalSize.xy) * 0.9700000286102294921875f) + 0.014999999664723873138427734375f.xx);
    }
    else
    {
        _1313 = 0.0f.xxxx;
    }
    float2 _447 = float2(global_SourceSize.z, 0.0f);
    float2 _453 = _886 * global_SourceSize.xy;
    float2 _462 = floor(_453) + 0.5f.xx;
    float _467 = _462.y;
    float _468 = _453.y - _467;
    float2 _1334 = float2(lerp(_886.x, _462.x * global_SourceSize.z, 0.20000000298023223876953125f), (_467 + (((4.0f * _468) * _468) * _468)) * global_SourceSize.w);
    float4 _497 = stock.Sample(_stock_sampler, _1334);
    float3 _548 = float3(0.5f * (_497.x + stock.Sample(_stock_sampler, _1334 + (_447 * params_CONV_R)).x), 0.5f * (_497.y + stock.Sample(_stock_sampler, _1334 + (_447 * params_CONV_G)).y), 0.5f * (_497.z + stock.Sample(_stock_sampler, _1334 + (_447 * params_CONV_B)).z));
    float3 _567 = lerp(_1313.xyz, global_ambient.xxx + (blur.Sample(_blur_sampler, _1334).xyz * params_REFLECT), 0.5f.xxx);
    float4 _1265 = _1313;
    _1265.x = _567.x;
    _1265.y = _567.y;
    _1265.z = _567.z;
    float _1145;
    if (global_vig == 1.0f)
    {
        float _587 = (vTexCoord.x * scale.x) - 0.5f;
        _1145 = _587 * _587;
    }
    else
    {
        _1145 = 0.0f;
    }
    float _596 = dot(params_BR_DEP.xxx, _548);
    float3 _1140;
    if (params_c_space != 0.0f)
    {
        float3 _1129;
        if (params_c_space == 1.0f)
        {
            _1129 = mul(float3x3(float3(1.07400000095367431640625f, -0.0573999993503093719482421875f, -0.011900000274181365966796875f), float3(0.038400001823902130126953125f, 0.96990001201629638671875f, -0.005900000222027301788330078125f), float3(-0.0078999996185302734375f, 0.02040000073611736297607421875f, 0.988399982452392578125f)), _548);
        }
        else
        {
            _1129 = _548;
        }
        float3 _1134;
        if (params_c_space == 2.0f)
        {
            _1134 = mul(float3x3(float3(0.93180000782012939453125f, 0.0412000007927417755126953125f, 0.02170000039041042327880859375f), float3(0.013500000350177288055419921875f, 0.97109997272491455078125f, 0.014800000004470348358154296875f), float3(0.0054999999701976776123046875f, -0.0142999999225139617919921875f, 1.00849997997283935546875f)), _1129);
        }
        else
        {
            _1134 = _1129;
        }
        float3 _1135;
        if (params_c_space == 3.0f)
        {
            _1135 = mul(float3x3(float3(0.950100004673004150390625f, -0.04309999942779541015625f, 0.085699997842311859130859375f), float3(0.02649999968707561492919921875f, 0.927799999713897705078125f, 0.04320000112056732177734375f), float3(0.0010999999940395355224609375f, -0.02060000039637088775634765625f, 1.31529998779296875f)), _1134);
        }
        else
        {
            _1135 = _1134;
        }
        _1140 = clamp(_1135 * float3(1.20833337306976318359375f, 0.8695652484893798828125f, 1.5714285373687744140625f), 0.0f.xxx, 1.0f.xxx);
    }
    else
    {
        _1140 = _548;
    }
    float _648 = _886.y * global_SourceSize.y;
    float _1137;
    if (global_OriginalSize.y > 400.0f)
    {
        float _664 = frac((_648 * 0.5f) - 0.5f);
        float _1138;
        if (params_INTERLACE == 1.0f)
        {
            float _1136;
            if (mod(float(global_FrameCount), 2.0f) < 1.0f)
            {
                _1136 = _664;
            }
            else
            {
                _1136 = _664 + 0.5f;
            }
            _1138 = _1136;
        }
        else
        {
            _1138 = _664;
        }
        _1137 = _1138;
    }
    else
    {
        _1137 = frac(_648 - 0.5f);
    }
    float3 _949;
    float _901 = params_SCANLINE + (0.1500000059604644775390625f * dot(_1140, (0.25f - (0.800000011920928955078125f * _1145)).xxx));
    float _904 = _1137 / _901;
    float _929 = (1.0f - _1137) / _901;
    float2 _720 = ((vTexCoord * global_OutputSize.xy) * scale) / params_MSIZE.xx;
    float _728 = lerp(params_Maskl, params_Maskh, _596);
    float3 _1160;
    do
    {
        _949 = _728.xxx;
        if (params_M_TYPE == 0.0f)
        {
            if (global_POTATO == 1.0f)
            {
                _1160 = (((1.0f - _728) * sin(_720.x * 3.1415927410125732421875f)) + _728).xxx;
                break;
            }
            else
            {
                float3 _1316;
                if (frac(_720.x * 0.5f) < 0.5f)
                {
                    float3 _1276 = _949;
                    _1276.x = 1.0f;
                    _1276.z = 1.0f;
                    _1316 = _1276;
                }
                else
                {
                    float3 _1274 = _949;
                    _1274.y = 1.0f;
                    _1316 = _1274;
                }
                _1160 = _1316;
                break;
            }
            break; // unreachable workaround
        }
        if (params_M_TYPE == 1.0f)
        {
            if (global_POTATO == 1.0f)
            {
                _1160 = (((1.0f - _728) * sin(_720.x * 2.0944998264312744140625f)) + _728).xxx;
                break;
            }
            else
            {
                float _1009 = frac(_720.x * 0.33329999446868896484375f);
                float3 _1314;
                if (_1009 < 0.33329999446868896484375f)
                {
                    float3 _1159;
                    if (params_BGR == 0.0f)
                    {
                        _1159 = float3(_728, _728, 1.0f);
                    }
                    else
                    {
                        _1159 = float3(1.0f, _728, _728);
                    }
                    _1314 = _1159;
                }
                else
                {
                    float3 _1315;
                    if (_1009 < 0.6665999889373779296875f)
                    {
                        float3 _1286 = _949;
                        _1286.y = 1.0f;
                        _1315 = _1286;
                    }
                    else
                    {
                        float3 _1158;
                        if (params_BGR == 0.0f)
                        {
                            _1158 = float3(1.0f, _728, _728);
                        }
                        else
                        {
                            _1158 = float3(_728, _728, 1.0f);
                        }
                        _1315 = _1158;
                    }
                    _1314 = _1315;
                }
                _1160 = _1314;
                break;
            }
            break; // unreachable workaround
        }
        else
        {
            _1160 = 1.0f.xxx;
            break;
        }
        break; // unreachable workaround
    } while(false);
    float3 _735 = (_1140 * (((0.4000000059604644775390625f * exp((-_904) * _904)) / _901) + ((0.4000000059604644775390625f * exp((-_929) * _929)) / _901))) * _1160;
    float3 _1186;
    if (params_SLOT == 1.0f)
    {
        float2 _743 = _720 * 0.5f.xx;
        float3 _1175;
        do
        {
            float _1074 = frac(_743.x / params_SLOTW);
            bool _1079 = frac(_743.y) < 0.5f;
            if (_1079)
            {
                if (_1074 < 0.5f)
                {
                    _1175 = 0.5f.xxx;
                    break;
                }
                else
                {
                    _1175 = 1.5f.xxx;
                    break;
                }
                break; // unreachable workaround
            }
            else
            {
                if (!_1079)
                {
                    if (_1074 < 0.5f)
                    {
                        _1175 = 1.5f.xxx;
                        break;
                    }
                    else
                    {
                        _1175 = 0.5f.xxx;
                        break;
                    }
                    break; // unreachable workaround
                }
            }
            _1175 = _1102;
            break;
        } while(false);
        _1186 = _735 * lerp(_1175, 1.0f.xxx, _949);
    }
    else
    {
        _1186 = _735;
    }
    float3 _1197;
    if (global_POTATO == 0.0f)
    {
        float3 _1110 = _1186 - 1.0f.xxx;
        _1197 = lerp(sqrt(_1186), sqrt(1.0f.xxx - (_1110 * _1110)), ((1.0f / ((((-1.0f) * params_SCANLINE) + 1.0f) * (((-0.800000011920928955078125f) * _728) + 1.0f))) - 1.2000000476837158203125f).xxx);
    }
    else
    {
        _1197 = sqrt(_1186) * lerp(1.2999999523162841796875f, 1.10000002384185791015625f, _596);
    }
    float3 _810 = (mul(float3x3(float3(1.0f, -global_RG, -global_RB), float3(global_RG, 1.0f, -global_GB), float3(global_RB, global_GB, 1.0f)), lerp(dot(float3(0.2899999916553497314453125f, 0.60000002384185791015625f, 0.10999999940395355224609375f), _1197).xxx, _1197, global_SATURATION.xxx) * global_BRIGHTNESS_) - global_BLACK.xxx) * (1.0f / (1.0f - global_BLACK));
    float3 _1217;
    if (global_bzl > 0.0f)
    {
        _1217 = lerp(max(_810, 0.0f.xxx), pow(abs(_1265.xyz), 1.39999997615814208984375f.xxx), (_1313.w * _1313.w).xxx);
    }
    else
    {
        _1217 = _810;
    }
    FragColor = float4(_1217, 1.0f);
}

SPIRV_Cross_Output main(SPIRV_Cross_Input stage_input)
{
    vTexCoord = stage_input.vTexCoord;
    scale = stage_input.scale;
    frag_main();
    SPIRV_Cross_Output stage_output;
    stage_output.FragColor = FragColor;
    return stage_output;
}
