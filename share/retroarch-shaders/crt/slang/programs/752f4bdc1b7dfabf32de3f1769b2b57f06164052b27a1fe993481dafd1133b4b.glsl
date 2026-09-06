// Generated from crt/shaders/crt-easymode.slang. See slang/upstream for licence/source.
#version 120
#pragma parameter SHARPNESS_H "Sharpness Horizontal" 0.5 0.0 1.0 0.05
#pragma parameter SHARPNESS_V "Sharpness Vertical" 1.0 0.0 1.0 0.05
#pragma parameter MASK_STRENGTH "Mask Strength" 0.3 0.0 1.0 0.01
#pragma parameter MASK_DOT_WIDTH "Mask Dot Width" 1.0 1.0 100.0 1.0
#pragma parameter MASK_DOT_HEIGHT "Mask Dot Height" 1.0 1.0 100.0 1.0
#pragma parameter MASK_STAGGER "Mask Stagger" 0.0 0.0 100.0 1.0
#pragma parameter MASK_SIZE "Mask Size" 1.0 1.0 100.0 1.0
#pragma parameter SCANLINE_STRENGTH "Scanline Strength" 1.0 0.0 1.0 0.05
#pragma parameter SCANLINE_BEAM_WIDTH_MIN "Scanline Beam Width Min." 1.5 0.5 5.0 0.5
#pragma parameter SCANLINE_BEAM_WIDTH_MAX "Scanline Beam Width Max." 1.5 0.5 5.0 0.5
#pragma parameter SCANLINE_BRIGHT_MIN "Scanline Brightness Min." 0.35 0.0 1.0 0.05
#pragma parameter SCANLINE_BRIGHT_MAX "Scanline Brightness Max." 0.65 0.0 1.0 0.05
#pragma parameter SCANLINE_CUTOFF "Scanline Cutoff" 400.0 1.0 1000.0 1.0
#pragma parameter GAMMA_INPUT "Gamma Input" 2.0 0.1 5.0 0.1
#pragma parameter GAMMA_OUTPUT "Gamma Output" 1.8 0.1 5.0 0.1
#pragma parameter BRIGHT_BOOST "Brightness Boost" 1.2 1.0 2.0 0.01
#pragma parameter DILATION "Dilation" 1.0 0.0 1.0 1.0
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
    RA_VARYING_0 = TexCoord;
}


#endif
#ifdef FRAGMENT

uniform float BRIGHT_BOOST;
uniform float DILATION;
uniform float GAMMA_INPUT;
uniform float GAMMA_OUTPUT;
uniform float MASK_DOT_HEIGHT;
uniform float MASK_DOT_WIDTH;
uniform float MASK_SIZE;
uniform float MASK_STAGGER;
uniform float MASK_STRENGTH;
uniform vec2 OutputSize;
uniform float SCANLINE_BEAM_WIDTH_MAX;
uniform float SCANLINE_BEAM_WIDTH_MIN;
uniform float SCANLINE_BRIGHT_MAX;
uniform float SCANLINE_BRIGHT_MIN;
uniform float SCANLINE_CUTOFF;
uniform float SCANLINE_STRENGTH;
uniform float SHARPNESS_H;
uniform float SHARPNESS_V;
uniform vec2 TextureSize;
struct UBO
{
    vec4 OutputSize;
    vec4 SourceSize;
};



struct Push
{
    float BRIGHT_BOOST;
    float DILATION;
    float GAMMA_INPUT;
    float GAMMA_OUTPUT;
    float MASK_SIZE;
    float MASK_STAGGER;
    float MASK_STRENGTH;
    float MASK_DOT_HEIGHT;
    float MASK_DOT_WIDTH;
    float SCANLINE_CUTOFF;
    float SCANLINE_BEAM_WIDTH_MAX;
    float SCANLINE_BEAM_WIDTH_MIN;
    float SCANLINE_BRIGHT_MAX;
    float SCANLINE_BRIGHT_MIN;
    float SCANLINE_STRENGTH;
    float SHARPNESS_H;
    float SHARPNESS_V;
};



uniform sampler2D Texture;

varying vec2 RA_VARYING_0;

