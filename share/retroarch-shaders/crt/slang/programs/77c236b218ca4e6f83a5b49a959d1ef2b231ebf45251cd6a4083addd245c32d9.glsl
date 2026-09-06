// Generated from crt/shaders/hyllian/crt-hyllian-base.slang. See slang/upstream for licence/source.
#version 120
#pragma parameter H_OUTPUT_GAMMA    "    Output Gamma"    2.2 1.0 3.0 0.05
#pragma parameter BRIGHTBOOST       "    Brightboost"     1.0 0.5 2.0 0.01
#pragma parameter pre_nonono        "PRESET OPTIONS:"                                             0.0 0.0 0.0 1.0
#pragma parameter pre_comment1      "// Presets greater than 0 disable options with '*'."         0.0 0.0 0.0 1.0
#pragma parameter PRESET_OPTION     "    Mask Preset [CUSTOM, APERT1, APERT2, SLOT1, SLOT2, DOT]" 0.0 0.0 5.0 1.0
#pragma parameter pre_comment2      "// Only affects presets greater than '0'."                   0.0 0.0 0.0 1.0
#pragma parameter DISPLAY_RES       "    Target Resolution [ 1080P, 4K ]"                         0.0 0.0 1.0 1.0
#pragma parameter scan_nonono        "SCANLINES SETTINGS:"                         0.0  0.0 0.0 1.0
#pragma parameter BEAM_MIN_WIDTH     "    * Min Beam Width"                        0.72 0.0 1.0 0.01
#pragma parameter BEAM_MAX_WIDTH     "    * Max Beam Width"                        1.0  0.0 1.0 0.01
#pragma parameter SCANLINES_STRENGTH "    * Scanlines Strength"                    0.72 0.0 1.0 0.01
#pragma parameter SCANLINES_SHAPE    "    * Scanlines Shape [ SHARP, SOFT ]"       1.0  0.0 1.0 1.0
#pragma parameter VSCANLINES         "    Orientation [ HORIZONTAL, VERTICAL ]"    0.0  0.0 1.0 1.0
#pragma parameter msk_nonono        "MASK SETTINGS:"                                             0.0 0.0  0.0 1.0
#pragma parameter PHOSPHOR_LAYOUT   "    * Mask [1-6 APERT, 7-10 DOT, 11-14 SLOT, 15-17 LOTTES]" 1.0 0.0 17.0 1.0
#pragma parameter MASK_STRENGTH     "    Mask Strength"                                          1.0 0.0  1.0 0.02
#pragma parameter H_MaskGamma       "    Mask Gamma"                                             2.4 1.0  3.0 0.05
#pragma parameter MONITOR_SUBPIXELS "    Monitor Subpixels Layout [ RGB, BGR ]"                  0.0 0.0  1.0 1.0
#pragma parameter scl_nonono        "SCALING SETTINGS:"                              0.0 0.0    0.0 1.0
#pragma parameter SCANLINES_CUTOFF  "    Scanlines Cutoff"                         400.0 0.0 1000.0 2.0
#pragma parameter SCANLINES_HIRES   "    High Resolution Scanlines"                  0.0 0.0    1.0 1.0
#pragma parameter IR_SCALE          "    Internal Resolution Scale (downsampling)"   1.0 1.0   10.0 1.0
#pragma parameter fil_nonono        "FILTERING SETTINGS:"                            0.0 0.0 0.0 1.0
#pragma parameter SHARPNESS_HACK    "    Sharpness Hack"                             1.0 1.0 4.0 1.0
#pragma parameter CRT_ANTI_RINGING  "    Anti Ringing"                               1.0 0.0 1.0 1.0
#ifdef VERTEX

uniform float BEAM_MAX_WIDTH;
uniform float BEAM_MIN_WIDTH;
uniform float IR_SCALE;
uniform mat4 MVPMatrix;
uniform float PRESET_OPTION;
uniform float SCANLINES_CUTOFF;
uniform float SCANLINES_SHAPE;
uniform float SCANLINES_STRENGTH;
uniform float SHARPNESS_HACK;
uniform vec2 TextureSize;
uniform float VSCANLINES;
struct UBO
{
    mat4 MVP;
};



struct Push
{
    vec4 SourceSize;
    float PRESET_OPTION;
    float BEAM_MIN_WIDTH;
    float BEAM_MAX_WIDTH;
    float SCANLINES_STRENGTH;
    float SCANLINES_SHAPE;
    float SHARPNESS_HACK;
    float SCANLINES_CUTOFF;
    float IR_SCALE;
    float VSCANLINES;
};



