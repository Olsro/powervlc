// Generated from crt/shaders/hyllian/support/ntsc/shaders/ntsc-adaptive-lite/ntsc-lite-pass1.slang. See slang/upstream for licence/source.
cbuffer UBO : register(b0)
{
    uint global_FrameCount : packoffset(c7);
    float global_ntsc_artifacting_rainbow : packoffset(c9.y);
};

Texture2D<float4> Source : register(t2);
SamplerState _Source_sampler : register(s2);

static float2 vTexCoord;
static float MERGE;
static float phase;
static float2 pix_no;
static float CHROMA_MOD_FREQ;
static float BRIGHTNESS;
static float FRINGING;
static float ARTIFACTING;
static float SATURATION;
static float4 FragColor;

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
    float4 _42 = Source.Sample(_Source_sampler, vTexCoord);
    float3 _280 = mul(float3x3(float3(0.29890000820159912109375f, 0.58700001239776611328125f, 0.114000000059604644775390625f), float3(0.595899999141693115234375f, -0.2743999958038330078125f, -0.3215999901294708251953125f), float3(0.21150000393390655517578125f, -0.52289998531341552734375f, 0.311399996280670166015625f)), _42.xyz);
    float3 _309;
    if (MERGE > 0.5f)
    {
        float _281;
        if (phase < 2.5f)
        {
            _281 = 3.1415927410125732421875f * (mod(pix_no.y, 2.0f) + mod(float(global_FrameCount + 1u), 2.0f));
        }
        else
        {
            _281 = 2.0944998264312744140625f * (mod(pix_no.y, 3.0f) + mod(float(global_FrameCount + 1u), 2.0f));
        }
        float _122 = ((global_ntsc_artifacting_rainbow + 1.0f) * _281) + (pix_no.x * CHROMA_MOD_FREQ);
        float2 _131 = float2(cos(_122), sin(_122));
        float2 _134 = _280.yz * _131;
        float3 _289 = _280;
        _289.y = _134.x;
        _289.z = _134.y;
        float _148 = 2.0f * SATURATION;
        float3 _158 = mul(float3x3(float3(BRIGHTNESS, FRINGING, FRINGING), float3(ARTIFACTING, _148, 0.0f), float3(ARTIFACTING, 0.0f, _148)), _289);
        float2 _164 = _158.yz * _131;
        float3 _293 = _158;
        _293.y = _164.x;
        _293.z = _164.y;
        _309 = _293;
    }
    else
    {
        _309 = _280;
    }
    float _286;
    if (phase < 2.5f)
    {
        _286 = 3.1415927410125732421875f * (mod(pix_no.y, 2.0f) + mod(float(global_FrameCount), 2.0f));
    }
    else
    {
        _286 = 2.0944998264312744140625f * (mod(pix_no.y, 3.0f) + mod(float(global_FrameCount), 2.0f));
    }
    float _207 = ((global_ntsc_artifacting_rainbow + 1.0f) * _286) + (pix_no.x * CHROMA_MOD_FREQ);
    float2 _216 = float2(cos(_207), sin(_207));
    float2 _219 = _280.yz * _216;
    float3 _297 = _280;
    _297.y = _219.x;
    _297.z = _219.y;
    float _228 = 2.0f * SATURATION;
    float3 _237 = mul(float3x3(float3(BRIGHTNESS, FRINGING, FRINGING), float3(ARTIFACTING, _228, 0.0f), float3(ARTIFACTING, 0.0f, _228)), _297);
    float2 _243 = _237.yz * _216;
    float3 _301 = _237;
    _301.y = _243.x;
    _301.z = _243.y;
    float3 _287;
    if (MERGE < 0.5f)
    {
        _287 = _301;
    }
    else
    {
        _287 = (_301 + _309) * 0.5f;
    }
    FragColor = float4(_287, 1.0f);
}

SPIRV_Cross_Output main(SPIRV_Cross_Input stage_input)
{
    vTexCoord = stage_input.vTexCoord;
    MERGE = stage_input.MERGE;
    phase = stage_input.phase;
    pix_no = stage_input.pix_no;
    CHROMA_MOD_FREQ = stage_input.CHROMA_MOD_FREQ;
    BRIGHTNESS = stage_input.BRIGHTNESS;
    FRINGING = stage_input.FRINGING;
    ARTIFACTING = stage_input.ARTIFACTING;
    SATURATION = stage_input.SATURATION;
    frag_main();
    SPIRV_Cross_Output stage_output;
    stage_output.FragColor = FragColor;
    return stage_output;
}
