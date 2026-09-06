// Generated from crt/shaders/geom-deluxe/gaussy.slang. See slang/upstream for licence/source.
cbuffer UBO : register(b0)
{
    float4 global_SourceSize : packoffset(c0);
    row_major float4x4 global_MVP : packoffset(c6);
};

cbuffer Push : register(b1)
{
    float params_width : packoffset(c0.w);
    float params_aspect_x : packoffset(c1);
    float params_aspect_y : packoffset(c1.y);
};


static float4 gl_Position;
static float4 Position;
static float2 v_texCoord;
static float2 TexCoord;
static float4 v_coeffs;

struct SPIRV_Cross_Input
{
    float4 Position : TEXCOORD0;
    float2 TexCoord : TEXCOORD1;
};

struct SPIRV_Cross_Output
{
    float2 v_texCoord : TEXCOORD0;
    float4 v_coeffs : TEXCOORD1;
    float4 gl_Position : SV_Position;
};

void vert_main()
{
    gl_Position = mul(Position, global_MVP);
    v_texCoord = TexCoord;
    float _90 = (params_width * global_SourceSize.y) / (320.0f * params_aspect_y);
    v_coeffs = exp(float4(1.0f, 4.0f, 9.0f, 16.0f) * (((-1.0f) / _90) / _90).xxxx);
}

SPIRV_Cross_Output main(SPIRV_Cross_Input stage_input)
{
    Position = stage_input.Position;
    TexCoord = stage_input.TexCoord;
    vert_main();
    SPIRV_Cross_Output stage_output;
    stage_output.gl_Position = gl_Position;
    stage_output.v_texCoord = v_texCoord;
    stage_output.v_coeffs = v_coeffs;
    return stage_output;
}
