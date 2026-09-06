// Generated from crt/shaders/crt-royale/src/crt-royale-bloom-approx-fake-bloom.slang. See slang/upstream for licence/source.
cbuffer UBO : register(b0)
{
    float global_beam_max_sigma : packoffset(c6);
    float global_convergence_offset_x_r : packoffset(c8);
    float global_convergence_offset_x_g : packoffset(c8.y);
    float global_convergence_offset_x_b : packoffset(c8.z);
    float global_convergence_offset_y_r : packoffset(c8.w);
    float global_convergence_offset_y_g : packoffset(c9);
    float global_convergence_offset_y_b : packoffset(c9.y);
    float global_mask_num_triads_desired : packoffset(c10);
    float global_mask_triad_size_desired : packoffset(c10.y);
    float global_mask_specify_num_triads : packoffset(c10.z);
};

cbuffer Push : register(b1)
{
    float4 params_SourceSize : packoffset(c0);
    float4 params_OutputSize : packoffset(c2);
};

Texture2D<float4> ORIG_LINEARIZED : register(t3);
SamplerState _ORIG_LINEARIZED_sampler : register(s3);

static float2 uv_scanline_step;
static float2 tex_uv;
static float estimated_viewport_size_x;
static float2 blur_dxdy;
static float2 texture_size_inv;
static float2 tex_uv_to_pixel_scale;
static float4 FragColor;

struct SPIRV_Cross_Input
{
    float2 tex_uv : TEXCOORD0;
    float2 blur_dxdy : TEXCOORD1;
    float2 uv_scanline_step : TEXCOORD2;
    float estimated_viewport_size_x : TEXCOORD3;
    float2 texture_size_inv : TEXCOORD4;
    float2 tex_uv_to_pixel_scale : TEXCOORD5;
};

struct SPIRV_Cross_Output
{
    float4 FragColor : SV_Target0;
};

