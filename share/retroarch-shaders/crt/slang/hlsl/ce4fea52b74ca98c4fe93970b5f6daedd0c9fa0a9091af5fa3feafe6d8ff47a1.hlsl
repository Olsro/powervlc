// Generated from crt/shaders/guest/advanced/ntsc/ntsc-pass1.slang. See slang/upstream for licence/source.
cbuffer UBO : register(b0)
{
    row_major float4x4 global_MVP : packoffset(c0);
};

cbuffer Push : register(b1)
{
    float4 params_OriginalSize : packoffset(c1);
    float params_ntsc_sat : packoffset(c3.z);
    float params_cust_fringing : packoffset(c3.w);
    float params_cust_artifacting : packoffset(c4);
    float params_ntsc_bright : packoffset(c4.y);
    float params_ntsc_scale : packoffset(c4.z);
    float params_ntsc_fields : packoffset(c4.w);
    float params_ntsc_phase : packoffset(c5);
    float params_auto_res : packoffset(c6);
    float params_speedup : packoffset(c6.w);
};


static float4 gl_Position;
static float4 Position;
static float2 vTexCoord;
static float2 TexCoord;
static float2 pix_no;
static float phase;
static float CHROMA_MOD_FREQ;
static float ARTIFACTING;
static float FRINGING;
static float SATURATION;
static float BRIGHTNESS;
static float MERGE;

struct SPIRV_Cross_Input
{
    float4 Position : TEXCOORD0;
    float2 TexCoord : TEXCOORD1;
};

struct SPIRV_Cross_Output
{
    float2 vTexCoord : TEXCOORD0;
    float2 pix_no : TEXCOORD1;
    float phase : TEXCOORD2;
    float BRIGHTNESS : TEXCOORD3;
    float SATURATION : TEXCOORD4;
    float FRINGING : TEXCOORD5;
    float ARTIFACTING : TEXCOORD6;
    float CHROMA_MOD_FREQ : TEXCOORD7;
    float MERGE : TEXCOORD8;
    float4 gl_Position : SV_Position;
};

void vert_main()
{
    float _38 = lerp(1.0f, 0.5f, clamp((params_auto_res * round(params_OriginalSize.x * 0.0033333334140479564666748046875f)) - 1.0f, 0.0f, 1.0f));
    float _46 = min(params_ntsc_scale * _38, 1.0f);
    float _51 = params_OriginalSize.x * _38;
    gl_Position = mul(Position, global_MVP);
    vTexCoord = TexCoord * float2(params_speedup, 1.0f);
    pix_no = ((vTexCoord * params_OriginalSize.xy) * float2(_46, _46 / _38)) * float2(4.0f, 1.0f);
    float _200;
    if (params_ntsc_phase < 1.5f)
    {
        _200 = (_51 > 300.0f) ? 2.0f : 3.0f;
    }
    else
    {
        _200 = (params_ntsc_phase > 2.5f) ? 3.0f : 2.0f;
    }
    phase = _200;
    if (params_ntsc_phase == 4.0f)
    {
        phase = 3.0f;
    }
    else
    {
        if (params_ntsc_phase == 5.0f)
        {
            phase = 2.0f;
        }
    }
    bool _135 = phase == 2.0f;
    bool _141;
    if (_135)
    {
        _141 = params_ntsc_phase != 5.0f;
    }
    else
    {
        _141 = _135;
    }
    float _205;
    if (_141)
    {
        _205 = 0.83775806427001953125f;
    }
    else
    {
        bool _148 = _51 <= 300.0f;
        bool _154;
        if (!_148)
        {
            _154 = phase == 3.0f;
        }
        else
        {
            _154 = _148;
        }
        _205 = _154 ? 1.0471975803375244140625f : 1.57079637050628662109375f;
    }
    CHROMA_MOD_FREQ = _205;
    ARTIFACTING = params_cust_artifacting;
    FRINGING = params_cust_fringing;
    SATURATION = params_ntsc_sat;
    BRIGHTNESS = params_ntsc_bright;
    MERGE = 0.0f;
    bool _180 = params_ntsc_fields == (-1.0f);
    bool _185;
    if (_180)
    {
        _185 = phase == 3.0f;
    }
    else
    {
        _185 = _180;
    }
    if (_185)
    {
        MERGE = 1.0f;
    }
    else
    {
        if (params_ntsc_fields == 0.0f)
        {
            MERGE = 0.0f;
        }
        else
        {
            if (params_ntsc_fields == 1.0f)
            {
                MERGE = 1.0f;
            }
        }
    }
}

SPIRV_Cross_Output main(SPIRV_Cross_Input stage_input)
{
    Position = stage_input.Position;
    TexCoord = stage_input.TexCoord;
    vert_main();
    SPIRV_Cross_Output stage_output;
    stage_output.gl_Position = gl_Position;
    stage_output.vTexCoord = vTexCoord;
    stage_output.pix_no = pix_no;
    stage_output.phase = phase;
    stage_output.CHROMA_MOD_FREQ = CHROMA_MOD_FREQ;
    stage_output.ARTIFACTING = ARTIFACTING;
    stage_output.FRINGING = FRINGING;
    stage_output.SATURATION = SATURATION;
    stage_output.BRIGHTNESS = BRIGHTNESS;
    stage_output.MERGE = MERGE;
    return stage_output;
}
