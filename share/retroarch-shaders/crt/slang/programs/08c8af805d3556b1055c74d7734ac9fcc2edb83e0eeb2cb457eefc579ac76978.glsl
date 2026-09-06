// Generated from crt/shaders/metacrt/Image.slang. See slang/upstream for licence/source.
#version 130
#pragma parameter flip_image "Flip Image (for hardware-rendered cores)" 0.0 0.0 1.0 1.0
#ifdef VERTEX

uniform mat4 MVPMatrix;
uniform float flip_image;
struct UBO
{
    mat4 MVP;
};



struct Push
{
    float flip_image;
};



in vec4 VertexCoord;
out vec2 RA_VARYING_0;
in vec2 TexCoord;

void main()
{
    gl_Position = (MVPMatrix) * VertexCoord;
    vec2 _60;
    if ((flip_image) != 0.0)
    {
        _60 = vec2(TexCoord.x, 1.0 - TexCoord.y);
    }
    else
    {
        _60 = TexCoord;
    }
    RA_VARYING_0 = _60;
}


#endif
#ifdef FRAGMENT

uniform int FrameCount;
uniform vec2 OutputSize;
struct Push
{
    vec4 OutputSize;
    uint FrameCount;
};



uniform sampler2D Texture;

in vec2 RA_VARYING_0;
out vec4 FragColor;

void main()
{
    vec3 _617 = texelFetch(Texture, ivec2(0), 0).xyz;
    vec4 _648 = texelFetch(Texture, ivec2(1, 0), 0);
    vec4 _654 = texelFetch(Texture, ivec2(2, 0), 0);
    float _635 = _654.z;
    vec3 _666 = texelFetch(Texture, ivec2(3, 0), 0).xyz;
    vec4 _697 = texelFetch(Texture, ivec2(4, 0), 0);
    vec4 _386 = texelFetch(Texture, ivec2(RA_VARYING_0 * (vec4(OutputSize, 1.0 / OutputSize)).xy), 0);
    float _707 = max(0.0, _386.w);
    vec2 _730 = (RA_VARYING_0 * 2.0) - vec2(1.0);
    vec3 _750 = normalize(_648.xyz - _617);
    vec3 _753 = normalize(cross(vec3(0.0, 1.0, 0.0), _750));
    vec3 _803 = normalize(_697.xyz - _666);
    vec3 _806 = normalize(cross(vec3(0.0, 1.0, 0.0), _803));
    vec3 _783 = ((_617 + (normalize(mat3(_753, normalize(cross(_750, _753)), _750) * vec3(_730.x * ((vec4(OutputSize, 1.0 / OutputSize)).x / (vec4(OutputSize, 1.0 / OutputSize)).y), _730.y, 1.0 / tan(radians(_648.w)))) * _707)) - _666) * mat3(_806, normalize(cross(_803, _806)), _803);
    vec2 _793 = _783.xy / vec2(_783.z * tan(radians(_697.w)));
    _793.x = _793.x * ((vec4(OutputSize, 1.0 / OutputSize)).y / (vec4(OutputSize, 1.0 / OutputSize)).x);
    vec2 _842 = (_793 * 0.5) + vec2(0.5);
    float _851 = min(1.0, (_635 * _635) * 0.5);
    float _862 = _635 - 0.02999999932944774627685546875;
    float _865 = abs((_851 * (0.02999999932944774627685546875 * (_707 - _635))) / (_707 * _862));
    float _435 = max(0.001000000047497451305389404296875, _865);
    float _1013;
    vec3 _1014;
    _1014 = _386.xyz * _435;
    _1013 = _435;
    float _557;
    float _1026;
    vec3 _1027;
    int _1012 = 1;
    float _1015 = 0.0;
    for (; _1012 < 64; _1015 = _557, _1014 = _1027, _1013 = _1026, _1012++)
    {
        vec2 _872 = fract(vec2((((float((uint(FrameCount))) * 0.01666666753590106964111328125) + _1015) + RA_VARYING_0.x) + (RA_VARYING_0.y * 12.34500026702880859375)) * vec2(4.438974857330322265625, 3.9729731082916259765625));
        vec2 _881 = _872 + vec2(dot(_872.yx, _872 + vec2(19.1900005340576171875)));
        float _500 = _1015 * 2.3999626636505126953125;
        vec4 _523 = textureLod(Texture, mix(RA_VARYING_0, _842, vec2((fract(_881.x * _881.y) - 0.5) * 0.5)) + (vec2(sin(_500), cos(_500)) * ((_865 * sqrt(_1015)) * 0.125)), 0.0);
        float _891 = max(0.0, _523.w);
        if (_891 > 0.0)
        {
            float _544 = max(0.001000000047497451305389404296875, abs((_851 * (0.02999999932944774627685546875 * (_891 - _635))) / (_891 * _862)));
            _1027 = _1014 + (_523.xyz * _544);
            _1026 = _1013 + _544;
        }
        else
        {
            _1027 = _1014;
            _1026 = _1013;
        }
        _557 = _1015 + 1.0;
    }
    FragColor = vec4(_1014 / vec3(_1013), 1.0);
    vec4 _579 = FragColor;
    vec3 _581 = _579.xyz * pow(max(0.0, 1.0 - length(((RA_VARYING_0 - vec2(0.5)) * 1.41421353816986083984375) * 0.699999988079071044921875)), 2.0);
    FragColor.x = _581.x;
    FragColor.y = _581.y;
    FragColor.z = _581.z;
    vec4 _590 = FragColor;
    vec3 _948 = _590.xyz * 0.00999999977648258209228515625;
    vec3 _964 = (_590.xyz * (_948 + vec3(0.1319999992847442626953125))) / ((_590.xyz * (_948 + vec3(0.16300000250339508056640625))) + vec3(0.101000003516674041748046875));
    FragColor.x = _964.x;
    FragColor.y = _964.y;
    FragColor.z = _964.z;
    FragColor.w = 1.0;
}


#endif