void main()
{
    vec2 _170 = vec2((vec4(TextureSize, 1.0 / TextureSize)).z, 0.0);
    vec2 _186 = (RA_VARYING_0 * (vec4(TextureSize, 1.0 / TextureSize)).xy) - vec2(0.5);
    vec2 _194 = (floor(_186) + vec2(0.5)) * (vec4(TextureSize, 1.0 / TextureSize)).zw;
    vec2 _197 = fract(_186);
    float _208 = _197.x;
    float _462 = _208 - step(0.5, _208);
    float _477 = mix(_208, 0.5 - (sqrt(0.25 - (_462 * _462)) * sign(0.5 - _208)), (SHARPNESS_H) * (SHARPNESS_H));
    vec4 _226 = max(abs(vec4(1.0 + _477, _477, 1.0 - _477, 2.0 - _477) * 3.1415927410125732421875), vec4(9.9999997473787516355514526367188e-06));
    vec4 _237 = ((sin(_226) * 2.0) * sin(_226 * 0.5)) / (_226 * _226);
    vec4 _242 = _237 / vec4(dot(_237, vec4(1.0)));
    vec4 _488 = texture2D(Texture, _194 - _170);
    vec4 _534 = vec4((DILATION));
    vec4 _492 = texture2D(Texture, _194);
    vec4 _549 = _492 * mix(vec4(1.0), _492, _534);
    vec4 _498 = texture2D(Texture, _194 + _170);
    vec4 _560 = _498 * mix(vec4(1.0), _498, _534);
    vec2 _503 = _170 * 2.0;
    vec4 _505 = texture2D(Texture, _194 + _503);
    vec2 _257 = _194 + vec2(0.0, (vec4(TextureSize, 1.0 / TextureSize)).w);
    vec4 _606 = texture2D(Texture, _257 - _170);
    vec4 _610 = texture2D(Texture, _257);
    vec4 _667 = _610 * mix(vec4(1.0), _610, _534);
    vec4 _616 = texture2D(Texture, _257 + _170);
    vec4 _678 = _616 * mix(vec4(1.0), _616, _534);
    vec4 _623 = texture2D(Texture, _257 + _503);
    float _272 = _197.y;
    float _722 = _272 - step(0.5, _272);
    vec3 _287 = pow(mix(clamp(mat4(_488 * mix(vec4(1.0), _488, _534), _549, _560, _505 * mix(vec4(1.0), _505, _534)) * _242, min(_549, _560), max(_549, _560)).xyz, clamp(mat4(_606 * mix(vec4(1.0), _606, _534), _667, _678, _623 * mix(vec4(1.0), _623, _534)) * _242, min(_667, _678), max(_667, _678)).xyz, vec3(mix(_272, 0.5 - (sqrt(0.25 - (_722 * _722)) * sign(0.5 - _272)), (SHARPNESS_V)))), vec3((GAMMA_INPUT) / ((DILATION) + 1.0)));
    float _306 = (max(_287.x, max(_287.y, _287.z)) + dot(vec3(0.2125999927520751953125, 0.715200006961822509765625, 0.072200000286102294921875), _287)) * 0.5;
    float _351 = 1.0 - (MASK_STRENGTH);
    vec2 _377 = floor(((RA_VARYING_0 * (vec4(OutputSize, 1.0 / OutputSize)).xy) * (vec4(TextureSize, 1.0 / TextureSize)).xy) / ((vec4(TextureSize, 1.0 / TextureSize)).xy * vec2((MASK_SIZE), (MASK_DOT_HEIGHT) * (MASK_SIZE))));
    int _396 = int(mod((_377.x + (mod(_377.y, 2.0) * (MASK_STAGGER))) / (MASK_DOT_WIDTH), 3.0));
    vec3 _745;
    if (_396 == 0)
    {
        _745 = vec3(1.0, _351, _351);
    }
    else
    {
        vec3 _746;
        if (_396 == 1)
        {
            _746 = vec3(_351, 1.0, _351);
        }
        else
        {
            _746 = vec3(_351, _351, 1.0);
        }
        _745 = _746;
    }
    gl_FragData[0] = vec4(pow(mix(_287 * vec3(((vec4(TextureSize, 1.0 / TextureSize)).y >= (SCANLINE_CUTOFF)) ? 1.0 : (1.0 - (pow((cos((RA_VARYING_0.y * 6.283185482025146484375) * (vec4(TextureSize, 1.0 / TextureSize)).y) * 0.5) + 0.5, clamp(_306 * (SCANLINE_BEAM_WIDTH_MAX), (SCANLINE_BEAM_WIDTH_MIN), (SCANLINE_BEAM_WIDTH_MAX))) * (SCANLINE_STRENGTH)))), _287, vec3(clamp(_306, (SCANLINE_BRIGHT_MIN), (SCANLINE_BRIGHT_MAX)))) * _745, vec3(1.0 / (GAMMA_OUTPUT))) * (BRIGHT_BOOST), 1.0);
}


#endif
