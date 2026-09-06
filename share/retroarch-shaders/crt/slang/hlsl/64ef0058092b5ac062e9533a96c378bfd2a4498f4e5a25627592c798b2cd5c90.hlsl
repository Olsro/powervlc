// Generated from crt/shaders/crtsim/composite.slang. See slang/upstream for licence/source.
static const float _211[3] = { 1.0f, -0.3162277042865753173828125f, 0.100000001490116119384765625f };

cbuffer Push : register(b1)
{
    float4 params_SourceSize : packoffset(c0);
    uint params_FrameCount : packoffset(c3);
    float params_Tuning_Sharp : packoffset(c3.y);
    float params_Tuning_Persistence_R : packoffset(c3.z);
    float params_Tuning_Persistence_G : packoffset(c3.w);
    float params_Tuning_Persistence_B : packoffset(c4);
    float params_Tuning_Bleed : packoffset(c4.y);
    float params_Tuning_Artifacts : packoffset(c4.z);
    float params_NTSCLerp : packoffset(c4.w);
    float params_NTSCArtifactScale : packoffset(c5);
    float params_animate_artifacts : packoffset(c5.y);
};

Texture2D<float4> NTSCArtifactSampler : register(t4);
SamplerState _NTSCArtifactSampler_sampler : register(s4);
Texture2D<float4> Source : register(t3);
SamplerState _Source_sampler : register(s3);
Texture2D<float4> PassFeedback0 : register(t2);
SamplerState _PassFeedback0_sampler : register(s2);

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
    float2 _47 = frac(((vTexCoord * 1.00010001659393310546875f) * params_SourceSize.xy) / params_NTSCArtifactScale.xx);
    float4 _55 = NTSCArtifactSampler.Sample(_NTSCArtifactSampler_sampler, _47);
    float4 _66 = NTSCArtifactSampler.Sample(_NTSCArtifactSampler_sampler, _47 + float2(0.0f, 1.0f / params_SourceSize.y));
    float _292;
    if (params_animate_artifacts > 0.5f)
    {
        _292 = mod(float(params_FrameCount), 2.0f);
    }
    else
    {
        _292 = params_NTSCLerp;
    }
    float4 _96 = lerp(_55, _66, (1.0f - _292).xxxx);
    float2 _103 = float2(1.0f / params_SourceSize.x, 0.0f);
    float2 _104 = vTexCoord - _103;
    float2 _111 = vTexCoord + _103;
    float4 _116 = Source.Sample(_Source_sampler, _104);
    float4 _120 = Source.Sample(_Source_sampler, vTexCoord);
    float4 _124 = Source.Sample(_Source_sampler, _111);
    float4 _135 = PassFeedback0.Sample(_PassFeedback0_sampler, _104);
    float4 _139 = PassFeedback0.Sample(_PassFeedback0_sampler, vTexCoord);
    float4 _143 = PassFeedback0.Sample(_PassFeedback0_sampler, _111);
    float4 _157 = clamp(_120 + (((_116 - _120) + (_124 - _120)) * (_96 * params_Tuning_Artifacts)), 0.0f.xxxx, 1.0f.xxxx);
    float _283 = dot(_157, float4(0.2989999949932098388671875f, 0.58700001239776611328125f, 0.114000000059604644775390625f, 0.0f));
    float _297;
    _297 = 0.0f;
    for (int _295 = 0; _295 < 3; )
    {
        int _177 = _295 + 1;
        float2 _179 = float2(0.00390625f, 0.0f) * float(_177);
        _297 += (((_283 - dot(Source.Sample(_Source_sampler, vTexCoord - _179), float4(0.2989999949932098388671875f, 0.58700001239776611328125f, 0.114000000059604644775390625f, 0.0f))) + (_283 - dot(Source.Sample(_Source_sampler, vTexCoord + _179), float4(0.2989999949932098388671875f, 0.58700001239776611328125f, 0.114000000059604644775390625f, 0.0f)))) * _211[_295]);
        _295 = _177;
        continue;
    }
    FragColor = clamp(max(clamp(_157 + (lerp(1.0f.xxxx, _96, params_Tuning_Artifacts.xxxx) * (_297 * params_Tuning_Sharp)), 0.0f.xxxx, 1.0f.xxxx), (float4(params_Tuning_Persistence_R, params_Tuning_Persistence_G, params_Tuning_Persistence_B, 1.0f) * (10.0f / (1.0f + (2.0f * params_Tuning_Bleed)))) * (_139 + ((_135 + _143) * params_Tuning_Bleed))), 0.0f.xxxx, 1.0f.xxxx);
}

SPIRV_Cross_Output main(SPIRV_Cross_Input stage_input)
{
    vTexCoord = stage_input.vTexCoord;
    frag_main();
    SPIRV_Cross_Output stage_output;
    stage_output.FragColor = FragColor;
    return stage_output;
}
