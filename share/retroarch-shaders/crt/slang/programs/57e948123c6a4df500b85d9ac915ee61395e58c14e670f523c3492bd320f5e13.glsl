// Generated from crt/shaders/hyllian/support/ntsc/shaders/ntsc-adaptive-lite/ntsc-lite-pass2.slang. See slang/upstream for licence/source.
#version 120
#pragma parameter chroma_scale "    Chroma Scaling"                  1.0 0.2 4.0 0.1 
#pragma parameter ntsc_scale   "    Resolution Scaling"              1.0 0.20 3.0 0.05
#pragma parameter ntsc_phase   "    Phase: Auto | 2 phase | 3 phase" 1.0 1.0 3.0 1.0
#pragma parameter linearize    "    Linearize Output Gamma"          0.0 0.0 1.0 1.0 
#ifdef VERTEX

uniform mat4 MVPMatrix;
uniform vec2 TextureSize;
struct UBO
{
    mat4 MVP;
    vec4 SourceSize;
};



attribute vec4 VertexCoord;
varying vec2 RA_VARYING_0;
attribute vec2 TexCoord;

void main()
{
    gl_Position = (MVPMatrix) * VertexCoord;
    RA_VARYING_0 = TexCoord - vec2(0.5 / (vec4(TextureSize, 1.0 / TextureSize)).x, 0.0);
}


#endif
#ifdef FRAGMENT

uniform vec2 OrigTextureSize;
uniform vec2 TextureSize;
uniform float chroma_scale;
uniform float linearize;
uniform float ntsc_phase;
uniform float ntsc_scale;
const float _486[25] = float[](-1.2020303074677940458059310913086e-05, -2.21465597860515117645263671875e-05, -1.3155332453607115894556045532227e-05, -1.2020303074677940458059310913086e-05, -4.9980262701865285634994506835938e-05, -0.00011394287867005914449691772460938, -0.000122153083793818950653076171875, -5.6121398301911540329456329345703e-06, 0.00017052030307240784168243408203125, 0.00023720499302726238965988159179688, 0.00016964427777566015720367431640625, 0.00028569521964527666568756103515625, 0.000984598882496356964111328125, 0.002018733881413936614990234375, 0.00200232560746371746063232421875, -0.000909904949367046356201171875, -0.0070492587983608245849609375, -0.013223193585872650146484375, -0.012607249431312084197998046875, 0.002460922114551067352294921875, 0.035869129002094268798828125, 0.08401857316493988037109375, 0.1355669200420379638671875, 0.17526568472385406494140625, 0.1901813447475433349609375);
const float _517[25] = float[](-0.00013574105105362832546234130859375, -0.000568115734495222568511962890625, -0.001306056859903037548065185546875, -0.00231369934044778347015380859375, -0.00350569677539169788360595703125, -0.00474731065332889556884765625, -0.0058598020114004611968994140625, -0.006631140597164630889892578125, -0.00683148391544818878173828125, -0.006232350133359432220458984375, -0.0046279276721179485321044921875, -0.001856654300354421138763427734375, 0.00217899004928767681121826171875, 0.00749647803604602813720703125, 0.014022787101566791534423828125, 0.0215908624231815338134765625, 0.02994374372065067291259765625, 0.0387464463710784912109375, 0.0476049743592739105224609375, 0.0560911484062671661376953125, 0.0637713372707366943359375, 0.070236839354038238525390625, 0.07513330876827239990234375, 0.078186847269535064697265625, 0.07922442257404327392578125);

struct UBO
{
    vec4 OriginalSize;
    vec4 SourceSize;
    float linearize;
    float ntsc_scale;
    float ntsc_phase;
    float chroma_scale;
};



uniform sampler2D Texture;

varying vec2 RA_VARYING_0;

