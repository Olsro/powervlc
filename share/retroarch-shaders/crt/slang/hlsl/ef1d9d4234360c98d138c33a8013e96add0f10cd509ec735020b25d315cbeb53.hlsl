// Generated from crt/shaders/crt-geom.slang. See slang/upstream for licence/source.
cbuffer UBO : register(b0)
{
    row_major float4x4 global_MVP : packoffset(c0);
    float4 global_OutputSize : packoffset(c4);
    float4 global_SourceSize : packoffset(c5);
};

cbuffer Push : register(b1)
{
    float registers_d : packoffset(c0.w);
    float registers_R : packoffset(c1);
    float registers_x_tilt : packoffset(c1.w);
    float registers_y_tilt : packoffset(c2);
    float registers_SHARPER : packoffset(c3.z);
    float registers_interlace_detect : packoffset(c4.y);
    float registers_invert_aspect : packoffset(c4.w);
    float registers_vertical_scanlines : packoffset(c5);
    float registers_xsize : packoffset(c5.y);
    float registers_ysize : packoffset(c5.z);
};


static float4 gl_Position;
static float2 sinangle;
static float2 cosangle;
static float4 Position;
static float2 vTexCoord;
static float2 TexCoord;
static float3 stretch;
static float2 TextureSize;
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
    float2 sinangle : TEXCOORD1;
    float2 cosangle : TEXCOORD2;
    float3 stretch : TEXCOORD3;
    float2 ilfac : TEXCOORD4;
    float2 one : TEXCOORD5;
    float mod_factor : TEXCOORD6;
    float2 TextureSize : TEXCOORD7;
    float4 gl_Position : SV_Position;
};

