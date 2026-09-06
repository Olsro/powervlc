// Generated from crt/shaders/crt-royale/src-fast/crt-royale-mask-resize-horizontal.slang. See slang/upstream for licence/source.
static float _829;

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
    if (max(tile_uv_wrap.x, tile_uv_wrap.y) <= (1.0f + (ceil(0.5f) * 0.125f)))
    {
        float2 _502 = frac(src_tex_uv_wrap);
        int _574 = int(ceil(96.0f / ceil(16.0f)) * 4.0f);
        float _576 = 1.0f / tile_size_uv.x;
        float2 _722 = _502 * params_SourceSize.xy;
        float2 _734 = (floor(_722 - 0.4995000064373016357421875f.xx) + 0.5f.xx) - ((float(_574) * 0.5f) - 1.0f).xx;
        float2 _743 = (_734 * src_dxdy.x) * _576;
        float2 _761 = float2((frac(_743) + float2(float(_743.x < 0.0f), _829)).x, (_722 - _734).x);
        float4 _585 = _761.xxxx;
        float4 _587 = _761.yyyy;
        float _590 = src_dxdy.x * _576;
        float4 _794;
        float3 _795;
        _795 = 0.0f.xxx;
        _794 = 0.0f.xxxx;
        for (int _792 = 0; _792 < _574; )
        {
            float4 _602 = float(_792).xxxx + float4(0.0f, 1.0f, 2.0f, 3.0f);
            float4 _611 = frac(_585 + (_602 * _590)) * tile_size_uv.x;
            float _615 = _502.y;
            float4 _645 = abs(_587 - _602) * resize_magnification_scale.x;
            float4 _648 = _645 * 3.1415927410125732421875f;
            float4 _651 = _645 * 1.0471975803375244140625f;
            float4 _661 = min((sin(_648) * sin(_651)) / (_648 * _651), 1.0f.xxxx);
            _795 = (((_795 + (Source.Sample(_Source_sampler, float2(_611.x, _615)).xyz * _661.xxx)) + (Source.Sample(_Source_sampler, float2(_611.y, _615)).xyz * _661.yyy)) + (Source.Sample(_Source_sampler, float2(_611.z, _615)).xyz * _661.zzz)) + (Source.Sample(_Source_sampler, float2(_611.w, _615)).xyz * _661.www);
            _794 += _661;
            _792 += 4;
            continue;
        }
        float2 _698 = _794.xy + _794.zw;
        FragColor = float4(_795 / (_698.x + _698.y).xxx, 1.0f);
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
