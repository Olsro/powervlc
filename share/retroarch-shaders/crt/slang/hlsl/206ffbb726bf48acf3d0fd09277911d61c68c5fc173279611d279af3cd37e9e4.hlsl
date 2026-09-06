// Generated from crt/shaders/hyllian/support/glow/blur-glow-mask-geom.slang. See slang/upstream for licence/source.
cbuffer UBO : register(b0)
{
    row_major float4x4 global_MVP : packoffset(c0);
};

cbuffer Push : register(b1)
{
    float params_PRESET_OPTION : packoffset(c0.w);
    float params_DISPLAY_RES : packoffset(c1);
    float params_PHOSPHOR_LAYOUT : packoffset(c1.y);
    float params_MASK_STRENGTH : packoffset(c1.z);
};


static float4 gl_Position;
static float4 Position;
static float2 vTexCoord;
static float2 TexCoord;
static float2 mask_profile;

struct SPIRV_Cross_Input
{
    float4 Position : TEXCOORD0;
    float2 TexCoord : TEXCOORD1;
};

struct SPIRV_Cross_Output
{
    float2 vTexCoord : TEXCOORD0;
    float2 mask_profile : TEXCOORD1;
    float4 gl_Position : SV_Position;
};

void vert_main()
{
    gl_Position = mul(Position, global_MVP);
    vTexCoord = TexCoord * 1.00010001659393310546875f.xx;
    float2 _187 = float2(params_PHOSPHOR_LAYOUT, params_MASK_STRENGTH);
    float2 _246;
    if (params_DISPLAY_RES < 0.5f)
    {
        bool2 _259 = (params_PRESET_OPTION == 1.0f).xx;
        float2 _260 = float2(_259.x ? 1.0f.xx.x : _187.x, _259.y ? 1.0f.xx.y : _187.y);
        bool2 _261 = (params_PRESET_OPTION == 2.0f).xx;
        float2 _262 = float2(_261.x ? float2(2.0f, 1.0f).x : _260.x, _261.y ? float2(2.0f, 1.0f).y : _260.y);
        bool2 _263 = (params_PRESET_OPTION == 3.0f).xx;
        float2 _264 = float2(_263.x ? float2(11.0f, 1.0f).x : _262.x, _263.y ? float2(11.0f, 1.0f).y : _262.y);
        bool2 _265 = (params_PRESET_OPTION == 4.0f).xx;
        float2 _266 = float2(_265.x ? float2(11.0f, 1.0f).x : _264.x, _265.y ? float2(11.0f, 1.0f).y : _264.y);
        bool2 _267 = (params_PRESET_OPTION == 5.0f).xx;
        _246 = float2(_267.x ? float2(7.0f, 1.0f).x : _266.x, _267.y ? float2(7.0f, 1.0f).y : _266.y);
    }
    else
    {
        bool2 _269 = (params_PRESET_OPTION == 1.0f).xx;
        float2 _270 = float2(_269.x ? float2(2.0f, 1.0f).x : _187.x, _269.y ? float2(2.0f, 1.0f).y : _187.y);
        bool2 _271 = (params_PRESET_OPTION == 2.0f).xx;
        float2 _272 = float2(_271.x ? float2(4.0f, 1.0f).x : _270.x, _271.y ? float2(4.0f, 1.0f).y : _270.y);
        bool2 _273 = (params_PRESET_OPTION == 3.0f).xx;
        float2 _274 = float2(_273.x ? float2(14.0f, 1.0f).x : _272.x, _273.y ? float2(14.0f, 1.0f).y : _272.y);
        bool2 _275 = (params_PRESET_OPTION == 4.0f).xx;
        float2 _276 = float2(_275.x ? float2(14.0f, 1.0f).x : _274.x, _275.y ? float2(14.0f, 1.0f).y : _274.y);
        bool2 _277 = (params_PRESET_OPTION == 5.0f).xx;
        _246 = float2(_277.x ? float2(9.0f, 1.0f).x : _276.x, _277.y ? float2(9.0f, 1.0f).y : _276.y);
    }
    mask_profile = _246;
}

SPIRV_Cross_Output main(SPIRV_Cross_Input stage_input)
{
    Position = stage_input.Position;
    TexCoord = stage_input.TexCoord;
    vert_main();
    SPIRV_Cross_Output stage_output;
    stage_output.gl_Position = gl_Position;
    stage_output.vTexCoord = vTexCoord;
    stage_output.mask_profile = mask_profile;
    return stage_output;
}
