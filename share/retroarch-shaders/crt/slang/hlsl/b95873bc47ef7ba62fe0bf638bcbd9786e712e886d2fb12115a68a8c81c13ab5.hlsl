// Generated from interpolation/shaders/EWA-Cubics.slang. See slang/upstream for licence/source.
cbuffer Push : register(b1)
{
    float4 params_SourceSize : packoffset(c0);
    float params_CubicMode : packoffset(c3.y);
};

Texture2D<float4> Source : register(t2);
SamplerState _Source_sampler : register(s2);

static float2 vTexCoord;
static float4 FragColor;

struct SPIRV_Cross_Input
{
    float2 vTexCoord : TEXCOORD0;
};

struct SPIRV_Cross_Output
{
    float4 FragColor : SV_Target0;
};

void frag_main()
{
    float _384;
    if (params_CubicMode < 0.5f)
    {
        _384 = 0.3782157599925994873046875f;
    }
    else
    {
        _384 = (params_CubicMode < 1.5f) ? 0.3333333432674407958984375f : 0.26201450824737548828125f;
    }
    float _293 = 1.0f - _384;
    float2 _175 = vTexCoord * params_SourceSize.xy;
    float2 _181 = floor(_175 - 0.5f.xx) + 0.5f.xx;
    float _387;
    float3 _388;
    _388 = 0.0f.xxx;
    _387 = 0.0f;
    float3 _403;
    float _405;
    for (int _386 = -1; _386 <= 2; _388 = _403, _387 = _405, _386++)
    {
        _405 = _387;
        _403 = _388;
        float3 _418;
        float _419;
        for (int _390 = -1; _390 <= 2; _405 = _419, _403 = _418, _390++)
        {
            float2 _212 = _181 + float2(float(_390), float(_386));
            float _219 = length(_175 - _212);
            if (_219 >= 2.0f)
            {
                _419 = _405;
                _418 = _403;
                continue;
            }
            float _400;
            do
            {
                float _304 = abs(_219);
                float _307 = _304 * _304;
                float _310 = _307 * _304;
                if (_304 < 1.0f)
                {
                    float _318 = _293 * 3.0f;
                    _400 = (((((12.0f - (9.0f * _384)) - _318) * _310) + ((((-18.0f) + (12.0f * _384)) + _318) * _307)) + (6.0f - (2.0f * _384))) * 0.16666667163372039794921875f;
                    break;
                }
                else
                {
                    if (_304 < 2.0f)
                    {
                        _400 = ((((((-_384) - (_293 * 3.0f)) * _310) + (((6.0f * _384) + (_293 * 15.0f)) * _307)) + ((((-12.0f) * _384) - (_293 * 24.0f)) * _304)) + ((8.0f * _384) + (_293 * 12.0f))) * 0.16666667163372039794921875f;
                        break;
                    }
                }
                _400 = 0.0f;
                break;
            } while(false);
            if (_400 == 0.0f)
            {
                _419 = _405;
                _418 = _403;
                continue;
            }
            _419 = _405 + _400;
            _418 = _403 + (Source.Sample(_Source_sampler, _212 * params_SourceSize.zw).xyz * _400);
        }
    }
    float3 _389;
    if (_387 > 0.0f)
    {
        _389 = _388 / _387.xxx;
    }
    else
    {
        _389 = _388;
    }
    FragColor = float4(_389, 1.0f);
}

SPIRV_Cross_Output main(SPIRV_Cross_Input stage_input)
{
    vTexCoord = stage_input.vTexCoord;
    frag_main();
    SPIRV_Cross_Output stage_output;
    stage_output.FragColor = FragColor;
    return stage_output;
}
