// Generated from crt/shaders/yee64.slang. See slang/upstream for licence/source.
#version 120
#pragma parameter viewSizeHD "Min Dimming Res" 720.0 0.0 2190.0 1.0
#pragma parameter brightness "CRT Brightness" 1.5 0.0 5.0 0.1
#pragma parameter intensityR "Red Dimming Intensity" 1.2 0.0 2.0 0.1
#pragma parameter intensityG "Green Dimming Intensity" 0.9 0.0 2.0 0.1
#pragma parameter intensityB "Blue Dimming Intensity" 0.9 0.0 2.0 0.1
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

uniform vec2 OrigTextureSize;
uniform vec2 RAViewportSize;
uniform vec2 TextureSize;
uniform float brightness;
uniform float intensityB;
uniform float intensityG;
uniform float intensityR;
uniform float viewSizeHD;
struct UBO
{
    vec4 FinalViewportSize;
};



struct Push
{
    float viewSizeHD;
    float brightness;
    float intensityR;
    float intensityG;
    float intensityB;
    vec4 SourceSize;
    vec4 OriginalSize;
};



uniform sampler2D Texture;

varying vec2 RA_VARYING_0;

void main()
{
    vec2 _50 = ((vec4(TextureSize, 1.0 / TextureSize)).xy / (vec4(OrigTextureSize, 1.0 / OrigTextureSize)).xy) * RA_VARYING_0;
    vec4 _59 = ((vec4(OrigTextureSize, 1.0 / OrigTextureSize)).xy / (vec4(TextureSize, 1.0 / TextureSize)).xy).xyxy * _50.xyxy;
    vec2 _64 = _59.zw * (vec4(TextureSize, 1.0 / TextureSize)).xy;
    vec2 _69 = floor(_64);
    vec2 _74 = (_64 - _69) + vec2(-0.5);
    float _83 = _74.x;
    float _88 = pow(2.0, pow((-1.0) - _83, 2.0) * (-3.0));
    float _96 = pow(2.0, pow(1.0 - _83, 2.0) * (-3.0));
    float _105 = pow(2.0, pow((-2.0) - _83, 2.0) * (-3.0));
    float _113 = pow(2.0, pow(2.0 - _83, 2.0) * (-3.0));
    float _121 = pow(2.0, pow(_83, 2.0) * (-3.0));
    float _127 = _74.y;
    vec2 _156 = floor(_50 * (vec4(RAViewportSize, 1.0 / RAViewportSize)).xy) + vec2(0.5);
    float _167 = fract(((_156.y * 3.0) + _156.x) * 0.16666699945926666259765625);
    vec4 _622;
    if (_167 < 0.333000004291534423828125)
    {
        vec4 _576 = vec4(0.0);
        _576.x = (intensityR);
        _576.y = (intensityG);
        _576.z = (intensityB);
        _622 = _576;
    }
    else
    {
        vec4 _623;
        if (_167 < 0.66600000858306884765625)
        {
            vec4 _582 = vec4(0.0);
            _582.x = (intensityB);
            _582.y = (intensityR);
            _582.z = (intensityG);
            _623 = _582;
        }
        else
        {
            vec4 _588 = vec4(0.0);
            _588.x = (intensityG);
            _588.y = (intensityB);
            _588.z = (intensityR);
            _623 = _588;
        }
        _622 = _623;
    }
    vec3 _491 = vec3((_96 + _88) + _121);
    vec3 _493 = ((((((((texture2D(Texture, (floor(_64 + vec2(-2.0, 0.0)) + vec2(0.5)) / (vec4(TextureSize, 1.0 / TextureSize)).xy).xyz * _105) * (brightness)) + ((texture2D(Texture, (floor(_64 + vec2(-1.0, 0.0)) + vec2(0.5)) / (vec4(TextureSize, 1.0 / TextureSize)).xy).xyz * _88) * (brightness))) + ((texture2D(Texture, (floor(_64 + vec2(1.0, 0.0)) + vec2(0.5)) / (vec4(TextureSize, 1.0 / TextureSize)).xy).xyz * _96) * (brightness))) + ((texture2D(Texture, (_69 + vec2(0.5)) / (vec4(TextureSize, 1.0 / TextureSize)).xy).xyz * _121) * (brightness))) + ((texture2D(Texture, (floor(_64 + vec2(2.0, 0.0)) + vec2(0.5)) / (vec4(TextureSize, 1.0 / TextureSize)).xy).xyz * _113) * (brightness))) * pow(2.0, pow(_127, 2.0) * (-8.0))) / vec3((((_105 + _88) + _96) + _121) + _113)) + ((((((texture2D(Texture, (floor(_64 + vec2(1.0, -1.0)) + vec2(0.5)) / (vec4(TextureSize, 1.0 / TextureSize)).xy).xyz * _96) * (brightness)) + ((texture2D(Texture, (floor(_64 + vec2(-1.0)) + vec2(0.5)) / (vec4(TextureSize, 1.0 / TextureSize)).xy).xyz * _88) * (brightness))) + ((texture2D(Texture, (floor(_64 + vec2(0.0, -1.0)) + vec2(0.5)) / (vec4(TextureSize, 1.0 / TextureSize)).xy).xyz * _121) * (brightness))) * pow(2.0, pow((-1.0) - _127, 2.0) * (-8.0))) / _491);
    vec3 _511 = _493 + ((((((texture2D(Texture, (floor(_64 + vec2(1.0)) + vec2(0.5)) / (vec4(TextureSize, 1.0 / TextureSize)).xy).xyz * _96) * (brightness)) + ((texture2D(Texture, (floor(_64 + vec2(-1.0, 1.0)) + vec2(0.5)) / (vec4(TextureSize, 1.0 / TextureSize)).xy).xyz * _88) * (brightness))) + ((texture2D(Texture, (floor((_59.xy * (vec4(TextureSize, 1.0 / TextureSize)).xy) + vec2(0.0, 1.0)) + vec2(0.5)) / (vec4(TextureSize, 1.0 / TextureSize)).xy).xyz * _121) * (brightness))) * pow(2.0, pow(1.0 - _127, 2.0) * (-8.0))) / _491);
    vec3 _545;
    if ((viewSizeHD) < (vec4(RAViewportSize, 1.0 / RAViewportSize)).y)
    {
        _545 = _622.xyz * _511;
    }
    else
    {
        _545 = _511;
    }
    gl_FragData[0] = vec4(_545, 1.0);
}


#endif
