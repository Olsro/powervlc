// Generated from crt/shaders/gizmo-slotmask-crt.slang. See slang/upstream for licence/source.
#version 130
#pragma parameter CURVATURE_X "Screen curvature - horizontal"  0.10 0.0 1.0  0.01
#pragma parameter CURVATURE_Y "Screen curvature - vertical"    0.15 0.0 1.0  0.01
#pragma parameter BRIGHTNESS "Scanline Intensity"              0.5 0.05 1.0 0.05
#pragma parameter HORIZONTAL_BLUR "Horizontal Blur"            0.0 0.0 1.0 1.0
#pragma parameter VERTICAL_BLUR "Vertical Blur"                0.0 0.0 1.0 1.0
#pragma parameter BLUR_OFFSET "Blur Intensity"                 0.5 0.0 1.0 0.05
#pragma parameter BGR_LCD_PATTERN "BGR output pattern"         0.0 0.0 1.0 1.0
#pragma parameter SHRINK "Horizontal scale"                    0.0 0.0 1.0 0.01
#pragma parameter SNR "Noise intensity"                        1.0 0.0 2.0 0.1
#pragma parameter COLOUR_BLEEDING "Colour bleeding intensity"  0.0 0.0 3.0 0.1
#pragma parameter GRID "Grid intensity"                        0.0 0.0 3.0 0.05
#pragma parameter SLOTMASK "Use slot mask"                     0.0 0.0 1.0 1.0
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
uniform float COLOUR_BLEEDING;
uniform float CURVATURE_X;
uniform float CURVATURE_Y;
uniform int FrameCount;
uniform float GRID;
uniform float HORIZONTAL_BLUR;
uniform vec2 OutputSize;
uniform float SHRINK;
uniform float SLOTMASK;
uniform float SNR;
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
    float SNR;
    float COLOUR_BLEEDING;
    float GRID;
    float SLOTMASK;
};



uniform sampler2D Texture;

in vec2 RA_VARYING_0;
out vec4 FragColor;

