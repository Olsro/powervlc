// Generated from crt/shaders/gtu-v050/pass3.slang. See slang/upstream for licence/source.
#version 120
#pragma parameter noScanlines "No Scanlines" 0.0 0.0 1.0 1.0
#pragma parameter tvVerticalResolution "TV Vertical Resolution" 250.0 20.0 1000.0 10.0
#pragma parameter blackLevel "Black Level" 0.07 -0.30 0.30 0.01
#pragma parameter contrast "Contrast" 1.0 0.0 2.0 0.1
#pragma parameter compositeConnection "Composite Connection Enable" 0.0 0.0 1.0 1.0
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

uniform vec2 OutputSize;
uniform vec2 TextureSize;
uniform float blackLevel;
uniform float contrast;
uniform float noScanlines;
uniform float tvVerticalResolution;
struct Push
{
    vec4 OutputSize;
    vec4 SourceSize;
    float noScanlines;
    float tvVerticalResolution;
    float blackLevel;
    float contrast;
};



uniform sampler2D Texture;

varying vec2 RA_VARYING_0;

void main()
{
    vec2 _158 = fract((RA_VARYING_0 * (vec4(TextureSize, 1.0 / TextureSize)).xy) - vec2(0.5));
    float _169 = ceil(0.5 + ((vec4(TextureSize, 1.0 / TextureSize)).y / (tvVerticalResolution)));
    vec3 _676;
    if ((noScanlines) > 0.0)
    {
        float _179 = -_169;
        vec3 _677;
        _677 = vec3(0.0);
        for (float _674 = _179; _674 < (_169 + 2.0); )
        {
            float _203 = _158.y - _674;
            float _216 = (tvVerticalResolution) * (vec4(TextureSize, 1.0 / TextureSize)).w;
            float _217 = 3.1415927410125732421875 * _216;
            float _222 = abs(_203);
            float _229 = 1.0 / _216;
            float _231 = _217 * min(_222 + 0.5, _229);
            float _281 = _217 * min(max(_222 - 0.5, (-1.0) / _216), _229);
            _677 += (texture2D(Texture, vec2(RA_VARYING_0.x, RA_VARYING_0.y - (_203 * (vec4(TextureSize, 1.0 / TextureSize)).w))).xyz * ((((_231 + sin(_231)) - _281) - sin(_281)) * 0.15915493667125701904296875));
            _674 += 1.0;
            continue;
        }
        _676 = _677;
    }
    else
    {
        float _321 = -_169;
        vec3 _673;
        _673 = vec3(0.0);
        for (float _671 = _321; _671 < (_169 + 2.0); )
        {
            float _334 = _158.y - _671;
            vec4 _349 = texture2D(Texture, vec2(RA_VARYING_0.x, RA_VARYING_0.y - (_334 * (vec4(TextureSize, 1.0 / TextureSize)).w)));
            float _403 = 2.5066282749176025390625 * ((tvVerticalResolution) * (vec4(TextureSize, 1.0 / TextureSize)).w);
            float _409 = 0.5 * ((vec4(TextureSize, 1.0 / TextureSize)).y * (vec4(OutputSize, 1.0 / OutputSize)).w);
            float _414 = (_334 + _409) * _403;
            float _419 = (_334 - _409) * _403;
            float _466 = 1.0 + (0.3326700031757354736328125 * abs(_414));
            float _467 = 1.0 / _466;
            float _502 = 1.0 + (0.3326700031757354736328125 * abs(_419));
            float _503 = 1.0 / _502;
            float _426 = ((0.5 - ((exp(((-_414) * _414) * 0.5) * 0.398942291736602783203125) * (_467 * (0.4361836016178131103515625 + (_467 * ((-0.12016759812831878662109375) + (0.937297999858856201171875 / _466))))))) * sign(_414)) - ((0.5 - ((exp(((-_419) * _419) * 0.5) * 0.398942291736602783203125) * (_503 * (0.4361836016178131103515625 + (_503 * ((-0.12016759812831878662109375) + (0.937297999858856201171875 / _502))))))) * sign(_419));
            _673 += (vec3(_349.x * _426, _349.y * _426, _349.z * _426) * ((vec4(OutputSize, 1.0 / OutputSize)).y * (vec4(TextureSize, 1.0 / TextureSize)).w));
            _671 += 1.0;
            continue;
        }
        _676 = _673;
    }
    gl_FragData[0] = vec4((_676 - vec3((blackLevel))) * (vec3((contrast)) / vec3(1.0 - (blackLevel))), 1.0);
}


#endif
