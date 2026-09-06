// Generated from crt/shaders/crt-royale/src/crt-royale-mask-resize-horizontal.slang. See slang/upstream for licence/source.
static float _852;

cbuffer UBO : register(b0)
{
    float global_mask_sample_mode_desired : packoffset(c9.w);
};

cbuffer Push : register(b1)
{
    float4 params_SourceSize : packoffset(c0);
};

Texture2D<float4> Source : register(t2);
SamplerState _Source_sampler : register(s2);

static float2 tile_uv_wrap;
static float2 src_dxdy;
static float2 src_tex_uv_wrap;
static float2 resize_magnification_scale;
static float2 tile_size_uv;
static float4 FragColor;

struct SPIRV_Cross_Input
{
    float2 src_tex_uv_wrap : TEXCOORD0;
    float2 tile_uv_wrap : TEXCOORD1;
    float2 resize_magnification_scale : TEXCOORD2;
    float2 src_dxdy : TEXCOORD3;
    float2 tile_size_uv : TEXCOORD4;
};

struct SPIRV_Cross_Output
{
    float4 FragColor : SV_Target0;
};

void frag_main()
{
    bool _495 = global_mask_sample_mode_desired < 0.5f;
    bool _505;
    if (_495)
    {
        _505 = max(tile_uv_wrap.x, tile_uv_wrap.y) <= 2.0f;
    }
    else
    {
        _505 = _495;
    }
    if (_505)
    {
        float2 _516 = frac(src_tex_uv_wrap);
        int _592 = int(ceil(96.0f / ceil(16.0f)) * 4.0f);
        float _594 = 1.0f / tile_size_uv.x;
        float2 _740 = _516 * params_SourceSize.xy;
        float2 _752 = (floor(_740 - 0.4995000064373016357421875f.xx) + 0.5f.xx) - ((float(_592) * 0.5f) - 1.0f).xx;
        float2 _761 = (_752 * src_dxdy.x) * _594;
        float2 _779 = float2((frac(_761) + float2(float(_761.x < 0.0f), _852)).x, (_740 - _752).x);
        float4 _603 = _779.xxxx;
        float4 _605 = _779.yyyy;
        float _608 = src_dxdy.x * _594;
        float4 _814;
        float3 _815;
        _815 = 0.0f.xxx;
        _814 = 0.0f.xxxx;
        for (int _812 = 0; _812 < _592; )
        {
            float4 _620 = float(_812).xxxx + float4(0.0f, 1.0f, 2.0f, 3.0f);
            float4 _629 = frac(_603 + (_620 * _608)) * tile_size_uv.x;
            float _633 = _516.y;
            float4 _663 = abs(_605 - _620) * resize_magnification_scale.x;
            float4 _666 = _663 * 3.1415927410125732421875f;
            float4 _669 = _663 * 1.0471975803375244140625f;
            float4 _679 = min((sin(_666) * sin(_669)) / (_666 * _669), 1.0f.xxxx);
            _815 = (((_815 + (Source.Sample(_Source_sampler, float2(_629.x, _633)).xyz * _679.xxx)) + (Source.Sample(_Source_sampler, float2(_629.y, _633)).xyz * _679.yyy)) + (Source.Sample(_Source_sampler, float2(_629.z, _633)).xyz * _679.zzz)) + (Source.Sample(_Source_sampler, float2(_629.w, _633)).xyz * _679.www);
            _814 += _679;
            _812 += 4;
            continue;
        }
        float2 _716 = _814.xy + _814.zw;
        FragColor = float4(_815 / (_716.x + _716.y).xxx, 1.0f);
    }
    else
    {
        discard;
    }
}

SPIRV_Cross_Output main(SPIRV_Cross_Input stage_input)
{
    tile_uv_wrap = stage_input.tile_uv_wrap;
    src_dxdy = stage_input.src_dxdy;
    src_tex_uv_wrap = stage_input.src_tex_uv_wrap;
    resize_magnification_scale = stage_input.resize_magnification_scale;
    tile_size_uv = stage_input.tile_size_uv;
    frag_main();
    SPIRV_Cross_Output stage_output;
    stage_output.FragColor = FragColor;
    return stage_output;
}