void frag_main()
{
    float2 _1185 = tex_uv - (float2(global_convergence_offset_x_r, global_convergence_offset_y_r) * uv_scanline_step);
    float2 _1191 = tex_uv - (float2(global_convergence_offset_x_g, global_convergence_offset_y_g) * uv_scanline_step);
    float2 _1197 = tex_uv - (float2(global_convergence_offset_x_b, global_convergence_offset_y_b) * uv_scanline_step);
    float _1426 = max(256.0f, lerp(estimated_viewport_size_x / global_mask_triad_size_desired, global_mask_num_triads_desired, global_mask_specify_num_triads));
    float _1445 = length(float2(((((-0.0516799986362457275390625f) + (901398.5f / _1426)) - (108770.2734375f / _1426)) * params_OutputSize.x) * 6.7816841919920989312231540679932e-07f, global_beam_max_sigma));
    float _1585 = 0.5f / (_1445 * _1445);
    float2 _1610 = float2(float(blur_dxdy.x <= texture_size_inv.x), float(blur_dxdy.y <= texture_size_inv.y));
    float2 _1613 = blur_dxdy * 0.5f;
    float2 _1618 = lerp(_1185 - _1613, (floor((_1185 * params_SourceSize.xy) - 0.4995000064373016357421875f.xx) + 0.5f.xx) * texture_size_inv, _1610);
    float2 _1621 = float2(blur_dxdy.x, 0.0f);
    float2 _1624 = _1618 - blur_dxdy;
    float2 _1627 = _1618 + blur_dxdy;
    float2 _1630 = blur_dxdy * 2.0f;
    float2 _1631 = _1618 + _1630;
    float2 _1634 = _1624 + _1621;
    float2 _1637 = _1621 * 2.0f;
    float2 _1641 = _1621 * 3.0f;
    float2 _1642 = _1624 + _1641;
    float2 _1645 = _1618 - _1621;
    float2 _1648 = _1618 + _1621;
    float2 _1652 = _1618 + _1637;
    float2 _1656 = _1627 - _1637;
    float2 _1659 = _1627 - _1621;
    float2 _1662 = _1627 + _1621;
    float2 _1666 = _1631 - _1641;
    float2 _1670 = _1631 - _1637;
    float2 _1673 = _1631 - _1621;
    float2 _1724 = _1185 * tex_uv_to_pixel_scale;
    float2 _1729 = (_1624 * tex_uv_to_pixel_scale) - _1724;
    float2 _1734 = (_1634 * tex_uv_to_pixel_scale) - _1724;
    float2 _1739 = ((_1624 + _1637) * tex_uv_to_pixel_scale) - _1724;
    float2 _1744 = (_1642 * tex_uv_to_pixel_scale) - _1724;
    float2 _1749 = (_1645 * tex_uv_to_pixel_scale) - _1724;
    float2 _1754 = (_1618 * tex_uv_to_pixel_scale) - _1724;
    float2 _1759 = (_1648 * tex_uv_to_pixel_scale) - _1724;
    float2 _1764 = (_1652 * tex_uv_to_pixel_scale) - _1724;
    float2 _1769 = (_1656 * tex_uv_to_pixel_scale) - _1724;
    float2 _1774 = (_1659 * tex_uv_to_pixel_scale) - _1724;
    float2 _1779 = (_1627 * tex_uv_to_pixel_scale) - _1724;
    float2 _1784 = (_1662 * tex_uv_to_pixel_scale) - _1724;
    float2 _1789 = (_1666 * tex_uv_to_pixel_scale) - _1724;
    float2 _1794 = (_1670 * tex_uv_to_pixel_scale) - _1724;
    float2 _1799 = (_1673 * tex_uv_to_pixel_scale) - _1724;
    float2 _1804 = (_1631 * tex_uv_to_pixel_scale) - _1724;
    float _1811 = exp((-dot(_1729, _1729)) * _1585);
    float _1818 = exp((-dot(_1734, _1734)) * _1585);
    float _1825 = exp((-dot(_1739, _1739)) * _1585);
    float _1832 = exp((-dot(_1744, _1744)) * _1585);
    float _1839 = exp((-dot(_1749, _1749)) * _1585);
    float _1846 = exp((-dot(_1754, _1754)) * _1585);
    float _1853 = exp((-dot(_1759, _1759)) * _1585);
    float _1860 = exp((-dot(_1764, _1764)) * _1585);
    float _1867 = exp((-dot(_1769, _1769)) * _1585);
    float _1874 = exp((-dot(_1774, _1774)) * _1585);
    float _1881 = exp((-dot(_1779, _1779)) * _1585);
    float _1888 = exp((-dot(_1784, _1784)) * _1585);
    float _1895 = exp((-dot(_1789, _1789)) * _1585);
    float _1902 = exp((-dot(_1794, _1794)) * _1585);
    float _1909 = exp((-dot(_1799, _1799)) * _1585);
    float _1916 = exp((-dot(_1804, _1804)) * _1585);
    float3 _1995 = (((((((((((ORIG_LINEARIZED.Sample(_ORIG_LINEARIZED_sampler, _1624).xyz * _1811) + (ORIG_LINEARIZED.Sample(_ORIG_LINEARIZED_sampler, _1634).xyz * _1818)) + (ORIG_LINEARIZED.Sample(_ORIG_LINEARIZED_sampler, _1621).xyz * _1825)) + (ORIG_LINEARIZED.Sample(_ORIG_LINEARIZED_sampler, _1642).xyz * _1832)) + (ORIG_LINEARIZED.Sample(_ORIG_LINEARIZED_sampler, _1645).xyz * _1839)) + (ORIG_LINEARIZED.Sample(_ORIG_LINEARIZED_sampler, _1618).xyz * _1846)) + (ORIG_LINEARIZED.Sample(_ORIG_LINEARIZED_sampler, _1648).xyz * _1853)) + (ORIG_LINEARIZED.Sample(_ORIG_LINEARIZED_sampler, _1652).xyz * _1860)) + (ORIG_LINEARIZED.Sample(_ORIG_LINEARIZED_sampler, _1656).xyz * _1867)) + (ORIG_LINEARIZED.Sample(_ORIG_LINEARIZED_sampler, _1659).xyz * _1874)) + (ORIG_LINEARIZED.Sample(_ORIG_LINEARIZED_sampler, _1627).xyz * _1881)) + (ORIG_LINEARIZED.Sample(_ORIG_LINEARIZED_sampler, _1662).xyz * _1888);
    float2 _2895 = lerp(_1191 - _1613, (floor((_1191 * params_SourceSize.xy) - 0.4995000064373016357421875f.xx) + 0.5f.xx) * texture_size_inv, _1610);
    float2 _2901 = _2895 - blur_dxdy;
    float2 _2904 = _2895 + blur_dxdy;
    float2 _2908 = _2895 + _1630;
    float2 _2911 = _2901 + _1621;
    float2 _2919 = _2901 + _1641;
    float2 _2922 = _2895 - _1621;
    float2 _2925 = _2895 + _1621;
    float2 _2929 = _2895 + _1637;
    float2 _2933 = _2904 - _1637;
    float2 _2936 = _2904 - _1621;
    float2 _2939 = _2904 + _1621;
    float2 _2943 = _2908 - _1641;
    float2 _2947 = _2908 - _1637;
    float2 _2950 = _2908 - _1621;
    float2 _3001 = _1191 * tex_uv_to_pixel_scale;
    float2 _3006 = (_2901 * tex_uv_to_pixel_scale) - _3001;
    float2 _3011 = (_2911 * tex_uv_to_pixel_scale) - _3001;
    float2 _3016 = ((_2901 + _1637) * tex_uv_to_pixel_scale) - _3001;
    float2 _3021 = (_2919 * tex_uv_to_pixel_scale) - _3001;
    float2 _3026 = (_2922 * tex_uv_to_pixel_scale) - _3001;
    float2 _3031 = (_2895 * tex_uv_to_pixel_scale) - _3001;
    float2 _3036 = (_2925 * tex_uv_to_pixel_scale) - _3001;
    float2 _3041 = (_2929 * tex_uv_to_pixel_scale) - _3001;
    float2 _3046 = (_2933 * tex_uv_to_pixel_scale) - _3001;
    float2 _3051 = (_2936 * tex_uv_to_pixel_scale) - _3001;
    float2 _3056 = (_2904 * tex_uv_to_pixel_scale) - _3001;
    float2 _3061 = (_2939 * tex_uv_to_pixel_scale) - _3001;
    float2 _3066 = (_2943 * tex_uv_to_pixel_scale) - _3001;
    float2 _3071 = (_2947 * tex_uv_to_pixel_scale) - _3001;
    float2 _3076 = (_2950 * tex_uv_to_pixel_scale) - _3001;
    float2 _3081 = (_2908 * tex_uv_to_pixel_scale) - _3001;
    float _3088 = exp((-dot(_3006, _3006)) * _1585);
    float _3095 = exp((-dot(_3011, _3011)) * _1585);
    float _3102 = exp((-dot(_3016, _3016)) * _1585);
    float _3109 = exp((-dot(_3021, _3021)) * _1585);
    float _3116 = exp((-dot(_3026, _3026)) * _1585);
    float _3123 = exp((-dot(_3031, _3031)) * _1585);
    float _3130 = exp((-dot(_3036, _3036)) * _1585);
    float _3137 = exp((-dot(_3041, _3041)) * _1585);
    float _3144 = exp((-dot(_3046, _3046)) * _1585);
    float _3151 = exp((-dot(_3051, _3051)) * _1585);
    float _3158 = exp((-dot(_3056, _3056)) * _1585);
    float _3165 = exp((-dot(_3061, _3061)) * _1585);
    float _3172 = exp((-dot(_3066, _3066)) * _1585);
    float _3179 = exp((-dot(_3071, _3071)) * _1585);
    float _3186 = exp((-dot(_3076, _3076)) * _1585);
    float _3193 = exp((-dot(_3081, _3081)) * _1585);
    float3 _3272 = (((((((((((ORIG_LINEARIZED.Sample(_ORIG_LINEARIZED_sampler, _2901).xyz * _3088) + (ORIG_LINEARIZED.Sample(_ORIG_LINEARIZED_sampler, _2911).xyz * _3095)) + (ORIG_LINEARIZED.Sample(_ORIG_LINEARIZED_sampler, _1621).xyz * _3102)) + (ORIG_LINEARIZED.Sample(_ORIG_LINEARIZED_sampler, _2919).xyz * _3109)) + (ORIG_LINEARIZED.Sample(_ORIG_LINEARIZED_sampler, _2922).xyz * _3116)) + (ORIG_LINEARIZED.Sample(_ORIG_LINEARIZED_sampler, _2895).xyz * _3123)) + (ORIG_LINEARIZED.Sample(_ORIG_LINEARIZED_sampler, _2925).xyz * _3130)) + (ORIG_LINEARIZED.Sample(_ORIG_LINEARIZED_sampler, _2929).xyz * _3137)) + (ORIG_LINEARIZED.Sample(_ORIG_LINEARIZED_sampler, _2933).xyz * _3144)) + (ORIG_LINEARIZED.Sample(_ORIG_LINEARIZED_sampler, _2936).xyz * _3151)) + (ORIG_LINEARIZED.Sample(_ORIG_LINEARIZED_sampler, _2904).xyz * _3158)) + (ORIG_LINEARIZED.Sample(_ORIG_LINEARIZED_sampler, _2939).xyz * _3165);
    float2 _4172 = lerp(_1197 - _1613, (floor((_1197 * params_SourceSize.xy) - 0.4995000064373016357421875f.xx) + 0.5f.xx) * texture_size_inv, _1610);
    float2 _4178 = _4172 - blur_dxdy;
    float2 _4181 = _4172 + blur_dxdy;
    float2 _4185 = _4172 + _1630;
    float2 _4188 = _4178 + _1621;
    float2 _4196 = _4178 + _1641;
    float2 _4199 = _4172 - _1621;
    float2 _4202 = _4172 + _1621;
    float2 _4206 = _4172 + _1637;
    float2 _4210 = _4181 - _1637;
    float2 _4213 = _4181 - _1621;
    float2 _4216 = _4181 + _1621;
    float2 _4220 = _4185 - _1641;
    float2 _4224 = _4185 - _1637;
    float2 _4227 = _4185 - _1621;
    float2 _4278 = _1197 * tex_uv_to_pixel_scale;
    float2 _4283 = (_4178 * tex_uv_to_pixel_scale) - _4278;
    float2 _4288 = (_4188 * tex_uv_to_pixel_scale) - _4278;
    float2 _4293 = ((_4178 + _1637) * tex_uv_to_pixel_scale) - _4278;
    float2 _4298 = (_4196 * tex_uv_to_pixel_scale) - _4278;
    float2 _4303 = (_4199 * tex_uv_to_pixel_scale) - _4278;
    float2 _4308 = (_4172 * tex_uv_to_pixel_scale) - _4278;
    float2 _4313 = (_4202 * tex_uv_to_pixel_scale) - _4278;
    float2 _4318 = (_4206 * tex_uv_to_pixel_scale) - _4278;
    float2 _4323 = (_4210 * tex_uv_to_pixel_scale) - _4278;
    float2 _4328 = (_4213 * tex_uv_to_pixel_scale) - _4278;
    float2 _4333 = (_4181 * tex_uv_to_pixel_scale) - _4278;
    float2 _4338 = (_4216 * tex_uv_to_pixel_scale) - _4278;
    float2 _4343 = (_4220 * tex_uv_to_pixel_scale) - _4278;
    float2 _4348 = (_4224 * tex_uv_to_pixel_scale) - _4278;
    float2 _4353 = (_4227 * tex_uv_to_pixel_scale) - _4278;
    float2 _4358 = (_4185 * tex_uv_to_pixel_scale) - _4278;
    float _4365 = exp((-dot(_4283, _4283)) * _1585);
    float _4372 = exp((-dot(_4288, _4288)) * _1585);
    float _4379 = exp((-dot(_4293, _4293)) * _1585);
    float _4386 = exp((-dot(_4298, _4298)) * _1585);
    float _4393 = exp((-dot(_4303, _4303)) * _1585);
    float _4400 = exp((-dot(_4308, _4308)) * _1585);
    float _4407 = exp((-dot(_4313, _4313)) * _1585);
    float _4414 = exp((-dot(_4318, _4318)) * _1585);
    float _4421 = exp((-dot(_4323, _4323)) * _1585);
    float _4428 = exp((-dot(_4328, _4328)) * _1585);
    float _4435 = exp((-dot(_4333, _4333)) * _1585);
    float _4442 = exp((-dot(_4338, _4338)) * _1585);
    float _4449 = exp((-dot(_4343, _4343)) * _1585);
    float _4456 = exp((-dot(_4348, _4348)) * _1585);
    float _4463 = exp((-dot(_4353, _4353)) * _1585);
    float _4470 = exp((-dot(_4358, _4358)) * _1585);
    float3 _4549 = (((((((((((ORIG_LINEARIZED.Sample(_ORIG_LINEARIZED_sampler, _4178).xyz * _4365) + (ORIG_LINEARIZED.Sample(_ORIG_LINEARIZED_sampler, _4188).xyz * _4372)) + (ORIG_LINEARIZED.Sample(_ORIG_LINEARIZED_sampler, _1621).xyz * _4379)) + (ORIG_LINEARIZED.Sample(_ORIG_LINEARIZED_sampler, _4196).xyz * _4386)) + (ORIG_LINEARIZED.Sample(_ORIG_LINEARIZED_sampler, _4199).xyz * _4393)) + (ORIG_LINEARIZED.Sample(_ORIG_LINEARIZED_sampler, _4172).xyz * _4400)) + (ORIG_LINEARIZED.Sample(_ORIG_LINEARIZED_sampler, _4202).xyz * _4407)) + (ORIG_LINEARIZED.Sample(_ORIG_LINEARIZED_sampler, _4206).xyz * _4414)) + (ORIG_LINEARIZED.Sample(_ORIG_LINEARIZED_sampler, _4210).xyz * _4421)) + (ORIG_LINEARIZED.Sample(_ORIG_LINEARIZED_sampler, _4213).xyz * _4428)) + (ORIG_LINEARIZED.Sample(_ORIG_LINEARIZED_sampler, _4181).xyz * _4435)) + (ORIG_LINEARIZED.Sample(_ORIG_LINEARIZED_sampler, _4216).xyz * _4442);
    FragColor = float4((((((_1995 + (ORIG_LINEARIZED.Sample(_ORIG_LINEARIZED_sampler, _1666).xyz * _1895)) + (ORIG_LINEARIZED.Sample(_ORIG_LINEARIZED_sampler, _1670).xyz * _1902)) + (ORIG_LINEARIZED.Sample(_ORIG_LINEARIZED_sampler, _1673).xyz * _1909)) + (ORIG_LINEARIZED.Sample(_ORIG_LINEARIZED_sampler, _1631).xyz * _1916)) * (1.0f / (((((((((((((((_1811 + _1818) + _1825) + _1832) + _1839) + _1846) + _1853) + _1860) + _1867) + _1874) + _1881) + _1888) + _1895) + _1902) + _1909) + _1916))).x, (((((_3272 + (ORIG_LINEARIZED.Sample(_ORIG_LINEARIZED_sampler, _2943).xyz * _3172)) + (ORIG_LINEARIZED.Sample(_ORIG_LINEARIZED_sampler, _2947).xyz * _3179)) + (ORIG_LINEARIZED.Sample(_ORIG_LINEARIZED_sampler, _2950).xyz * _3186)) + (ORIG_LINEARIZED.Sample(_ORIG_LINEARIZED_sampler, _2908).xyz * _3193)) * (1.0f / (((((((((((((((_3088 + _3095) + _3102) + _3109) + _3116) + _3123) + _3130) + _3137) + _3144) + _3151) + _3158) + _3165) + _3172) + _3179) + _3186) + _3193))).y, (((((_4549 + (ORIG_LINEARIZED.Sample(_ORIG_LINEARIZED_sampler, _4220).xyz * _4449)) + (ORIG_LINEARIZED.Sample(_ORIG_LINEARIZED_sampler, _4224).xyz * _4456)) + (ORIG_LINEARIZED.Sample(_ORIG_LINEARIZED_sampler, _4227).xyz * _4463)) + (ORIG_LINEARIZED.Sample(_ORIG_LINEARIZED_sampler, _4185).xyz * _4470)) * (1.0f / (((((((((((((((_4365 + _4372) + _4379) + _4386) + _4393) + _4400) + _4407) + _4414) + _4421) + _4428) + _4435) + _4442) + _4449) + _4456) + _4463) + _4470))).z, 1.0f);
}

SPIRV_Cross_Output main(SPIRV_Cross_Input stage_input)
{
    uv_scanline_step = stage_input.uv_scanline_step;
    tex_uv = stage_input.tex_uv;
    estimated_viewport_size_x = stage_input.estimated_viewport_size_x;
    blur_dxdy = stage_input.blur_dxdy;
    texture_size_inv = stage_input.texture_size_inv;
    tex_uv_to_pixel_scale = stage_input.tex_uv_to_pixel_scale;
    frag_main();
    SPIRV_Cross_Output stage_output;
    stage_output.FragColor = FragColor;
    return stage_output;
}
