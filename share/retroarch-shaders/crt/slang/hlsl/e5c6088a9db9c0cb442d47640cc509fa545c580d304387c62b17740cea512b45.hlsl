// Generated from crt/shaders/hyllian/crt-hyllian-base.slang. See slang/upstream for licence/source.
cbuffer UBO : register(b0)
{
    row_major float4x4 global_MVP : packoffset(c0);
};

cbuffer Push : register(b1)
{
    float4 params_SourceSize : packoffset(c2);
    float params_PRESET_OPTION : packoffset(c3);
    float params_BEAM_MIN_WIDTH : packoffset(c3.y);
    float params_BEAM_MAX_WIDTH : packoffset(c3.z);
    float params_SCANLINES_STRENGTH : packoffset(c3.w);
    float params_SCANLINES_SHAPE : packoffset(c4);
    float params_SHARPNESS_HACK : packoffset(c4.y);
    float params_SCANLINES_CUTOFF : packoffset(c4.z);
    float params_IR_SCALE : packoffset(c5);
    float params_VSCANLINES : packoffset(c5.z);
};


static float4 gl_Position;
static float4 Position;
static float2 vTexCoord;
static float2 TexCoord;
static float4 TextureSize;
static float2 dx;
static float2 dy;
static float4 profile;
static float draw_scanlines;

struct SPIRV_Cross_Input
{
    float4 Position : TEXCOORD0;
    float2 TexCoord : TEXCOORD1;
};

struct SPIRV_Cross_Output
{
    float2 vTexCoord : TEXCOORD0;
    float4 TextureSize : TEXCOORD1;
    float2 dx : TEXCOORD2;
    float2 dy : TEXCOORD3;
    float4 profile : TEXCOORD4;
    float draw_scanlines : TEXCOORD5;
    float4 gl_Position : SV_Position;
};

void vert_main()
{
    gl_Position = mul(Position, global_MVP);
    vTexCoord = TexCoord * 1.00010001659393310546875f;
    float2 _116 = float2(params_SHARPNESS_HACK, 1.0f / params_IR_SCALE);
    float2 _123 = params_VSCANLINES.xx;
    float2 _124 = lerp(_116, _116.yx, _123);
    TextureSize = float4(_124, 1.0f.xx / _124) * params_SourceSize;
    dx = lerp(float2(TextureSize.z, 0.0f), float2(0.0f, TextureSize.w), _123);
    dy = lerp(float2(0.0f, TextureSize.w), float2(TextureSize.z, 0.0f), _123);
    float4 _196 = float4(((-0.1599999964237213134765625f) * params_SCANLINES_SHAPE) + params_SCANLINES_STRENGTH, params_BEAM_MIN_WIDTH, params_BEAM_MAX_WIDTH, params_SCANLINES_SHAPE);
    bool4 _230 = (params_PRESET_OPTION == 1.0f).xxxx;
    float4 _231 = float4(_230.x ? float4(0.7200000286102294921875f, 0.7200000286102294921875f, 1.0f, 1.0f).x : _196.x, _230.y ? float4(0.7200000286102294921875f, 0.7200000286102294921875f, 1.0f, 1.0f).y : _196.y, _230.z ? float4(0.7200000286102294921875f, 0.7200000286102294921875f, 1.0f, 1.0f).z : _196.z, _230.w ? float4(0.7200000286102294921875f, 0.7200000286102294921875f, 1.0f, 1.0f).w : _196.w);
    bool4 _232 = (params_PRESET_OPTION == 2.0f).xxxx;
    float4 _233 = float4(_232.x ? float4(0.579999983310699462890625f, 0.7200000286102294921875f, 1.0f, 1.0f).x : _231.x, _232.y ? float4(0.579999983310699462890625f, 0.7200000286102294921875f, 1.0f, 1.0f).y : _231.y, _232.z ? float4(0.579999983310699462890625f, 0.7200000286102294921875f, 1.0f, 1.0f).z : _231.z, _232.w ? float4(0.579999983310699462890625f, 0.7200000286102294921875f, 1.0f, 1.0f).w : _231.w);
    bool4 _234 = (params_PRESET_OPTION == 3.0f).xxxx;
    float4 _235 = float4(_234.x ? float4(0.579999983310699462890625f, 0.86000001430511474609375f, 1.0f, 0.0f).x : _233.x, _234.y ? float4(0.579999983310699462890625f, 0.86000001430511474609375f, 1.0f, 0.0f).y : _233.y, _234.z ? float4(0.579999983310699462890625f, 0.86000001430511474609375f, 1.0f, 0.0f).z : _233.z, _234.w ? float4(0.579999983310699462890625f, 0.86000001430511474609375f, 1.0f, 0.0f).w : _233.w);
    bool4 _236 = (params_PRESET_OPTION == 4.0f).xxxx;
    float4 _237 = float4(_236.x ? float4(0.579999983310699462890625f, 0.86000001430511474609375f, 1.0f, 1.0f).x : _235.x, _236.y ? float4(0.579999983310699462890625f, 0.86000001430511474609375f, 1.0f, 1.0f).y : _235.y, _236.z ? float4(0.579999983310699462890625f, 0.86000001430511474609375f, 1.0f, 1.0f).z : _235.z, _236.w ? float4(0.579999983310699462890625f, 0.86000001430511474609375f, 1.0f, 1.0f).w : _235.w);
    bool4 _238 = (params_PRESET_OPTION == 5.0f).xxxx;
    profile = float4(_238.x ? float4(0.579999983310699462890625f, 0.7200000286102294921875f, 1.0f, 1.0f).x : _237.x, _238.y ? float4(0.579999983310699462890625f, 0.7200000286102294921875f, 1.0f, 1.0f).y : _237.y, _238.z ? float4(0.579999983310699462890625f, 0.7200000286102294921875f, 1.0f, 1.0f).z : _237.z, _238.w ? float4(0.579999983310699462890625f, 0.7200000286102294921875f, 1.0f, 1.0f).w : _237.w);
    draw_scanlines = float(lerp(TextureSize.y, TextureSize.x, params_VSCANLINES) <= params_SCANLINES_CUTOFF);
}

SPIRV_Cross_Output main(SPIRV_Cross_Input stage_input)
{
    Position = stage_input.Position;
    TexCoord = stage_input.TexCoord;
    vert_main();
    SPIRV_Cross_Output stage_output;
    stage_output.gl_Position = gl_Position;
    stage_output.vTexCoord = vTexCoord;
    stage_output.TextureSize = TextureSize;
    stage_output.dx = dx;
    stage_output.dy = dy;
    stage_output.profile = profile;
    stage_output.draw_scanlines = draw_scanlines;
    return stage_output;
}
