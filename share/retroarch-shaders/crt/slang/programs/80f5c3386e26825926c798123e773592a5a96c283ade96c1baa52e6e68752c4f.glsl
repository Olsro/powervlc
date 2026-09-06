// Generated from crt/shaders/crt-interlaced-halation/crt-interlaced-halation-pass2.slang. See slang/upstream for licence/source.
#version 130

#ifdef VERTEX

uniform mat4 MVPMatrix;
uniform vec2 OutputSize;
uniform vec2 Pass1TextureSize;
uniform vec2 TextureSize;
struct UBO
{
    mat4 MVP;
};



struct Push
{
    vec4 SourceSize;
    vec4 crt_interlaced_halation_refpassSize;
    vec4 OutputSize;
};



in vec4 VertexCoord;
out vec2 RA_VARYING_0;
in vec2 TexCoord;
out vec2 RA_VARYING_5;
out vec2 RA_VARYING_6;
out vec3 RA_VARYING_4;
out vec2 RA_VARYING_3;
out vec2 RA_VARYING_1;
out float RA_VARYING_2;

void main()
{
    gl_Position = (MVPMatrix) * VertexCoord;
    RA_VARYING_0 = TexCoord;
    RA_VARYING_5 = vec2(0.0);
    RA_VARYING_6 = vec2(1.0);
    vec2 _472 = (RA_VARYING_5 * (-2.0)) / vec2(1.0 + (RA_VARYING_6.x * RA_VARYING_6.y));
    float _642 = dot(_472, _472) + 4.0;
    float _659 = (2.0 * (dot(_472, RA_VARYING_5) - ((2.0 * RA_VARYING_6.x) * RA_VARYING_6.y))) - 4.0;
    vec2 _575 = ((vec2(((_659 * (-2.0)) - sqrt((4.0 * (_659 * _659)) - ((4.0 * _642) * (4.0 + ((8.0 * RA_VARYING_6.x) * RA_VARYING_6.y))))) / (2.0 * _642)) * _472) - (vec2(-2.0) * RA_VARYING_5)) * vec2(0.5);
    vec2 _578 = RA_VARYING_5 / RA_VARYING_6;
    vec2 _581 = _575 / RA_VARYING_6;
    float _585 = dot(_578, _578) + 1.0;
    float _588 = dot(_581, _578);
    float _608 = ((_588 * 2.0) + sqrt((4.0 * (_588 * _588)) - ((4.0 * _585) * (dot(_581, _581) - 1.0)))) / (2.0 * _585);
    float _621 = max(abs(2.0 * acos(_608)), 9.9999997473787516355514526367188e-06);
    vec2 _630 = (((_575 - (RA_VARYING_5 * _608)) / RA_VARYING_6) * _621) / vec2(sin(_621 * 0.5));
    float _482 = _630.y;
    vec2 _483 = vec2(-0.5, _482);
    float _700 = max(abs(sqrt(dot(_483, _483))), 9.9999997473787516355514526367188e-06);
    float _703 = _700 * 0.5;
    vec2 _708 = _483 * (sin(_703) / _700);
    float _713 = 1.0 - cos(_703);
    float _489 = _630.x;
    vec2 _493 = vec2(_489, -0.375);
    float _751 = max(abs(sqrt(dot(_493, _493))), 9.9999997473787516355514526367188e-06);
    float _754 = _751 * 0.5;
    vec2 _759 = _493 * (sin(_754) / _751);
    float _764 = 1.0 - cos(_754);
    vec2 _500 = vec2(((((_708 * RA_VARYING_6) - (RA_VARYING_5 * _713)) * 2.0) / vec2((1.0 + ((_713 * RA_VARYING_6.x) * RA_VARYING_6.y)) + dot(_708, RA_VARYING_5))).x, ((((_759 * RA_VARYING_6) - (RA_VARYING_5 * _764)) * 2.0) / vec2((1.0 + ((_764 * RA_VARYING_6.x) * RA_VARYING_6.y)) + dot(_759, RA_VARYING_5))).y) * vec2(1.0, 1.33333337306976318359375);
    vec2 _505 = vec2(0.5, _482);
    float _802 = max(abs(sqrt(dot(_505, _505))), 9.9999997473787516355514526367188e-06);
    float _805 = _802 * 0.5;
    vec2 _810 = _505 * (sin(_805) / _802);
    float _815 = 1.0 - cos(_805);
    vec2 _514 = vec2(_489, 0.375);
    float _853 = max(abs(sqrt(dot(_514, _514))), 9.9999997473787516355514526367188e-06);
    float _856 = _853 * 0.5;
    vec2 _861 = _514 * (sin(_856) / _853);
    float _866 = 1.0 - cos(_856);
    vec2 _521 = vec2(((((_810 * RA_VARYING_6) - (RA_VARYING_5 * _815)) * 2.0) / vec2((1.0 + ((_815 * RA_VARYING_6.x) * RA_VARYING_6.y)) + dot(_810, RA_VARYING_5))).x, ((((_861 * RA_VARYING_6) - (RA_VARYING_5 * _866)) * 2.0) / vec2((1.0 + ((_866 * RA_VARYING_6.x) * RA_VARYING_6.y)) + dot(_861, RA_VARYING_5))).y) * vec2(1.0, 1.33333337306976318359375);
    RA_VARYING_4 = vec3(((_521 + _500) * vec2(1.0, 0.75)) * 0.5, max(_521.x - _500.x, _521.y - _500.y));
    RA_VARYING_3 = vec2(1.0, clamp(floor((vec4(TextureSize, 1.0 / TextureSize)).y * 0.004999999888241291046142578125), 1.0, 2.0));
    RA_VARYING_1 = RA_VARYING_3 / (vec4(Pass1TextureSize, 1.0 / Pass1TextureSize)).xy;
    RA_VARYING_2 = ((RA_VARYING_0.x * (vec4(Pass1TextureSize, 1.0 / Pass1TextureSize)).x) * (vec4(OutputSize, 1.0 / OutputSize)).x) / (vec4(Pass1TextureSize, 1.0 / Pass1TextureSize)).x;
}


