// Generated from crt/shaders/hyllian/crt-hyllian-sinc-pass0.slang. See slang/upstream for licence/source.
#version 120
#pragma parameter H_OUTPUT_GAMMA    "    Output Gamma"    2.2 1.0 3.0 0.05
#pragma parameter BRIGHTBOOST       "    Brightboost"     1.0 0.5 2.0 0.01
#pragma parameter scan_nonono        "SCANLINES SETTINGS:"                         0.0  0.0 0.0 1.0
#pragma parameter BEAM_MIN_WIDTH     "    Min Beam Width"                        0.72 0.0 1.0 0.01
#pragma parameter BEAM_MAX_WIDTH     "    Max Beam Width"                        1.0  0.0 1.0 0.01
#pragma parameter SCANLINES_STRENGTH "    Scanlines Strength"                    0.72 0.0 1.0 0.01
#pragma parameter SCANLINES_SHAPE    "    Scanlines Shape [ SHARP, SOFT ]"       1.0  0.0 1.0 1.0
#pragma parameter msk_nonono        "MASK SETTINGS:"                                             0.0 0.0  0.0 1.0
#pragma parameter PHOSPHOR_LAYOUT   "    Mask [1-6 APERT, 7-10 DOT, 11-14 SLOT, 15-17 LOTTES]" 1.0 0.0 17.0 1.0
#pragma parameter MASK_STRENGTH     "    Mask Strength"                                          1.0 0.0  1.0 0.02
#pragma parameter H_MaskGamma       "    Mask Gamma"                                             2.4 1.0  3.0 0.05
#pragma parameter MONITOR_SUBPIXELS "    Monitor Subpixels Layout [ RGB, BGR ]"                  0.0 0.0  1.0 1.0
#pragma parameter fil_nonono        "FILTERING SETTINGS:"                            0.0 0.0 0.0 1.0
#pragma parameter HFILTER_PROFILE   "    H-Filter [ Custom | Composite1 | Composite2 ]"  0.0 0.0 2.0 1.0
#pragma parameter SHP               "    Custom Sharpness"                           1.0 0.50 1.0 0.01
#pragma parameter RADIUS            "    Custom Radius"                              4.0 2.0 4.0 0.1
#pragma parameter SHARPNESS_HACK    "    Sharpness Hack"                             1.0 1.0 4.0 1.0
#pragma parameter CRT_ANTI_RINGING  "    Anti Ringing"                               1.0 0.0 1.0 1.0
#pragma parameter h_nonono        "CURVATURE SETTINGS:"                 0.0  0.0  0.0 1.0
#pragma parameter CURVATURE         "    Curvature Toggle" 0.0 0.0 1.0 1.0
#pragma parameter WARP_X            "        Curvature-X" 0.015 0.0 0.125 0.005
#pragma parameter WARP_Y            "        Curvature-Y" 0.015 0.0 0.125 0.005
#pragma parameter CORNER_SIZE       "        Corner Size" 0.02 0.001 1.0 0.005
#pragma parameter CORNER_SMOOTHNESS "        Corner Smoothness" 1.10 1.0 2.2 0.02
#ifdef VERTEX

uniform mat4 MVPMatrix;
struct UBO
{
    mat4 MVP;
};



attribute vec4 VertexCoord;
varying vec2 RA_VARYING_0;
attribute vec2 TexCoord;

void main()
{
    gl_Position = (MVPMatrix) * VertexCoord;
    RA_VARYING_0 = TexCoord * 1.00010001659393310546875;
}


#endif
#ifdef FRAGMENT

uniform float CRT_ANTI_RINGING;
uniform float CURVATURE;
uniform float HFILTER_PROFILE;
uniform float RADIUS;
uniform float SHARPNESS_HACK;
uniform float SHP;
uniform vec2 TextureSize;
uniform float WARP_X;
struct UBO
{
    vec4 SourceSize;
};



struct Push
{
    float HFILTER_PROFILE;
    float SHARPNESS_HACK;
    float SHP;
    float RADIUS;
    float CRT_ANTI_RINGING;
    float CURVATURE;
    float WARP_X;
};



uniform sampler2D Texture;

varying vec2 RA_VARYING_0;

