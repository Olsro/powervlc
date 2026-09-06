// Generated from crt/shaders/simple-crt/simple-crt.slang. See slang/upstream for licence/source.
cbuffer UBO : register(b0)
{
    row_major float4x4 global_MVP : packoffset(c0);
};

cbuffer Push : register(b1)
{
    float4 params_OutputSize : packoffset(c2);
    uint params_FrameCount : packoffset(c3);
    float params_OSC_STRENGTH : packoffset(c3.y);
    float params_OSC_SPEED : packoffset(c3.z);
    float params_NOISE_SIZE : packoffset(c4);
    float params_CRT_MASK_STRENGTH : packoffset(c5.z);
};


static float4 gl_Position;
static float4 Position;
static float2 vTexCoord;
static float2 TexCoord;
static float osc_mul;
static float2 noise_div;
static int noise_offset;
static float3 flicker;
static float crt_add;
static float crt_mul;

struct SPIRV_Cross_Input
{
    float4 Position : TEXCOORD0;
    float2 TexCoord : TEXCOORD1;
};

struct SPIRV_Cross_Output
{
    float2 vTexCoord : TEXCOORD0;
    nointerpolation float osc_mul : TEXCOORD1;
    nointerpolation float2 noise_div : TEXCOORD2;
    nointerpolation int noise_offset : TEXCOORD3;
    nointerpolation float3 flicker : TEXCOORD4;
    nointerpolation float crt_add : TEXCOORD5;
    nointerpolation float crt_mul : TEXCOORD6;
    float4 gl_Position : SV_Position;
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

void vert_main()
{
    gl_Position = mul(Position, global_MVP);
    vTexCoord = TexCoord;
    float _122 = params_OSC_STRENGTH * 0.100000001490116119384765625f;
    float _128 = 1.0f - _122;
    float _305 = _122 + _122;
    float _150 = (1.0f - pow(params_OSC_SPEED, 0.5f)) * 10.0f;
    float _215 = float(params_FrameCount);
    osc_mul = (((_305 * 0.5f) + _128) * sin(sin((mod(_215, _150) / _150) * 6.283185482025146484375f) * _305)) + _128;
    noise_div = 1.0f.xx / (params_OutputSize.xy * params_NOISE_SIZE.xx);
    uint4 _230 = (params_FrameCount.xxxx * uint4(2348682457u, 636532089u, 3368437335u, 2717797467u)) + uint4(2891336453u, 2891336453u, 2891336453u, 2891336453u);
    uint4 _241 = ((_230 >> ((_230 >> uint4(28u, 28u, 28u, 28u)) + uint4(4u, 4u, 4u, 4u))) ^ _230) * uint4(277803737u, 277803737u, 277803737u, 277803737u);
    uint4 _246 = (_241 >> uint4(22u, 22u, 22u, 22u)) ^ _241;
    noise_offset = int(mod(float(_246.x), 1021.0f));
    flicker = dot(asfloat((_246 & uint4(8388607u, 8388607u, 8388607u, 8388607u)) | uint4(1065353216u, 1065353216u, 1065353216u, 1065353216u)) - 1.0f.xxxx, 0.25f.xxxx).xxx;
    crt_add = mod(_215, 16383.0f) * 0.00038351860712282359600067138671875f;
    crt_mul = 1.0f + (params_CRT_MASK_STRENGTH * 1.5f);
}

SPIRV_Cross_Output main(SPIRV_Cross_Input stage_input)
{
    Position = stage_input.Position;
    TexCoord = stage_input.TexCoord;
    vert_main();
    SPIRV_Cross_Output stage_output;
    stage_output.gl_Position = gl_Position;
    stage_output.vTexCoord = vTexCoord;
    stage_output.osc_mul = osc_mul;
    stage_output.noise_div = noise_div;
    stage_output.noise_offset = noise_offset;
    stage_output.flicker = flicker;
    stage_output.crt_add = crt_add;
    stage_output.crt_mul = crt_mul;
    return stage_output;
}
