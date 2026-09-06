// Generated from crt/shaders/newpixie/blur_vert.slang. See slang/upstream for licence/source.
cbuffer Push : register(b1)
{
    float4 params_OutputSize : packoffset(c2);
    float params_blur_y : packoffset(c3.y);
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

void frag_main()
{
    float2 _27 = float2(0.0f, params_blur_y) * params_OutputSize.zw;
    float _52 = _27.x;
    float _53 = 4.0f * _52;
    float _59 = _27.y;
    float _60 = 4.0f * _59;
    float _74 = 3.0f * _52;
    float _80 = 3.0f * _59;
    float _94 = 2.0f * _52;
    float _100 = 2.0f * _59;
    FragColor = ((((((((Source.Sample(_Source_sampler, vTexCoord) * 0.2270270287990570068359375f) + (Source.Sample(_Source_sampler, float2(vTexCoord.x - _53, vTexCoord.y - _60)) * 0.01621621660888195037841796875f)) + (Source.Sample(_Source_sampler, float2(vTexCoord.x - _74, vTexCoord.y - _80)) * 0.0540540553629398345947265625f)) + (Source.Sample(_Source_sampler, float2(vTexCoord.x - _94, vTexCoord.y - _100)) * 0.12162162363529205322265625f)) + (Source.Sample(_Source_sampler, float2(vTexCoord.x - _52, vTexCoord.y - _59)) * 0.1945945918560028076171875f)) + (Source.Sample(_Source_sampler, float2(vTexCoord.x + _52, vTexCoord.y + _59)) * 0.1945945918560028076171875f)) + (Source.Sample(_Source_sampler, float2(vTexCoord.x + _94, vTexCoord.y + _100)) * 0.12162162363529205322265625f)) + (Source.Sample(_Source_sampler, float2(vTexCoord.x + _74, vTexCoord.y + _80)) * 0.0540540553629398345947265625f)) + (Source.Sample(_Source_sampler, float2(vTexCoord.x + _53, vTexCoord.y + _60)) * 0.01621621660888195037841796875f);
}

SPIRV_Cross_Output main(SPIRV_Cross_Input stage_input)
{
    vTexCoord = stage_input.vTexCoord;
    frag_main();
    SPIRV_Cross_Output stage_output;
    stage_output.FragColor = FragColor;
    return stage_output;
}