attribute vec4 VertexCoord;
varying vec2 RA_VARYING_0;
attribute vec2 TexCoord;
varying vec4 RA_VARYING_1;
varying vec2 RA_VARYING_2;
varying vec2 RA_VARYING_3;
varying vec4 RA_VARYING_4;
varying float RA_VARYING_5;

void main()
{
    gl_Position = (MVPMatrix) * VertexCoord;
    RA_VARYING_0 = TexCoord * 1.00010001659393310546875;
    vec2 _116 = vec2((SHARPNESS_HACK), 1.0 / (IR_SCALE));
    vec2 _123 = vec2((VSCANLINES));
    vec2 _124 = mix(_116, _116.yx, _123);
    RA_VARYING_1 = vec4(_124, vec2(1.0) / _124) * (vec4(TextureSize, 1.0 / TextureSize));
    RA_VARYING_2 = mix(vec2(RA_VARYING_1.z, 0.0), vec2(0.0, RA_VARYING_1.w), _123);
    RA_VARYING_3 = mix(vec2(0.0, RA_VARYING_1.w), vec2(RA_VARYING_1.z, 0.0), _123);
    vec4 _196 = vec4(((-0.1599999964237213134765625) * (SCANLINES_SHAPE)) + (SCANLINES_STRENGTH), (BEAM_MIN_WIDTH), (BEAM_MAX_WIDTH), (SCANLINES_SHAPE));
    bvec4 _230 = bvec4((PRESET_OPTION) == 1.0);
    vec4 _231 = vec4(_230.x ? vec4(0.7200000286102294921875, 0.7200000286102294921875, 1.0, 1.0).x : _196.x, _230.y ? vec4(0.7200000286102294921875, 0.7200000286102294921875, 1.0, 1.0).y : _196.y, _230.z ? vec4(0.7200000286102294921875, 0.7200000286102294921875, 1.0, 1.0).z : _196.z, _230.w ? vec4(0.7200000286102294921875, 0.7200000286102294921875, 1.0, 1.0).w : _196.w);
    bvec4 _232 = bvec4((PRESET_OPTION) == 2.0);
    vec4 _233 = vec4(_232.x ? vec4(0.579999983310699462890625, 0.7200000286102294921875, 1.0, 1.0).x : _231.x, _232.y ? vec4(0.579999983310699462890625, 0.7200000286102294921875, 1.0, 1.0).y : _231.y, _232.z ? vec4(0.579999983310699462890625, 0.7200000286102294921875, 1.0, 1.0).z : _231.z, _232.w ? vec4(0.579999983310699462890625, 0.7200000286102294921875, 1.0, 1.0).w : _231.w);
    bvec4 _234 = bvec4((PRESET_OPTION) == 3.0);
    vec4 _235 = vec4(_234.x ? vec4(0.579999983310699462890625, 0.86000001430511474609375, 1.0, 0.0).x : _233.x, _234.y ? vec4(0.579999983310699462890625, 0.86000001430511474609375, 1.0, 0.0).y : _233.y, _234.z ? vec4(0.579999983310699462890625, 0.86000001430511474609375, 1.0, 0.0).z : _233.z, _234.w ? vec4(0.579999983310699462890625, 0.86000001430511474609375, 1.0, 0.0).w : _233.w);
    bvec4 _236 = bvec4((PRESET_OPTION) == 4.0);
    vec4 _237 = vec4(_236.x ? vec4(0.579999983310699462890625, 0.86000001430511474609375, 1.0, 1.0).x : _235.x, _236.y ? vec4(0.579999983310699462890625, 0.86000001430511474609375, 1.0, 1.0).y : _235.y, _236.z ? vec4(0.579999983310699462890625, 0.86000001430511474609375, 1.0, 1.0).z : _235.z, _236.w ? vec4(0.579999983310699462890625, 0.86000001430511474609375, 1.0, 1.0).w : _235.w);
    bvec4 _238 = bvec4((PRESET_OPTION) == 5.0);
    RA_VARYING_4 = vec4(_238.x ? vec4(0.579999983310699462890625, 0.7200000286102294921875, 1.0, 1.0).x : _237.x, _238.y ? vec4(0.579999983310699462890625, 0.7200000286102294921875, 1.0, 1.0).y : _237.y, _238.z ? vec4(0.579999983310699462890625, 0.7200000286102294921875, 1.0, 1.0).z : _237.z, _238.w ? vec4(0.579999983310699462890625, 0.7200000286102294921875, 1.0, 1.0).w : _237.w);
    RA_VARYING_5 = float(mix(RA_VARYING_1.y, RA_VARYING_1.x, (VSCANLINES)) <= (SCANLINES_CUTOFF));
}


#endif
#ifdef FRAGMENT

