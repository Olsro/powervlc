// Generated from crt/shaders/crt-royale/src/crt-royale-scanlines-vertical-interlacing.slang. See slang/upstream for licence/source.
cbuffer UBO : register(b0)
{
    float global_beam_min_sigma : packoffset(c5.w);
    float global_beam_max_sigma : packoffset(c6);
    float global_beam_spot_power : packoffset(c6.y);
    float global_beam_min_shape : packoffset(c6.z);
    float global_beam_max_shape : packoffset(c6.w);
    float global_beam_shape_power : packoffset(c7);
    float global_convergence_offset_y_r : packoffset(c8.w);
    float global_convergence_offset_y_g : packoffset(c9);
    float global_convergence_offset_y_b : packoffset(c9.y);
    float global_interlace_bff : packoffset(c14.w);
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
    float2 _1606 = tex_uv * params_SourceSize.xy;
    float2 _1611 = floor(_1606 - 0.4995000064373016357421875f.xx);
    float2 _1624 = (_1611 - float2(0.0f, mod(_1611.y + (floor(il_step_multiple.y * 0.75f) * mod(float(params_FrameCount) + global_interlace_bff, 2.0f)), il_step_multiple.y))) + 0.5f.xx;
    float2 _1627 = _1624 * (1.0f.xx / params_SourceSize.xy);
    float _1635 = (_1606.y - _1624.y) / il_step_multiple.y;
    float2 _1163 = float2(0.0f, uv_step.y);
    float3 _1169 = Source.Sample(_Source_sampler, _1627).xyz;
    float3 _1176 = Source.Sample(_Source_sampler, _1627 + _1163).xyz;
    float _1275 = round(_1635);
    float3 _1289 = Source.Sample(_Source_sampler, _1627 + lerp(-_1163, _1163 * 2.0f, _1275.xx)).xyz;
    float3 _1301 = _1635.xxx - float3(global_convergence_offset_y_r, global_convergence_offset_y_g, global_convergence_offset_y_b);
    float _1311 = max(global_beam_max_sigma, global_beam_min_sigma) - global_beam_min_sigma;
    float _1321 = max(global_beam_max_shape, global_beam_min_shape) - global_beam_min_shape;
    float3 _2835 = global_beam_min_sigma.xxx;
    float3 _2840 = global_beam_spot_power.xxx;
    float3 _2869 = global_beam_shape_power.xxx;
    float3 _2872 = global_beam_min_shape.xxx;
    float3 _2873 = _2872 + (pow(_1169, _2869) * _1321);
    float3 _2751 = 1.0f.xxx / ((_2835 + (pow(_1169, _2840) * _1311)) * 1.41421353816986083984375f);
    float3 _2753 = 1.0f.xxx / _2873;
    float3 _2769 = (pixel_height_in_scanlines * 0.3333333432674407958984375f).xxx;
    float3 _1337 = abs(1.0f.xxx - _1301);
    float3 _3858 = _2872 + (pow(_1176, _2869) * _1321);
    float3 _3736 = 1.0f.xxx / ((_2835 + (pow(_1176, _2840) * _1311)) * 1.41421353816986083984375f);
    float3 _3738 = 1.0f.xxx / _3858;
    float3 _1528 = lerp(_1301 + 1.0f.xxx, 2.0f.xxx - _1301, _1275.xxx);
    float3 _13708 = _2872 + (pow(_1289, _2869) * _1321);
    float3 _13586 = 1.0f.xxx / ((_2835 + (pow(_1289, _2840) * _1311)) * 1.41421353816986083984375f);
    float3 _13588 = 1.0f.xxx / _13708;
    float3 _1543 = (((((((_1169 * _2873) * 0.5f) * _2751) / ((pow((_2753 + 1.62906825542449951171875f.xxx) * 0.367879450321197509765625f.xxx, _2753 + 0.5f.xxx) * (0.810911953449249267578125f.xxx + (0.4808354675769805908203125f.xxx / (_2753 + 1.0f.xxx)))) * _2873)) * 0.3333333432674407958984375f.xxx) * ((exp(-pow(abs(_1301 * _2751), _2873)) + exp(-pow(abs((_1301 + _2769) * _2751), _2873))) + exp(-pow(abs(abs(_1301 - _2769) * _2751), _2873)))) + ((((((_1176 * _3858) * 0.5f) * _3736) / ((pow((_3738 + 1.62906825542449951171875f.xxx) * 0.367879450321197509765625f.xxx, _3738 + 0.5f.xxx) * (0.810911953449249267578125f.xxx + (0.4808354675769805908203125f.xxx / (_3738 + 1.0f.xxx)))) * _3858)) * 0.3333333432674407958984375f.xxx) * ((exp(-pow(abs(_1337 * _3736), _3858)) + exp(-pow(abs((_1337 + _2769) * _3736), _3858))) + exp(-pow(abs(abs(_1337 - _2769) * _3736), _3858))))) + ((((((_1289 * _13708) * 0.5f) * _13586) / ((pow((_13588 + 1.62906825542449951171875f.xxx) * 0.367879450321197509765625f.xxx, _13588 + 0.5f.xxx) * (0.810911953449249267578125f.xxx + (0.4808354675769805908203125f.xxx / (_13588 + 1.0f.xxx)))) * _13708)) * 0.3333333432674407958984375f.xxx) * ((exp(-pow(abs(_1528 * _13586), _13708)) + exp(-pow(abs((_1528 + _2769) * _13586), _13708))) + exp(-pow(abs(abs(_1528 - _2769) * _13586), _13708))));
    FragColor = float4(_1543 * 0.5f, 1.0f);
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
