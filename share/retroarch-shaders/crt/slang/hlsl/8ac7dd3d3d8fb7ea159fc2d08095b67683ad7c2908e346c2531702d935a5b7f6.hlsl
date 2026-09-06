// Generated from crt/shaders/hyllian/crt-hyllian-sinc-pass0.slang. See slang/upstream for licence/source.
cbuffer UBO : register(b0)
{
    float4 global_SourceSize : packoffset(c6);
};

cbuffer Push : register(b1)
{
    float params_HFILTER_PROFILE : packoffset(c0);
    float params_SHARPNESS_HACK : packoffset(c0.y);
    float params_SHP : packoffset(c0.z);
    float params_RADIUS : packoffset(c0.w);
    float params_CRT_ANTI_RINGING : packoffset(c1);
    float params_CURVATURE : packoffset(c1.y);
    float params_WARP_X : packoffset(c1.z);
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

void frag_main()
{
    float _188 = params_SHARPNESS_HACK * global_SourceSize.x;
    float2 _191 = float2(_188, global_SourceSize.y);
    float2 _196 = float2(1.0f / _188, 0.0f);
    float2 _635;
    if (params_CURVATURE > 0.5f)
    {
        float2 _484 = (vTexCoord * 2.0f) - 1.0f.xx;
        float _486 = _484.x;
        float _491 = _484.y;
        float _496 = sqrt((_486 * _486) + (_491 * _491));
        float2 _511 = 1.0f.xx / (1.0f.xx + ((float2(params_WARP_X, 0.0f) * 15.0f) * 0.20000000298023223876953125f));
        _635 = ((((_484 / _496.xx) * (1.0f.xx - pow((1.0f - (_496 * 0.707106769084930419921875f)).xx, _511))) / (1.0f.xx - pow(0.292893230915069580078125f.xx, _511))) * 0.5f) + 0.5f.xx;
    }
    else
    {
        _635 = vTexCoord;
    }
    float2 _220 = (_635 * _191) + float2(-0.5f, 0.0f);
    float2 _227 = (floor(_220) + 0.5f.xx) / _191;
    float2 _230 = frac(_220);
    float2 _242 = _196 * 3.0f;
    float4 _244 = Source.Sample(_Source_sampler, _227 - _242);
    float2 _250 = _196 * 2.0f;
    float4 _252 = Source.Sample(_Source_sampler, _227 - _250);
    float4 _259 = Source.Sample(_Source_sampler, _227 - _196);
    float3 _260 = _259.xyz;
    float4 _264 = Source.Sample(_Source_sampler, _227);
    float3 _265 = _264.xyz;
    float4 _271 = Source.Sample(_Source_sampler, _227 + _196);
    float3 _272 = _271.xyz;
    float4 _279 = Source.Sample(_Source_sampler, _227 + _250);
    float3 _280 = _279.xyz;
    float4 _287 = Source.Sample(_Source_sampler, _227 + _242);
    float4 _295 = Source.Sample(_Source_sampler, _227 + (_196 * 4.0f));
    float3 _304 = min(min(_260, _265), min(_272, _280));
    float3 _312 = max(max(_260, _265), max(_272, _280));
    float3 _316 = _304 * 0.3333333432674407958984375f;
    float3 _319 = _312 * 3.0f;
    float2 _538 = float2(params_SHP, params_RADIUS);
    float2 _637;
    if (params_HFILTER_PROFILE == 1.0f)
    {
        _637 = float2(0.86000001430511474609375f, 4.0f);
    }
    else
    {
        bool2 _661 = (params_HFILTER_PROFILE == 2.0f).xx;
        _637 = float2(_661.x ? float2(0.75f, 4.0f).x : _538.x, _661.y ? float2(0.75f, 4.0f).y : _538.y);
    }
    float _386 = _230.x;
    float4 _561 = max(abs(float4(3.0f + _386, 2.0f + _386, 1.0f + _386, _386)), 9.9999997473787516355514526367188e-06f.xxxx) * _637.x;
    float4 _580 = _561 * 3.1415927410125732421875f;
    float4 _573 = _637.y.xxxx;
    float4 _588 = (_561 / _573) * 3.1415927410125732421875f;
    float4 _576 = (sin(_580) / _580) * (sin(_588) / _588);
    float4 _603 = max(abs(float4(1.0f - _386, 2.0f - _386, 3.0f - _386, 4.0f - _386)), 9.9999997473787516355514526367188e-06f.xxxx) * _637.x;
    float4 _622 = _603 * 3.1415927410125732421875f;
    float4 _630 = (_603 / _573) * 3.1415927410125732421875f;
    float4 _618 = (sin(_622) / _622) * (sin(_630) / _630);
    float4 _428 = (dot(_576, 1.0f.xxxx) + dot(_618, 1.0f.xxxx)).xxxx;
    float3 _444 = clamp(mul(_576 / _428, float4x3(clamp(_244.xyz, _316, _319), clamp(_252.xyz, _316, _319), float3(_259.xyz), float3(_264.xyz))) + mul(_618 / _428, float4x3(float3(_271.xyz), float3(_279.xyz), clamp(_287.xyz, _316, _319), clamp(_295.xyz, _316, _319))), 0.0f.xxx, 1.0f.xxx);
    float3 _655;
    if (params_CRT_ANTI_RINGING > 0.5f)
    {
        _655 = lerp(_444, clamp(_444, _304, _312), step(0.0f.xxx, (_260 - _265) * (_272 - _280)));
    }
    else
    {
        _655 = _444;
    }
    FragColor = float4(_655, 1.0f);
}

SPIRV_Cross_Output main(SPIRV_Cross_Input stage_input)
{
    vTexCoord = stage_input.vTexCoord;
    frag_main();
    SPIRV_Cross_Output stage_output;
    stage_output.FragColor = FragColor;
    return stage_output;
}
