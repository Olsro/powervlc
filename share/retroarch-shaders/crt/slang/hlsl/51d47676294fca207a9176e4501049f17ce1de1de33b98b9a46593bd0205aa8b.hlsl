// Generated from crt/shaders/crt-royale/src-fast/crt-royale-mask-resize-vertical.slang. See slang/upstream for licence/source.
static float _1422;

cbuffer UBO : register(b0)
{
    float global_mask_type : packoffset(c9);
};

Texture2D<float4> mask_grille_texture_small : register(t3);
SamplerState _mask_grille_texture_small_sampler : register(s3);
Texture2D<float4> mask_slot_texture_small : register(t4);
SamplerState _mask_slot_texture_small_sampler : register(s4);
Texture2D<float4> mask_shadow_texture_small : register(t5);
SamplerState _mask_shadow_texture_small_sampler : register(s5);

static float2 src_tex_uv_wrap;
static float2 resize_magnification_scale;
static float4 FragColor;

struct SPIRV_Cross_Input
{
    float2 src_tex_uv_wrap : TEXCOORD0;
    float2 resize_magnification_scale : TEXCOORD1;
};

struct SPIRV_Cross_Output
{
    float4 FragColor : SV_Target0;
};

void frag_main()
{
    float _226 = ceil(96.0f / ceil(16.0f)) * 4.0f;
    if (src_tex_uv_wrap.y <= (1.0f + (ceil(0.5f) * 0.125f)))
    {
        float2 _497 = frac(src_tex_uv_wrap);
        float3 _1359;
        if (global_mask_type < 0.5f)
        {
            int _601 = int(_226);
            float2 _749 = _497 * 64.0f.xx;
            float2 _761 = (floor(_749 - 0.4995000064373016357421875f.xx) + 0.5f.xx) - ((float(_601) * 0.5f) - 1.0f).xx;
            float2 _770 = (_761 * 0.015625f) * 1.0f;
            float2 _793 = float2((frac(_770) + float2(_1422, float(_770.y < 0.0f))).y, (_749 - _761).y);
            float4 _612 = _793.xxxx;
            float4 _614 = _793.yyyy;
            float4 _1357;
            float3 _1358;
            _1358 = 0.0f.xxx;
            _1357 = 0.0f.xxxx;
            for (int _1355 = 0; _1355 < _601; )
            {
                float4 _629 = float(_1355).xxxx + float4(0.0f, 1.0f, 2.0f, 3.0f);
                float4 _638 = frac(_612 + (_629 * 0.015625f)) * 1.0f;
                float _640 = _497.x;
                float4 _672 = abs(_614 - _629) * resize_magnification_scale.y;
                float4 _675 = _672 * 3.1415927410125732421875f;
                float4 _678 = _672 * 1.0471975803375244140625f;
                float4 _688 = min((sin(_675) * sin(_678)) / (_675 * _678), 1.0f.xxxx);
                _1358 = (((_1358 + (mask_grille_texture_small.Sample(_mask_grille_texture_small_sampler, float2(_640, _638.x)).xyz * _688.xxx)) + (mask_grille_texture_small.Sample(_mask_grille_texture_small_sampler, float2(_640, _638.y)).xyz * _688.yyy)) + (mask_grille_texture_small.Sample(_mask_grille_texture_small_sampler, float2(_640, _638.z)).xyz * _688.zzz)) + (mask_grille_texture_small.Sample(_mask_grille_texture_small_sampler, float2(_640, _638.w)).xyz * _688.www);
                _1357 += _688;
                _1355 += 4;
                continue;
            }
            float2 _725 = _1357.xy + _1357.zw;
            _1359 = _1358 / (_725.x + _725.y).xxx;
        }
        else
        {
            float3 _1360;
            if (global_mask_type < 1.5f)
            {
                int _856 = int(_226);
                float2 _1004 = _497 * 64.0f.xx;
                float2 _1016 = (floor(_1004 - 0.4995000064373016357421875f.xx) + 0.5f.xx) - ((float(_856) * 0.5f) - 1.0f).xx;
                float2 _1025 = (_1016 * 0.015625f) * 1.0f;
                float2 _1048 = float2((frac(_1025) + float2(_1422, float(_1025.y < 0.0f))).y, (_1004 - _1016).y);
                float4 _867 = _1048.xxxx;
                float4 _869 = _1048.yyyy;
                float4 _1344;
                float3 _1345;
                _1345 = 0.0f.xxx;
                _1344 = 0.0f.xxxx;
                for (int _1342 = 0; _1342 < _856; )
                {
                    float4 _884 = float(_1342).xxxx + float4(0.0f, 1.0f, 2.0f, 3.0f);
                    float4 _893 = frac(_867 + (_884 * 0.015625f)) * 1.0f;
                    float _895 = _497.x;
                    float4 _927 = abs(_869 - _884) * resize_magnification_scale.y;
                    float4 _930 = _927 * 3.1415927410125732421875f;
                    float4 _933 = _927 * 1.0471975803375244140625f;
                    float4 _943 = min((sin(_930) * sin(_933)) / (_930 * _933), 1.0f.xxxx);
                    _1345 = (((_1345 + (mask_slot_texture_small.Sample(_mask_slot_texture_small_sampler, float2(_895, _893.x)).xyz * _943.xxx)) + (mask_slot_texture_small.Sample(_mask_slot_texture_small_sampler, float2(_895, _893.y)).xyz * _943.yyy)) + (mask_slot_texture_small.Sample(_mask_slot_texture_small_sampler, float2(_895, _893.z)).xyz * _943.zzz)) + (mask_slot_texture_small.Sample(_mask_slot_texture_small_sampler, float2(_895, _893.w)).xyz * _943.www);
                    _1344 += _943;
                    _1342 += 4;
                    continue;
                }
                float2 _980 = _1344.xy + _1344.zw;
                _1360 = _1345 / (_980.x + _980.y).xxx;
            }
            else
            {
                int _1111 = int(_226);
                float2 _1259 = _497 * 64.0f.xx;
                float2 _1271 = (floor(_1259 - 0.4995000064373016357421875f.xx) + 0.5f.xx) - ((float(_1111) * 0.5f) - 1.0f).xx;
                float2 _1280 = (_1271 * 0.015625f) * 1.0f;
                float2 _1303 = float2((frac(_1280) + float2(_1422, float(_1280.y < 0.0f))).y, (_1259 - _1271).y);
                float4 _1122 = _1303.xxxx;
                float4 _1124 = _1303.yyyy;
                float4 _1331;
                float3 _1332;
                _1332 = 0.0f.xxx;
                _1331 = 0.0f.xxxx;
                for (int _1329 = 0; _1329 < _1111; )
                {
                    float4 _1139 = float(_1329).xxxx + float4(0.0f, 1.0f, 2.0f, 3.0f);
                    float4 _1148 = frac(_1122 + (_1139 * 0.015625f)) * 1.0f;
                    float _1150 = _497.x;
                    float4 _1182 = abs(_1124 - _1139) * resize_magnification_scale.y;
                    float4 _1185 = _1182 * 3.1415927410125732421875f;
                    float4 _1188 = _1182 * 1.0471975803375244140625f;
                    float4 _1198 = min((sin(_1185) * sin(_1188)) / (_1185 * _1188), 1.0f.xxxx);
                    _1332 = (((_1332 + (mask_shadow_texture_small.Sample(_mask_shadow_texture_small_sampler, float2(_1150, _1148.x)).xyz * _1198.xxx)) + (mask_shadow_texture_small.Sample(_mask_shadow_texture_small_sampler, float2(_1150, _1148.y)).xyz * _1198.yyy)) + (mask_shadow_texture_small.Sample(_mask_shadow_texture_small_sampler, float2(_1150, _1148.z)).xyz * _1198.zzz)) + (mask_shadow_texture_small.Sample(_mask_shadow_texture_small_sampler, float2(_1150, _1148.w)).xyz * _1198.www);
                    _1331 += _1198;
                    _1329 += 4;
                    continue;
                }
                float2 _1235 = _1331.xy + _1331.zw;
                _1360 = _1332 / (_1235.x + _1235.y).xxx;
            }
            _1359 = _1360;
        }
        FragColor = float4(_1359, 1.0f);
    }
    else
    {
        discard;
    }
}

SPIRV_Cross_Output main(SPIRV_Cross_Input stage_input)
{
    src_tex_uv_wrap = stage_input.src_tex_uv_wrap;
    resize_magnification_scale = stage_input.resize_magnification_scale;
    frag_main();
    SPIRV_Cross_Output stage_output;
    stage_output.FragColor = FragColor;
    return stage_output;
}