#endif
#ifdef FRAGMENT

uniform int FrameCount;
uniform vec2 TextureSize;
struct Push
{
    vec4 SourceSize;
    uint FrameCount;
};



uniform sampler2D Pass1Texture;
uniform sampler2D Texture;

in vec2 RA_VARYING_0;
in vec3 RA_VARYING_4;
in vec2 RA_VARYING_5;
in vec2 RA_VARYING_6;
in vec2 RA_VARYING_3;
in vec2 RA_VARYING_1;
in float RA_VARYING_2;
out vec4 FragColor;

void main()
{
    vec2 _248 = (((RA_VARYING_0 - vec2(0.5)) * vec2(1.0, 0.75)) * RA_VARYING_4.z) + RA_VARYING_4.xy;
    float _705 = dot(_248, _248) + 4.0;
    float _722 = (2.0 * (dot(_248, RA_VARYING_5) - ((2.0 * RA_VARYING_6.x) * RA_VARYING_6.y))) - 4.0;
    vec2 _638 = ((vec2(((_722 * (-2.0)) - sqrt((4.0 * (_722 * _722)) - ((4.0 * _705) * (4.0 + ((8.0 * RA_VARYING_6.x) * RA_VARYING_6.y))))) / (2.0 * _705)) * _248) - (vec2(-2.0) * RA_VARYING_5)) * vec2(0.5);
    vec2 _641 = RA_VARYING_5 / RA_VARYING_6;
    vec2 _644 = _638 / RA_VARYING_6;
    float _648 = dot(_641, _641) + 1.0;
    float _651 = dot(_644, _641);
    float _671 = ((_651 * 2.0) + sqrt((4.0 * (_651 * _651)) - ((4.0 * _648) * (dot(_644, _644) - 1.0)))) / (2.0 * _648);
    float _684 = max(abs(2.0 * acos(_671)), 9.9999997473787516355514526367188e-06);
    vec2 _262 = ((((_638 - (RA_VARYING_5 * _671)) / RA_VARYING_6) * _684) / vec2(sin(_684 * 0.5))) * vec2(1.0, 1.33333337306976318359375);
    vec2 _263 = _262 + vec2(0.5);
    vec2 _284 = vec2(0.00999999977648258209228515625) - min(min(_263, vec2(0.5) - _262) * vec2(1.0, 0.75), vec2(0.00999999977648258209228515625));
    float _795;
    if (RA_VARYING_3.y > 1.5)
    {
        _795 = mod(float((uint(FrameCount))), 2.0);
    }
    else
    {
        _795 = 0.0;
    }
    vec2 _331 = vec2(0.0, _795);
    vec2 _344 = (((_263 * (vec4(TextureSize, 1.0 / TextureSize)).xy) - vec2(0.5)) + _331) / RA_VARYING_3;
    vec2 _347 = fract(_344);
    vec2 _358 = (((floor(_344) * RA_VARYING_3) + vec2(0.5)) - _331) / (vec4(TextureSize, 1.0 / TextureSize)).xy;
    float _362 = _347.x;
    vec4 _377 = max(abs(vec4(1.0 + _362, _362, 1.0 - _362, 2.0 - _362) * 3.1415927410125732421875), vec4(9.9999997473787516355514526367188e-06));
    vec4 _389 = ((sin(_377) * 2.0) * sin(_377 * vec4(0.5))) / (_377 * _377);
    vec4 _395 = _389 / vec4(dot(_389, vec4(1.0)));
    float _406 = -RA_VARYING_1.x;
    float _433 = 2.0 * RA_VARYING_1.x;
    vec4 _466 = clamp(mat4(pow(texture(Pass1Texture, _358 + vec2(_406, 0.0)), vec4(2.400000095367431640625)), pow(texture(Pass1Texture, _358), vec4(2.400000095367431640625)), pow(texture(Pass1Texture, _358 + vec2(RA_VARYING_1.x, 0.0)), vec4(2.400000095367431640625)), pow(texture(Pass1Texture, _358 + vec2(_433, 0.0)), vec4(2.400000095367431640625))) * _395, vec4(0.0), vec4(1.0));
    vec4 _537 = clamp(mat4(pow(texture(Pass1Texture, _358 + vec2(_406, RA_VARYING_1.y)), vec4(2.400000095367431640625)), pow(texture(Pass1Texture, _358 + vec2(0.0, RA_VARYING_1.y)), vec4(2.400000095367431640625)), pow(texture(Pass1Texture, _358 + RA_VARYING_1), vec4(2.400000095367431640625)), pow(texture(Pass1Texture, _358 + vec2(_433, RA_VARYING_1.y)), vec4(2.400000095367431640625))) * _395, vec4(0.0), vec4(1.0));
    float _541 = _347.y;
    vec4 _761 = vec4(0.300000011920928955078125) + (pow(_466, vec4(3.0)) * 0.100000001490116119384765625);
    vec4 _765 = vec4(_541) / _761;
    vec4 _782 = vec4(0.300000011920928955078125) + (pow(_537, vec4(3.0)) * 0.100000001490116119384765625);
    vec4 _786 = vec4(1.0 - _541) / _782;
    FragColor = vec4(pow(((((_466 * ((exp((-_765) * _765) * 0.4000000059604644775390625) / _761)) + (_537 * ((exp((-_786) * _786) * 0.4000000059604644775390625) / _782))).xyz + (pow(texture(Texture, _263).xyz, vec3(2.2000000476837158203125)) * 0.100000001490116119384765625)) * vec3(clamp((0.00999999977648258209228515625 - sqrt(dot(_284, _284))) * 800.0, 0.0, 1.0))) * mix(vec3(1.0), vec3(1.0), vec3(floor(mod(RA_VARYING_2, 2.0)))), vec3(0.454545438289642333984375)), 1.0);
}


#endif
