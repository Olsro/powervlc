// Generated from crt/shaders/crt-easymode.slang. See slang/upstream for licence/source.
cbuffer UBO : register(b0)
{
    float4 global_OutputSize : packoffset(c4);
    float4 global_SourceSize : packoffset(c6);
};

cbuffer Push : register(b1)
{
    float params_BRIGHT_BOOST : packoffset(c0);
    float params_DILATION : packoffset(c0.y);
    float params_GAMMA_INPUT : packoffset(c0.z);
    float params_GAMMA_OUTPUT : packoffset(c0.w);
    float params_MASK_SIZE : packoffset(c1);
    float params_MASK_STAGGER : packoffset(c1.y);
    float params_MASK_STRENGTH : packoffset(c1.z);
    float params_MASK_DOT_HEIGHT : packoffset(c1.w);
    float params_MASK_DOT_WIDTH : packoffset(c2);
    float params_SCANLINE_CUTOFF : packoffset(c2.y);
    float params_SCANLINE_BEAM_WIDTH_MAX : packoffset(c2.z);
    float params_SCANLINE_BEAM_WIDTH_MIN : packoffset(c2.w);
    float params_SCANLINE_BRIGHT_MAX : packoffset(c3);
    float params_SCANLINE_BRIGHT_MIN : packoffset(c3.y);
    float params_SCANLINE_STRENGTH : packoffset(c3.z);
    float params_SHARPNESS_H : packoffset(c3.w);
    float params_SHARPNESS_V : packoffset(c4);
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
    float2 _170 = float2(global_SourceSize.z, 0.0f);
    float2 _186 = (vTexCoord * global_SourceSize.xy) - 0.5f.xx;
    float2 _194 = (floor(_186) + 0.5f.xx) * global_SourceSize.zw;
    float2 _197 = frac(_186);
    float _208 = _197.x;
    float _462 = _208 - step(0.5f, _208);
    float _477 = lerp(_208, 0.5f - (sqrt(0.25f - (_462 * _462)) * sign(0.5f - _208)), params_SHARPNESS_H * params_SHARPNESS_H);
    float4 _226 = max(abs(float4(1.0f + _477, _477, 1.0f - _477, 2.0f - _477) * 3.1415927410125732421875f), 9.9999997473787516355514526367188e-06f.xxxx);
    float4 _237 = ((sin(_226) * 2.0f) * sin(_226 * 0.5f)) / (_226 * _226);
    float4 _242 = _237 / dot(_237, 1.0f.xxxx).xxxx;
    float4 _488 = Source.Sample(_Source_sampler, _194 - _170);
    float4 _534 = params_DILATION.xxxx;
    float4 _492 = Source.Sample(_Source_sampler, _194);
    float4 _549 = _492 * lerp(1.0f.xxxx, _492, _534);
    float4 _498 = Source.Sample(_Source_sampler, _194 + _170);
    float4 _560 = _498 * lerp(1.0f.xxxx, _498, _534);
    float2 _503 = _170 * 2.0f;
    float4 _505 = Source.Sample(_Source_sampler, _194 + _503);
    float2 _257 = _194 + float2(0.0f, global_SourceSize.w);
    float4 _606 = Source.Sample(_Source_sampler, _257 - _170);
    float4 _610 = Source.Sample(_Source_sampler, _257);
    float4 _667 = _610 * lerp(1.0f.xxxx, _610, _534);
    float4 _616 = Source.Sample(_Source_sampler, _257 + _170);
    float4 _678 = _616 * lerp(1.0f.xxxx, _616, _534);
    float4 _623 = Source.Sample(_Source_sampler, _257 + _503);
    float _272 = _197.y;
    float _722 = _272 - step(0.5f, _272);
    float3 _287 = pow(lerp(clamp(mul(_242, float4x4(_488 * lerp(1.0f.xxxx, _488, _534), _549, _560, _505 * lerp(1.0f.xxxx, _505, _534))), min(_549, _560), max(_549, _560)).xyz, clamp(mul(_242, float4x4(_606 * lerp(1.0f.xxxx, _606, _534), _667, _678, _623 * lerp(1.0f.xxxx, _623, _534))), min(_667, _678), max(_667, _678)).xyz, lerp(_272, 0.5f - (sqrt(0.25f - (_722 * _722)) * sign(0.5f - _272)), params_SHARPNESS_V).xxx), (params_GAMMA_INPUT / (params_DILATION + 1.0f)).xxx);
    float _306 = (max(_287.x, max(_287.y, _287.z)) + dot(float3(0.2125999927520751953125f, 0.715200006961822509765625f, 0.072200000286102294921875f), _287)) * 0.5f;
    float _351 = 1.0f - params_MASK_STRENGTH;
    float2 _377 = floor(((vTexCoord * global_OutputSize.xy) * global_SourceSize.xy) / (global_SourceSize.xy * float2(params_MASK_SIZE, params_MASK_DOT_HEIGHT * params_MASK_SIZE)));
    int _396 = int(mod((_377.x + (mod(_377.y, 2.0f) * params_MASK_STAGGER)) / params_MASK_DOT_WIDTH, 3.0f));
    float3 _745;
    if (_396 == 0)
    {
        _745 = float3(1.0f, _351, _351);
    }
    else
    {
        float3 _746;
        if (_396 == 1)
        {
            _746 = float3(_351, 1.0f, _351);
        }
        else
        {
            _746 = float3(_351, _351, 1.0f);
        }
        _745 = _746;
    }
    FragColor = float4(pow(lerp(_287 * ((global_SourceSize.y >= params_SCANLINE_CUTOFF) ? 1.0f : (1.0f - (pow((cos((vTexCoord.y * 6.283185482025146484375f) * global_SourceSize.y) * 0.5f) + 0.5f, clamp(_306 * params_SCANLINE_BEAM_WIDTH_MAX, params_SCANLINE_BEAM_WIDTH_MIN, params_SCANLINE_BEAM_WIDTH_MAX)) * params_SCANLINE_STRENGTH))).xxx, _287, clamp(_306, params_SCANLINE_BRIGHT_MIN, params_SCANLINE_BRIGHT_MAX).xxx) * _745, (1.0f / params_GAMMA_OUTPUT).xxx) * params_BRIGHT_BOOST, 1.0f);
}

SPIRV_Cross_Output main(SPIRV_Cross_Input stage_input)
{
    vTexCoord = stage_input.vTexCoord;
    frag_main();
    SPIRV_Cross_Output stage_output;
    stage_output.FragColor = FragColor;
    return stage_output;
}
