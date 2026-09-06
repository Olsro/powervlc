// Generated from crt/shaders/geom-deluxe/crt-geom-deluxe.slang. See slang/upstream for licence/source.
cbuffer UBO : register(b0)
{
    float4 global_SourceSize : packoffset(c0);
    row_major float4x4 global_MVP : packoffset(c6);
};

cbuffer Push : register(b1)
{
    float params_aspect_x : packoffset(c1);
    float params_aspect_y : packoffset(c1.y);
    float params_d : packoffset(c1.z);
    float params_R : packoffset(c1.w);
    float params_angle_x : packoffset(c2);
    float params_angle_y : packoffset(c2.y);
    float params_interlace_detect : packoffset(c5.w);
};


static float4 gl_Position;
static float4 Position;
static float2 v_texCoord;
static float2 TexCoord;
static float2 v_sinangle;
static float2 v_cosangle;
static float3 v_stretch;
static float2 TextureSize;
static float2 ilfac;
static float2 v_one;

struct SPIRV_Cross_Input
{
    float4 Position : TEXCOORD0;
    float2 TexCoord : TEXCOORD1;
};

struct SPIRV_Cross_Output
{
    float2 v_texCoord : TEXCOORD0;
    float2 v_sinangle : TEXCOORD1;
    float2 v_cosangle : TEXCOORD2;
    float3 v_stretch : TEXCOORD3;
    float2 v_one : TEXCOORD4;
    float2 ilfac : TEXCOORD5;
    float2 TextureSize : TEXCOORD6;
    float4 gl_Position : SV_Position;
};

void vert_main()
{
    float2 _45 = float2(params_aspect_x, params_aspect_y);
    float2 _53 = float2(params_angle_x, params_angle_y);
    gl_Position = mul(Position, global_MVP);
    v_texCoord = TexCoord;
    v_sinangle = sin(_53);
    v_cosangle = cos(_53);
    float _503 = -params_R;
    float2 _519 = (v_sinangle * _503) / (1.0f + (((params_R / params_d) * v_cosangle.x) * v_cosangle.y)).xx;
    float _694 = params_d * params_d;
    float _695 = dot(_519, _519) + _694;
    float _716 = (params_R * (dot(_519, v_sinangle) - ((params_d * v_cosangle.x) * v_cosangle.y))) - _694;
    float2 _624 = (((((_716 * (-2.0f)) - sqrt((4.0f * (_716 * _716)) - ((4.0f * _695) * (_694 + ((((2.0f * params_R) * params_d) * v_cosangle.x) * v_cosangle.y))))) / (2.0f * _695)).xx * _519) - (_503.xx * v_sinangle)) / params_R.xx;
    float2 _627 = v_sinangle / v_cosangle;
    float2 _630 = _624 / v_cosangle;
    float _634 = dot(_627, _627) + 1.0f;
    float _637 = dot(_630, _627);
    float _657 = ((_637 * 2.0f) + sqrt((4.0f * (_637 * _637)) - ((4.0f * _634) * (dot(_630, _630) - 1.0f)))) / (2.0f * _634);
    float _671 = max(abs(params_R * acos(_657)), 9.9999997473787516355514526367188e-06f);
    float2 _681 = (((_624 - (v_sinangle * _657)) / v_cosangle) * _671) / sin(_671 / params_R).xx;
    float2 _524 = 0.5f.xx * _45;
    float _526 = _524.x;
    float _529 = _681.y;
    float2 _530 = float2(-_526, _529);
    float _761 = max(abs(sqrt(dot(_530, _530))), 9.9999997473787516355514526367188e-06f);
    float _765 = _761 / params_R;
    float2 _770 = _530 * (sin(_765) / _761);
    float _776 = 1.0f - cos(_765);
    float _781 = params_d / params_R;
    float _536 = _681.x;
    float _538 = _524.y;
    float2 _540 = float2(_536, -_538);
    float _817 = max(abs(sqrt(dot(_540, _540))), 9.9999997473787516355514526367188e-06f);
    float _821 = _817 / params_R;
    float2 _826 = _540 * (sin(_821) / _817);
    float _832 = 1.0f - cos(_821);
    float2 _547 = float2(((((_770 * v_cosangle) - (v_sinangle * _776)) * params_d) / ((_781 + ((_776 * v_cosangle.x) * v_cosangle.y)) + dot(_770, v_sinangle)).xx).x, ((((_826 * v_cosangle) - (v_sinangle * _832)) * params_d) / ((_781 + ((_832 * v_cosangle.x) * v_cosangle.y)) + dot(_826, v_sinangle)).xx).y) / _45;
    float2 _552 = float2(_526, _529);
    float _873 = max(abs(sqrt(dot(_552, _552))), 9.9999997473787516355514526367188e-06f);
    float _877 = _873 / params_R;
    float2 _882 = _552 * (sin(_877) / _873);
    float _888 = 1.0f - cos(_877);
    float2 _561 = float2(_536, _538);
    float _929 = max(abs(sqrt(dot(_561, _561))), 9.9999997473787516355514526367188e-06f);
    float _933 = _929 / params_R;
    float2 _938 = _561 * (sin(_933) / _929);
    float _944 = 1.0f - cos(_933);
    float2 _568 = float2(((((_882 * v_cosangle) - (v_sinangle * _888)) * params_d) / ((_781 + ((_888 * v_cosangle.x) * v_cosangle.y)) + dot(_882, v_sinangle)).xx).x, ((((_938 * v_cosangle) - (v_sinangle * _944)) * params_d) / ((_781 + ((_944 * v_cosangle.x) * v_cosangle.y)) + dot(_938, v_sinangle)).xx).y) / _45;
    v_stretch = float3(((_568 + _547) * _45) * 0.5f, max(_568.x - _547.x, _568.y - _547.y));
    TextureSize = global_SourceSize.xy;
    ilfac = float2(1.0f, clamp(floor(global_SourceSize.y / ((params_interlace_detect == 1.0f) ? 200.0f : 1000.0f)), 1.0f, 2.0f));
    v_one = ilfac / TextureSize;
}

SPIRV_Cross_Output main(SPIRV_Cross_Input stage_input)
{
    Position = stage_input.Position;
    TexCoord = stage_input.TexCoord;
    vert_main();
    SPIRV_Cross_Output stage_output;
    stage_output.gl_Position = gl_Position;
    stage_output.v_texCoord = v_texCoord;
    stage_output.v_sinangle = v_sinangle;
    stage_output.v_cosangle = v_cosangle;
    stage_output.v_stretch = v_stretch;
    stage_output.TextureSize = TextureSize;
    stage_output.ilfac = ilfac;
    stage_output.v_one = v_one;
    return stage_output;
}
