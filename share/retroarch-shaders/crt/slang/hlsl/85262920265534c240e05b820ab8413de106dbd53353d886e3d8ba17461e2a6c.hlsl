// Generated from crt/shaders/newpixie/newpixie-crt.slang. See slang/upstream for licence/source.
cbuffer Push : register(b1)
{
    float4 params_OutputSize : packoffset(c1);
    uint params_FrameCount : packoffset(c2);
    float params_use_frame : packoffset(c2.y);
    float params_curvature : packoffset(c2.z);
    float params_wiggle_toggle : packoffset(c2.w);
    float params_scanroll : packoffset(c3);
    float params_vignette : packoffset(c3.y);
    float params_ghosting : packoffset(c3.z);
};

Texture2D<float4> accum1 : register(t3);
SamplerState _accum1_sampler : register(s3);
Texture2D<float4> blur2 : register(t4);
SamplerState _blur2_sampler : register(s4);
Texture2D<float4> frametexture : register(t5);
SamplerState _frametexture_sampler : register(s5);

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
    float _169 = float(params_FrameCount);
    float _171 = mod(_169, 849.0f);
    float2 _850 = ((vTexCoord - 0.5f.xx) * float2(0.925000011920928955078125f, 1.0950000286102294921875f)) * params_curvature;
    float _859 = _850.x * (1.0f + pow(abs(_850.y) * 0.25f, 2.0f));
    float2 _185 = lerp((((float2(_859, _850.y * (1.0f + pow(abs(_859) * 0.3333333432674407958984375f, 2.0f))) / params_curvature.xx) + 0.5f.xx) * 0.920000016689300537109375f) + 0.039999999105930328369140625f.xx, vTexCoord, 0.4000000059604644775390625f.xx);
    float2 _200 = (_185 * 1.10099995136260986328125f) + float2(-0.0475000031292438507080078125f, -0.051500000059604644775390625f);
    float _210 = _185.y;
    float2 _247 = vTexCoord * params_OutputSize.xy;
    float _259 = ((((params_wiggle_toggle * sin((_171 * 3.6000001430511474609375f) + (_210 * 13.0f))) * sin((_171 * 8.27999973297119140625f) + (_210 * 19.0f))) * sin((0.300000011920928955078125f + (_171 * 3.96000003814697265625f)) + (_210 * 23.0f))) * 0.00120000005699694156646728515625f) + ((sin(_247.y * 1.5f) / params_OutputSize.x) * 0.25f);
    float _264 = mod(_169, 640.0f);
    float _270 = _200.x;
    float _271 = _259 + _270;
    float _275 = _200.y;
    float2 _889 = (float2(_271 + 0.000899999984540045261383056640625f, _275 + 0.000899999984540045261383056640625f) * float2(1.02499997615814208984375f, 0.920000016689300537109375f)) + float2(-0.012500000186264514923095703125f, 0.039999999105930328369140625f);
    float _291 = (pow(abs(accum1.Sample(_accum1_sampler, float2(_889.x, 1.0f - _889.y)).xyz), 2.2000000476837158203125f.xxx) * 1.25f.xxx).x + 0.0199999995529651641845703125f;
    float2 _908 = (float2(_271, _275 - 0.0010999999940395355224609375f) * float2(1.02499997615814208984375f, 0.920000016689300537109375f)) + float2(-0.012500000186264514923095703125f, 0.039999999105930328369140625f);
    float _314 = (pow(abs(accum1.Sample(_accum1_sampler, float2(_908.x, 1.0f - _908.y)).xyz), 2.2000000476837158203125f.xxx) * 1.25f.xxx).y + 0.0199999995529651641845703125f;
    float2 _927 = (float2(_271 - 0.00150000001303851604461669921875f, _275) * float2(1.02499997615814208984375f, 0.920000016689300537109375f)) + float2(-0.012500000186264514923095703125f, 0.039999999105930328369140625f);
    float _338 = (pow(abs(accum1.Sample(_accum1_sampler, float2(_927.x, 1.0f - _927.y)).xyz), 2.2000000476837158203125f.xxx) * 1.25f.xxx).z + 0.0199999995529651641845703125f;
    float _385 = 15.0f * _210;
    float _397 = 10.0f * _210;
    float2 _946 = ((((float2(_259 - 0.01400000043213367462158203125f, -0.02700000070035457611083984375f) * 0.85000002384185791015625f) + (float2(0.3499999940395355224609375f * sin((0.14285714924335479736328125f + _385) + (0.89999997615814208984375f * _264)), 0.3499999940395355224609375f * sin((0.2857142984867095947265625f + _397) + (1.37000000476837158203125f * _264))) * 0.007000000216066837310791015625f)) + float2(_270 + 0.001000000047497451305389404296875f, _275 + 0.001000000047497451305389404296875f)) * float2(1.02499997615814208984375f, 0.920000016689300537109375f)) + float2(-0.012500000186264514923095703125f, 0.039999999105930328369140625f);
    float2 _965 = ((((float2(_259 - 0.01899999938905239105224609375f, -0.0199999995529651641845703125f) * 0.85000002384185791015625f) + (float2(0.3499999940395355224609375f * cos((0.111111111938953399658203125f + _385) + (0.5f * _264)), 0.3499999940395355224609375f * sin((0.22222222387790679931640625f + _397) + (1.5f * _264))) * 0.007000000216066837310791015625f)) + float2(_270, _275 - 0.00200000009499490261077880859375f)) * float2(1.02499997615814208984375f, 0.920000016689300537109375f)) + float2(-0.012500000186264514923095703125f, 0.039999999105930328369140625f);
    float2 _984 = ((((float2(_259 - 0.0170000009238719940185546875f, -0.0030000000260770320892333984375f) * 0.85000002384185791015625f) + (float2(0.3499999940395355224609375f * sin((0.666666686534881591796875f + _385) + (0.699999988079071044921875f * _264)), 0.3499999940395355224609375f * cos((0.666666686534881591796875f + _397) + (1.62999999523162841796875f * _264))) * 0.007000000216066837310791015625f)) + float2(_270 - 0.00200000009499490261077880859375f, _275)) * float2(1.02499997615814208984375f, 0.920000016689300537109375f)) + float2(-0.012500000186264514923095703125f, 0.039999999105930328369140625f);
    float3 _576 = (((1.0f - pow(1.0f - pow(clamp(((_291 * 0.2989999949932098388671875f) + (_314 * 0.58700001239776611328125f)) + (_338 * 0.114000000059604644775390625f), 0.0f, 1.0f), 2.0f), 1.0f)) * 0.85000002384185791015625f) + 0.1500000059604644775390625f).xxx;
    float3 _612 = (((float3(_291, _314, _338) + (((params_ghosting * 0.10514999926090240478515625f).xxx * pow(clamp(pow(abs(blur2.Sample(_blur2_sampler, float2(_946.x, 1.0f - _946.y)).xyz), 2.2000000476837158203125f.xxx) * float3(1.875f, 0.9375f, 0.9375f), 0.0f.xxx, 1.0f.xxx), 2.0f.xxx)) * _576)) + (((params_ghosting * 0.0619500018656253814697265625f).xxx * pow(clamp(pow(abs(blur2.Sample(_blur2_sampler, float2(_965.x, 1.0f - _965.y)).xyz), 2.2000000476837158203125f.xxx) * float3(0.9375f, 1.875f, 0.9375f), 0.0f.xxx, 1.0f.xxx), 2.0f.xxx)) * _576)) + (((params_ghosting * 0.1328999996185302734375f).xxx * pow(clamp(pow(abs(blur2.Sample(_blur2_sampler, float2(_984.x, 1.0f - _984.y)).xyz), 2.2000000476837158203125f.xxx) * float3(0.9375f, 0.9375f, 1.875f), 0.0f.xxx, 1.0f.xxx), 2.0f.xxx)) * _576)) * float3(0.949999988079071044921875f, 1.0499999523162841796875f, 0.949999988079071044921875f);
    float _643 = _185.x;
    float _654 = 1.0f - _210;
    float _667 = _264 * params_scanroll;
    float3 _1003 = max(0.0f.xxx, (((clamp(((_612 * 1.2999999523162841796875f) + ((_612 * 0.75f) * _612)) + (((((_612 * 1.25f) * _612) * _612) * _612) * _612), 0.0f.xxx, 10.0f.xxx) * (1.2999999523162841796875f * pow((1.0f - (0.9900000095367431640625f * params_vignette)) + ((((16.0f * _643) * _210) * (1.0f - _643)) * _654), 0.5f))) * pow(clamp(0.3499999940395355224609375f + (0.180000007152557373046875f * sin((6.0f * _667) - ((_210 * params_OutputSize.y) * 1.5f))), 0.0f, 1.0f), 0.89999997615814208984375f).xxx) * (1.0f - (0.23000000417232513427734375f * clamp(mod(_247.x, 3.0f) * 0.5f, 0.0f, 1.0f)))) - 0.0040000001899898052215576171875f.xxx);
    float3 _1006 = _1003 * 6.19999980926513671875f;
    float2 _712 = _185 * params_OutputSize.xy;
    float3 _753 = (((_1003 * (_1006 + 0.5f.xxx)) / ((_1003 * (_1006 + 1.7000000476837158203125f.xxx)) + 0.0599999986588954925537109375f.xxx)) - (pow(float3(frac(sin(dot(_712 + _667.xx, float2(12.98980045318603515625f, 78.233001708984375f))) * 43758.546875f), frac(sin(dot(_712 + (_667 * 2.0f).xx, float2(12.98980045318603515625f, 78.233001708984375f))) * 43758.546875f), frac(sin(dot(_712 + (_667 * 3.0f).xx, float2(12.98980045318603515625f, 78.233001708984375f))) * 43758.546875f)), 1.5f.xxx) * 0.014999999664723873138427734375f)) * (1.0f - (0.0040000001899898052215576171875f * ((sin((50.0f * _667) + (_210 * 2.0f)) * 0.5f) + 0.5f)));
    float4 _770 = frametexture.Sample(_frametexture_sampler, vTexCoord);
    float3 _775 = lerp(_770.xyz, 0.5f.xxx, 0.5f.xxx);
    float4 _1127 = _770;
    _1127.x = _775.x;
    _1127.y = _775.y;
    _1127.z = _775.z;
    float _817 = _770.w;
    float3 _827 = lerp(_753, lerp(max(_753, 0.0f.xxx), pow(abs(_1127.xyz), 1.39999997615814208984375f.xxx) * clamp((((512.0f * _643) * _654) * (1.0f - _643)) * _210, 0.20000000298023223876953125f, 0.800000011920928955078125f), (_817 * _817).xxx), params_use_frame.xxx);
    FragColor = float4(_827, 1.0f);
}

SPIRV_Cross_Output main(SPIRV_Cross_Input stage_input)
{
    vTexCoord = stage_input.vTexCoord;
    frag_main();
    SPIRV_Cross_Output stage_output;
    stage_output.FragColor = FragColor;
    return stage_output;
}
