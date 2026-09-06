// Generated from crt/shaders/glow/gauss_horiz.slang. See slang/upstream for licence/source.
cbuffer UBO : register(b0)
{
    float4 global_SourceSize : packoffset(c6);
};

Texture2D<float4> Source : register(t2);
SamplerState _Source_sampler : register(s2);

static float data_pix_no;
static float2 vTexCoord;
static float data_one;
static float4 FragColor;

struct SPIRV_Cross_Input
{
    float2 vTexCoord : TEXCOORD0;
    float data_pix_no : TEXCOORD1;
    float data_one : TEXCOORD2;
};

struct SPIRV_Cross_Output
{
    float4 FragColor : SV_Target0;
};

void frag_main()
{
    float _12 = floor(data_pix_no);
    float _20 = (data_pix_no - _12) - 0.5f;
    float2 _44 = float2((_12 + 0.5f) * global_SourceSize.z, vTexCoord.y);
    float3 _110;
    _110 = 0.0f.xxx;
    for (int _109 = -2; _109 <= 2; )
    {
        float _65 = float(_109);
        float _66 = _20 - _65;
        _110 += (Source.Sample(_Source_sampler, _44 + float2(_65 * data_one, 0.0f)).xyz * (exp((((-0.5f) * _66) * _66) * 4.0f) * 0.7599999904632568359375f));
        _109++;
        continue;
    }
    FragColor = float4(_110, 1.0f);
}

SPIRV_Cross_Output main(SPIRV_Cross_Input stage_input)
{
    data_pix_no = stage_input.data_pix_no;
    vTexCoord = stage_input.vTexCoord;
    data_one = stage_input.data_one;
    frag_main();
    SPIRV_Cross_Output stage_output;
    stage_output.FragColor = FragColor;
    return stage_output;
}
