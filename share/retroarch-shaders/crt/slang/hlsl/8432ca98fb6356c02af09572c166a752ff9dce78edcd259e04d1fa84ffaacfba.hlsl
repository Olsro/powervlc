// Generated from crt/shaders/glow/gauss_vert.slang. See slang/upstream for licence/source.
cbuffer UBO : register(b0)
{
    float4 global_SourceSize : packoffset(c6);
};

cbuffer Push : register(b1)
{
    float params_BOOST : packoffset(c0);
};

Texture2D<float4> Source : register(t2);
SamplerState _Source_sampler : register(s2);

static float2 data_pix_no;
static float data_one;
static float4 FragColor;

struct SPIRV_Cross_Input
{
    float2 data_pix_no : TEXCOORD1;
    float data_one : TEXCOORD2;
};

struct SPIRV_Cross_Output
{
    float4 FragColor : SV_Target0;
};

void frag_main()
{
    float2 _58 = floor(data_pix_no);
    float _67 = data_pix_no.y - _58.y;
    float2 _83 = (_58 + 0.5f.xx) * global_SourceSize.zw;
    float3 _98 = Source.Sample(_Source_sampler, _83).xyz;
    float3 _108 = Source.Sample(_Source_sampler, _83 + float2(0.0f, data_one)).xyz;
    float3 _156 = 2.0f.xxx + (pow(_98, 4.0f.xxx) * 2.0f);
    float3 _186 = 2.0f.xxx + (pow(_108, 4.0f.xxx) * 2.0f);
    FragColor = float4((((((_98 * 2.0f) * exp(-pow((abs(_67) * 3.3333332538604736328125f).xxx * rsqrt(_156 * 0.5f), _156))) / (0.60000002384185791015625f.xxx + (_156 * 0.20000000298023223876953125f))) + (((_108 * 2.0f) * exp(-pow((abs(1.0f - _67) * 3.3333332538604736328125f).xxx * rsqrt(_186 * 0.5f), _186))) / (0.60000002384185791015625f.xxx + (_186 * 0.20000000298023223876953125f)))) * params_BOOST) * 0.869565188884735107421875f, 1.0f);
}

SPIRV_Cross_Output main(SPIRV_Cross_Input stage_input)
{
    data_pix_no = stage_input.data_pix_no;
    data_one = stage_input.data_one;
    frag_main();
    SPIRV_Cross_Output stage_output;
    stage_output.FragColor = FragColor;
    return stage_output;
}
