// Generated from crt/shaders/simple-crt/simple-crt.slang. See slang/upstream for licence/source.
cbuffer Push : register(b1)
{
    float params_NOISE_STRENGTH : packoffset(c3.w);
    float params_NOISE_MIN : packoffset(c4.y);
    float params_NOISE_MAX : packoffset(c4.z);
    float params_FLICKER_STRENGTH : packoffset(c4.w);
    float params_FLICKER_MIN : packoffset(c5);
    float params_FLICKER_MAX : packoffset(c5.y);
    float params_CRT_MASK_STRENGTH : packoffset(c5.z);
    float params_CRT_MASK_RES_X : packoffset(c5.w);
    float params_CRT_MASK_RES_Y : packoffset(c6);
    float params_CRT_MASK_MODE : packoffset(c6.y);
    float params_LUMA_INTENSITY : packoffset(c6.z);
    float params_LUMA_THRESHOLD : packoffset(c6.w);
};

Texture2D<float4> Source : register(t2);
SamplerState _Source_sampler : register(s2);

static float4 gl_FragCoord;
static float2 vTexCoord;
static float osc_mul;
static float2 noise_div;
static int noise_offset;
static float3 flicker;
static float crt_add;
static float crt_mul;
static float4 FragColor;

struct SPIRV_Cross_Input
{
    float2 vTexCoord : TEXCOORD0;
    nointerpolation float osc_mul : TEXCOORD1;
    nointerpolation float2 noise_div : TEXCOORD2;
    nointerpolation int noise_offset : TEXCOORD3;
    nointerpolation float3 flicker : TEXCOORD4;
    nointerpolation float crt_add : TEXCOORD5;
    nointerpolation float crt_mul : TEXCOORD6;
    float4 gl_FragCoord : SV_Position;
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
    float4 _85 = Source.Sample(_Source_sampler, vTexCoord);
    float3 _95 = _85.xyz * osc_mul;
    float2 _119 = mod(round(frac(gl_FragCoord.xy * noise_div) * 1021.0f) + float(noise_offset).xx, 1021.0f.xx) + 1.0f.xx;
    uint4 _313 = (asuint((5000.0f + _119.x) * _119.y).xxxx * uint4(2348682457u, 636532089u, 3368437335u, 2717797467u)) + uint4(2891336453u, 2891336453u, 2891336453u, 2891336453u);
    uint4 _324 = ((_313 >> ((_313 >> uint4(28u, 28u, 28u, 28u)) + uint4(4u, 4u, 4u, 4u))) ^ _313) * uint4(277803737u, 277803737u, 277803737u, 277803737u);
    float3 _154 = lerp(_95, (asfloat((((_324 >> uint4(22u, 22u, 22u, 22u)) ^ _324) & uint4(8388607u, 8388607u, 8388607u, 8388607u)) | uint4(1065353216u, 1065353216u, 1065353216u, 1065353216u)) - 1.0f.xxxx).xyz * clamp(_95, params_NOISE_MIN.xxx, params_NOISE_MAX.xxx), params_NOISE_STRENGTH.xxx);
    float3 _174 = lerp(_154, flicker * clamp(_154, params_FLICKER_MIN.xxx, params_FLICKER_MAX.xxx), params_FLICKER_STRENGTH.xxx);
    float _178 = _85.w;
    float _184 = _178 - params_LUMA_THRESHOLD;
    float3 _210 = (lerp(_174, _174 * ((_178 * params_LUMA_INTENSITY) + 1.0f), pow(_184, 3.0f).xxx) * float(_184 > 0.0f)) + (_174 * float(_184 <= 0.0f));
    float2 _228 = mod((gl_FragCoord.xy / float2(params_CRT_MASK_RES_X, params_CRT_MASK_RES_Y)) + crt_add.xx, 6.283185482025146484375f.xx);
    float3 _242 = dot(float2(cos(_228.x), sin(_228.y)), 0.5f.xx).xxx;
    float3 _271 = lerp(_210, (((_242 * _242) * float(params_CRT_MASK_MODE > 1.5f)) + (_242 * float(params_CRT_MASK_MODE <= 1.5f))) * _210, params_CRT_MASK_STRENGTH.xxx) * crt_mul;
    FragColor.x = _271.x;
    FragColor.y = _271.y;
    FragColor.z = _271.z;
}

SPIRV_Cross_Output main(SPIRV_Cross_Input stage_input)
{
    gl_FragCoord = stage_input.gl_FragCoord;
    gl_FragCoord.w = 1.0 / gl_FragCoord.w;
    vTexCoord = stage_input.vTexCoord;
    osc_mul = stage_input.osc_mul;
    noise_div = stage_input.noise_div;
    noise_offset = stage_input.noise_offset;
    flicker = stage_input.flicker;
    crt_add = stage_input.crt_add;
    crt_mul = stage_input.crt_mul;
    frag_main();
    SPIRV_Cross_Output stage_output;
    stage_output.FragColor = FragColor;
    return stage_output;
}
