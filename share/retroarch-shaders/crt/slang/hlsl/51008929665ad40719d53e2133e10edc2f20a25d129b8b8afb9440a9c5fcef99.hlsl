// Generated from crt/shaders/crt-interlaced-halation/crt-interlaced-halation-pass1.slang. See slang/upstream for licence/source.
Texture2D<float4> Source : register(t2);
SamplerState _Source_sampler : register(s2);

static float4 t1;
static float4 t2;
static float2 vTexCoord;
static float4 t3;
static float4 FragColor;

struct SPIRV_Cross_Input
{
    float2 vTexCoord : TEXCOORD0;
    float4 t1 : TEXCOORD1;
    float4 t2 : TEXCOORD2;
    float4 t3 : TEXCOORD3;
};

struct SPIRV_Cross_Output
{
    float4 FragColor : SV_Target0;
};

void frag_main()
{
    FragColor = pow((((((((((pow(Source.Sample(_Source_sampler, t1.xw), 2.2000000476837158203125f.xxxx) * 0.0183156393468379974365234375f.xxxx) + (pow(Source.Sample(_Source_sampler, t1.yw), 2.2000000476837158203125f.xxxx) * 0.1053992211818695068359375f.xxxx)) + (pow(Source.Sample(_Source_sampler, t1.zw), 2.2000000476837158203125f.xxxx) * 0.367879450321197509765625f.xxxx)) + (pow(Source.Sample(_Source_sampler, t2.xw), 2.2000000476837158203125f.xxxx) * 0.778800785541534423828125f.xxxx)) + pow(Source.Sample(_Source_sampler, vTexCoord), 2.2000000476837158203125f.xxxx)) + (pow(Source.Sample(_Source_sampler, t2.zw), 2.2000000476837158203125f.xxxx) * 0.778800785541534423828125f.xxxx)) + (pow(Source.Sample(_Source_sampler, t3.xw), 2.2000000476837158203125f.xxxx) * 0.367879450321197509765625f.xxxx)) + (pow(Source.Sample(_Source_sampler, t3.yw), 2.2000000476837158203125f.xxxx) * 0.1053992211818695068359375f.xxxx)) + (pow(Source.Sample(_Source_sampler, t3.zw), 2.2000000476837158203125f.xxxx) * 0.0183156393468379974365234375f.xxxx)) * 0.2824228107929229736328125f.xxxx, 0.4545454680919647216796875f.xxxx);
}

SPIRV_Cross_Output main(SPIRV_Cross_Input stage_input)
{
    t1 = stage_input.t1;
    t2 = stage_input.t2;
    vTexCoord = stage_input.vTexCoord;
    t3 = stage_input.t3;
    frag_main();
    SPIRV_Cross_Output stage_output;
    stage_output.FragColor = FragColor;
    return stage_output;
}
