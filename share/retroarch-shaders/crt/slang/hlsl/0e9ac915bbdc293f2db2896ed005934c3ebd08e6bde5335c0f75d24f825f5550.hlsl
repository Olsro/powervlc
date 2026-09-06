// Generated from crt/shaders/crt-super-xbr/super-xbr-pass1.slang. See slang/upstream for licence/source.
cbuffer Push : register(b1)
{
    float4 params_SourceSize : packoffset(c0);
    float params_MODE : packoffset(c3.y);
    float params_XBR_EDGE_SHP : packoffset(c3.z);
    float params_XBR_TEXTURE_SHP : packoffset(c3.w);
    float params_XBR_EDGE_STR_P1 : packoffset(c4);
};

Texture2D<float4> XbrSource : register(t3);
SamplerState _XbrSource_sampler : register(s3);
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

void frag_main()
{
    float _1913 = (params_MODE == 1.0f) ? 1.0f : 8.0f;
    float2 _325 = frac(vTexCoord * params_SourceSize.xy);
    float2 _330 = _325 - 0.5f.xx;
    float _333 = _330.x;
    if ((_333 * _330.y) > 0.0f)
    {
        FragColor = lerp(XbrSource.Sample(_XbrSource_sampler, vTexCoord), Source.Sample(_Source_sampler, vTexCoord), step(0.0f, _333).xxxx);
    }
    else
    {
        bool _363 = _325.x > 0.5f;
        float2 _1855;
        if (_363)
        {
            _1855 = float2(0.5f / params_SourceSize.x, 0.0f);
        }
        else
        {
            _1855 = float2(0.0f, 0.5f / params_SourceSize.y);
        }
        float2 _1856;
        if (_363)
        {
            _1856 = float2(0.0f, 0.5f / params_SourceSize.y);
        }
        else
        {
            _1856 = float2(0.5f / params_SourceSize.x, 0.0f);
        }
        float2 _399 = _1855 * 3.0f;
        float4 _401 = XbrSource.Sample(_XbrSource_sampler, vTexCoord - _399);
        float3 _402 = _401.xyz;
        float2 _407 = _1856 * 3.0f;
        float4 _409 = Source.Sample(_Source_sampler, vTexCoord - _407);
        float3 _410 = _409.xyz;
        float4 _417 = Source.Sample(_Source_sampler, vTexCoord + _407);
        float3 _418 = _417.xyz;
        float4 _425 = XbrSource.Sample(_XbrSource_sampler, vTexCoord + _399);
        float3 _426 = _425.xyz;
        float2 _431 = _1855 * 2.0f;
        float2 _432 = vTexCoord - _431;
        float4 _435 = Source.Sample(_Source_sampler, _432 - _1856);
        float3 _436 = _435.xyz;
        float2 _441 = vTexCoord - _1855;
        float2 _443 = _1856 * 2.0f;
        float4 _445 = XbrSource.Sample(_XbrSource_sampler, _441 - _443);
        float3 _446 = _445.xyz;
        float4 _455 = Source.Sample(_Source_sampler, _432 + _1856);
        float3 _456 = _455.xyz;
        float4 _462 = XbrSource.Sample(_XbrSource_sampler, _441);
        float3 _463 = _462.xyz;
        float4 _469 = Source.Sample(_Source_sampler, vTexCoord - _1856);
        float3 _470 = _469.xyz;
        float4 _479 = XbrSource.Sample(_XbrSource_sampler, _441 + _443);
        float3 _480 = _479.xyz;
        float4 _486 = Source.Sample(_Source_sampler, vTexCoord + _1856);
        float3 _487 = _486.xyz;
        float2 _492 = vTexCoord + _1855;
        float4 _493 = XbrSource.Sample(_XbrSource_sampler, _492);
        float3 _494 = _493.xyz;
        float4 _503 = XbrSource.Sample(_XbrSource_sampler, _492 - _443);
        float3 _504 = _503.xyz;
        float2 _510 = vTexCoord + _431;
        float4 _513 = Source.Sample(_Source_sampler, _510 - _1856);
        float3 _514 = _513.xyz;
        float4 _523 = XbrSource.Sample(_XbrSource_sampler, _492 + _443);
        float3 _524 = _523.xyz;
        float4 _533 = Source.Sample(_Source_sampler, _510 + _1856);
        float3 _534 = _533.xyz;
        float _1139 = dot(_436, float3(0.2125999927520751953125f, 0.715200006961822509765625f, 0.072200000286102294921875f));
        float _1143 = dot(_446, float3(0.2125999927520751953125f, 0.715200006961822509765625f, 0.072200000286102294921875f));
        float _1147 = dot(_456, float3(0.2125999927520751953125f, 0.715200006961822509765625f, 0.072200000286102294921875f));
        float _1151 = dot(_463, float3(0.2125999927520751953125f, 0.715200006961822509765625f, 0.072200000286102294921875f));
        float _1155 = dot(_470, float3(0.2125999927520751953125f, 0.715200006961822509765625f, 0.072200000286102294921875f));
        float _1159 = dot(_480, float3(0.2125999927520751953125f, 0.715200006961822509765625f, 0.072200000286102294921875f));
        float _1163 = dot(_487, float3(0.2125999927520751953125f, 0.715200006961822509765625f, 0.072200000286102294921875f));
        float _1167 = dot(_494, float3(0.2125999927520751953125f, 0.715200006961822509765625f, 0.072200000286102294921875f));
        float _1171 = dot(_514, float3(0.2125999927520751953125f, 0.715200006961822509765625f, 0.072200000286102294921875f));
        float _1179 = dot(_534, float3(0.2125999927520751953125f, 0.715200006961822509765625f, 0.072200000286102294921875f));
        float _1187 = dot(_524, float3(0.2125999927520751953125f, 0.715200006961822509765625f, 0.072200000286102294921875f));
        float _1195 = dot(_504, float3(0.2125999927520751953125f, 0.715200006961822509765625f, 0.072200000286102294921875f));
        float _682 = _1913 * ((((abs(_1151 - _1143) + abs(_1151 - _1159)) + abs(_1167 - _1187)) + abs(_1167 - _1195)) - (((abs(_1155 - _1171) + abs(_1155 - _1139)) + abs(_1163 - _1147)) + abs(_1163 - _1179)));
        float4 _1894;
        float3 _1900;
        float3 _1901;
        if (params_MODE == 2.0f)
        {
            float _813 = (smoothstep(0.0f, 0.60000002384185791015625f, max(max(abs(_1151 - _1155), max(abs(_1151 - _1167), max(abs(_1151 - _1163), abs(_1155 - _1163)))), max(abs(_1155 - _1167), abs(_1163 - _1167))) / (_1151 + 0.001000000047497451305389404296875f)) * params_XBR_EDGE_SHP) + params_XBR_TEXTURE_SHP;
            float _829 = _813 * (-0.12963299453258514404296875f);
            float _831 = (0.12963299453258514404296875f * _813) + 0.5f;
            float _839 = _813 * (-0.087534002959728240966796875f);
            float _842 = (0.087534002959728240966796875f * _813) + 0.25f;
            float4 _847 = float4(_839, _842, _842, _839);
            _1901 = mul(_847, float4x3((_402 + ((_446 + _436) * 2.0f)) + _410, (_456 + ((_470 + _463) * 2.0f)) + _504, (_480 + ((_494 + _487) * 2.0f)) + _514, (_418 + ((_534 + _524) * 2.0f)) + _426)) * 0.3333333432674407958984375f.xxx;
            _1900 = mul(_847, float4x3((_402 + ((_456 + _480) * 2.0f)) + _418, (_436 + ((_463 + _487) * 2.0f)) + _524, (_446 + ((_470 + _494) * 2.0f)) + _534, (_410 + ((_504 + _514) * 2.0f)) + _426)) * 0.3333333432674407958984375f.xxx;
            _1894 = float4(_829, _831, _831, _829);
        }
        else
        {
            _1901 = mul(float4(-0.087534002959728240966796875f, 0.337534010410308837890625f, 0.337534010410308837890625f, -0.087534002959728240966796875f), float4x3(_446 + _436, _470 + _463, _494 + _487, _534 + _524));
            _1900 = mul(float4(-0.087534002959728240966796875f, 0.337534010410308837890625f, 0.337534010410308837890625f, -0.087534002959728240966796875f), float4x3(_456 + _480, _463 + _487, _470 + _494, _504 + _514));
            _1894 = float4(-0.12963299453258514404296875f, 0.629633009433746337890625f, 0.629633009433746337890625f, -0.12963299453258514404296875f);
        }
        float3 _1126 = clamp(lerp(lerp(mul(_1894, float4x3(float3(_417.xyz), float3(_486.xyz), float3(_469.xyz), float3(_409.xyz))), mul(_1894, float4x3(float3(_401.xyz), float3(_462.xyz), float3(_493.xyz), float3(_425.xyz))), step(0.0f, _682).xxx), lerp(_1900, _1901, step(0.0f, _1913 * ((((abs(_1155 - _1143) + abs(_1167 - _1179)) + abs(_1151 - _1139)) + abs(_1163 - _1187)) - (((abs(_1151 - _1147) + abs(_1155 - _1195)) + abs(_1163 - _1159)) + abs(_1167 - _1171)))).xxx), (1.0f - smoothstep(0.0f, params_XBR_EDGE_STR_P1 + 9.9999999747524270787835121154785e-07f, abs(_682))).xxx), min(_463, min(_470, min(_487, _494))), max(_463, max(_470, max(_487, _494))));
        FragColor = float4(_1126, 1.0f);
    }
}

SPIRV_Cross_Output main(SPIRV_Cross_Input stage_input)
{
    vTexCoord = stage_input.vTexCoord;
    frag_main();
    SPIRV_Cross_Output stage_output;
    stage_output.FragColor = FragColor;
    return stage_output;
}
