// Generated from crt/shaders/gizmo-crt.slang. See slang/upstream for licence/source.
#version 130
#pragma parameter CURVATURE_X "Screen curvature - horizontal"  0.10 0.0 1.0  0.01
#pragma parameter CURVATURE_Y "Screen curvature - vertical"    0.15 0.0 1.0  0.01
#pragma parameter BRIGHTNESS "Scanline Intensity"              0.5 0.05 1.0 0.05
#pragma parameter HORIZONTAL_BLUR "Horizontal Blur"            0.0 0.0 1.0 1.0
#pragma parameter VERTICAL_BLUR "Vertical Blur"                0.0 0.0 1.0 1.0
#pragma parameter BLUR_OFFSET "Blur Intensity"                 0.5 0.0 1.0 0.05
#pragma parameter BGR_LCD_PATTERN "BGR output pattern"         0.0 0.0 1.0 1.0
#pragma parameter SHRINK "Shrink screen"                       0.0 0.0 1.0 0.05
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

uniform float BGR_LCD_PATTERN;
uniform float BLUR_OFFSET;
uniform float BRIGHTNESS;
uniform float CURVATURE_X;
uniform float CURVATURE_Y;
uniform int FrameCount;
uniform float HORIZONTAL_BLUR;
uniform vec2 OutputSize;
uniform float SHRINK;
uniform float VERTICAL_BLUR;
struct Push
{
    vec4 OutputSize;
    uint FrameCount;
    float CURVATURE_X;
    float CURVATURE_Y;
    float BRIGHTNESS;
    float HORIZONTAL_BLUR;
    float VERTICAL_BLUR;
    float BLUR_OFFSET;
    float BGR_LCD_PATTERN;
    float SHRINK;
};



uniform sampler2D Texture;

in vec2 RA_VARYING_0;
out vec4 FragColor;

