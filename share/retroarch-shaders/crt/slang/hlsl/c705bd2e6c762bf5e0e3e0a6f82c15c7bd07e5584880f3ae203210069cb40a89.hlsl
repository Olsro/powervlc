// Generated from crt/shaders/hyllian/support/ntsc/shaders/ntsc-adaptive-lite/ntsc-lite-pass2.slang. See slang/upstream for licence/source.
static const float _486[25] = { -1.2020303074677940458059310913086e-05f, -2.21465597860515117645263671875e-05f, -1.3155332453607115894556045532227e-05f, -1.2020303074677940458059310913086e-05f, -4.9980262701865285634994506835938e-05f, -0.00011394287867005914449691772460938f, -0.000122153083793818950653076171875f, -5.6121398301911540329456329345703e-06f, 0.00017052030307240784168243408203125f, 0.00023720499302726238965988159179688f, 0.00016964427777566015720367431640625f, 0.00028569521964527666568756103515625f, 0.000984598882496356964111328125f, 0.002018733881413936614990234375f, 0.00200232560746371746063232421875f, -0.000909904949367046356201171875f, -0.0070492587983608245849609375f, -0.013223193585872650146484375f, -0.012607249431312084197998046875f, 0.002460922114551067352294921875f, 0.035869129002094268798828125f, 0.08401857316493988037109375f, 0.1355669200420379638671875f, 0.17526568472385406494140625f, 0.1901813447475433349609375f };
static const float _517[25] = { -0.00013574105105362832546234130859375f, -0.000568115734495222568511962890625f, -0.001306056859903037548065185546875f, -0.00231369934044778347015380859375f, -0.00350569677539169788360595703125f, -0.00474731065332889556884765625f, -0.0058598020114004611968994140625f, -0.006631140597164630889892578125f, -0.00683148391544818878173828125f, -0.006232350133359432220458984375f, -0.0046279276721179485321044921875f, -0.001856654300354421138763427734375f, 0.00217899004928767681121826171875f, 0.00749647803604602813720703125f, 0.014022787101566791534423828125f, 0.0215908624231815338134765625f, 0.02994374372065067291259765625f, 0.0387464463710784912109375f, 0.0476049743592739105224609375f, 0.0560911484062671661376953125f, 0.0637713372707366943359375f, 0.070236839354038238525390625f, 0.07513330876827239990234375f, 0.078186847269535064697265625f, 0.07922442257404327392578125f };

cbuffer UBO : register(b0)
{
    float4 global_OriginalSize : packoffset(c5);
    float4 global_SourceSize : packoffset(c6);
    float global_linearize : packoffset(c7);
    float global_ntsc_scale : packoffset(c7.y);
    float global_ntsc_phase : packoffset(c7.z);
    float global_chroma_scale : packoffset(c8);
};

Texture2D<float4> Source : register(t2);
SamplerState _Source_sampler : register(s2);

static float2 vTexCoord;
static float4 FragColor;

struct SPIRV_Cross_Input
{
    float2 vTexCoord : TEXCOORD0;
};

struct SPIRV_Cross_Output
{
    float4 FragColor : SV_Target0;
};

