// Generated from crt/shaders/crt-super-xbr/super-xbr-pass1.slang. See slang/upstream for licence/source.
#version 120
#pragma parameter XBR_EDGE_STR_P1 "Xbr - Edge Strength p1" 1.0 0.0 5.0 0.5
#pragma parameter MODE "Mode - Normal, Details, Adaptive" 1.0 0.0 2.0 1.0
#pragma parameter XBR_EDGE_SHP "Adaptive Dynamic Edge Sharp" 0.4 0.0 3.0 0.1
#pragma parameter XBR_TEXTURE_SHP "Adaptive Static Edge Sharp" 1.0 0.0 2.0 0.1
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
    RA_VARYING_0 = TexCoord * 1.00010001659393310546875;
}


#endif
#ifdef FRAGMENT

uniform float MODE;
uniform vec2 TextureSize;
uniform float XBR_EDGE_SHP;
uniform float XBR_EDGE_STR_P1;
uniform float XBR_TEXTURE_SHP;
struct Push
{
    vec4 SourceSize;
    float MODE;
    float XBR_EDGE_SHP;
    float XBR_TEXTURE_SHP;
    float XBR_EDGE_STR_P1;
};



uniform sampler2D Pass1Texture;
uniform sampler2D Texture;

varying vec2 RA_VARYING_0;

