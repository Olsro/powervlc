// Generated from crt/shaders/crt-yo6/crt-yo6-flat-trinitron-tv.slang. See slang/upstream for licence/source.
cbuffer Push : register(b1)
{
    float4 params_SourceSize : packoffset(c0);
    float params_GAMMA : packoffset(c4.z);
};

Texture2D<float4> Source : register(t2);
SamplerState _Source_sampler : register(s2);
Texture2D<float4> TEX : register(t3);
SamplerState _TEX_sampler : register(s3);

static float2 vXY;
static float4 patNFO;
static float vOff;
static float4 crtSize;
static float4 FragColor;

struct SPIRV_Cross_Input
{
    float2 vXY : TEXCOORD0;
    float4 patNFO : TEXCOORD1;
    float4 crtSize : TEXCOORD2;
    float vOff : TEXCOORD3;
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
    float _50 = (floor(vXY.y / patNFO.y) + vOff) + 0.5f;
    float3 dst = 0.0f.xxx;
    float3 src;
    for (int _222 = 0; _222 < 3; )
    {
        float2 _80 = vXY + float2(float(1 - _222) * patNFO.z, 0.0f);
        src = Source.Sample(_Source_sampler, float2((floor(_80.x / patNFO.x) + 0.5f) / crtSize.z, _50 / params_SourceSize.y)).xyz;
        dst[_222] = TEX.Sample(_TEX_sampler, (float2(floor(pow(src[_222], params_GAMMA) * 255.0f) * patNFO.x, patNFO.w) + mod(_80, patNFO.xy)) * float2(0.00039062500582076609134674072265625f, 0.008547008968889713287353515625f)).x;
        _222++;
        continue;
    }
    float2 _188 = (sign(float2(_50, params_SourceSize.y - _50)) + 1.0f.xx) * 0.5f.xx;
    float2 _202 = (sign(vXY) + 1.0f.xx) * 0.5f.xx;
    float2 _216 = (sign(crtSize.xy - vXY) + 1.0f.xx) * 0.5f.xx;
    FragColor = float4(dst * (((_188.x * _188.y) * (_202.x * _202.y)) * (_216.x * _216.y)), 1.0f);
}

SPIRV_Cross_Output main(SPIRV_Cross_Input stage_input)
{
    vXY = stage_input.vXY;
    patNFO = stage_input.patNFO;
    vOff = stage_input.vOff;
    crtSize = stage_input.crtSize;
    frag_main();
    SPIRV_Cross_Output stage_output;
    stage_output.FragColor = FragColor;
    return stage_output;
}
