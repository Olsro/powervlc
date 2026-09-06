// Generated from crt/shaders/gtu-v050/pass1.slang. See slang/upstream for licence/source.
cbuffer Push : register(b1)
{
    float params_compositeConnection : packoffset(c3);
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
    float4 _19 = Source.Sample(_Source_sampler, vTexCoord);
    float4 _77;
    if (params_compositeConnection > 0.0f)
    {
        float3 _50 = mul(float3x3(float3(0.2989999949932098388671875f, 0.595715999603271484375f, 0.211456000804901123046875f), float3(0.58700001239776611328125f, -0.2744530141353607177734375f, -0.52259099483489990234375f), float3(0.114000000059604644775390625f, -0.3212629854679107666015625f, 0.311134994029998779296875f)), _19.xyz);
        float4 _70 = _19;
        _70.x = _50.x;
        _70.y = _50.y;
        _70.z = _50.z;
        _77 = _70;
    }
    else
    {
        _77 = _19;
    }
    FragColor = _77;
}

SPIRV_Cross_Output main(SPIRV_Cross_Input stage_input)
{
    vTexCoord = stage_input.vTexCoord;
    frag_main();
    SPIRV_Cross_Output stage_output;
    stage_output.FragColor = FragColor;
    return stage_output;
}
