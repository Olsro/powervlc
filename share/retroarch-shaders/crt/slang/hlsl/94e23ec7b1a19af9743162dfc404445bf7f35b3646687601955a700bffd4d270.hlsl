// Generated from crt/shaders/crt-slangtest/sinc.slang. See slang/upstream for licence/source.
cbuffer UBO
{
    float4 global_SourceSize : packoffset(c0);
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
    float _57 = (vTexCoord.x * global_SourceSize.x) - 0.5f;
    float _60 = frac(_57);
    float2 _73 = float2((floor(_57) + 0.5f) * global_SourceSize.z, vTexCoord.y);
    float _148 = max(abs(_60 + 1.0f) * 3.1415927410125732421875f, 9.9999997473787516355514526367188e-05f);
    float _152 = 0.5f * _148;
    float _174 = max(abs(_60) * 3.1415927410125732421875f, 9.9999997473787516355514526367188e-05f);
    float _178 = 0.5f * _174;
    float _200 = max(abs(_60 - 1.0f) * 3.1415927410125732421875f, 9.9999997473787516355514526367188e-05f);
    float _204 = 0.5f * _200;
    float _226 = max(abs(_60 - 2.0f) * 3.1415927410125732421875f, 9.9999997473787516355514526367188e-05f);
    float _230 = 0.5f * _226;
    float3 _129 = (((Source.SampleLevel(_Source_sampler, _73, 0.0f, int2(-1, 0)).xyz * ((sin(_148) / _148) * (sin(_152) / _152))) + (Source.SampleLevel(_Source_sampler, _73, 0.0f, int2(0, 0)).xyz * ((sin(_174) / _174) * (sin(_178) / _178)))) + (Source.SampleLevel(_Source_sampler, _73, 0.0f, int2(1, 0)).xyz * ((sin(_200) / _200) * (sin(_204) / _204)))) + (Source.SampleLevel(_Source_sampler, _73, 0.0f, int2(2, 0)).xyz * ((sin(_226) / _226) * (sin(_230) / _230)));
    FragColor = float4(_129, 1.0f);
}

SPIRV_Cross_Output main(SPIRV_Cross_Input stage_input)
{
    vTexCoord = stage_input.vTexCoord;
    frag_main();
    SPIRV_Cross_Output stage_output;
    stage_output.FragColor = FragColor;
    return stage_output;
}
