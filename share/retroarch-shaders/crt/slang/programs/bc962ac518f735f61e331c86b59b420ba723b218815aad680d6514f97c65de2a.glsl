// Generated from crt/shaders/simple-crt/simple-crt.slang. See slang/upstream for licence/source.
#version 330
#pragma parameter LUMA_INTENSITY    "[CRT] Luma boost strength"           4.00   0.00  8.00   1.00 // how strong the boost is
#pragma parameter LUMA_THRESHOLD    "[CRT] Luma boost threshold"          0.50   0.00  1.00   0.10 // 0.00 all pixels are boosted // 1.00 no pixels are boosted
#pragma parameter OSC_STRENGTH      "[CRT] Oscillate brightness strength" 0.05   0.00  0.25   0.01
#pragma parameter OSC_SPEED         "[CRT] Oscillate brightness speed"    0.50   0.00  0.75   0.05
#pragma parameter NOISE_STRENGTH    "[CRT] Noise strength"                0.20   0.00  0.50   0.01
#pragma parameter NOISE_SIZE        "[CRT] Noise size"                    2.00   0.25  4.00   0.25
#pragma parameter NOISE_MIN         "[CRT] Noise lower threshold"         0.05   0.00  1.00   0.05
#pragma parameter NOISE_MAX         "[CRT] Noise upper threshold"         0.25   0.00  1.00   0.05
#pragma parameter FLICKER_STRENGTH  "[CRT] Flicker strength"              0.05   0.00  0.50   0.01
#pragma parameter FLICKER_MIN       "[CRT] Flicker lower threshold"       0.05   0.00  1.00   0.05
#pragma parameter FLICKER_MAX       "[CRT] Flicker upper threshold"       0.25   0.00  1.00   0.05
#pragma parameter CRT_MASK_STRENGTH "[CRT] Mask strength"                 1.00   0.00  1.00   0.10
#pragma parameter CRT_MASK_RES_X    "[CRT] Mask resolution X"             1.00   0.25  4.00   0.25
#pragma parameter CRT_MASK_RES_Y    "[CRT] Mask resolution Y"             3.00   0.25  4.00   0.25
#pragma parameter CRT_MASK_MODE     "[CRT] Mask mode SD/HD"               2.00   1.00  2.00   1.00
#ifdef VERTEX

uniform float CRT_MASK_STRENGTH;
uniform int FrameCount;
uniform mat4 MVPMatrix;
uniform float NOISE_SIZE;
uniform float OSC_SPEED;
uniform float OSC_STRENGTH;
uniform vec2 OutputSize;
struct UBO
{
    mat4 MVP;
};



struct Push
{
    vec4 OutputSize;
    uint FrameCount;
    float OSC_STRENGTH;
    float OSC_SPEED;
    float NOISE_SIZE;
    float CRT_MASK_STRENGTH;
};



layout(location = 0) in vec4 VertexCoord;
out vec2 RA_VARYING_0;
layout(location = 1) in vec2 TexCoord;
flat out float RA_VARYING_1;
flat out vec2 RA_VARYING_2;
flat out int RA_VARYING_3;
flat out vec3 RA_VARYING_4;
flat out float RA_VARYING_5;
flat out float RA_VARYING_6;

void main()
{
    gl_Position = (MVPMatrix) * VertexCoord;
    RA_VARYING_0 = TexCoord;
    float _122 = (OSC_STRENGTH) * 0.100000001490116119384765625;
    float _128 = 1.0 - _122;
    float _305 = _122 + _122;
    float _150 = (1.0 - pow((OSC_SPEED), 0.5)) * 10.0;
    float _215 = float((uint(FrameCount)));
    RA_VARYING_1 = (((_305 * 0.5) + _128) * sin(sin((mod(_215, _150) / _150) * 6.283185482025146484375) * _305)) + _128;
    RA_VARYING_2 = vec2(1.0) / ((vec4(OutputSize, 1.0 / OutputSize)).xy * vec2((NOISE_SIZE)));
    uvec4 _230 = (uvec4((uint(FrameCount))) * uvec4(2348682457u, 636532089u, 3368437335u, 2717797467u)) + uvec4(2891336453u);
    uvec4 _241 = ((_230 >> ((_230 >> uvec4(28u)) + uvec4(4u))) ^ _230) * uvec4(277803737u);
    uvec4 _246 = (_241 >> uvec4(22u)) ^ _241;
    RA_VARYING_3 = int(mod(float(_246.x), 1021.0));
    RA_VARYING_4 = vec3(dot(uintBitsToFloat((_246 & uvec4(8388607u)) | uvec4(1065353216u)) - vec4(1.0), vec4(0.25)));
    RA_VARYING_5 = mod(_215, 16383.0) * 0.00038351860712282359600067138671875;
    RA_VARYING_6 = 1.0 + ((CRT_MASK_STRENGTH) * 1.5);
}


