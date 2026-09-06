// Generated from crt/shaders/simple-crt/simple-color-correction.slang. See slang/upstream for licence/source.
cbuffer Push : register(b1)
{
    float4 params_OutputSize : packoffset(c2);
    float params_SHARPNESS : packoffset(c3.y);
    float params_COLOR_BRIGHTNESS : packoffset(c3.z);
    float params_COLOR_BRIGHTNESS_O : packoffset(c3.w);
    float params_COLOR_SATURATION : packoffset(c4);
    float params_COLOR_CONTRAST_SIG : packoffset(c4.y);
    float params_COLOR_CONTRAST_SQR : packoffset(c4.z);
    float params_COLOR_CONTRAST_SQRL : packoffset(c4.w);
    float params_COLOR_GAMMA : packoffset(c5);
    float params_COLOR_BMIN : packoffset(c5.y);
    float params_COLOR_BMAX : packoffset(c5.z);
    float params_VIGNETTE_STRENGTH : packoffset(c5.w);
    float params_VIGNETTE_SIZE : packoffset(c6);
    float params_VIGNETTE_POW : packoffset(c6.y);
    float params_MAX_COLOR_BITS : packoffset(c6.z);
};

Texture2D<float4> Source : register(t2);
SamplerState _Source_sampler : register(s2);

static float4 gl_FragCoord;
static float2 vTexCoord;
static float4 FragColor;

struct SPIRV_Cross_Input
{
    float2 vTexCoord : TEXCOORD0;
    float4 gl_FragCoord : SV_Position;
};

struct SPIRV_Cross_Output
{
    float4 FragColor : SV_Target0;
};

void frag_main()
{
    float4 _308 = Source.Sample(_Source_sampler, vTexCoord);
    float3 _328 = ((((_308 + Source.Sample(_Source_sampler, vTexCoord, int2(0, -1))) + Source.Sample(_Source_sampler, vTexCoord, int2(1, 0))) + Source.Sample(_Source_sampler, vTexCoord, int2(0, 1))) + Source.Sample(_Source_sampler, vTexCoord, int2(-1, 0))).xyz * 0.20000000298023223876953125f;
    float _335 = dot(_328, float3(0.2989999949932098388671875f, 0.58700001239776611328125f, 0.114000000059604644775390625f));
    float3 _197 = (float4(lerp(_308.xyz, _328, params_SHARPNESS.xxx), _335).xyz * params_COLOR_BRIGHTNESS) + params_COLOR_BRIGHTNESS_O.xxx;
    float3 _345 = lerp(dot(_197, 0.3333333432674407958984375f.xxx).xxx, _197, params_COLOR_SATURATION.xxx);
    float3 _354 = _345 / (0.5f.xxx + exp(_345 * (-(params_COLOR_CONTRAST_SIG * params_COLOR_CONTRAST_SIG))));
    float3 _360 = lerp(_354, _354 * _354, (params_COLOR_CONTRAST_SQR - 1.0f).xxx);
    float _237 = pow(2.0f, params_MAX_COLOR_BITS);
    float3 _283 = (round(((pow(lerp(_360, _360 * max(_360.x, max(_360.y, _360.z)), (params_COLOR_CONTRAST_SQRL - 1.0f).xxx), params_COLOR_GAMMA.xxx) * (params_COLOR_BMAX - params_COLOR_BMIN)) + params_COLOR_BMIN.xxx) * _237) / _237.xxx) * lerp(1.0f, 1.0f - smoothstep(0.0f, params_VIGNETTE_SIZE, pow(length(((gl_FragCoord.xy / params_OutputSize.xy) * 2.0f) - 1.0f.xx), params_VIGNETTE_POW)), params_VIGNETTE_STRENGTH);
    FragColor = float4(clamp(_283 / max(max(max(_283.x, _283.y), _283.z), 1.0f).xxx, 0.0f.xxx, 1.0f.xxx), _335);
}

SPIRV_Cross_Output main(SPIRV_Cross_Input stage_input)
{
    gl_FragCoord = stage_input.gl_FragCoord;
    gl_FragCoord.w = 1.0 / gl_FragCoord.w;
    vTexCoord = stage_input.vTexCoord;
    frag_main();
    SPIRV_Cross_Output stage_output;
    stage_output.FragColor = FragColor;
    return stage_output;
}
