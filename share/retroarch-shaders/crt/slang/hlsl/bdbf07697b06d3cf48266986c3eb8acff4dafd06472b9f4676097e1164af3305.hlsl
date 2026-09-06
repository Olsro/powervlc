// Generated from crt/shaders/crt-royale/src-fast/crt-royale-scanlines-vertical-interlacing.slang. See slang/upstream for licence/source.
cbuffer UBO : register(b0)
{
    float global_beam_min_sigma : packoffset(c5.y);
    float global_beam_max_sigma : packoffset(c5.z);
    float global_beam_spot_power : packoffset(c5.w);
    float global_beam_min_shape : packoffset(c6);
    float global_beam_max_shape : packoffset(c6.y);
    float global_beam_shape_power : packoffset(c6.z);
    float global_convergence_offset_y_r : packoffset(c8.y);
    float global_convergence_offset_y_g : packoffset(c8.z);
    float global_convergence_offset_y_b : packoffset(c8.w);
    float global_interlace_bff : packoffset(c11);
};

cbuffer Push : register(b1)
{
    float4 params_SourceSize : packoffset(c0);
    uint params_FrameCount : packoffset(c3);
};

Texture2D<float4> Source : register(t2);
SamplerState _Source_sampler : register(s2);

static float pixel_height_in_scanlines;
static float2 tex_uv;
static float2 il_step_multiple;
static float2 uv_step;
static float4 FragColor;

struct SPIRV_Cross_Input
{
    float2 tex_uv : TEXCOORD0;
    float2 uv_step : TEXCOORD1;
    float2 il_step_multiple : TEXCOORD2;
    float pixel_height_in_scanlines : TEXCOORD3;
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
    float2 _1217 = tex_uv * params_SourceSize.xy;
    float2 _1222 = floor(_1217 - 0.4995000064373016357421875f.xx);
    float2 _1235 = (_1222 - float2(0.0f, mod(_1222.y + (floor(il_step_multiple.y * 0.75f) * mod(float(params_FrameCount) + global_interlace_bff, 2.0f)), il_step_multiple.y))) + 0.5f.xx;
    float2 _1238 = _1235 * params_SourceSize.zw;
    float _1246 = (_1217.y - _1235.y) / il_step_multiple.y;
    float2 _1046 = float2(0.0f, uv_step.y);
    float3 _1055 = Source.Sample(_Source_sampler, _1238).xyz;
    float3 _1062 = Source.Sample(_Source_sampler, _1238 + _1046).xyz;
    float _1065 = round(_1246);
    float3 _1080 = Source.Sample(_Source_sampler, _1238 + lerp(-_1046, _1046 * 2.0f, _1065.xx)).xyz;
    float3 _1092 = _1246.xxx - float3(global_convergence_offset_y_r, global_convergence_offset_y_g, global_convergence_offset_y_b);
    float _1102 = max(global_beam_max_sigma, global_beam_min_sigma) - global_beam_min_sigma;
    float _1112 = max(global_beam_max_shape, global_beam_min_shape) - global_beam_min_shape;
    float3 _1882 = global_beam_min_sigma.xxx;
    float3 _1887 = global_beam_spot_power.xxx;
    float3 _1916 = global_beam_shape_power.xxx;
    float3 _1919 = global_beam_min_shape.xxx;
    float3 _1920 = _1919 + (pow(_1055, _1916) * _1112);
    float3 _1798 = 1.0f.xxx / ((_1882 + (pow(_1055, _1887) * _1102)) * 1.41421353816986083984375f);
    float3 _1800 = 1.0f.xxx / _1920;
    float3 _1816 = (pixel_height_in_scanlines * 0.3333333432674407958984375f).xxx;
    float3 _1128 = abs(1.0f.xxx - _1092);
    float3 _2905 = _1919 + (pow(_1062, _1916) * _1112);
    float3 _2783 = 1.0f.xxx / ((_1882 + (pow(_1062, _1887) * _1102)) * 1.41421353816986083984375f);
    float3 _2785 = 1.0f.xxx / _2905;
    float3 _1151 = lerp(_1092 + 1.0f.xxx, 2.0f.xxx - _1092, _1065.xxx);
    float3 _3890 = _1919 + (pow(_1080, _1916) * _1112);
    float3 _3768 = 1.0f.xxx / ((_1882 + (pow(_1080, _1887) * _1102)) * 1.41421353816986083984375f);
    float3 _3770 = 1.0f.xxx / _3890;
    float3 _1166 = (((((((_1055 * _1920) * 0.5f) * _1798) / ((pow((_1800 + 1.62906825542449951171875f.xxx) * 0.367879450321197509765625f.xxx, _1800 + 0.5f.xxx) * (0.810911953449249267578125f.xxx + (0.4808354675769805908203125f.xxx / (_1800 + 1.0f.xxx)))) * _1920)) * 0.3333333432674407958984375f.xxx) * ((exp(-pow(abs(_1092 * _1798), _1920)) + exp(-pow(abs((_1092 + _1816) * _1798), _1920))) + exp(-pow(abs(abs(_1092 - _1816) * _1798), _1920)))) + ((((((_1062 * _2905) * 0.5f) * _2783) / ((pow((_2785 + 1.62906825542449951171875f.xxx) * 0.367879450321197509765625f.xxx, _2785 + 0.5f.xxx) * (0.810911953449249267578125f.xxx + (0.4808354675769805908203125f.xxx / (_2785 + 1.0f.xxx)))) * _2905)) * 0.3333333432674407958984375f.xxx) * ((exp(-pow(abs(_1128 * _2783), _2905)) + exp(-pow(abs((_1128 + _1816) * _2783), _2905))) + exp(-pow(abs(abs(_1128 - _1816) * _2783), _2905))))) + ((((((_1080 * _3890) * 0.5f) * _3768) / ((pow((_3770 + 1.62906825542449951171875f.xxx) * 0.367879450321197509765625f.xxx, _3770 + 0.5f.xxx) * (0.810911953449249267578125f.xxx + (0.4808354675769805908203125f.xxx / (_3770 + 1.0f.xxx)))) * _3890)) * 0.3333333432674407958984375f.xxx) * ((exp(-pow(abs(_1151 * _3768), _3890)) + exp(-pow(abs((_1151 + _1816) * _3768), _3890))) + exp(-pow(abs(abs(_1151 - _1816) * _3768), _3890))));
    FragColor = float4(_1166 * 0.5f, 1.0f);
}

SPIRV_Cross_Output main(SPIRV_Cross_Input stage_input)
{
    pixel_height_in_scanlines = stage_input.pixel_height_in_scanlines;
    tex_uv = stage_input.tex_uv;
    il_step_multiple = stage_input.il_step_multiple;
    uv_step = stage_input.uv_step;
    frag_main();
    SPIRV_Cross_Output stage_output;
    stage_output.FragColor = FragColor;
    return stage_output;
}
