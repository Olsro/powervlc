// Generated from crt/shaders/hyllian/crt-hyllian-fast.slang. See slang/upstream for licence/source.
cbuffer UBO : register(b0)
{
    float4 global_SourceSize : packoffset(c4);
    float4 global_OutputSize : packoffset(c6);
};

cbuffer Push : register(b1)
{
    float params_MASK_INTENSITY : packoffset(c0);
    float params_InputGamma : packoffset(c0.y);
    float params_OutputGamma : packoffset(c0.z);
    float params_BRIGHTBOOST : packoffset(c0.w);
    float params_SCANLINES : packoffset(c1);
    float params_SHARPER : packoffset(c1.y);
};

Texture2D<float4> Source : register(t1);
SamplerState _Source_sampler : register(s1);

static float2 ps;
static float2 vTexCoord;
static float4 FragColor;

struct SPIRV_Cross_Input
{
    float2 vTexCoord : TEXCOORD0;
    float2 ps : TEXCOORD1;
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
    float2 _18 = float2(ps.x, 0.0f);
    float2 _38 = vTexCoord * global_SourceSize.xy;
    float2 _46 = (floor(_38) + 0.499989986419677734375f.xx) / global_SourceSize.xy;
    float2 _53 = frac(_38);
    float4 _65 = Source.Sample(_Source_sampler, _46 - _18);
    float4 _70 = Source.Sample(_Source_sampler, _46);
    float4 _77 = Source.Sample(_Source_sampler, _46 + _18);
    float4 _86 = Source.Sample(_Source_sampler, _46 + (_18 * 2.0f));
    float _92 = _53.x;
    float _95 = _92 * _92;
    float4 _107 = float4(_95 * _92, _95, _92, 1.0f);
    float4 _326;
    if (params_SHARPER == 0.0f)
    {
        _326 = float4(dot(float4(-0.5f, 1.0f, -0.5f, 0.0f), _107), dot(float4(1.5f, -2.5f, 0.0f, 1.0f), _107), dot(float4(-1.5f, 2.0f, 0.5f, 0.0f), _107), dot(float4(0.5f, -0.5f, 0.0f, 0.0f), _107));
    }
    else
    {
        float4 _327;
        if (params_SHARPER == 1.0f)
        {
            float4 _309 = 0.0f.xxxx;
            _309.y = dot(float4(2.0f, -3.0f, 0.0f, 1.0f), _107);
            _309.z = dot(float4(-2.0f, 3.0f, 0.0f, 0.0f), _107);
            _309.w = 0.0f;
            _327 = _309;
        }
        else
        {
            _327 = 0.0f.xxxx;
        }
        _326 = _327;
    }
    float _212 = max(0.0f, min(1.0f, (1.5f - params_SCANLINES) - abs(_53.y - 0.5f)));
    float _239 = 1.0f - params_MASK_INTENSITY;
    FragColor = float4(pow((pow((((_65.xyz * _326.x) + (_70.xyz * _326.y)) + (_77.xyz * _326.z)) + (_86.xyz * _326.w), params_InputGamma.xxx) * ((_212 * _212) * ((3.0f + params_BRIGHTBOOST) - (2.0f * _212)))) * float3(lerp(float4(1.0f, _239, 1.0f, 1.0f), float4(_239, 1.0f, _239, 1.0f), floor(mod(vTexCoord.x * global_OutputSize.x, 2.0f)).xxxx).xyz), (1.0f / params_OutputGamma).xxx), 1.0f);
}

SPIRV_Cross_Output main(SPIRV_Cross_Input stage_input)
{
    ps = stage_input.ps;
    vTexCoord = stage_input.vTexCoord;
    frag_main();
    SPIRV_Cross_Output stage_output;
    stage_output.FragColor = FragColor;
    return stage_output;
}