void main()
{
    do
    {
        float _1520;
        if ((ntsc_phase) < 1.5)
        {
            _1520 = ((vec4(OrigTextureSize, 1.0 / OrigTextureSize)).x > 300.0) ? 2.0 : 3.0;
        }
        else
        {
            _1520 = ((ntsc_phase) > 2.5) ? 3.0 : 2.0;
        }
        bool _119 = _1520 > 2.5;
        float _1521;
        if (_119)
        {
            _1521 = min((chroma_scale), 2.2000000476837158203125);
        }
        else
        {
            _1521 = (chroma_scale) * 0.5;
        }
        vec2 _142 = vec2(1.0, 1.0 / _1521) * ((vec4(TextureSize, 1.0 / TextureSize)).z / (ntsc_scale));
        vec3 _1530;
        if (_1520 < 2.5)
        {
            float _595 = _142.x;
            float _606 = _142.y;
            vec3 _219 = ((((vec3(texture2D(Texture, RA_VARYING_0 + vec2((-15.0) * _595, 0.0)).x, texture2D(Texture, RA_VARYING_0 + vec2((-15.0) * _606, 0.0)).yz) + vec3(texture2D(Texture, RA_VARYING_0 + vec2(15.0 * _595, 0.0)).x, texture2D(Texture, RA_VARYING_0 + vec2(15.0 * _606, 0.0)).yz)) * vec3(0.001343728625215590000152587890625, 0.00406084768474102020263671875, 0.00406084768474102020263671875)) + ((vec3(texture2D(Texture, RA_VARYING_0 + vec2((-14.0) * _595, 0.0)).x, texture2D(Texture, RA_VARYING_0 + vec2((-14.0) * _606, 0.0)).yz) + vec3(texture2D(Texture, RA_VARYING_0 + vec2(14.0 * _595, 0.0)).x, texture2D(Texture, RA_VARYING_0 + vec2(14.0 * _606, 0.0)).yz)) * vec3(0.0029423166997730731964111328125, 0.005785736255347728729248046875, 0.005785736255347728729248046875))) + ((vec3(texture2D(Texture, RA_VARYING_0 + vec2((-13.0) * _595, 0.0)).x, texture2D(Texture, RA_VARYING_0 + vec2((-13.0) * _606, 0.0)).yz) + vec3(texture2D(Texture, RA_VARYING_0 + vec2(13.0 * _595, 0.0)).x, texture2D(Texture, RA_VARYING_0 + vec2(13.0 * _606, 0.0)).yz)) * vec3(0.00399617664515972137451171875, 0.008044474758207798004150390625, 0.008044474758207798004150390625))) + ((vec3(texture2D(Texture, RA_VARYING_0 + vec2((-12.0) * _595, 0.0)).x, texture2D(Texture, RA_VARYING_0 + vec2((-12.0) * _606, 0.0)).yz) + vec3(texture2D(Texture, RA_VARYING_0 + vec2(12.0 * _595, 0.0)).x, texture2D(Texture, RA_VARYING_0 + vec2(12.0 * _606, 0.0)).yz)) * vec3(0.0030363262630999088287353515625, 0.010915254242718219757080078125, 0.010915254242718219757080078125));
            vec3 _291 = (((_219 + ((vec3(texture2D(Texture, RA_VARYING_0 + vec2((-11.0) * _595, 0.0)).x, texture2D(Texture, RA_VARYING_0 + vec2((-11.0) * _606, 0.0)).yz) + vec3(texture2D(Texture, RA_VARYING_0 + vec2(11.0 * _595, 0.0)).x, texture2D(Texture, RA_VARYING_0 + vec2(11.0 * _606, 0.0)).yz)) * vec3(-0.001105567323975265026092529296875, 0.0144533030688762664794921875, 0.0144533030688762664794921875))) + ((vec3(texture2D(Texture, RA_VARYING_0 + vec2((-10.0) * _595, 0.0)).x, texture2D(Texture, RA_VARYING_0 + vec2((-10.0) * _606, 0.0)).yz) + vec3(texture2D(Texture, RA_VARYING_0 + vec2(10.0 * _595, 0.0)).x, texture2D(Texture, RA_VARYING_0 + vec2(10.0 * _606, 0.0)).yz)) * vec3(-0.008399703539907932281494140625, 0.018676586449146270751953125, 0.018676586449146270751953125))) + ((vec3(texture2D(Texture, RA_VARYING_0 + vec2((-9.0) * _595, 0.0)).x, texture2D(Texture, RA_VARYING_0 + vec2((-9.0) * _606, 0.0)).yz) + vec3(texture2D(Texture, RA_VARYING_0 + vec2(9.0 * _595, 0.0)).x, texture2D(Texture, RA_VARYING_0 + vec2(9.0 * _606, 0.0)).yz)) * vec3(-0.016951538622379302978515625, 0.02355184592306613922119140625, 0.02355184592306613922119140625))) + ((vec3(texture2D(Texture, RA_VARYING_0 + vec2((-8.0) * _595, 0.0)).x, texture2D(Texture, RA_VARYING_0 + vec2((-8.0) * _606, 0.0)).yz) + vec3(texture2D(Texture, RA_VARYING_0 + vec2(8.0 * _595, 0.0)).x, texture2D(Texture, RA_VARYING_0 + vec2(8.0 * _606, 0.0)).yz)) * vec3(-0.0229874886572360992431640625, 0.028983414173126220703125, 0.028983414173126220703125));
            vec3 _363 = (((_291 + ((vec3(texture2D(Texture, RA_VARYING_0 + vec2((-7.0) * _595, 0.0)).x, texture2D(Texture, RA_VARYING_0 + vec2((-7.0) * _606, 0.0)).yz) + vec3(texture2D(Texture, RA_VARYING_0 + vec2(7.0 * _595, 0.0)).x, texture2D(Texture, RA_VARYING_0 + vec2(7.0 * _606, 0.0)).yz)) * vec3(-0.0217113010585308074951171875, 0.0348073728382587432861328125, 0.0348073728382587432861328125))) + ((vec3(texture2D(Texture, RA_VARYING_0 + vec2((-6.0) * _595, 0.0)).x, texture2D(Texture, RA_VARYING_0 + vec2((-6.0) * _606, 0.0)).yz) + vec3(texture2D(Texture, RA_VARYING_0 + vec2(6.0 * _595, 0.0)).x, texture2D(Texture, RA_VARYING_0 + vec2(6.0 * _606, 0.0)).yz)) * vec3(-0.008891512639820575714111328125, 0.0407934151589870452880859375, 0.0407934151589870452880859375))) + ((vec3(texture2D(Texture, RA_VARYING_0 + vec2((-5.0) * _595, 0.0)).x, texture2D(Texture, RA_VARYING_0 + vec2((-5.0) * _606, 0.0)).yz) + vec3(texture2D(Texture, RA_VARYING_0 + vec2(5.0 * _595, 0.0)).x, texture2D(Texture, RA_VARYING_0 + vec2(5.0 * _606, 0.0)).yz)) * vec3(0.017326988279819488525390625, 0.046655833721160888671875, 0.046655833721160888671875))) + ((vec3(texture2D(Texture, RA_VARYING_0 + vec2((-4.0) * _595, 0.0)).x, texture2D(Texture, RA_VARYING_0 + vec2((-4.0) * _606, 0.0)).yz) + vec3(texture2D(Texture, RA_VARYING_0 + vec2(4.0 * _595, 0.0)).x, texture2D(Texture, RA_VARYING_0 + vec2(4.0 * _606, 0.0)).yz)) * vec3(0.0550969056785106658935546875, 0.0520737655460834503173828125, 0.0520737655460834503173828125));
            vec3 _424 = (((_363 + ((vec3(texture2D(Texture, RA_VARYING_0 + vec2((-3.0) * _595, 0.0)).x, texture2D(Texture, RA_VARYING_0 + vec2((-3.0) * _606, 0.0)).yz) + vec3(texture2D(Texture, RA_VARYING_0 + vec2(3.0 * _595, 0.0)).x, texture2D(Texture, RA_VARYING_0 + vec2(3.0 * _606, 0.0)).yz)) * vec3(0.0986559092998504638671875, 0.0567190684378147125244140625, 0.0567190684378147125244140625))) + ((vec3(texture2D(Texture, RA_VARYING_0 + vec2((-2.0) * _595, 0.0)).x, texture2D(Texture, RA_VARYING_0 + vec2((-2.0) * _606, 0.0)).yz) + vec3(texture2D(Texture, RA_VARYING_0 + vec2(2.0 * _595, 0.0)).x, texture2D(Texture, RA_VARYING_0 + vec2(2.0 * _606, 0.0)).yz)) * vec3(0.1394872963428497314453125, 0.0602887570858001708984375, 0.0602887570858001708984375))) + ((vec3(texture2D(Texture, RA_VARYING_0 + vec2((-1.0) * _595, 0.0)).x, texture2D(Texture, RA_VARYING_0 + vec2((-1.0) * _606, 0.0)).yz) + vec3(texture2D(Texture, RA_VARYING_0 + vec2(_595, 0.0)).x, texture2D(Texture, RA_VARYING_0 + vec2(_606, 0.0)).yz)) * vec3(0.16859127581119537353515625, 0.0625375211238861083984375, 0.0625375211238861083984375))) + (texture2D(Texture, RA_VARYING_0).xyz * vec3(0.17914037406444549560546875, 0.06330560147762298583984375, 0.06330560147762298583984375));
            _1530 = _424;
        }
        else
        {
            vec3 _1531;
            if (_119)
            {
                vec3 _1526;
                _1526 = vec3(0.0);
                for (int _1525 = 0; _1525 < 24; )
                {
                    float _443 = float(_1525);
                    float _447 = _443 - 24.0;
                    float _1465 = _142.x;
                    float _1476 = _142.y;
                    float _453 = 24.0 - _443;
                    _1526 += ((vec3(texture2D(Texture, RA_VARYING_0 + vec2(_447 * _1465, 0.0)).x, texture2D(Texture, RA_VARYING_0 + vec2(_447 * _1476, 0.0)).yz) + vec3(texture2D(Texture, RA_VARYING_0 + vec2(_453 * _1465, 0.0)).x, texture2D(Texture, RA_VARYING_0 + vec2(_453 * _1476, 0.0)).yz)) * vec3(_486[_1525], _517[_1525], _517[_1525]));
                    _1525++;
                    continue;
                }
                _1531 = _1526 + (texture2D(Texture, RA_VARYING_0).xyz * vec3(0.1901813447475433349609375, 0.07922442257404327392578125, 0.07922442257404327392578125));
            }
            else
            {
                _1531 = vec3(0.0);
            }
            _1530 = _1531;
        }
        gl_FragData[0] = vec4(_1530 * mat3(vec3(1.0, 0.95599997043609619140625, 0.620999991893768310546875), vec3(1.0, -0.272000014781951904296875, -0.64740002155303955078125), vec3(1.0, -1.10599994659423828125, 1.70459997653961181640625)), 1.0);
        if ((linearize) < 0.5)
        {
            break;
        }
        gl_FragData[0] = pow(gl_FragData[0], vec4(2.2000000476837158203125));
        break;
    } while(false);
}


#endif
