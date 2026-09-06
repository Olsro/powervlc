// Generated from crt/shaders/hyllian/support/ntsc/shaders/ntsc-adaptive-lite/ntsc-lite-pass1.slang. See slang/upstream for licence/source.
cbuffer UBO : register(b0)
{
    row_major float4x4 global_MVP : packoffset(c0);
    float4 global_OutputSize : packoffset(c4);
    float4 global_OriginalSize : packoffset(c5);
    float4 global_SourceSize : packoffset(c6);
    float global_quality : packoffset(c7.y);
    float global_ntsc_sat : packoffset(c7.z);
    float global_cust_fringing : packoffset(c7.w);
    float global_cust_artifacting : packoffset(c8);
    float global_ntsc_bright : packoffset(c8.y);
    float global_ntsc_scale : packoffset(c8.z);
    float global_ntsc_fields : packoffset(c8.w);
    float global_ntsc_phase : packoffset(c9);
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
    gl_Position = mul(Position, global_MVP);
    vTexCoord = TexCoord;
    if (global_ntsc_scale < 1.0f)
    {
        pix_no = (TexCoord * global_SourceSize.xy) * ((global_OutputSize.xy * global_ntsc_scale) / global_SourceSize.xy);
    }
    else
    {
        pix_no = (TexCoord * global_SourceSize.xy) * (global_OutputSize.xy / global_SourceSize.xy);
    }
    float _192;
    if (global_ntsc_phase < 1.5f)
    {
        _192 = (global_OriginalSize.x > 300.0f) ? 2.0f : 3.0f;
    }
    else
    {
        _192 = (global_ntsc_phase > 2.5f) ? 3.0f : 2.0f;
    }
    phase = _192;
    float _109 = max(global_ntsc_scale, 1.0f);
    CHROMA_MOD_FREQ = (phase < 2.5f) ? 0.83775806427001953125f : 1.0471975803375244140625f;
    bool _121 = global_quality > (-0.5f);
    float _195;
    if (_121)
    {
        _195 = (global_quality * 0.5f) * (_109 + 1.0f);
    }
    else
    {
        _195 = global_cust_artifacting;
    }
    ARTIFACTING = _195;
    float _196;
    if (_121)
    {
        _196 = global_quality;
    }
    else
    {
        _196 = global_cust_fringing;
    }
    FRINGING = _196;
    SATURATION = global_ntsc_sat;
    BRIGHTNESS = global_ntsc_bright;
    pix_no.x *= _109;
    int _167 = int(global_quality);
    bool _168 = _167 == 2;
    bool _174;
    if (!_168)
    {
        _174 = phase < 2.5f;
    }
    else
    {
        _174 = _168;
    }
    MERGE = _174 ? 0.0f : 1.0f;
    float _199;
    if (_167 == (-1))
    {
        _199 = global_ntsc_fields;
    }
    else
    {
        _199 = MERGE;
    }
    MERGE = _199;
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
