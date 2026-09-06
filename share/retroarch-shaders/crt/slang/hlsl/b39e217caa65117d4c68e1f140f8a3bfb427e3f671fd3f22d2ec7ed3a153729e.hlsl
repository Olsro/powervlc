// Generated from crt/shaders/glow/lanczos_horiz.slang. See slang/upstream for licence/source.
cbuffer UBO : register(b0)
{
    float4 global_SourceSize : packoffset(c6);
};

Texture2D<float4> Source : register(t2);
SamplerState _Source_sampler : register(s2);

static float data_pix_no;
static float2 vTexCoord;
static float data_one;
static float4 FragColor;

struct SPIRV_Cross_Input
{
    float2 vTexCoord : TEXCOORD0;
    float data_pix_no : TEXCOORD1;
    float data_one : TEXCOORD2;
};

struct SPIRV_Cross_Output
{
    float4 FragColor : SV_Target0;
};

void frag_main()
{
    float _34 = floor(data_pix_no);
    float _42 = (data_pix_no - _34) - 0.5f;
    float2 _66 = float2((_34 + 0.5f) * global_SourceSize.z, vTexCoord.y);
    float3 _179;
    _179 = 0.0f.xxx;
    float3 _192;
    for (int _178 = -2; _178 <= 2; _179 = _192, _178++)
    {
        float _86 = float(_178);
        float _87 = _42 - _86;
        float _89 = abs(_87);
        if (_89 < 2.0f)
        {
            float _181;
            do
            {
                if (_89 < 0.001000000047497451305389404296875f)
                {
                    _181 = 1.0f;
                    break;
                }
                float _153 = _87 * 3.1415927410125732421875f;
                _181 = sin(_153) / _153;
                break;
            } while(false);
            float _183;
            do
            {
                if (abs(0.5f * _87) < 0.001000000047497451305389404296875f)
                {
                    _183 = 1.0f;
                    break;
                }
                float _171 = _87 * 1.57079637050628662109375f;
                _183 = sin(_171) / _171;
                break;
            } while(false);
            _192 = _179 + (Source.Sample(_Source_sampler, _66 + float2(_86 * data_one, 0.0f)).xyz * (_181 * _183));
        }
        else
        {
            _192 = _179;
        }
    }
    FragColor = float4(_179, 1.0f);
}

SPIRV_Cross_Output main(SPIRV_Cross_Input stage_input)
{
    data_pix_no = stage_input.data_pix_no;
    vTexCoord = stage_input.vTexCoord;
    data_one = stage_input.data_one;
    frag_main();
    SPIRV_Cross_Output stage_output;
    stage_output.FragColor = FragColor;
    return stage_output;
}
