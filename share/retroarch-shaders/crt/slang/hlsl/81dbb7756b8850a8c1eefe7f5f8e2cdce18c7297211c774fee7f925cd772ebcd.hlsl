// Generated from crt/shaders/crt-nobody.slang. See slang/upstream for licence/source.
cbuffer UBO : register(b0)
{
    row_major float4x4 global_MVP : packoffset(c0);
    float4 global_SourceSize : packoffset(c4);
    uint global_FrameCount : packoffset(c7);
};

cbuffer Push : register(b1)
{
    float params_fr_zoom : packoffset(c3.z);
    float params_fr_scale_x : packoffset(c3.w);
    float params_fr_scale_y : packoffset(c4);
    float params_fr_center_x : packoffset(c4.y);
    float params_fr_center_y : packoffset(c4.z);
    float params_h_curvature : packoffset(c6.w);
};


static float4 gl_Position;
static float4 Position;
static float2 TexCoord;
static float2 vTexCoord;
static float4 intl_profile;

struct SPIRV_Cross_Input
{
    float4 Position : TEXCOORD0;
    float2 TexCoord : TEXCOORD1;
};

struct SPIRV_Cross_Output
{
    float2 vTexCoord : TEXCOORD0;
    float4 intl_profile : TEXCOORD1;
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
    vTexCoord = (0.5f.xx + (((TexCoord * 1.00000095367431640625f.xx) - 0.5f.xx) / ((float2(params_fr_scale_x, params_fr_scale_y) * params_fr_zoom) * 9.9999997473787516355514526367188e-05f.xx))) - (float2(params_fr_center_x, params_fr_center_y) * 0.00999999977648258209228515625f.xx);
    vTexCoord = lerp(vTexCoord, (vTexCoord * 2.0f) - 1.0f.xx, params_h_curvature.xx);
    float4 _237 = float4(global_SourceSize.y, global_SourceSize.w, 0.5f, 0.0f);
    bool _240 = global_SourceSize.y > 288.5f;
    bool _246;
    if (_240)
    {
        _246 = global_SourceSize.y < 576.5f;
    }
    else
    {
        _246 = _240;
    }
    float4 _293;
    if (_246)
    {
        float _251 = mod(float(global_FrameCount), 2.0f);
        float2 _254 = _237.xy * float2(0.5f, 2.0f);
        float _256 = _254.x;
        float4 _281 = _237;
        _281.x = _256;
        _281.y = _254.y;
        _293 = float4(_256, _254.y, _281.zw + (float2(_251 - 0.5f, _251) * 0.5f));
    }
    else
    {
        _293 = _237;
    }
    intl_profile = _293;
}

SPIRV_Cross_Output main(SPIRV_Cross_Input stage_input)
{
    Position = stage_input.Position;
    TexCoord = stage_input.TexCoord;
    vert_main();
    SPIRV_Cross_Output stage_output;
    stage_output.gl_Position = gl_Position;
    stage_output.vTexCoord = vTexCoord;
    stage_output.intl_profile = intl_profile;
    return stage_output;
}
