// Generated from crt/shaders/metacrt/bufD.slang. See slang/upstream for licence/source.
#version 130

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
uniform vec2 OutputSize;
struct Push
{
    vec4 OutputSize;
    uint FrameCount;
};



uniform sampler2D Texture;
uniform sampler2D cubeMap;

in vec2 RA_VARYING_0;
out vec4 FragColor;

void main()
{
    vec4 _679 = texelFetch(Texture, ivec2(0), 0);
    vec3 _654 = _679.xyz;
    vec4 _685 = texelFetch(Texture, ivec2(1, 0), 0);
    vec4 _691 = texelFetch(Texture, ivec2(2, 0), 0);
    vec4 _728 = texelFetch(cubeMap, ivec2(0), 0);
    vec3 _703 = _728.xyz;
    vec4 _734 = texelFetch(cubeMap, ivec2(1, 0), 0);
    vec2 _401 = RA_VARYING_0 * (vec4(OutputSize, 1.0 / OutputSize)).xy;
    FragColor = textureLod(Texture, RA_VARYING_0 - (_691.xy / (vec4(OutputSize, 1.0 / OutputSize)).xy), 0.0);
    vec2 _763 = (RA_VARYING_0 * 2.0) - vec2(1.0);
    vec3 _783 = normalize(_685.xyz - _654);
    vec3 _786 = normalize(cross(vec3(0.0, 1.0, 0.0), _783));
    ivec2 _436 = ivec2(_401);
    vec3 _840 = normalize(_734.xyz - _703);
    vec3 _843 = normalize(cross(vec3(0.0, 1.0, 0.0), _840));
    vec3 _820 = ((_654 + (normalize(mat3(_786, normalize(cross(_783, _786)), _783) * vec3(_763.x * ((vec4(OutputSize, 1.0 / OutputSize)).x / (vec4(OutputSize, 1.0 / OutputSize)).y), _763.y, 1.0 / tan(radians(_685.w)))) * max(0.0, texelFetch(Texture, _436, 0).w))) - _703) * mat3(_843, normalize(cross(_840, _843)), _840);
    vec2 _830 = _820.xy / vec2(_820.z * tan(radians(_734.w)));
    _830.x = _830.x * ((vec4(OutputSize, 1.0 / OutputSize)).y / (vec4(OutputSize, 1.0 / OutputSize)).x);
    vec2 _879 = (_830 * 0.5) + vec2(0.5);
    bool _461 = all(greaterThanEqual(_879, vec2(0.0)));
    bool _468;
    if (_461)
    {
        _468 = all(lessThan(_879, vec2(1.0)));
    }
    else
    {
        _468 = _461;
    }
    if (_468)
    {
        ivec2 _484 = ivec2(floor(_401));
        int _1224;
        vec3 _1226;
        vec3 _1227;
        _1227 = vec3(-10000.0);
        _1226 = vec3(10000.0);
        _1224 = -1;
        vec3 _1289;
        vec3 _1290;
        for (; _1224 <= 1; _1227 = _1290, _1226 = _1289, _1224++)
        {
            _1290 = _1227;
            _1289 = _1226;
            for (int _1284 = -1; _1284 <= 1; )
            {
                vec3 _520 = texelFetch(Texture, _484 + ivec2(_1284, _1224), 0).xyz;
                vec3 _895 = _520 * 0.00999999977648258209228515625;
                vec3 _911 = (_520 * (_895 + vec3(0.1319999992847442626953125))) / ((_520 * (_895 + vec3(0.16300000250339508056640625))) + vec3(0.101000003516674041748046875));
                _1290 = max(_1290, _911);
                _1289 = min(_1289, _911);
                _1284++;
                continue;
            }
        }
        vec3 _550 = textureLod(cubeMap, _879, 0.0).xyz;
        vec3 _927 = _550 * 0.00999999977648258209228515625;
        vec3 _943 = (_550 * (_927 + vec3(0.1319999992847442626953125))) / ((_550 * (_927 + vec3(0.16300000250339508056640625))) + vec3(0.101000003516674041748046875));
        bool _556 = all(greaterThanEqual(_943, _1226 - vec3(0.001000000047497451305389404296875)));
        bool _563;
        if (_556)
        {
            _563 = all(lessThanEqual(_943, _1227 + vec3(0.001000000047497451305389404296875)));
        }
        else
        {
            _563 = _556;
        }
        vec4 _567 = FragColor;
        vec3 _573 = mix(_567.xyz, _550, vec3(_563 ? 0.89999997615814208984375 : 0.0));
        FragColor.x = _573.x;
        FragColor.y = _573.y;
        FragColor.z = _573.z;
    }
    vec3 _948 = fract(vec3(_401, float((uint(FrameCount))) * 0.01666666753590106964111328125) * 443.897491455078125);
    vec3 _957 = _948 + vec3(dot(_948, _948.yzx + vec3(19.1900005340576171875)));
    vec4 _601 = FragColor;
    vec3 _604 = _601.xyz + vec3(((fract((_957.x + _957.y) * _957.z) * 2.0) - 1.0) * 0.02999999932944774627685546875);
    FragColor.x = _604.x;
    FragColor.y = _604.y;
    FragColor.z = _604.z;
    vec4 _986 = vec4(_679.xyz, 0.0);
    bvec4 _1022 = bvec4(all(equal(_436, ivec2(0))));
    vec4 _1023 = vec4(_1022.x ? _986.x : FragColor.x, _1022.y ? _986.y : FragColor.y, _1022.z ? _986.z : FragColor.z, _1022.w ? _986.w : FragColor.w);
    bvec4 _1039 = bvec4(all(equal(_436, ivec2(1, 0))));
    vec4 _1040 = vec4(_1039.x ? _685.x : _1023.x, _1039.y ? _685.y : _1023.y, _1039.z ? _685.z : _1023.z, _1039.w ? _685.w : _1023.w);
    vec4 _1009 = vec4(_691.xyz, 0.0);
    bvec4 _1055 = bvec4(all(equal(_436, ivec2(2, 0))));
    FragColor = vec4(_1055.x ? _1009.x : _1040.x, _1055.y ? _1009.y : _1040.y, _1055.z ? _1009.z : _1040.z, _1055.w ? _1009.w : _1040.w);
    vec4 _1082 = vec4(_728.xyz, 0.0);
    bvec4 _1118 = bvec4(all(equal(_436, ivec2(3, 0))));
    vec4 _1119 = vec4(_1118.x ? _1082.x : FragColor.x, _1118.y ? _1082.y : FragColor.y, _1118.z ? _1082.z : FragColor.z, _1118.w ? _1082.w : FragColor.w);
    bvec4 _1134 = bvec4(all(equal(_436, ivec2(4, 0))));
    vec4 _1135 = vec4(_1134.x ? _734.x : _1119.x, _1134.y ? _734.y : _1119.y, _1134.z ? _734.z : _1119.z, _1134.w ? _734.w : _1119.w);
    vec4 _1105 = vec4(texelFetch(cubeMap, ivec2(2, 0), 0).xyz, 0.0);
    bvec4 _1150 = bvec4(all(equal(_436, ivec2(5, 0))));
    FragColor = vec4(_1150.x ? _1105.x : _1135.x, _1150.y ? _1105.y : _1135.y, _1150.z ? _1105.z : _1135.z, _1150.w ? _1105.w : _1135.w);
}


#endif