uniform float CRT_ANTI_RINGING;
uniform float SCANLINES_HIRES;
uniform float VSCANLINES;
struct Push
{
    float SCANLINES_HIRES;
    float CRT_ANTI_RINGING;
    float VSCANLINES;
};



uniform sampler2D Texture;

varying vec2 RA_VARYING_0;
varying vec4 RA_VARYING_1;
varying vec2 RA_VARYING_2;
varying vec2 RA_VARYING_3;
varying vec4 RA_VARYING_4;
varying float RA_VARYING_5;

void main()
{
    vec2 _71 = (RA_VARYING_0 * RA_VARYING_1.xy) - vec2(0.5);
    vec2 _74 = floor(_71);
    vec2 _97 = vec2((VSCANLINES));
    vec2 _98 = mix(vec2(_74.x, _71.y), vec2(_71.x, _74.y), _97);
    bvec2 _107 = bvec2((SCANLINES_HIRES) > 0.5);
    vec2 _112 = (vec2(_107.x ? _98.x : _74.x, _107.y ? _98.y : _74.y) + vec2(0.5)) * RA_VARYING_1.zw;
    vec2 _122 = mix(fract(_71), fract(_71.yx), _97);
    vec2 _132 = _112 - RA_VARYING_2;
    vec4 _133 = texture2D(Texture, _132);
    vec4 _138 = texture2D(Texture, _112);
    vec3 _139 = _138.xyz;
    vec2 _144 = _112 + RA_VARYING_2;
    vec4 _145 = texture2D(Texture, _144);
    vec3 _146 = _145.xyz;
    vec2 _153 = _112 + (RA_VARYING_2 * 2.0);
    vec4 _154 = texture2D(Texture, _153);
    vec3 _452;
    vec3 _453;
    vec3 _454;
    vec3 _455;
    if ((SCANLINES_HIRES) < 0.5)
    {
        _455 = texture2D(Texture, _153 + RA_VARYING_3).xyz;
        _454 = texture2D(Texture, _144 + RA_VARYING_3).xyz;
        _453 = texture2D(Texture, _112 + RA_VARYING_3).xyz;
        _452 = texture2D(Texture, _132 + RA_VARYING_3).xyz;
    }
    else
    {
        _455 = _154.xyz;
        _454 = _146;
        _453 = _139;
        _452 = _133.xyz;
    }
    float _251 = _122.x;
    float _254 = _251 * _251;
    vec4 _276 = vec4(_254 * _251, _254, _251, 1.0) * mat4(vec4(-0.5, 1.0, -0.5, 0.0), vec4(1.5, -2.5, 0.0, 1.0), vec4(-1.5, 2.0, 0.5, 0.0), vec4(0.5, -0.5, 0.0, 0.0));
    vec3 _280 = mat4x3(vec3(_133.xyz), vec3(_138.xyz), vec3(_145.xyz), vec3(_154.xyz)) * _276;
    vec3 _284 = mat4x3(_452, _453, _454, _455) * _276;
    vec3 _312 = vec3((CRT_ANTI_RINGING));
    vec3 _313 = mix(_280, clamp(_280, min(_139, _146), max(_139, _146)), _312);
    vec3 _324 = mix(_284, clamp(_284, min(_453, _454), max(_453, _454)), _312);
    float _327 = _122.y;
    vec3 _337 = vec3(RA_VARYING_4.y);
    vec3 _341 = vec3(RA_VARYING_4.z);
    vec3 _343 = mix(_337, _341, _313);
    vec3 _352 = mix(_337, _341, _324);
    vec3 _365 = vec3(RA_VARYING_4.x * _327) / ((_343 * _343) + vec3(1.0000000116860974230803549289703e-07));
    vec3 _377 = vec3(RA_VARYING_4.x * (1.0 - _327)) / ((_352 * _352) + vec3(1.0000000116860974230803549289703e-07));
    vec3 _460;
    if (RA_VARYING_5 > 0.5)
    {
        vec3 _457;
        vec3 _459;
        if (RA_VARYING_4.w > 0.5)
        {
            _459 = exp((_377 * (-16.0)) * _377);
            _457 = exp((_365 * (-16.0)) * _365);
        }
        else
        {
            _459 = vec3(1.0) - smoothstep(vec3(0.0), vec3(0.5), _377);
            _457 = vec3(1.0) - smoothstep(vec3(0.0), vec3(0.5), _365);
        }
        _460 = (_313 * _457) + (_324 * _459);
    }
    else
    {
        _460 = texture2D(Texture, RA_VARYING_0).xyz;
    }
    gl_FragData[0] = vec4(_460, 1.0);
}


#endif
