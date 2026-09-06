// Generated from crt/shaders/crt-royale/src/crt-royale-mask-resize-vertical.slang. See slang/upstream for licence/source.
static float _1445;

cbuffer UBO : register(b0)
{
    float global_mask_type : packoffset(c9.z);
    float global_mask_sample_mode_desired : packoffset(c9.w);
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
    float _230 = ceil(96.0f / ceil(16.0f)) * 4.0f;
    bool _495 = global_mask_sample_mode_desired < 0.5f;
    bool _502;
    if (_495)
    {
        _502 = src_tex_uv_wrap.y <= 2.0f;
    }
    else
    {
        _502 = _495;
    }
    if (_502)
    {
        float2 _511 = frac(src_tex_uv_wrap);
        float3 _1381;
        if (global_mask_type < 0.5f)
        {
            int _619 = int(_230);
            float2 _767 = _511 * 64.0f.xx;
            float2 _779 = (floor(_767 - 0.4995000064373016357421875f.xx) + 0.5f.xx) - ((float(_619) * 0.5f) - 1.0f).xx;
            float2 _788 = (_779 * 0.015625f) * 1.0f;
            float2 _811 = float2((frac(_788) + float2(_1445, float(_788.y < 0.0f))).y, (_767 - _779).y);
            float4 _630 = _811.xxxx;
            float4 _632 = _811.yyyy;
            float4 _1379;
            float3 _1380;
            _1380 = 0.0f.xxx;
            _1379 = 0.0f.xxxx;
            for (int _1377 = 0; _1377 < _619; )
            {
                float4 _647 = float(_1377).xxxx + float4(0.0f, 1.0f, 2.0f, 3.0f);
                float4 _656 = frac(_630 + (_647 * 0.015625f)) * 1.0f;
                float _658 = _511.x;
                float4 _690 = abs(_632 - _647) * resize_magnification_scale.y;
                float4 _693 = _690 * 3.1415927410125732421875f;
                float4 _696 = _690 * 1.0471975803375244140625f;
                float4 _706 = min((sin(_693) * sin(_696)) / (_693 * _696), 1.0f.xxxx);
                _1380 = (((_1380 + (mask_grille_texture_small.Sample(_mask_grille_texture_small_sampler, float2(_658, _656.x)).xyz * _706.xxx)) + (mask_grille_texture_small.Sample(_mask_grille_texture_small_sampler, float2(_658, _656.y)).xyz * _706.yyy)) + (mask_grille_texture_small.Sample(_mask_grille_texture_small_sampler, float2(_658, _656.z)).xyz * _706.zzz)) + (mask_grille_texture_small.Sample(_mask_grille_texture_small_sampler, float2(_658, _656.w)).xyz * _706.www);
                _1379 += _706;
                _1377 += 4;
                continue;
            }
            float2 _743 = _1379.xy + _1379.zw;
            _1381 = _1380 / (_743.x + _743.y).xxx;
        }
        else
        {
            float3 _1382;
            if (global_mask_type < 1.5f)
            {
                int _874 = int(_230);
                float2 _1022 = _511 * 64.0f.xx;
                float2 _1034 = (floor(_1022 - 0.4995000064373016357421875f.xx) + 0.5f.xx) - ((float(_874) * 0.5f) - 1.0f).xx;
                float2 _1043 = (_1034 * 0.015625f) * 1.0f;
                float2 _1066 = float2((frac(_1043) + float2(_1445, float(_1043.y < 0.0f))).y, (_1022 - _1034).y);
                float4 _885 = _1066.xxxx;
                float4 _887 = _1066.yyyy;
                float4 _1366;
                float3 _1367;
                _1367 = 0.0f.xxx;
                _1366 = 0.0f.xxxx;
                for (int _1364 = 0; _1364 < _874; )
                {
                    float4 _902 = float(_1364).xxxx + float4(0.0f, 1.0f, 2.0f, 3.0f);
                    float4 _911 = frac(_885 + (_902 * 0.015625f)) * 1.0f;
                    float _913 = _511.x;
                    float4 _945 = abs(_887 - _902) * resize_magnification_scale.y;
                    float4 _948 = _945 * 3.1415927410125732421875f;
                    float4 _951 = _945 * 1.0471975803375244140625f;
                    float4 _961 = min((sin(_948) * sin(_951)) / (_948 * _951), 1.0f.xxxx);
                    _1367 = (((_1367 + (mask_slot_texture_small.Sample(_mask_slot_texture_small_sampler, float2(_913, _911.x)).xyz * _961.xxx)) + (mask_slot_texture_small.Sample(_mask_slot_texture_small_sampler, float2(_913, _911.y)).xyz * _961.yyy)) + (mask_slot_texture_small.Sample(_mask_slot_texture_small_sampler, float2(_913, _911.z)).xyz * _961.zzz)) + (mask_slot_texture_small.Sample(_mask_slot_texture_small_sampler, float2(_913, _911.w)).xyz * _961.www);
                    _1366 += _961;
                    _1364 += 4;
                    continue;
                }
                float2 _998 = _1366.xy + _1366.zw;
                _1382 = _1367 / (_998.x + _998.y).xxx;
            }
            else
            {
                int _1129 = int(_230);
                float2 _1277 = _511 * 64.0f.xx;
                float2 _1289 = (floor(_1277 - 0.4995000064373016357421875f.xx) + 0.5f.xx) - ((float(_1129) * 0.5f) - 1.0f).xx;
                float2 _1298 = (_1289 * 0.015625f) * 1.0f;
                float2 _1321 = float2((frac(_1298) + float2(_1445, float(_1298.y < 0.0f))).y, (_1277 - _1289).y);
                float4 _1140 = _1321.xxxx;
                float4 _1142 = _1321.yyyy;
                float4 _1351;
                float3 _1352;
                _1352 = 0.0f.xxx;
                _1351 = 0.0f.xxxx;
                for (int _1349 = 0; _1349 < _1129; )
                {
                    float4 _1157 = float(_1349).xxxx + float4(0.0f, 1.0f, 2.0f, 3.0f);
                    float4 _1166 = frac(_1140 + (_1157 * 0.015625f)) * 1.0f;
                    float _1168 = _511.x;
                    float4 _1200 = abs(_1142 - _1157) * resize_magnification_scale.y;
                    float4 _1203 = _1200 * 3.1415927410125732421875f;
                    float4 _1206 = _1200 * 1.0471975803375244140625f;
                    float4 _1216 = min((sin(_1203) * sin(_1206)) / (_1203 * _1206), 1.0f.xxxx);
                    _1352 = (((_1352 + (mask_shadow_texture_small.Sample(_mask_shadow_texture_small_sampler, float2(_1168, _1166.x)).xyz * _1216.xxx)) + (mask_shadow_texture_small.Sample(_mask_shadow_texture_small_sampler, float2(_1168, _1166.y)).xyz * _1216.yyy)) + (mask_shadow_texture_small.Sample(_mask_shadow_texture_small_sampler, float2(_1168, _1166.z)).xyz * _1216.zzz)) + (mask_shadow_texture_small.Sample(_mask_shadow_texture_small_sampler, float2(_1168, _1166.w)).xyz * _1216.www);
                    _1351 += _1216;
                    _1349 += 4;
                    continue;
                }
                float2 _1253 = _1351.xy + _1351.zw;
                _1382 = _1352 / (_1253.x + _1253.y).xxx;
            }
            _1381 = _1382;
        }
        FragColor = float4(_1381, 1.0f);
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
