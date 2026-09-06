// Generated from crt/shaders/crt-interlaced-halation/crt-interlaced-halation-pass2.slang. See slang/upstream for licence/source.
cbuffer UBO : register(b0)
{
    row_major float4x4 global_MVP : packoffset(c0);
};

cbuffer Push : register(b1)
{
    float4 params_SourceSize : packoffset(c0);
    float4 params_crt_interlaced_halation_refpassSize : packoffset(c1);
    float4 params_OutputSize : packoffset(c2);
};


static float4 gl_Position;
static float4 Position;
static float2 vTexCoord;
static float2 TexCoord;
static float2 sinangle;
static float2 cosangle;
static float3 stretch;
static float2 ilfac;
static float2 one;
static float mod_factor;

struct SPIRV_Cross_Input
{
    float4 Position : TEXCOORD0;
    float2 TexCoord : TEXCOORD1;
};

struct SPIRV_Cross_Output
{
    float2 vTexCoord : TEXCOORD0;
    float2 one : TEXCOORD1;
    float mod_factor : TEXCOORD2;
    float2 ilfac : TEXCOORD3;
    float3 stretch : TEXCOORD4;
    float2 sinangle : TEXCOORD5;
    float2 cosangle : TEXCOORD6;
    float4 gl_Position : SV_Position;
};

void vert_main()
{
    gl_Position = mul(Position, global_MVP);
    vTexCoord = TexCoord;
    sinangle = 0.0f.xx;
    cosangle = 1.0f.xx;
    float2 _472 = (sinangle * (-2.0f)) / (1.0f + (cosangle.x * cosangle.y)).xx;
    float _642 = dot(_472, _472) + 4.0f;
    float _659 = (2.0f * (dot(_472, sinangle) - ((2.0f * cosangle.x) * cosangle.y))) - 4.0f;
    float2 _575 = (((((_659 * (-2.0f)) - sqrt((4.0f * (_659 * _659)) - ((4.0f * _642) * (4.0f + ((8.0f * cosangle.x) * cosangle.y))))) / (2.0f * _642)).xx * _472) - ((-2.0f).xx * sinangle)) * 0.5f.xx;
    float2 _578 = sinangle / cosangle;
    float2 _581 = _575 / cosangle;
    float _585 = dot(_578, _578) + 1.0f;
    float _588 = dot(_581, _578);
    float _608 = ((_588 * 2.0f) + sqrt((4.0f * (_588 * _588)) - ((4.0f * _585) * (dot(_581, _581) - 1.0f)))) / (2.0f * _585);
    float _621 = max(abs(2.0f * acos(_608)), 9.9999997473787516355514526367188e-06f);
    float2 _630 = (((_575 - (sinangle * _608)) / cosangle) * _621) / sin(_621 * 0.5f).xx;
    float _482 = _630.y;
    float2 _483 = float2(-0.5f, _482);
    float _700 = max(abs(sqrt(dot(_483, _483))), 9.9999997473787516355514526367188e-06f);
    float _703 = _700 * 0.5f;
    float2 _708 = _483 * (sin(_703) / _700);
    float _713 = 1.0f - cos(_703);
    float _489 = _630.x;
    float2 _493 = float2(_489, -0.375f);
    float _751 = max(abs(sqrt(dot(_493, _493))), 9.9999997473787516355514526367188e-06f);
    float _754 = _751 * 0.5f;
    float2 _759 = _493 * (sin(_754) / _751);
    float _764 = 1.0f - cos(_754);
    float2 _500 = float2(((((_708 * cosangle) - (sinangle * _713)) * 2.0f) / ((1.0f + ((_713 * cosangle.x) * cosangle.y)) + dot(_708, sinangle)).xx).x, ((((_759 * cosangle) - (sinangle * _764)) * 2.0f) / ((1.0f + ((_764 * cosangle.x) * cosangle.y)) + dot(_759, sinangle)).xx).y) * float2(1.0f, 1.33333337306976318359375f);
    float2 _505 = float2(0.5f, _482);
    float _802 = max(abs(sqrt(dot(_505, _505))), 9.9999997473787516355514526367188e-06f);
    float _805 = _802 * 0.5f;
    float2 _810 = _505 * (sin(_805) / _802);
    float _815 = 1.0f - cos(_805);
    float2 _514 = float2(_489, 0.375f);
    float _853 = max(abs(sqrt(dot(_514, _514))), 9.9999997473787516355514526367188e-06f);
    float _856 = _853 * 0.5f;
    float2 _861 = _514 * (sin(_856) / _853);
    float _866 = 1.0f - cos(_856);
    float2 _521 = float2(((((_810 * cosangle) - (sinangle * _815)) * 2.0f) / ((1.0f + ((_815 * cosangle.x) * cosangle.y)) + dot(_810, sinangle)).xx).x, ((((_861 * cosangle) - (sinangle * _866)) * 2.0f) / ((1.0f + ((_866 * cosangle.x) * cosangle.y)) + dot(_861, sinangle)).xx).y) * float2(1.0f, 1.33333337306976318359375f);
    stretch = float3(((_521 + _500) * float2(1.0f, 0.75f)) * 0.5f, max(_521.x - _500.x, _521.y - _500.y));
    ilfac = float2(1.0f, clamp(floor(params_SourceSize.y * 0.004999999888241291046142578125f), 1.0f, 2.0f));
    one = ilfac / params_crt_interlaced_halation_refpassSize.xy;
    mod_factor = ((vTexCoord.x * params_crt_interlaced_halation_refpassSize.x) * params_OutputSize.x) / params_crt_interlaced_halation_refpassSize.x;
}

SPIRV_Cross_Output main(SPIRV_Cross_Input stage_input)
{
    Position = stage_input.Position;
    TexCoord = stage_input.TexCoord;
    vert_main();
    SPIRV_Cross_Output stage_output;
    stage_output.gl_Position = gl_Position;
    stage_output.vTexCoord = vTexCoord;
    stage_output.sinangle = sinangle;
    stage_output.cosangle = cosangle;
    stage_output.stretch = stretch;
    stage_output.ilfac = ilfac;
    stage_output.one = one;
    stage_output.mod_factor = mod_factor;
    return stage_output;
}