void vert_main()
{
    float2 _1022;
    if (registers_ysize > 0.001000000047497451305389404296875f)
    {
        _1022 = float2(registers_ysize, 1.0f / registers_ysize);
    }
    else
    {
        _1022 = global_SourceSize.yw;
    }
    float2 _1023;
    if (registers_xsize > 0.001000000047497451305389404296875f)
    {
        _1023 = float2(registers_xsize, 1.0f / registers_xsize);
    }
    else
    {
        _1023 = global_SourceSize.xz;
    }
    float2 _106 = ((registers_invert_aspect > 0.5f) ? 1.0f : 0.75f).xx;
    gl_Position = mul(Position, global_MVP);
    vTexCoord = TexCoord * 1.000010013580322265625f.xx;
    float2 _454 = float2(registers_x_tilt, registers_y_tilt);
    sinangle = sin(_454);
    cosangle = cos(_454);
    float _560 = -registers_R;
    float2 _576 = (sinangle * _560) / (1.0f + (((registers_R / registers_d) * cosangle.x) * cosangle.y)).xx;
    float _740 = registers_d * registers_d;
    float _741 = dot(_576, _576) + _740;
    float _762 = (registers_R * (dot(_576, sinangle) - ((registers_d * cosangle.x) * cosangle.y))) - _740;
    float2 _670 = (((((_762 * (-2.0f)) - sqrt((4.0f * (_762 * _762)) - ((4.0f * _741) * (_740 + ((((2.0f * registers_R) * registers_d) * cosangle.x) * cosangle.y))))) / (2.0f * _741)).xx * _576) - (_560.xx * sinangle)) / registers_R.xx;
    float2 _673 = _670 / cosangle;
    float2 _676 = sinangle / cosangle;
    float _680 = dot(_676, _676) + 1.0f;
    float _683 = dot(_673, _676);
    float _703 = ((_683 * 2.0f) + sqrt((4.0f * (_683 * _683)) - ((4.0f * _680) * (dot(_673, _673) - 1.0f)))) / (2.0f * _680);
    float _717 = max(abs(registers_R * acos(_703)), 9.9999997473787516355514526367188e-06f);
    float2 _727 = (((_670 - (sinangle * _703)) / cosangle) * _717) / sin(_717 / registers_R).xx;
    float2 _579 = 0.5f.xx * _106;
    float _581 = _579.x;
    float2 _585 = float2(-_581, _727.y);
    float _807 = max(abs(sqrt(dot(_585, _585))), 9.9999997473787516355514526367188e-06f);
    float _811 = _807 / registers_R;
    float2 _816 = _585 * (sin(_811) / _807);
    float _822 = 1.0f - cos(_811);
    float _827 = registers_d / registers_R;
    float _591 = _579.y;
    float2 _593 = float2(_727.x, -_591);
    float _863 = max(abs(sqrt(dot(_593, _593))), 9.9999997473787516355514526367188e-06f);
    float _867 = _863 / registers_R;
    float2 _872 = _593 * (sin(_867) / _863);
    float _878 = 1.0f - cos(_867);
    float2 _598 = float2(((((_816 * cosangle) - (sinangle * _822)) * registers_d) / ((_827 + ((_822 * cosangle.x) * cosangle.y)) + dot(_816, sinangle)).xx).x, ((((_872 * cosangle) - (sinangle * _878)) * registers_d) / ((_827 + ((_878 * cosangle.x) * cosangle.y)) + dot(_872, sinangle)).xx).y) / _106;
    float2 _603 = float2(_581, _727.y);
    float _919 = max(abs(sqrt(dot(_603, _603))), 9.9999997473787516355514526367188e-06f);
    float _923 = _919 / registers_R;
    float2 _928 = _603 * (sin(_923) / _919);
    float _934 = 1.0f - cos(_923);
    float2 _610 = float2(_727.x, _591);
    float _975 = max(abs(sqrt(dot(_610, _610))), 9.9999997473787516355514526367188e-06f);
    float _979 = _975 / registers_R;
    float2 _984 = _610 * (sin(_979) / _975);
    float _990 = 1.0f - cos(_979);
    float2 _615 = float2(((((_928 * cosangle) - (sinangle * _934)) * registers_d) / ((_827 + ((_934 * cosangle.x) * cosangle.y)) + dot(_928, sinangle)).xx).x, ((((_984 * cosangle) - (sinangle * _990)) * registers_d) / ((_827 + ((_990 * cosangle.x) * cosangle.y)) + dot(_984, sinangle)).xx).y) / _106;
    stretch = float3(((_615 + _598) * _106) * 0.5f, max(_615.x - _598.x, _615.y - _598.y));
    if (registers_vertical_scanlines < 0.5f)
    {
        TextureSize = float2(registers_SHARPER * _1023.x, _1022.x);
        ilfac = float2(1.0f, clamp(floor(_1022.x / ((registers_interlace_detect > 0.5f) ? 200.0f : 1000.0f)), 1.0f, 2.0f));
        one = ilfac / TextureSize;
        mod_factor = ((vTexCoord.x * _1023.x) * global_OutputSize.x) / _1023.x;
    }
    else
    {
        TextureSize = float2(_1023.x, registers_SHARPER * _1022.x);
        ilfac = float2(clamp(floor(_1023.x / ((registers_interlace_detect > 0.5f) ? 200.0f : 1000.0f)), 1.0f, 2.0f), 1.0f);
        one = ilfac / TextureSize;
        mod_factor = ((vTexCoord.y * _1022.x) * global_OutputSize.y) / _1022.x;
    }
}

SPIRV_Cross_Output main(SPIRV_Cross_Input stage_input)
{
    Position = stage_input.Position;
    TexCoord = stage_input.TexCoord;
    vert_main();
    SPIRV_Cross_Output stage_output;
    stage_output.gl_Position = gl_Position;
    stage_output.sinangle = sinangle;
    stage_output.cosangle = cosangle;
    stage_output.vTexCoord = vTexCoord;
    stage_output.stretch = stretch;
    stage_output.TextureSize = TextureSize;
    stage_output.ilfac = ilfac;
    stage_output.one = one;
    stage_output.mod_factor = mod_factor;
    return stage_output;
}
