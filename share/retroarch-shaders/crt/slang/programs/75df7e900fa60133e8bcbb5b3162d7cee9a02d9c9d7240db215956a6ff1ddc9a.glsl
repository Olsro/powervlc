// Generated from crt/shaders/crt-pi.slang. See slang/upstream for licence/source.
#version 120
#pragma parameter CURVATURE_X             "Screen curvature - horizontal" 0.10 0.0 1.0  0.01
#pragma parameter CURVATURE_Y             "Screen curvature - vertical"   0.15 0.0 1.0  0.01
#pragma parameter MASK_BRIGHTNESS         "Mask brightness"               0.70 0.0 1.0  0.01
#pragma parameter SCANLINE_WEIGHT         "Scanline weight"               6.0  0.0 15.0 0.1
#pragma parameter SCANLINE_GAP_BRIGHTNESS "Scanline gap brightness"       0.12 0.0 1.0  0.01
#pragma parameter BLOOM_FACTOR            "Bloom factor"                  1.5  0.0 5.0  0.01
#pragma parameter INPUT_GAMMA             "Input gamma"                   2.4  0.0 5.0  0.01
#pragma parameter OUTPUT_GAMMA            "Output gamma"                  2.2  0.0 5.0  0.01
#ifdef VERTEX

uniform mat4 MVPMatrix;
uniform vec2 OutputSize;
uniform vec2 TextureSize;
struct UBO
{
    mat4 MVP;
    vec4 OutputSize;
    vec4 SourceSize;
};



attribute vec4 VertexCoord;
varying vec2 RA_VARYING_0;
attribute vec2 TexCoord;
varying float RA_VARYING_1;

void main()
{
    gl_Position = (MVPMatrix) * VertexCoord;
    RA_VARYING_0 = TexCoord;
    RA_VARYING_1 = ((vec4(TextureSize, 1.0 / TextureSize)).y * (vec4(OutputSize, 1.0 / OutputSize)).w) * 0.3333333432674407958984375;
}


#endif
#ifdef FRAGMENT

uniform float BLOOM_FACTOR;
uniform float CURVATURE_X;
uniform float CURVATURE_Y;
uniform float MASK_BRIGHTNESS;
uniform vec2 OutputSize;
uniform float SCANLINE_GAP_BRIGHTNESS;
uniform float SCANLINE_WEIGHT;
uniform vec2 TextureSize;
struct UBO
{
    vec4 OutputSize;
    vec4 SourceSize;
};



struct Push
{
    float CURVATURE_X;
    float CURVATURE_Y;
    float MASK_BRIGHTNESS;
    float SCANLINE_WEIGHT;
    float SCANLINE_GAP_BRIGHTNESS;
    float BLOOM_FACTOR;
};



uniform sampler2D Texture;

varying float RA_VARYING_1;
varying vec2 RA_VARYING_0;

void main()
{
    do
    {
        vec2 _34 = vec2((CURVATURE_X), (CURVATURE_Y));
        vec2 _275 = RA_VARYING_0 - vec2(0.5);
        float _277 = _275.x;
        float _282 = _275.y;
        vec2 _296 = (_275 + (_275 * (_34 * ((_277 * _277) + (_282 * _282))))) * (vec2(1.0) - (_34 * 0.23000000417232513427734375));
        bool _300 = abs(_296.x) >= 0.5;
        bool _308;
        if (!_300)
        {
            _308 = abs(_296.y) >= 0.5;
        }
        else
        {
            _308 = _300;
        }
        vec2 _399;
        if (_308)
        {
            _399 = vec2(-1.0);
        }
        else
        {
            _399 = _296 + vec2(0.5);
        }
        if (_399.x < 0.0)
        {
            gl_FragData[0] = vec4(0.0);
            break;
        }
        vec2 _162 = _399 * (vec4(TextureSize, 1.0 / TextureSize)).xy;
        float _165 = _162.y;
        float _167 = floor(_165) + 0.5;
        float _179 = _165 - _167;
        float _325 = _179 - RA_VARYING_1;
        float _331 = _179 + RA_VARYING_1;
        float _188 = abs(_179);
        vec4 _219 = texture2D(Texture, vec2(_399.x, (_167 * (vec4(TextureSize, 1.0 / TextureSize)).w) + ((8.0 * ((_188 * _188) * _188)) * ((0.5 * (vec4(TextureSize, 1.0 / TextureSize)).w) * sign(_179)))));
        float _236 = fract((RA_VARYING_0.x * (vec4(OutputSize, 1.0 / OutputSize)).x) * 0.333333313465118408203125);
        vec3 _241 = vec3((MASK_BRIGHTNESS));
        vec3 _400;
        if (_236 < 0.333333313465118408203125)
        {
            vec3 _392 = _241;
            _392.x = 1.0;
            _400 = _392;
        }
        else
        {
            vec3 _401;
            if (_236 < 0.66666662693023681640625)
            {
                vec3 _394 = _241;
                _394.y = 1.0;
                _401 = _394;
            }
            else
            {
                vec3 _396 = _241;
                _396.z = 1.0;
                _401 = _396;
            }
            _400 = _401;
        }
        gl_FragData[0] = vec4((_219.xyz * ((((max(1.0 - ((_179 * _179) * (SCANLINE_WEIGHT)), (SCANLINE_GAP_BRIGHTNESS)) + max(1.0 - ((_325 * _325) * (SCANLINE_WEIGHT)), (SCANLINE_GAP_BRIGHTNESS))) + max(1.0 - ((_331 * _331) * (SCANLINE_WEIGHT)), (SCANLINE_GAP_BRIGHTNESS))) * 0.333333313465118408203125) * (BLOOM_FACTOR))) * _400, 1.0);
        break;
    } while(false);
}


#endif
