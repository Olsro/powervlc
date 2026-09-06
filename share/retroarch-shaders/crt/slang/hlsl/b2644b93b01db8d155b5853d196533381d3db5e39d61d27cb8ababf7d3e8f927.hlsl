// Generated from crt/shaders/crt-yo6/crt-yo6-flat-trinitron-tv.slang. See slang/upstream for licence/source.
static const float4 _117[13] = { float4(2.0f, 3.0f, 0.0f, 0.0f), float4(3.0f, 4.0f, 1.0f, 3.0f), float4(3.0f, 5.0f, 1.0f, 7.0f), float4(4.0f, 6.0f, 1.0f, 12.0f), float4(5.0f, 7.0f, 1.0f, 18.0f), float4(5.0f, 8.0f, 1.0f, 25.0f), float4(6.0f, 9.0f, 2.0f, 33.0f), float4(7.0f, 10.0f, 2.0f, 42.0f), float4(7.0f, 11.0f, 2.0f, 52.0f), float4(8.0f, 12.0f, 2.0f, 63.0f), float4(9.0f, 13.0f, 3.0f, 75.0f), float4(9.0f, 14.0f, 3.0f, 88.0f), float4(10.0f, 15.0f, 3.0f, 102.0f) };

cbuffer UBO : register(b0)
{
    row_major float4x4 global_MVP : packoffset(c0);
};

cbuffer Push : register(b1)
{
    float4 params_SourceSize : packoffset(c0);
    float4 params_OutputSize : packoffset(c2);
    float params_TVL : packoffset(c3.y);
    float params_VSIZE : packoffset(c3.z);
    float params_VZOOM : packoffset(c3.w);
    float params_VOFF : packoffset(c4);
    float params_VOFFC : packoffset(c4.y);
};


static float4 gl_Position;
static float2 vXY;
static float2 TexCoord;
static float4 patNFO;
static float4 crtSize;
static float vOff;
static float4 Position;

struct SPIRV_Cross_Input
{
    float4 Position : TEXCOORD0;
    float2 TexCoord : TEXCOORD1;
};

struct SPIRV_Cross_Output
{
    float2 vXY : TEXCOORD0;
    float4 patNFO : TEXCOORD1;
    float4 crtSize : TEXCOORD2;
    float vOff : TEXCOORD3;
    float4 gl_Position : SV_Position;
};

void vert_main()
{
    float _229;
    if (int(params_VSIZE) <= 0)
    {
        _229 = params_SourceSize.y;
    }
    else
    {
        _229 = params_VSIZE;
    }
    float _230;
    if (int(params_TVL) <= 0)
    {
        _230 = _229 * 2.0f;
    }
    else
    {
        _230 = params_TVL;
    }
    float2 _54 = float2(_230, _229);
    int _62 = int(params_VZOOM) - 3;
    int _234;
    if (_62 < 0)
    {
        int _232_copy;
        int _236;
        _236 = 0;
        for (int _232 = 1; _232 < 13; _232_copy = _232, _232++, _236 = _232_copy)
        {
            float2 _126 = _117[_232].xy * _54;
            bool _133 = _126.x > params_OutputSize.x;
            bool _142;
            if (!_133)
            {
                _142 = _126.y > params_OutputSize.y;
            }
            else
            {
                _142 = _133;
            }
            if (_142)
            {
                break;
            }
        }
        _234 = _236;
    }
    else
    {
        _234 = _62;
    }
    float2 _156 = _117[_234].xy * _54;
    vXY = (TexCoord * params_OutputSize.xy) - floor((params_OutputSize.xy - _156) * 0.5f.xx);
    patNFO = _117[_234];
    crtSize = float4(_156, _230, _229);
    float _238;
    if (int(params_VOFFC) == 1)
    {
        _238 = floor((params_SourceSize.y - _229) * 0.5f);
    }
    else
    {
        _238 = 0.0f;
    }
    vOff = params_VOFF + _238;
    gl_Position = mul(Position, global_MVP);
}

SPIRV_Cross_Output main(SPIRV_Cross_Input stage_input)
{
    TexCoord = stage_input.TexCoord;
    Position = stage_input.Position;
    vert_main();
    SPIRV_Cross_Output stage_output;
    stage_output.gl_Position = gl_Position;
    stage_output.vXY = vXY;
    stage_output.patNFO = patNFO;
    stage_output.crtSize = crtSize;
    stage_output.vOff = vOff;
    return stage_output;
}
