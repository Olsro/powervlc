// Generated from crt/shaders/crt-consumer/reflect_blur.slang. See slang/upstream for licence/source.
Texture2D<float4> Source : register(t2);
SamplerState _Source_sampler : register(s2);

static float2 vTexCoord;
static float2 pix;
static float4 FragColor;

struct SPIRV_Cross_Input
{
    float2 vTexCoord : TEXCOORD0;
    float2 pix : TEXCOORD2;
};

struct SPIRV_Cross_Output
{
    float4 FragColor : SV_Target0;
};

float mod(float x, float y)
{
    return x - y * floor(x / y);
}

float2 mod(float2 x, float2 y)
{
    return x - y * floor(x / y);
}

float3 mod(float3 x, float3 y)
{
    return x - y * floor(x / y);
}

float4 mod(float4 x, float4 y)
{
    return x - y * floor(x / y);
}

void frag_main()
{
    float2 _307 = (vTexCoord * 2.0f) - 1.0f.xx;
    float _309 = _307.y;
    float _316 = _307.x;
    float2 _328 = ((_307 * float2(1.0f + ((_309 * _309) * (-0.02999999932944774627685546875f)), 1.0f + ((_316 * _316) * 0.02999999932944774627685546875f))) * 0.5f) + 0.5f.xx;
    float _167 = _328.x;
    float _169 = (_167 * 2.0f) - 1.0f;
    float _172 = _169 * _169;
    float _175 = _328.y;
    float _177 = (_175 * 2.0f) - 1.0f;
    float _180 = _177 * _177;
    float _183 = lerp(0.0f, 0.0199999995529651641845703125f, _172);
    float _186 = lerp(0.0f, 0.0199999995529651641845703125f, _180);
    float _191 = lerp(1.0f, 0.980000019073486328125f, _172);
    float _194 = lerp(1.0f, 0.980000019073486328125f, _180);
    float2 _201 = float2(pix.x, 0.0f);
    float2 _205 = float2(0.0f, pix.y);
    float _501;
    do
    {
        float _367 = _191 - _183;
        if (_167 < _183)
        {
            float _378 = mod(_183 - _167, _367 * 2.0f);
            float _500;
            if (_378 <= _367)
            {
                _500 = _183 + _378;
            }
            else
            {
                _500 = _191 - (_378 - _367);
            }
            _501 = _500;
            break;
        }
        else
        {
            if (_167 > _191)
            {
                float _405 = mod(_167 - _191, _367 * 2.0f);
                float _499;
                if (_405 <= _367)
                {
                    _499 = _191 - _405;
                }
                else
                {
                    _499 = _183 + (_405 - _367);
                }
                _501 = _499;
                break;
            }
        }
        _501 = _167;
        break;
    } while(false);
    float _504;
    do
    {
        float _440 = _194 - _186;
        if (_175 < _186)
        {
            float _451 = mod(_186 - _175, _440 * 2.0f);
            float _503;
            if (_451 <= _440)
            {
                _503 = _186 + _451;
            }
            else
            {
                _503 = _194 - (_451 - _440);
            }
            _504 = _503;
            break;
        }
        else
        {
            if (_175 > _194)
            {
                float _478 = mod(_175 - _194, _440 * 2.0f);
                float _502;
                if (_478 <= _440)
                {
                    _502 = _194 - _478;
                }
                else
                {
                    _502 = _186 + (_478 - _440);
                }
                _504 = _502;
                break;
            }
        }
        _504 = _175;
        break;
    } while(false);
    float2 _352 = float2(_501, _504);
    int _505;
    float _506;
    float4 _513;
    _513 = 0.0f.xxxx;
    _506 = 0.0f;
    _505 = -2;
    float4 _540;
    float _541;
    for (; _505 < 3; _513 = _540, _506 = _541, _505++)
    {
        _541 = _506;
        _540 = _513;
        for (int _520 = -2; _520 < 3; )
        {
            float _241 = float(_505);
            float _248 = exp(((-0.100000001490116119384765625f) * _241) * _241);
            _541 += _248;
            _540 += (Source.Sample(_Source_sampler, (_352 + (_201 * _241)) + (_205 * float(_520))) * _248);
            _520++;
            continue;
        }
    }
    FragColor = (_513 / _506.xxxx) * 1.25f;
}

SPIRV_Cross_Output main(SPIRV_Cross_Input stage_input)
{
    vTexCoord = stage_input.vTexCoord;
    pix = stage_input.pix;
    frag_main();
    SPIRV_Cross_Output stage_output;
    stage_output.FragColor = FragColor;
    return stage_output;
}
