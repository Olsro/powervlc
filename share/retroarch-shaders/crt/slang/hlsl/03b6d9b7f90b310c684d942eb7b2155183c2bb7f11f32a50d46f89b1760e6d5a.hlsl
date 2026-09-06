// Generated from crt/shaders/CreativeForce/crt-CreativeForce-SharpSmooth.slang. See slang/upstream for licence/source.
cbuffer Push : register(b1)
{
    float4 pc_OriginalSize : packoffset(c1);
    float4 pc_OutputSize : packoffset(c2);
    float pc_GBA_MODE_GAMMA : packoffset(c3.y);
    float pc_V_BLACKS_PER : packoffset(c3.z);
    float pc_V_STRENGTH : packoffset(c3.w);
    float pc_V_PHASE : packoffset(c4);
    float pc_AUTO_PHASE : packoffset(c4.y);
};

Texture2D<float4> Source : register(t2);
SamplerState _Source_sampler : register(s2);

static float4 gl_FragCoord;
static float2 vTexCoord;
static float4 FragColor;

struct SPIRV_Cross_Input
{
    float2 vTexCoord : TEXCOORD0;
    float4 gl_FragCoord : SV_Position;
};

struct SPIRV_Cross_Output
{
    float4 FragColor : SV_Target0;
};

void frag_main()
{
    float4 _119 = Source.Sample(_Source_sampler, vTexCoord);
    int _135 = clamp(int(floor(pc_V_BLACKS_PER + 0.5f)), 0, 17);
    int _138 = _135 + 1;
    int _161 = int(floor(pc_V_PHASE + 0.5f));
    int _346;
    if (pc_AUTO_PHASE >= 0.5f)
    {
        int _280 = int(floor((pc_OutputSize.x / pc_OriginalSize.x) + 9.9999999747524270787835121154785e-07f));
        int _347;
        if ((_135 > 0) && (_138 > 0))
        {
            int _207 = ((int(pc_OutputSize.x) - (int(pc_OriginalSize.x) * ((_280 < 1) ? 1 : _280))) / 2) % _138;
            int _340;
            if (_207 < 0)
            {
                _340 = _207 + _138;
            }
            else
            {
                _340 = _207;
            }
            _347 = _161 + (1 - _340);
        }
        else
        {
            _347 = _161;
        }
        _346 = _347;
    }
    else
    {
        _346 = _161;
    }
    float _382;
    if (_135 > 0)
    {
        int _387 = (_138 < 1) ? 1 : _138;
        int _388 = (_135 < 0) ? 0 : _135;
        int _311 = (int(floor(gl_FragCoord.x - 0.5f)) + int(floor(float(_346) + 0.5f))) % _387;
        int _362;
        if (_311 < 0)
        {
            _362 = _311 + _387;
        }
        else
        {
            _362 = _311;
        }
        _382 = lerp(1.0f, 1.0f - clamp(pc_V_STRENGTH, 0.0f, 1.0f), float(_362 < ((_388 > _387) ? _387 : _388)));
    }
    else
    {
        _382 = 1.0f;
    }
    FragColor = float4(pow(max(pow(max(_119.xyz, 0.0f.xxx), ((pc_GBA_MODE_GAMMA >= 0.5f) ? 2.7000000476837158203125f : 2.2000000476837158203125f).xxx) * _382.xxx, 0.0f.xxx), 0.454545438289642333984375f.xxx), 1.0f);
}

SPIRV_Cross_Output main(SPIRV_Cross_Input stage_input)
{
    gl_FragCoord = stage_input.gl_FragCoord;
    gl_FragCoord.w = 1.0 / gl_FragCoord.w;
    vTexCoord = stage_input.vTexCoord;
    frag_main();
    SPIRV_Cross_Output stage_output;
    stage_output.FragColor = FragColor;
    return stage_output;
}
