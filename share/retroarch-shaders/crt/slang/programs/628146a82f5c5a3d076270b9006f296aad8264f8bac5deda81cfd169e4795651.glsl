// Generated from crt/shaders/crt-beans/composite_output.slang. See slang/upstream for licence/source.
#version 130
#pragma parameter OutputGamma "Output gamma (0: sRGB, 1: 2.2 gamma)" 1.0 0.0 1.0 1.0
#pragma parameter OverscanHorizontal "Horizontal overscan (proportion to crop)" 0.0 0.0 0.1 0.01
#pragma parameter OverscanVertical "Vertical overscan (proportion to crop)" 0.0 0.0 0.1 0.01
#pragma parameter MaxSpotSize "Maximum spot size (proportion of scanline)" 0.90 0.6 1.0 0.05
#pragma parameter MinSpotSize "Minimum spot size (proportion of maximum)" 0.4 0.3 1.0 0.1
#pragma parameter MaskType "Mask type (0: disabled, 1: subpixel, 2: dynamic)" 2.0 0.0 2.0 1.0
#pragma parameter SubpixelPattern "Monitor subpixel pattern (0: RGB, 1: BGR)" 0.0 0.0 1.0 1.0
#pragma parameter SubpixelMaskPattern "Subpixel mask width (pixels per triad)" 4.0 2.0 5.0 1.0
#pragma parameter DynamicMaskTriads "Dynamic mask phosphor triads (per screen width)" 550.0 400.0 800.0 25.0
#pragma parameter GlowSigma "Glow width (proportion of screen height)" 0.05 0.01 0.10 0.01
#pragma parameter GlowAmount "Glow amount (mix ratio)" 0.04 0.0 0.10 0.005
#ifdef VERTEX

uniform mat4 MVPMatrix;
struct UBO
{
    mat4 MVP;
};



in vec4 VertexCoord;
out vec2 RA_VARYING_0;
in vec2 TexCoord;

void main()
{
    gl_Position = (MVPMatrix) * VertexCoord;
    RA_VARYING_0 = TexCoord;
}


#endif
#ifdef FRAGMENT

uniform int FrameCount;
uniform float GlowAmount;
uniform float OutputGamma;
uniform vec2 Pass3TextureSize;
struct Push
{
    float OutputGamma;
    vec4 ScanlinesSize;
    uint FrameCount;
    float GlowAmount;
};



uniform sampler2D BlueNoiseTex;
uniform sampler2D Texture;
uniform sampler2D Pass3Texture;

in vec2 RA_VARYING_0;
out vec4 FragColor;

void main()
{
    ivec2 _246 = ivec2(floor(RA_VARYING_0 * (vec4(Pass3TextureSize, 1.0 / Pass3TextureSize)).xy));
    vec3 _262 = mix(texelFetch(Pass3Texture, _246, 0).xyz, textureLod(Texture, RA_VARYING_0, 0.0).xyz, vec3((GlowAmount)));
    vec3 _476;
    if ((OutputGamma) < 0.5)
    {
        vec3 _345 = clamp(_262, vec3(0.0), vec3(1.0));
        bvec3 _347 = lessThan(_345, vec3(0.003130800090730190277099609375));
        vec3 _349 = _345 * vec3(12.9200000762939453125);
        vec3 _353 = (vec3(1.05499994754791259765625) * pow(_345, vec3(0.4166666567325592041015625))) - vec3(0.054999999701976776123046875);
        vec3 _321 = floor(vec3(_347.x ? _349.x : _353.x, _347.y ? _349.y : _353.y, _347.z ? _349.z : _353.z) * vec3(254.9999847412109375)) * 0.0039215688593685626983642578125;
        vec3 _324 = _321 + vec3(0.0039215688593685626983642578125);
        vec3 _366 = clamp(_321, vec3(0.0), vec3(1.0));
        bvec3 _368 = lessThan(_366, vec3(0.040449999272823333740234375));
        vec3 _371 = _366 * vec3(0.077399380505084991455078125);
        vec3 _377 = pow((_366 + vec3(0.054999999701976776123046875)) * vec3(0.947867333889007568359375), vec3(2.400000095367431640625));
        vec3 _390 = clamp(_324, vec3(0.0), vec3(1.0));
        bvec3 _392 = lessThan(_390, vec3(0.040449999272823333740234375));
        vec3 _395 = _390 * vec3(0.077399380505084991455078125);
        vec3 _401 = pow((_390 + vec3(0.054999999701976776123046875)) * vec3(0.947867333889007568359375), vec3(2.400000095367431640625));
        bvec3 _335 = lessThan(mix(vec3(_368.x ? _371.x : _377.x, _368.y ? _371.y : _377.y, _368.z ? _371.z : _377.z), vec3(_392.x ? _395.x : _401.x, _392.y ? _395.y : _401.y, _392.z ? _395.z : _401.z), texelFetch(BlueNoiseTex, (_246 + (ivec2(int((uint(FrameCount)) & 63u)) * ivec2(17, 13))) & ivec2(63), 0).xyz), _262);
        _476 = vec3(_335.x ? _324.x : _321.x, _335.y ? _324.y : _321.y, _335.z ? _324.z : _321.z);
    }
    else
    {
        vec3 _436 = floor(pow(clamp(_262, vec3(0.0), vec3(1.0)), vec3(0.4545454680919647216796875)) * vec3(254.9999847412109375)) * 0.0039215688593685626983642578125;
        vec3 _439 = _436 + vec3(0.0039215688593685626983642578125);
        bvec3 _450 = lessThan(mix(pow(clamp(_436, vec3(0.0), vec3(1.0)), vec3(2.2000000476837158203125)), pow(clamp(_439, vec3(0.0), vec3(1.0)), vec3(2.2000000476837158203125)), texelFetch(BlueNoiseTex, (_246 + (ivec2(int((uint(FrameCount)) & 63u)) * ivec2(17, 13))) & ivec2(63), 0).xyz), _262);
        _476 = vec3(_450.x ? _439.x : _436.x, _450.y ? _439.y : _436.y, _450.z ? _439.z : _436.z);
    }
    FragColor = vec4(_476, 1.0);
}


#endif