void main()
{
    do
    {
        vec2 _80 = vec2((CURVATURE_X), (CURVATURE_Y));
        vec2 _486 = vec2(textureSize(Texture, 0));
        vec2 _490 = RA_VARYING_0;
        vec2 _1361;
        if ((SHRINK) > 0.0)
        {
            float _499 = _490.y - 0.5;
            vec2 _1314 = _490;
            _1314.y = _499;
            float _506 = _499 * (1.0 + (SHRINK));
            _1314.y = _506;
            _1314.y = _506 + 0.5;
            _1361 = _1314;
        }
        else
        {
            _1361 = _490;
        }
        vec2 _615 = _1361 - vec2(0.5);
        float _617 = _615.x;
        float _622 = _615.y;
        vec2 _636 = (_615 + (_615 * (_80 * ((_617 * _617) + (_622 * _622))))) * (vec2(1.0) - (_80 * 0.23000000417232513427734375));
        bool _640 = abs(_636.x) >= 0.5;
        bool _648;
        if (!_640)
        {
            _648 = abs(_636.y) >= 0.5;
        }
        else
        {
            _648 = _640;
        }
        vec2 _1363;
        if (_648)
        {
            _1363 = vec2(-1.0);
        }
        else
        {
            _1363 = _636 + vec2(0.5);
        }
        if (_1363.x < 0.0)
        {
            FragColor = vec4(0.0);
            break;
        }
        vec2 _530 = _1363 * (vec4(OutputSize, 1.0 / OutputSize)).xy;
        vec2 _536 = _486 / (vec4(OutputSize, 1.0 / OutputSize)).xy;
        float _659 = _530.y * _536.y;
        float _548 = _530.x;
        vec3 _670 = vec3(_548);
        vec3 _1364;
        if ((BGR_LCD_PATTERN) == 1.0)
        {
            vec3 _1337 = _670;
            _1337.x = _548 + 0.66600000858306884765625;
            _1364 = _1337;
        }
        else
        {
            vec3 _1334 = _670;
            _1334.z = _548 + 0.66600000858306884765625;
            _1364 = _1334;
        }
        bool _751;
        vec3 _1340 = _1364;
        _1340.y = _1364.y + 0.333000004291534423828125;
        vec3 _696 = _1340 * _536.x;
        vec2 _561 = vec2(_696.x / _486.x, _1363.y);
        vec4 _1271;
        do
        {
            vec2 _735 = vec2(textureSize(Texture, 0));
            vec2 _830 = _561 * _735;
            vec2 _834 = fwidth(_830);
            vec2 _840 = clamp(fract(_830) / clamp(_834, vec2(0.0), vec2(1.0)), vec2(0.0), vec2(1.0)) + floor(_830);
            _751 = (HORIZONTAL_BLUR) == 1.0;
            if (_751)
            {
                float _760 = (-0.5) + (BLUR_OFFSET);
                vec4 _767 = texture(Texture, (_840 + vec2(-0.5)) / _735);
                vec4 _770 = texture(Texture, (_840 + vec2(_760, -0.5)) / _735);
                vec4 _774 = (_767 + _770) * vec4(0.5);
                vec4 _1270;
                if ((VERTICAL_BLUR) == 1.0)
                {
                    _1270 = (((texture(Texture, (_840 + vec2(-0.5, _760)) / _735) + texture(Texture, (_840 + vec2(_760)) / _735)) * vec4(0.5)) + _774) * vec4(0.5);
                }
                else
                {
                    _1270 = _774;
                }
                _1271 = _1270;
                break;
            }
            else
            {
                _1271 = texture(Texture, (_840 + vec2(-0.5)) / _735);
                break;
            }
            break; // unreachable workaround
        } while(false);
        vec4 _1275;
        do
        {
            vec2 _879 = vec2(textureSize(Texture, 0));
            vec2 _974 = (vec2(_696.y, _659) / _486) * _879;
            vec2 _978 = fwidth(_974);
            vec2 _984 = clamp(fract(_974) / clamp(_978, vec2(0.0), vec2(1.0)), vec2(0.0), vec2(1.0)) + floor(_974);
            if (_751)
            {
                float _904 = (-0.5) + (BLUR_OFFSET);
                vec4 _911 = texture(Texture, (_984 + vec2(-0.5)) / _879);
                vec4 _914 = texture(Texture, (_984 + vec2(_904, -0.5)) / _879);
                vec4 _918 = (_911 + _914) * vec4(0.5);
                vec4 _1274;
                if ((VERTICAL_BLUR) == 1.0)
                {
                    _1274 = (((texture(Texture, (_984 + vec2(-0.5, _904)) / _879) + texture(Texture, (_984 + vec2(_904)) / _879)) * vec4(0.5)) + _918) * vec4(0.5);
                }
                else
                {
                    _1274 = _918;
                }
                _1275 = _1274;
                break;
            }
            else
            {
                _1275 = texture(Texture, (_984 + vec2(-0.5)) / _879);
                break;
            }
            break; // unreachable workaround
        } while(false);
        vec4 _1281;
        do
        {
            vec2 _1023 = vec2(textureSize(Texture, 0));
            vec2 _1118 = (vec2(_696.z, _659) / _486) * _1023;
            vec2 _1122 = fwidth(_1118);
            vec2 _1128 = clamp(fract(_1118) / clamp(_1122, vec2(0.0), vec2(1.0)), vec2(0.0), vec2(1.0)) + floor(_1118);
            if (_751)
            {
                float _1048 = (-0.5) + (BLUR_OFFSET);
                vec4 _1055 = texture(Texture, (_1128 + vec2(-0.5)) / _1023);
                vec4 _1058 = texture(Texture, (_1128 + vec2(_1048, -0.5)) / _1023);
                vec4 _1062 = (_1055 + _1058) * vec4(0.5);
                vec4 _1280;
                if ((VERTICAL_BLUR) == 1.0)
                {
                    _1280 = (((texture(Texture, (_1128 + vec2(-0.5, _1048)) / _1023) + texture(Texture, (_1128 + vec2(_1048)) / _1023)) * vec4(0.5)) + _1062) * vec4(0.5);
                }
                else
                {
                    _1280 = _1062;
                }
                _1281 = _1280;
                break;
            }
            else
            {
                _1281 = texture(Texture, (_1128 + vec2(-0.5)) / _1023);
                break;
            }
            break; // unreachable workaround
        } while(false);
        FragColor = vec4(_1271.x, _1275.y, _1281.z, 255.0);
        FragColor = clamp((FragColor + vec4(fract(tan(distance(_530 * 1.61803400516510009765625, _530) * sin(float((uint(FrameCount))) * 0.02500000037252902984619140625)) * _548) * 0.03125)) - vec4(0.015625), vec4(0.0), vec4(1.0));
        vec4 _589 = FragColor;
        vec2 _1242 = (_561 * vec2(textureSize(Texture, 0))) + vec2(0.5);
        vec2 _1247 = _1242 - floor(_1242);
        vec3 _1221 = _589.xyz - (abs(((vec3(1.0) - _589.xyz) * 1.5) * abs(abs(abs((((_1247 * _1247) * _1247) * ((_1247 * ((_1247 * 6.0) - vec2(15.0))) + vec2(10.0))).y - 0.5) - 0.5))) * (0.02500000037252902984619140625 * (((vec4(OutputSize, 1.0 / OutputSize)).y / vec2(textureSize(Texture, 0)).y) / (BRIGHTNESS))));
        vec4 _1349 = _589;
        _1349.x = _1221.x;
        _1349.y = _1221.y;
        _1349.z = _1221.z;
        FragColor = _1349;
        FragColor.w = 1.0;
        break;
    } while(false);
}


#endif