void frag_main()
{
    do
    {
        float _1520;
        if (global_ntsc_phase < 1.5f)
        {
            _1520 = (global_OriginalSize.x > 300.0f) ? 2.0f : 3.0f;
        }
        else
        {
            _1520 = (global_ntsc_phase > 2.5f) ? 3.0f : 2.0f;
        }
        bool _119 = _1520 > 2.5f;
        float _1521;
        if (_119)
        {
            _1521 = min(global_chroma_scale, 2.2000000476837158203125f);
        }
        else
        {
            _1521 = global_chroma_scale * 0.5f;
        }
        float2 _142 = float2(1.0f, 1.0f / _1521) * (global_SourceSize.z / global_ntsc_scale);
        float3 _1530;
        if (_1520 < 2.5f)
        {
            float _595 = _142.x;
            float _606 = _142.y;
            float3 _219 = ((((float3(Source.Sample(_Source_sampler, vTexCoord + float2((-15.0f) * _595, 0.0f)).x, Source.Sample(_Source_sampler, vTexCoord + float2((-15.0f) * _606, 0.0f)).yz) + float3(Source.Sample(_Source_sampler, vTexCoord + float2(15.0f * _595, 0.0f)).x, Source.Sample(_Source_sampler, vTexCoord + float2(15.0f * _606, 0.0f)).yz)) * float3(0.001343728625215590000152587890625f, 0.00406084768474102020263671875f, 0.00406084768474102020263671875f)) + ((float3(Source.Sample(_Source_sampler, vTexCoord + float2((-14.0f) * _595, 0.0f)).x, Source.Sample(_Source_sampler, vTexCoord + float2((-14.0f) * _606, 0.0f)).yz) + float3(Source.Sample(_Source_sampler, vTexCoord + float2(14.0f * _595, 0.0f)).x, Source.Sample(_Source_sampler, vTexCoord + float2(14.0f * _606, 0.0f)).yz)) * float3(0.0029423166997730731964111328125f, 0.005785736255347728729248046875f, 0.005785736255347728729248046875f))) + ((float3(Source.Sample(_Source_sampler, vTexCoord + float2((-13.0f) * _595, 0.0f)).x, Source.Sample(_Source_sampler, vTexCoord + float2((-13.0f) * _606, 0.0f)).yz) + float3(Source.Sample(_Source_sampler, vTexCoord + float2(13.0f * _595, 0.0f)).x, Source.Sample(_Source_sampler, vTexCoord + float2(13.0f * _606, 0.0f)).yz)) * float3(0.00399617664515972137451171875f, 0.008044474758207798004150390625f, 0.008044474758207798004150390625f))) + ((float3(Source.Sample(_Source_sampler, vTexCoord + float2((-12.0f) * _595, 0.0f)).x, Source.Sample(_Source_sampler, vTexCoord + float2((-12.0f) * _606, 0.0f)).yz) + float3(Source.Sample(_Source_sampler, vTexCoord + float2(12.0f * _595, 0.0f)).x, Source.Sample(_Source_sampler, vTexCoord + float2(12.0f * _606, 0.0f)).yz)) * float3(0.0030363262630999088287353515625f, 0.010915254242718219757080078125f, 0.010915254242718219757080078125f));
            float3 _291 = (((_219 + ((float3(Source.Sample(_Source_sampler, vTexCoord + float2((-11.0f) * _595, 0.0f)).x, Source.Sample(_Source_sampler, vTexCoord + float2((-11.0f) * _606, 0.0f)).yz) + float3(Source.Sample(_Source_sampler, vTexCoord + float2(11.0f * _595, 0.0f)).x, Source.Sample(_Source_sampler, vTexCoord + float2(11.0f * _606, 0.0f)).yz)) * float3(-0.001105567323975265026092529296875f, 0.0144533030688762664794921875f, 0.0144533030688762664794921875f))) + ((float3(Source.Sample(_Source_sampler, vTexCoord + float2((-10.0f) * _595, 0.0f)).x, Source.Sample(_Source_sampler, vTexCoord + float2((-10.0f) * _606, 0.0f)).yz) + float3(Source.Sample(_Source_sampler, vTexCoord + float2(10.0f * _595, 0.0f)).x, Source.Sample(_Source_sampler, vTexCoord + float2(10.0f * _606, 0.0f)).yz)) * float3(-0.008399703539907932281494140625f, 0.018676586449146270751953125f, 0.018676586449146270751953125f))) + ((float3(Source.Sample(_Source_sampler, vTexCoord + float2((-9.0f) * _595, 0.0f)).x, Source.Sample(_Source_sampler, vTexCoord + float2((-9.0f) * _606, 0.0f)).yz) + float3(Source.Sample(_Source_sampler, vTexCoord + float2(9.0f * _595, 0.0f)).x, Source.Sample(_Source_sampler, vTexCoord + float2(9.0f * _606, 0.0f)).yz)) * float3(-0.016951538622379302978515625f, 0.02355184592306613922119140625f, 0.02355184592306613922119140625f))) + ((float3(Source.Sample(_Source_sampler, vTexCoord + float2((-8.0f) * _595, 0.0f)).x, Source.Sample(_Source_sampler, vTexCoord + float2((-8.0f) * _606, 0.0f)).yz) + float3(Source.Sample(_Source_sampler, vTexCoord + float2(8.0f * _595, 0.0f)).x, Source.Sample(_Source_sampler, vTexCoord + float2(8.0f * _606, 0.0f)).yz)) * float3(-0.0229874886572360992431640625f, 0.028983414173126220703125f, 0.028983414173126220703125f));
            float3 _363 = (((_291 + ((float3(Source.Sample(_Source_sampler, vTexCoord + float2((-7.0f) * _595, 0.0f)).x, Source.Sample(_Source_sampler, vTexCoord + float2((-7.0f) * _606, 0.0f)).yz) + float3(Source.Sample(_Source_sampler, vTexCoord + float2(7.0f * _595, 0.0f)).x, Source.Sample(_Source_sampler, vTexCoord + float2(7.0f * _606, 0.0f)).yz)) * float3(-0.0217113010585308074951171875f, 0.0348073728382587432861328125f, 0.0348073728382587432861328125f))) + ((float3(Source.Sample(_Source_sampler, vTexCoord + float2((-6.0f) * _595, 0.0f)).x, Source.Sample(_Source_sampler, vTexCoord + float2((-6.0f) * _606, 0.0f)).yz) + float3(Source.Sample(_Source_sampler, vTexCoord + float2(6.0f * _595, 0.0f)).x, Source.Sample(_Source_sampler, vTexCoord + float2(6.0f * _606, 0.0f)).yz)) * float3(-0.008891512639820575714111328125f, 0.0407934151589870452880859375f, 0.0407934151589870452880859375f))) + ((float3(Source.Sample(_Source_sampler, vTexCoord + float2((-5.0f) * _595, 0.0f)).x, Source.Sample(_Source_sampler, vTexCoord + float2((-5.0f) * _606, 0.0f)).yz) + float3(Source.Sample(_Source_sampler, vTexCoord + float2(5.0f * _595, 0.0f)).x, Source.Sample(_Source_sampler, vTexCoord + float2(5.0f * _606, 0.0f)).yz)) * float3(0.017326988279819488525390625f, 0.046655833721160888671875f, 0.046655833721160888671875f))) + ((float3(Source.Sample(_Source_sampler, vTexCoord + float2((-4.0f) * _595, 0.0f)).x, Source.Sample(_Source_sampler, vTexCoord + float2((-4.0f) * _606, 0.0f)).yz) + float3(Source.Sample(_Source_sampler, vTexCoord + float2(4.0f * _595, 0.0f)).x, Source.Sample(_Source_sampler, vTexCoord + float2(4.0f * _606, 0.0f)).yz)) * float3(0.0550969056785106658935546875f, 0.0520737655460834503173828125f, 0.0520737655460834503173828125f));
            float3 _424 = (((_363 + ((float3(Source.Sample(_Source_sampler, vTexCoord + float2((-3.0f) * _595, 0.0f)).x, Source.Sample(_Source_sampler, vTexCoord + float2((-3.0f) * _606, 0.0f)).yz) + float3(Source.Sample(_Source_sampler, vTexCoord + float2(3.0f * _595, 0.0f)).x, Source.Sample(_Source_sampler, vTexCoord + float2(3.0f * _606, 0.0f)).yz)) * float3(0.0986559092998504638671875f, 0.0567190684378147125244140625f, 0.0567190684378147125244140625f))) + ((float3(Source.Sample(_Source_sampler, vTexCoord + float2((-2.0f) * _595, 0.0f)).x, Source.Sample(_Source_sampler, vTexCoord + float2((-2.0f) * _606, 0.0f)).yz) + float3(Source.Sample(_Source_sampler, vTexCoord + float2(2.0f * _595, 0.0f)).x, Source.Sample(_Source_sampler, vTexCoord + float2(2.0f * _606, 0.0f)).yz)) * float3(0.1394872963428497314453125f, 0.0602887570858001708984375f, 0.0602887570858001708984375f))) + ((float3(Source.Sample(_Source_sampler, vTexCoord + float2((-1.0f) * _595, 0.0f)).x, Source.Sample(_Source_sampler, vTexCoord + float2((-1.0f) * _606, 0.0f)).yz) + float3(Source.Sample(_Source_sampler, vTexCoord + float2(_595, 0.0f)).x, Source.Sample(_Source_sampler, vTexCoord + float2(_606, 0.0f)).yz)) * float3(0.16859127581119537353515625f, 0.0625375211238861083984375f, 0.0625375211238861083984375f))) + (Source.Sample(_Source_sampler, vTexCoord).xyz * float3(0.17914037406444549560546875f, 0.06330560147762298583984375f, 0.06330560147762298583984375f));
            _1530 = _424;
        }
        else
        {
            float3 _1531;
            if (_119)
            {
                float3 _1526;
                _1526 = 0.0f.xxx;
                for (int _1525 = 0; _1525 < 24; )
                {
                    float _443 = float(_1525);
                    float _447 = _443 - 24.0f;
                    float _1465 = _142.x;
                    float _1476 = _142.y;
                    float _453 = 24.0f - _443;
                    _1526 += ((float3(Source.Sample(_Source_sampler, vTexCoord + float2(_447 * _1465, 0.0f)).x, Source.Sample(_Source_sampler, vTexCoord + float2(_447 * _1476, 0.0f)).yz) + float3(Source.Sample(_Source_sampler, vTexCoord + float2(_453 * _1465, 0.0f)).x, Source.Sample(_Source_sampler, vTexCoord + float2(_453 * _1476, 0.0f)).yz)) * float3(_486[_1525], _517[_1525], _517[_1525]));
                    _1525++;
                    continue;
                }
                _1531 = _1526 + (Source.Sample(_Source_sampler, vTexCoord).xyz * float3(0.1901813447475433349609375f, 0.07922442257404327392578125f, 0.07922442257404327392578125f));
            }
            else
            {
                _1531 = 0.0f.xxx;
            }
            _1530 = _1531;
        }
        FragColor = float4(mul(float3x3(float3(1.0f, 0.95599997043609619140625f, 0.620999991893768310546875f), float3(1.0f, -0.272000014781951904296875f, -0.64740002155303955078125f), float3(1.0f, -1.10599994659423828125f, 1.70459997653961181640625f)), _1530), 1.0f);
        if (global_linearize < 0.5f)
        {
            break;
        }
        FragColor = pow(FragColor, 2.2000000476837158203125f.xxxx);
        break;
    } while(false);
}

SPIRV_Cross_Output main(SPIRV_Cross_Input stage_input)
{
    vTexCoord = stage_input.vTexCoord;
    frag_main();
    SPIRV_Cross_Output stage_output;
    stage_output.FragColor = FragColor;
    return stage_output;
}