#endif
#ifdef FRAGMENT

uniform float CRT_MASK_MODE;
uniform float CRT_MASK_RES_X;
uniform float CRT_MASK_RES_Y;
uniform float CRT_MASK_STRENGTH;
uniform float FLICKER_MAX;
uniform float FLICKER_MIN;
uniform float FLICKER_STRENGTH;
uniform float LUMA_INTENSITY;
uniform float LUMA_THRESHOLD;
uniform float NOISE_MAX;
uniform float NOISE_MIN;
uniform float NOISE_STRENGTH;
struct Push
{
    float NOISE_STRENGTH;
    float NOISE_MIN;
    float NOISE_MAX;
    float FLICKER_STRENGTH;
    float FLICKER_MIN;
    float FLICKER_MAX;
    float CRT_MASK_STRENGTH;
    float CRT_MASK_RES_X;
    float CRT_MASK_RES_Y;
    float CRT_MASK_MODE;
    float LUMA_INTENSITY;
    float LUMA_THRESHOLD;
};



uniform sampler2D Texture;

in vec2 RA_VARYING_0;
flat in float RA_VARYING_1;
flat in vec2 RA_VARYING_2;
flat in int RA_VARYING_3;
flat in vec3 RA_VARYING_4;
flat in float RA_VARYING_5;
flat in float RA_VARYING_6;
layout(location = 0) out vec4 FragColor;

void main()
{
    vec4 _85 = texture(Texture, RA_VARYING_0);
    vec3 _95 = _85.xyz * RA_VARYING_1;
    vec2 _119 = mod(round(fract(gl_FragCoord.xy * RA_VARYING_2) * 1021.0) + vec2(float(RA_VARYING_3)), vec2(1021.0)) + vec2(1.0);
    uvec4 _313 = (uvec4(floatBitsToUint((5000.0 + _119.x) * _119.y)) * uvec4(2348682457u, 636532089u, 3368437335u, 2717797467u)) + uvec4(2891336453u);
    uvec4 _324 = ((_313 >> ((_313 >> uvec4(28u)) + uvec4(4u))) ^ _313) * uvec4(277803737u);
    vec3 _154 = mix(_95, (uintBitsToFloat((((_324 >> uvec4(22u)) ^ _324) & uvec4(8388607u)) | uvec4(1065353216u)) - vec4(1.0)).xyz * clamp(_95, vec3((NOISE_MIN)), vec3((NOISE_MAX))), vec3((NOISE_STRENGTH)));
    vec3 _174 = mix(_154, RA_VARYING_4 * clamp(_154, vec3((FLICKER_MIN)), vec3((FLICKER_MAX))), vec3((FLICKER_STRENGTH)));
    float _178 = _85.w;
    float _184 = _178 - (LUMA_THRESHOLD);
    vec3 _210 = (mix(_174, _174 * ((_178 * (LUMA_INTENSITY)) + 1.0), vec3(pow(_184, 3.0))) * float(_184 > 0.0)) + (_174 * float(_184 <= 0.0));
    vec2 _228 = mod((gl_FragCoord.xy / vec2((CRT_MASK_RES_X), (CRT_MASK_RES_Y))) + vec2(RA_VARYING_5), vec2(6.283185482025146484375));
    vec3 _242 = vec3(dot(vec2(cos(_228.x), sin(_228.y)), vec2(0.5)));
    vec3 _271 = mix(_210, (((_242 * _242) * float((CRT_MASK_MODE) > 1.5)) + (_242 * float((CRT_MASK_MODE) <= 1.5))) * _210, vec3((CRT_MASK_STRENGTH))) * RA_VARYING_6;
    FragColor.x = _271.x;
    FragColor.y = _271.y;
    FragColor.z = _271.z;
}


#endif
