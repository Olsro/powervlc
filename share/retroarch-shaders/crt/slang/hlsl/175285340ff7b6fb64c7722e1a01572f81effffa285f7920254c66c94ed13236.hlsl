// Generated from crt/shaders/crt-pi.slang. See slang/upstream for licence/source.
cbuffer UBO : register(b0)
{
    float4 global_OutputSize : packoffset(c4);
    float4 global_SourceSize : packoffset(c6);
};

cbuffer Push : register(b1)
{
    float param_CURVATURE_X : packoffset(c0);
    float param_CURVATURE_Y : packoffset(c0.y);
    float param_MASK_BRIGHTNESS : packoffset(c0.z);
    float param_SCANLINE_WEIGHT : packoffset(c0.w);
    float param_SCANLINE_GAP_BRIGHTNESS : packoffset(c1);
    float param_BLOOM_FACTOR : packoffset(c1.y);
};

Texture2D<float4> Source : register(t2);
SamplerState _Source_sampler : register(s2);

static float filterWidth;
static float2 vTexCoord;
static float4 FragColor;

struct SPIRV_Cross_Input
{
    float2 vTexCoord : TEXCOORD0;
    float filterWidth : TEXCOORD1;
};

struct SPIRV_Cross_Output
{
    float4 FragColor : SV_Target0;
};

void frag_main()
{
    do
    {
        float2 _34 = float2(param_CURVATURE_X, param_CURVATURE_Y);
        float2 _275 = vTexCoord - 0.5f.xx;
        float _277 = _275.x;
        float _282 = _275.y;
        float2 _296 = (_275 + (_275 * (_34 * ((_277 * _277) + (_282 * _282))))) * (1.0f.xx - (_34 * 0.23000000417232513427734375f));
        bool _300 = abs(_296.x) >= 0.5f;
        bool _308;
        if (!_300)
        {
            _308 = abs(_296.y) >= 0.5f;
        }
        else
        {
            _308 = _300;
        }
        float2 _399;
        if (_308)
        {
            _399 = (-1.0f).xx;
        }
        else
        {
            _399 = _296 + 0.5f.xx;
        }
        if (_399.x < 0.0f)
        {
            FragColor = 0.0f.xxxx;
            break;
        }
        float2 _162 = _399 * global_SourceSize.xy;
        float _165 = _162.y;
        float _167 = floor(_165) + 0.5f;
        float _179 = _165 - _167;
        float _325 = _179 - filterWidth;
        float _331 = _179 + filterWidth;
        float _188 = abs(_179);
        float4 _219 = Source.Sample(_Source_sampler, float2(_399.x, (_167 * global_SourceSize.w) + ((8.0f * ((_188 * _188) * _188)) * ((0.5f * global_SourceSize.w) * sign(_179)))));
        float _236 = frac((vTexCoord.x * global_OutputSize.x) * 0.333333313465118408203125f);
        float3 _241 = param_MASK_BRIGHTNESS.xxx;
        float3 _400;
        if (_236 < 0.333333313465118408203125f)
        {
            float3 _392 = _241;
            _392.x = 1.0f;
            _400 = _392;
        }
        else
        {
            float3 _401;
            if (_236 < 0.66666662693023681640625f)
            {
                float3 _394 = _241;
                _394.y = 1.0f;
                _401 = _394;
            }
            else
            {
                float3 _396 = _241;
                _396.z = 1.0f;
                _401 = _396;
            }
            _400 = _401;
        }
        FragColor = float4((_219.xyz * ((((max(1.0f - ((_179 * _179) * param_SCANLINE_WEIGHT), param_SCANLINE_GAP_BRIGHTNESS) + max(1.0f - ((_325 * _325) * param_SCANLINE_WEIGHT), param_SCANLINE_GAP_BRIGHTNESS)) + max(1.0f - ((_331 * _331) * param_SCANLINE_WEIGHT), param_SCANLINE_GAP_BRIGHTNESS)) * 0.333333313465118408203125f) * param_BLOOM_FACTOR)) * _400, 1.0f);
        break;
    } while(false);
}

SPIRV_Cross_Output main(SPIRV_Cross_Input stage_input)
{
    filterWidth = stage_input.filterWidth;
    vTexCoord = stage_input.vTexCoord;
    frag_main();
    SPIRV_Cross_Output stage_output;
    stage_output.FragColor = FragColor;
    return stage_output;
}
