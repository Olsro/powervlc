// Generated from crt/shaders/hyllian/crt-hyllian-base.slang. See slang/upstream for licence/source.
cbuffer Push : register(b1)
{
    float params_SCANLINES_HIRES : packoffset(c4.w);
    float params_CRT_ANTI_RINGING : packoffset(c5.y);
    float params_VSCANLINES : packoffset(c5.z);
};

Texture2D<float4> Source : register(t2);
SamplerState _Source_sampler : register(s2);

static float2 vTexCoord;
static float4 TextureSize;
static float2 dx;
static float2 dy;
static float4 profile;
static float draw_scanlines;
static float4 FragColor;

struct SPIRV_Cross_Input
{
    float2 vTexCoord : TEXCOORD0;
    float4 TextureSize : TEXCOORD1;
    float2 dx : TEXCOORD2;
    float2 dy : TEXCOORD3;
    float4 profile : TEXCOORD4;
    float draw_scanlines : TEXCOORD5;
};

struct SPIRV_Cross_Output
{
    float4 FragColor : SV_Target0;
};

void frag_main()
{
    float2 _71 = (vTexCoord * TextureSize.xy) - 0.5f.xx;
    float2 _74 = floor(_71);
    float2 _97 = params_VSCANLINES.xx;
    float2 _98 = lerp(float2(_74.x, _71.y), float2(_71.x, _74.y), _97);
    bool2 _107 = (params_SCANLINES_HIRES > 0.5f).xx;
    float2 _112 = (float2(_107.x ? _98.x : _74.x, _107.y ? _98.y : _74.y) + 0.5f.xx) * TextureSize.zw;
    float2 _122 = lerp(frac(_71), frac(_71.yx), _97);
    float2 _132 = _112 - dx;
    float4 _133 = Source.Sample(_Source_sampler, _132);
    float4 _138 = Source.Sample(_Source_sampler, _112);
    float3 _139 = _138.xyz;
    float2 _144 = _112 + dx;
    float4 _145 = Source.Sample(_Source_sampler, _144);
    float3 _146 = _145.xyz;
    float2 _153 = _112 + (dx * 2.0f);
    float4 _154 = Source.Sample(_Source_sampler, _153);
    float3 _452;
    float3 _453;
    float3 _454;
    float3 _455;
    if (params_SCANLINES_HIRES < 0.5f)
    {
        _455 = Source.Sample(_Source_sampler, _153 + dy).xyz;
        _454 = Source.Sample(_Source_sampler, _144 + dy).xyz;
        _453 = Source.Sample(_Source_sampler, _112 + dy).xyz;
        _452 = Source.Sample(_Source_sampler, _132 + dy).xyz;
    }
    else
    {
        _455 = _154.xyz;
        _454 = _146;
        _453 = _139;
        _452 = _133.xyz;
    }
    float _251 = _122.x;
    float _254 = _251 * _251;
    float4 _276 = mul(float4x4(float4(-0.5f, 1.0f, -0.5f, 0.0f), float4(1.5f, -2.5f, 0.0f, 1.0f), float4(-1.5f, 2.0f, 0.5f, 0.0f), float4(0.5f, -0.5f, 0.0f, 0.0f)), float4(_254 * _251, _254, _251, 1.0f));
    float3 _280 = mul(_276, float4x3(float3(_133.xyz), float3(_138.xyz), float3(_145.xyz), float3(_154.xyz)));
    float3 _284 = mul(_276, float4x3(_452, _453, _454, _455));
    float3 _312 = params_CRT_ANTI_RINGING.xxx;
    float3 _313 = lerp(_280, clamp(_280, min(_139, _146), max(_139, _146)), _312);
    float3 _324 = lerp(_284, clamp(_284, min(_453, _454), max(_453, _454)), _312);
    float _327 = _122.y;
    float3 _337 = profile.y.xxx;
    float3 _341 = profile.z.xxx;
    float3 _343 = lerp(_337, _341, _313);
    float3 _352 = lerp(_337, _341, _324);
    float3 _365 = (profile.x * _327).xxx / ((_343 * _343) + 1.0000000116860974230803549289703e-07f.xxx);
    float3 _377 = (profile.x * (1.0f - _327)).xxx / ((_352 * _352) + 1.0000000116860974230803549289703e-07f.xxx);
    float3 _460;
    if (draw_scanlines > 0.5f)
    {
        float3 _457;
        float3 _459;
        if (profile.w > 0.5f)
        {
            _459 = exp((_377 * (-16.0f)) * _377);
            _457 = exp((_365 * (-16.0f)) * _365);
        }
        else
        {
            _459 = 1.0f.xxx - smoothstep(0.0f.xxx, 0.5f.xxx, _377);
            _457 = 1.0f.xxx - smoothstep(0.0f.xxx, 0.5f.xxx, _365);
        }
        _460 = (_313 * _457) + (_324 * _459);
    }
    else
    {
        _460 = Source.Sample(_Source_sampler, vTexCoord).xyz;
    }
    FragColor = float4(_460, 1.0f);
}

SPIRV_Cross_Output main(SPIRV_Cross_Input stage_input)
{
    vTexCoord = stage_input.vTexCoord;
    TextureSize = stage_input.TextureSize;
    dx = stage_input.dx;
    dy = stage_input.dy;
    profile = stage_input.profile;
    draw_scanlines = stage_input.draw_scanlines;
    frag_main();
    SPIRV_Cross_Output stage_output;
    stage_output.FragColor = FragColor;
    return stage_output;
}