void main()
{
    float _1913 = ((MODE) == 1.0) ? 1.0 : 8.0;
    vec2 _325 = fract(RA_VARYING_0 * (vec4(TextureSize, 1.0 / TextureSize)).xy);
    vec2 _330 = _325 - vec2(0.5);
    float _333 = _330.x;
    if ((_333 * _330.y) > 0.0)
    {
        gl_FragData[0] = mix(texture2D(Pass1Texture, RA_VARYING_0), texture2D(Texture, RA_VARYING_0), vec4(step(0.0, _333)));
    }
    else
    {
        bool _363 = _325.x > 0.5;
        vec2 _1855;
        if (_363)
        {
            _1855 = vec2(0.5 / (vec4(TextureSize, 1.0 / TextureSize)).x, 0.0);
        }
        else
        {
            _1855 = vec2(0.0, 0.5 / (vec4(TextureSize, 1.0 / TextureSize)).y);
        }
        vec2 _1856;
        if (_363)
        {
            _1856 = vec2(0.0, 0.5 / (vec4(TextureSize, 1.0 / TextureSize)).y);
        }
        else
        {
            _1856 = vec2(0.5 / (vec4(TextureSize, 1.0 / TextureSize)).x, 0.0);
        }
        vec2 _399 = _1855 * 3.0;
        vec4 _401 = texture2D(Pass1Texture, RA_VARYING_0 - _399);
        vec3 _402 = _401.xyz;
        vec2 _407 = _1856 * 3.0;
        vec4 _409 = texture2D(Texture, RA_VARYING_0 - _407);
        vec3 _410 = _409.xyz;
        vec4 _417 = texture2D(Texture, RA_VARYING_0 + _407);
        vec3 _418 = _417.xyz;
        vec4 _425 = texture2D(Pass1Texture, RA_VARYING_0 + _399);
        vec3 _426 = _425.xyz;
        vec2 _431 = _1855 * 2.0;
        vec2 _432 = RA_VARYING_0 - _431;
        vec4 _435 = texture2D(Texture, _432 - _1856);
        vec3 _436 = _435.xyz;
        vec2 _441 = RA_VARYING_0 - _1855;
        vec2 _443 = _1856 * 2.0;
        vec4 _445 = texture2D(Pass1Texture, _441 - _443);
        vec3 _446 = _445.xyz;
        vec4 _455 = texture2D(Texture, _432 + _1856);
        vec3 _456 = _455.xyz;
        vec4 _462 = texture2D(Pass1Texture, _441);
        vec3 _463 = _462.xyz;
        vec4 _469 = texture2D(Texture, RA_VARYING_0 - _1856);
        vec3 _470 = _469.xyz;
        vec4 _479 = texture2D(Pass1Texture, _441 + _443);
        vec3 _480 = _479.xyz;
        vec4 _486 = texture2D(Texture, RA_VARYING_0 + _1856);
        vec3 _487 = _486.xyz;
        vec2 _492 = RA_VARYING_0 + _1855;
        vec4 _493 = texture2D(Pass1Texture, _492);
        vec3 _494 = _493.xyz;
        vec4 _503 = texture2D(Pass1Texture, _492 - _443);
        vec3 _504 = _503.xyz;
        vec2 _510 = RA_VARYING_0 + _431;
        vec4 _513 = texture2D(Texture, _510 - _1856);
        vec3 _514 = _513.xyz;
        vec4 _523 = texture2D(Pass1Texture, _492 + _443);
        vec3 _524 = _523.xyz;
        vec4 _533 = texture2D(Texture, _510 + _1856);
        vec3 _534 = _533.xyz;
        float _1139 = dot(_436, vec3(0.2125999927520751953125, 0.715200006961822509765625, 0.072200000286102294921875));
        float _1143 = dot(_446, vec3(0.2125999927520751953125, 0.715200006961822509765625, 0.072200000286102294921875));
        float _1147 = dot(_456, vec3(0.2125999927520751953125, 0.715200006961822509765625, 0.072200000286102294921875));
        float _1151 = dot(_463, vec3(0.2125999927520751953125, 0.715200006961822509765625, 0.072200000286102294921875));
        float _1155 = dot(_470, vec3(0.2125999927520751953125, 0.715200006961822509765625, 0.072200000286102294921875));
        float _1159 = dot(_480, vec3(0.2125999927520751953125, 0.715200006961822509765625, 0.072200000286102294921875));
        float _1163 = dot(_487, vec3(0.2125999927520751953125, 0.715200006961822509765625, 0.072200000286102294921875));
        float _1167 = dot(_494, vec3(0.2125999927520751953125, 0.715200006961822509765625, 0.072200000286102294921875));
        float _1171 = dot(_514, vec3(0.2125999927520751953125, 0.715200006961822509765625, 0.072200000286102294921875));
        float _1179 = dot(_534, vec3(0.2125999927520751953125, 0.715200006961822509765625, 0.072200000286102294921875));
        float _1187 = dot(_524, vec3(0.2125999927520751953125, 0.715200006961822509765625, 0.072200000286102294921875));
        float _1195 = dot(_504, vec3(0.2125999927520751953125, 0.715200006961822509765625, 0.072200000286102294921875));
        float _682 = _1913 * ((((abs(_1151 - _1143) + abs(_1151 - _1159)) + abs(_1167 - _1187)) + abs(_1167 - _1195)) - (((abs(_1155 - _1171) + abs(_1155 - _1139)) + abs(_1163 - _1147)) + abs(_1163 - _1179)));
        vec4 _1894;
        vec3 _1900;
        vec3 _1901;
        if ((MODE) == 2.0)
        {
            float _813 = (smoothstep(0.0, 0.60000002384185791015625, max(max(abs(_1151 - _1155), max(abs(_1151 - _1167), max(abs(_1151 - _1163), abs(_1155 - _1163)))), max(abs(_1155 - _1167), abs(_1163 - _1167))) / (_1151 + 0.001000000047497451305389404296875)) * (XBR_EDGE_SHP)) + (XBR_TEXTURE_SHP);
            float _829 = _813 * (-0.12963299453258514404296875);
            float _831 = (0.12963299453258514404296875 * _813) + 0.5;
            float _839 = _813 * (-0.087534002959728240966796875);
            float _842 = (0.087534002959728240966796875 * _813) + 0.25;
            vec4 _847 = vec4(_839, _842, _842, _839);
            _1901 = (mat4x3((_402 + ((_446 + _436) * 2.0)) + _410, (_456 + ((_470 + _463) * 2.0)) + _504, (_480 + ((_494 + _487) * 2.0)) + _514, (_418 + ((_534 + _524) * 2.0)) + _426) * _847) * vec3(0.3333333432674407958984375);
            _1900 = (mat4x3((_402 + ((_456 + _480) * 2.0)) + _418, (_436 + ((_463 + _487) * 2.0)) + _524, (_446 + ((_470 + _494) * 2.0)) + _534, (_410 + ((_504 + _514) * 2.0)) + _426) * _847) * vec3(0.3333333432674407958984375);
            _1894 = vec4(_829, _831, _831, _829);
        }
        else
        {
            _1901 = mat4x3(_446 + _436, _470 + _463, _494 + _487, _534 + _524) * vec4(-0.087534002959728240966796875, 0.337534010410308837890625, 0.337534010410308837890625, -0.087534002959728240966796875);
            _1900 = mat4x3(_456 + _480, _463 + _487, _470 + _494, _504 + _514) * vec4(-0.087534002959728240966796875, 0.337534010410308837890625, 0.337534010410308837890625, -0.087534002959728240966796875);
            _1894 = vec4(-0.12963299453258514404296875, 0.629633009433746337890625, 0.629633009433746337890625, -0.12963299453258514404296875);
        }
        vec3 _1126 = clamp(mix(mix(mat4x3(vec3(_417.xyz), vec3(_486.xyz), vec3(_469.xyz), vec3(_409.xyz)) * _1894, mat4x3(vec3(_401.xyz), vec3(_462.xyz), vec3(_493.xyz), vec3(_425.xyz)) * _1894, vec3(step(0.0, _682))), mix(_1900, _1901, vec3(step(0.0, _1913 * ((((abs(_1155 - _1143) + abs(_1167 - _1179)) + abs(_1151 - _1139)) + abs(_1163 - _1187)) - (((abs(_1151 - _1147) + abs(_1155 - _1195)) + abs(_1163 - _1159)) + abs(_1167 - _1171)))))), vec3(1.0 - smoothstep(0.0, (XBR_EDGE_STR_P1) + 9.9999999747524270787835121154785e-07, abs(_682)))), min(_463, min(_470, min(_487, _494))), max(_463, max(_470, max(_487, _494))));
        gl_FragData[0] = vec4(_1126, 1.0);
    }
}


#endif