void main()
{
    float _188 = (SHARPNESS_HACK) * (vec4(TextureSize, 1.0 / TextureSize)).x;
    vec2 _191 = vec2(_188, (vec4(TextureSize, 1.0 / TextureSize)).y);
    vec2 _196 = vec2(1.0 / _188, 0.0);
    vec2 _635;
    if ((CURVATURE) > 0.5)
    {
        vec2 _484 = (RA_VARYING_0 * 2.0) - vec2(1.0);
        float _486 = _484.x;
        float _491 = _484.y;
        float _496 = sqrt((_486 * _486) + (_491 * _491));
        vec2 _511 = vec2(1.0) / (vec2(1.0) + ((vec2((WARP_X), 0.0) * 15.0) * 0.20000000298023223876953125));
        _635 = ((((_484 / vec2(_496)) * (vec2(1.0) - pow(vec2(1.0 - (_496 * 0.707106769084930419921875)), _511))) / (vec2(1.0) - pow(vec2(0.292893230915069580078125), _511))) * 0.5) + vec2(0.5);
    }
    else
    {
        _635 = RA_VARYING_0;
    }
    vec2 _220 = (_635 * _191) + vec2(-0.5, 0.0);
    vec2 _227 = (floor(_220) + vec2(0.5)) / _191;
    vec2 _230 = fract(_220);
    vec2 _242 = _196 * 3.0;
    vec4 _244 = texture2D(Texture, _227 - _242);
    vec2 _250 = _196 * 2.0;
    vec4 _252 = texture2D(Texture, _227 - _250);
    vec4 _259 = texture2D(Texture, _227 - _196);
    vec3 _260 = _259.xyz;
    vec4 _264 = texture2D(Texture, _227);
    vec3 _265 = _264.xyz;
    vec4 _271 = texture2D(Texture, _227 + _196);
    vec3 _272 = _271.xyz;
    vec4 _279 = texture2D(Texture, _227 + _250);
    vec3 _280 = _279.xyz;
    vec4 _287 = texture2D(Texture, _227 + _242);
    vec4 _295 = texture2D(Texture, _227 + (_196 * 4.0));
    vec3 _304 = min(min(_260, _265), min(_272, _280));
    vec3 _312 = max(max(_260, _265), max(_272, _280));
    vec3 _316 = _304 * 0.3333333432674407958984375;
    vec3 _319 = _312 * 3.0;
    vec2 _538 = vec2((SHP), (RADIUS));
    vec2 _637;
    if ((HFILTER_PROFILE) == 1.0)
    {
        _637 = vec2(0.86000001430511474609375, 4.0);
    }
    else
    {
        bvec2 _661 = bvec2((HFILTER_PROFILE) == 2.0);
        _637 = vec2(_661.x ? vec2(0.75, 4.0).x : _538.x, _661.y ? vec2(0.75, 4.0).y : _538.y);
    }
    float _386 = _230.x;
    vec4 _561 = max(abs(vec4(3.0 + _386, 2.0 + _386, 1.0 + _386, _386)), vec4(9.9999997473787516355514526367188e-06)) * _637.x;
    vec4 _580 = _561 * 3.1415927410125732421875;
    vec4 _573 = vec4(_637.y);
    vec4 _588 = (_561 / _573) * 3.1415927410125732421875;
    vec4 _576 = (sin(_580) / _580) * (sin(_588) / _588);
    vec4 _603 = max(abs(vec4(1.0 - _386, 2.0 - _386, 3.0 - _386, 4.0 - _386)), vec4(9.9999997473787516355514526367188e-06)) * _637.x;
    vec4 _622 = _603 * 3.1415927410125732421875;
    vec4 _630 = (_603 / _573) * 3.1415927410125732421875;
    vec4 _618 = (sin(_622) / _622) * (sin(_630) / _630);
    vec4 _428 = vec4(dot(_576, vec4(1.0)) + dot(_618, vec4(1.0)));
    vec3 _444 = clamp((mat4x3(clamp(_244.xyz, _316, _319), clamp(_252.xyz, _316, _319), vec3(_259.xyz), vec3(_264.xyz)) * (_576 / _428)) + (mat4x3(vec3(_271.xyz), vec3(_279.xyz), clamp(_287.xyz, _316, _319), clamp(_295.xyz, _316, _319)) * (_618 / _428)), vec3(0.0), vec3(1.0));
    vec3 _655;
    if ((CRT_ANTI_RINGING) > 0.5)
    {
        _655 = mix(_444, clamp(_444, _304, _312), step(vec3(0.0), (_260 - _265) * (_272 - _280)));
    }
    else
    {
        _655 = _444;
    }
    gl_FragData[0] = vec4(_655, 1.0);
}


#endif
