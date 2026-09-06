// Generated from crt/shaders/geom-deluxe/phosphor_update.slang. See slang/upstream for licence/source.
cbuffer Push : register(b1)
{
    float params_phosphor_power : packoffset(c0);
};

Texture2D<float4> Source : register(t2);
SamplerState _Source_sampler : register(s2);
Texture2D<float4> phosphorFeedback : register(t3);
SamplerState _phosphorFeedback_sampler : register(s3);

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
    float4 _61 = Source.Sample(_Source_sampler, vTexCoord);
    float4 _66 = phosphorFeedback.Sample(_phosphorFeedback_sampler, vTexCoord);
    float _103 = _66.z * 63.75f;
    float _107 = (1.0f + (255.0f * _66.w)) + (frac(_103) * 1024.0f);
    float _177;
    if (_107 > 1023.0f)
    {
        _177 = 0.0f;
    }
    else
    {
        _177 = dot(pow(_66.xyz, 2.2000000476837158203125f.xxx), float3(0.2989999949932098388671875f, 0.58700001239776611328125f, 0.114000000059604644775390625f)) * pow(_107, -params_phosphor_power);
    }
    float4 _180;
    if (dot(pow(_61.xyz, 2.2000000476837158203125f.xxx), float3(0.2989999949932098388671875f, 0.58700001239776611328125f, 0.114000000059604644775390625f)) >= _177)
    {
        _180 = float4(_61.xy, floor(_61.z * 63.75f) * 0.01568627543747425079345703125f, 0.0039215688593685626983642578125f);
    }
    else
    {
        float _158 = _107 * 0.00390625f;
        _180 = float4(_66.xy, ((floor(_103) * 4.0f) + floor(_158)) * 0.0039215688593685626983642578125f, frac(_158) * 1.00392162799835205078125f);
    }
    FragColor = _180;
}

SPIRV_Cross_Output main(SPIRV_Cross_Input stage_input)
{
    vTexCoord = stage_input.vTexCoord;
    frag_main();
    SPIRV_Cross_Output stage_output;
    stage_output.FragColor = FragColor;
    return stage_output;
}