void main()
{
    do
    {
        vec2 _90 = vec2((CURVATURE_X), (CURVATURE_Y));
        vec2 _623 = vec2(textureSize(Texture, 0));
        vec2 _627 = RA_VARYING_0;
        vec2 _1739;
        if ((SHRINK) > 0.0)
        {
            float _636 = _627.x - 0.5;
            vec2 _1680 = _627;
            _1680.x = _636;
            float _643 = _636 * (1.0 + (SHRINK));
            _1680.x = _643;
            _1680.x = _643 + 0.5;
            _1739 = _1680;
        }
        else
        {
            _1739 = _627;
        }
        vec2 _767 = _1739 - vec2(0.5);
        float _769 = _767.x;
        float _774 = _767.y;
        vec2 _788 = (_767 + (_767 * (_90 * ((_769 * _769) + (_774 * _774))))) * (vec2(1.0) - (_90 * 0.23000000417232513427734375));
        bool _792 = abs(_788.x) >= 0.5;
        bool _800;
        if (!_792)
        {
            _800 = abs(_788.y) >= 0.5;
        }
        else
        {
            _800 = _792;
        }
        vec2 _1741;
        if (_800)
        {
            _1741 = vec2(-1.0);
        }
        else
        {
            _1741 = _788 + vec2(0.5);
        }
        if (_1741.x < 0.0)
        {
            FragColor = vec4(0.0);
            break;
        }
        vec2 _667 = _1741 * (vec4(OutputSize, 1.0 / OutputSize)).xy;
        vec2 _673 = _623 / (vec4(OutputSize, 1.0 / OutputSize)).xy;
        float _812 = float((uint(FrameCount)));
        float _820 = _667.y + (sin(_812 * 5.502500057220458984375) * 0.100000001490116119384765625);
        vec2 _1696 = _667;
        _1696.y = _820;
        float _827 = _820 * _673.y;
        float _688 = _667.x;
        float _839 = 0.3333333432674407958984375 + (COLOUR_BLEEDING);
        vec3 _841 = vec3(_688);
        vec3 _1742;
        if ((BGR_LCD_PATTERN) == 1.0)
        {
            vec3 _1706 = _841;
            _1706.x = _688 + (_839 * 2.0);
            _1742 = _1706;
        }
        else
        {
            vec3 _1703 = _841;
            _1703.z = _688 + (_839 * 2.0);
            _1742 = _1703;
        }
        bool _922;
        vec3 _1709 = _1742;
        _1709.y = _1742.y + _839;
        vec3 _867 = _1709 * _673.x;
        vec2 _701 = vec2(_867.x / _623.x, _1741.y);
        vec2 _708 = vec2(_867.y, _827) / _623;
        vec2 _715 = vec2(_867.z, _827) / _623;
        vec4 _1613;
        do
        {
            vec2 _906 = vec2(textureSize(Texture, 0));
            vec2 _1001 = _701 * _906;
            vec2 _1005 = fwidth(_1001);
            vec2 _1011 = clamp(fract(_1001) / clamp(_1005, vec2(0.0), vec2(1.0)), vec2(0.0), vec2(1.0)) + floor(_1001);
            _922 = (HORIZONTAL_BLUR) == 1.0;
            if (_922)
            {
                float _931 = (-0.5) - (BLUR_OFFSET);
                vec4 _938 = texture(Texture, (_1011 + vec2(-0.5)) / _906);
                vec4 _941 = texture(Texture, (_1011 + vec2(_931, -0.5)) / _906);
                vec4 _945 = (_938 + _941) * vec4(0.5);
                vec4 _1612;
                if ((VERTICAL_BLUR) == 1.0)
                {
                    _1612 = (((texture(Texture, (_1011 + vec2(-0.5, _931)) / _906) + texture(Texture, (_1011 + vec2(_931)) / _906)) * vec4(0.5)) + _945) * vec4(0.5);
                }
                else
                {
                    _1612 = _945;
                }
                _1613 = _1612;
                break;
            }
            else
            {
                _1613 = texture(Texture, (_1011 + vec2(-0.5)) / _906);
                break;
            }
            break; // unreachable workaround
        } while(false);
        vec4 _1617;
        do
        {
            vec2 _1050 = vec2(textureSize(Texture, 0));
            vec2 _1145 = _708 * _1050;
            vec2 _1149 = fwidth(_1145);
            vec2 _1155 = clamp(fract(_1145) / clamp(_1149, vec2(0.0), vec2(1.0)), vec2(0.0), vec2(1.0)) + floor(_1145);
            if (_922)
            {
                float _1075 = (-0.5) - (BLUR_OFFSET);
                vec4 _1082 = texture(Texture, (_1155 + vec2(-0.5)) / _1050);
                vec4 _1085 = texture(Texture, (_1155 + vec2(_1075, -0.5)) / _1050);
                vec4 _1089 = (_1082 + _1085) * vec4(0.5);
                vec4 _1616;
                if ((VERTICAL_BLUR) == 1.0)
                {
                    _1616 = (((texture(Texture, (_1155 + vec2(-0.5, _1075)) / _1050) + texture(Texture, (_1155 + vec2(_1075)) / _1050)) * vec4(0.5)) + _1089) * vec4(0.5);
                }
                else
                {
                    _1616 = _1089;
                }
                _1617 = _1616;
                break;
            }
            else
            {
                _1617 = texture(Texture, (_1155 + vec2(-0.5)) / _1050);
                break;
            }
            break; // unreachable workaround
        } while(false);
        vec4 _1623;
        do
        {
            vec2 _1194 = vec2(textureSize(Texture, 0));
            vec2 _1289 = _715 * _1194;
            vec2 _1293 = fwidth(_1289);
            vec2 _1299 = clamp(fract(_1289) / clamp(_1293, vec2(0.0), vec2(1.0)), vec2(0.0), vec2(1.0)) + floor(_1289);
            if (_922)
            {
                float _1219 = (-0.5) - (BLUR_OFFSET);
                vec4 _1226 = texture(Texture, (_1299 + vec2(-0.5)) / _1194);
                vec4 _1229 = texture(Texture, (_1299 + vec2(_1219, -0.5)) / _1194);
                vec4 _1233 = (_1226 + _1229) * vec4(0.5);
                vec4 _1622;
                if ((VERTICAL_BLUR) == 1.0)
                {
                    _1622 = (((texture(Texture, (_1299 + vec2(-0.5, _1219)) / _1194) + texture(Texture, (_1299 + vec2(_1219)) / _1194)) * vec4(0.5)) + _1233) * vec4(0.5);
                }
                else
                {
                    _1622 = _1233;
                }
                _1623 = _1622;
                break;
            }
            else
            {
                _1623 = texture(Texture, (_1299 + vec2(-0.5)) / _1194);
                break;
            }
            break; // unreachable workaround
        } while(false);
        FragColor = vec4(_1613.x, _1617.y, _1623.z, 1.0);
        FragColor = clamp((FragColor + vec4(fract(tan(distance(_1696 * 1.61803400516510009765625, _1696) * sin(_812 * 0.02500000037252902984619140625)) * _688) * ((SNR) * 0.03125))) - vec4((SNR) * 0.015625), vec4(0.0), vec4(1.0));
        vec4 _729 = FragColor;
        vec2 _1426 = (_701 * vec2(textureSize(Texture, 0))) + vec2(0.5);
        vec2 _1431 = _1426 - floor(_1426);
        vec2 _1462 = (_708 * vec2(textureSize(Texture, 0))) + vec2(0.5);
        vec2 _1467 = _1462 - floor(_1462);
        vec2 _1498 = (_715 * vec2(textureSize(Texture, 0))) + vec2(0.5);
        vec2 _1503 = _1498 - floor(_1498);
        vec3 _1405 = _729.xyz - (abs(((vec3(1.0) - _729.xyz) * 1.5) * (vec3(0.5) - vec3(abs((((_1431 * _1431) * _1431) * ((_1431 * ((_1431 * 6.0) - vec2(15.0))) + vec2(10.0))).y - 0.5), abs((((_1467 * _1467) * _1467) * ((_1467 * ((_1467 * 6.0) - vec2(15.0))) + vec2(10.0))).y - 0.5), abs((((_1503 * _1503) * _1503) * ((_1503 * ((_1503 * 6.0) - vec2(15.0))) + vec2(10.0))).y - 0.5)))) * (0.02500000037252902984619140625 * (((vec4(OutputSize, 1.0 / OutputSize)).y / vec2(textureSize(Texture, 0)).y) / (BRIGHTNESS))));
        vec4 _1718 = _729;
        _1718.x = _1405.x;
        _1718.y = _1405.y;
        _1718.z = _1405.z;
        FragColor = _1718;
        float _1534 = (vec4(OutputSize, 1.0 / OutputSize)).x / vec2(textureSize(Texture, 0)).y;
        vec4 _1659;
        if (mod(floor(gl_FragCoord.x), 3.0) == 0.0)
        {
            _1659 = mix(FragColor, vec4(0.0, 0.0, 0.0, _1534 * 0.125), vec4((GRID)));
        }
        else
        {
            vec4 _1660;
            if ((SLOTMASK) == 1.0)
            {
                float _1559 = fract(gl_FragCoord.x * 0.16666667163372039794921875);
                bool _1564 = (_1559 >= 0.16599999368190765380859375) && (_1559 <= 0.5);
                bool _1574;
                if (_1564)
                {
                    _1574 = mod(floor(gl_FragCoord.y + 1.0), 3.0) == 0.0;
                }
                else
                {
                    _1574 = _1564;
                }
                bool _1592;
                if (!_1574)
                {
                    bool _1581 = (_1559 >= 0.66600000858306884765625) && (_1559 <= 1.0);
                    bool _1590;
                    if (_1581)
                    {
                        _1590 = mod(floor(gl_FragCoord.y), 3.0) == 0.0;
                    }
                    else
                    {
                        _1590 = _1581;
                    }
                    _1592 = _1590;
                }
                else
                {
                    _1592 = _1574;
                }
                vec4 _1661;
                if (_1592)
                {
                    _1661 = mix(FragColor, vec4(0.0, 0.0, 0.0, _1534 * 0.125), vec4((GRID) * 0.300000011920928955078125));
                }
                else
                {
                    _1661 = FragColor;
                }
                _1660 = _1661;
            }
            else
            {
                _1660 = FragColor;
            }
            _1659 = _1660;
        }
        FragColor = _1659;
        FragColor.w = 1.0;
        break;
    } while(false);
}


#endif
