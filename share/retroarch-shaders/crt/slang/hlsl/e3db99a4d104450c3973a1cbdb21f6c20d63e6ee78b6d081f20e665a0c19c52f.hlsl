// Generated from crt/shaders/crt-beans/cubic_downsample.slang. See slang/upstream for licence/source.
cbuffer Push : register(b1)
{
    float4 params_SourceSize : packoffset(c0);
};

Texture2D<float4> Source : register(t1);
SamplerState _Source_sampler : register(s1);

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
    float2 _23 = vTexCoord * params_SourceSize.xy;
    float2 _29 = floor(_23 - 0.5f.xx);
    float2 _35 = _23 - (_29 + 0.5f.xx);
    float2 _38 = _35 + 1.0f.xx;
    float2 _65 = (_35 * _35) * ((abs(_35) * 0.25f) - 0.75f.xx);
    float2 _72 = _35 - 1.0f.xx;
    float2 _90 = _35 - 2.0f.xx;
    float2 _100 = (_90 * _90) * ((abs(_90) * 0.25f) - 0.75f.xx);
    float2 _227 = ((_38 * _38) * ((abs(_38) * 0.25f) - 0.75f.xx)) + _65;
    float2 _106 = 2.0f.xx + _227;
    float2 _228 = ((_72 * _72) * ((abs(_72) * 0.25f) - 0.75f.xx)) + _100;
    float2 _110 = 2.0f.xx + _228;
    float2 _122 = ((_29 + (-0.5f).xx) + ((_65 + 1.0f.xx) / _106)) * params_SourceSize.zw;
    float2 _134 = ((_29 + 1.5f.xx) + ((_100 + 1.0f.xx) / _110)) * params_SourceSize.zw;
    float _156 = _106.x;
    float _167 = _110.x;
    float2 _203 = 4.0f.xx + (_227 + _228);
    FragColor = float4(((((Source.SampleLevel(_Source_sampler, _122, 0.0f).xyz * _156) + (Source.SampleLevel(_Source_sampler, float2(_134.x, _122.y), 0.0f).xyz * _167)) * _106.y) + (((Source.SampleLevel(_Source_sampler, float2(_122.x, _134.y), 0.0f).xyz * _156) + (Source.SampleLevel(_Source_sampler, _134, 0.0f).xyz * _167)) * _110.y)) / (_203.x * _203.y).xxx, 1.0f);
}

SPIRV_Cross_Output main(SPIRV_Cross_Input stage_input)
{
    vTexCoord = stage_input.vTexCoord;
    frag_main();
    SPIRV_Cross_Output stage_output;
    stage_output.FragColor = FragColor;
    return stage_output;
}
