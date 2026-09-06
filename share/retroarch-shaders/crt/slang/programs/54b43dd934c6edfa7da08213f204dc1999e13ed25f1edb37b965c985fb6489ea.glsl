// Generated from crt/shaders/cathode-retro/cathode-retro-crt-generate-screen-texture.slang. See slang/upstream for licence/source.
#version 130
#pragma parameter div0 "--------Screen Settings--------" 0.0 0.0 0.0 0.0
#pragma parameter scan_intens "Scanline Intensity" 0.4 0.0 1.0 0.01
#pragma parameter cat_mask_picker "Mask (0=none, 1=aperture, 2=slot, 3=shadow)" 1.0 0.0 3.0 1.0
#pragma parameter mask_intens "Mask Strength" 0.4 0.0 1.0 0.01
#pragma parameter mask_scale "Mask Scale (2 or 3 for 4K)" 1.0 1.0 200.0 1.0
#pragma parameter mask_depth "Mask Background Darkness" 0.3 0.0 1.0 0.01
#pragma parameter warpX "Barrel Distortion X" 0.2 0.0 1.0 0.01
#pragma parameter warpY "Barrel Distortion Y" 0.1 0.0 1.0 0.01
#pragma parameter anim_noise "Animate Anti-Moire Noise" 0.0 0.0 1.0 1.0
#pragma parameter corner "Rounded Corner Size" 0.03 0.0 1.0 0.01
#pragma parameter persistence "Phosphor Persistence" 0.25 0.0 1.0 0.01
#pragma parameter diffusion "Diffusion Strength" 0.5 0.0 1.0 0.01
#pragma parameter div1 "---------TV Knob Settings---------" 0.0 0.0 0.0 0.0
#pragma parameter cat_sat "Saturation" 1.0 0.0 2.0 0.01
#pragma parameter cat_bright "Brightness" 1.0 0.0 2.0 0.01
#pragma parameter cat_white_lvl "White Level" 1.0 0.0 2.0 0.01
#pragma parameter cat_black_lvl "Black Level" 0.0 0.0 2.0 0.01
#pragma parameter tint "Tint Knob Adjustment" 0.0 -1.0 1.0 0.01
#pragma parameter blurStrength "Sharpness" -0.15 -1.0 1.0 0.01
#pragma parameter div2 "---------Signal Parameters---------" 0.0 0.0 0.0 0.0
#pragma parameter composite "Blend Chrome/Luma (aka Composite)" 1.0 0.0 1.0 1.0
#pragma parameter sig_pad "Signal Padding at Edges" 0.0 0.0 10.0 1.0
#pragma parameter minlum "Minimum Luminance" 1.0 0.0 1.0 0.01
#pragma parameter colorpower "Color Power" 1.0 0.0 2.0 0.01
#pragma parameter noise_seed "Noise Seed" 247.0 179.0 313.0 1.0
#pragma parameter cb_samples "Samples Per Color Burst Cyle" 2.0 1.0 100.0 1.0
#pragma parameter cb_first_start "Color Burst Phase First Scanline" 0.0 0.0 100.0 1.0
#pragma parameter cb_last_start "CB Phase Prev Frame First Scanline" 1.0 0.0 100.0 1.0
#pragma parameter cb_phase_inc "Color Burst Phase Increment" 1.66666 0.0 3.0 0.01
#pragma parameter stepSize "Texels Between Each Sample" 1.0 1.0 100.0 1.0
#pragma parameter div3 "-------Artifact Settings-------" 0.0 0.0 0.0 0.0
#pragma parameter horz_track_scale "Horizontal Tracking Instability Scale" 1.0 0.0 3.0 0.05
#pragma parameter ghost_vis "Ghost Visibility" 0.15 0.0 1.0 0.01
#pragma parameter ghost_dist "Ghost Delay Cycles" 1.0 0.0 100.0 1.0
#pragma parameter ghost_spread "Ghost Spread Cycles" 1.0 0.0 100.0 1.0
#pragma parameter noise_strength "Artifact Noise Strength" 0.15 0.0 1.0 0.01
#pragma parameter temp_artifact_blend "Temporal Artifact Blending (Toggle)" 0.0 0.0 1.0 1.0
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
    RA_VARYING_0 = vec2(TexCoord.x, TexCoord.y) * 1.00010001659393310546875;
}


#endif
#ifdef FRAGMENT

uniform int FrameCount;
uniform float anim_noise;
uniform float corner;
uniform float warpX;
uniform float warpY;
const vec2 _606[64] = vec2[](vec2(-0.61339199542999267578125, 0.6174809932708740234375), vec2(0.1700190007686614990234375, -0.0402540005743503570556640625), vec2(-0.2994169890880584716796875, 0.791925013065338134765625), vec2(0.645680010318756103515625, 0.4932099878787994384765625), vec2(-0.651784002780914306640625, 0.717886984348297119140625), vec2(0.4210030138492584228515625, 0.02707000076770782470703125), vec2(-0.8171939849853515625, -0.2710959911346435546875), vec2(-0.7053740024566650390625, -0.66820299625396728515625), vec2(0.977050006389617919921875, -0.108615003526210784912109375), vec2(0.06332600116729736328125, 0.1423690021038055419921875), vec2(0.20352800190448760986328125, 0.2143310010433197021484375), vec2(-0.66753101348876953125, 0.3260900080204010009765625), vec2(-0.098421998322010040283203125, -0.2957549989223480224609375), vec2(-0.885922014713287353515625, 0.21536900103092193603515625), vec2(0.566636979579925537109375, 0.605212986469268798828125), vec2(0.03976599872112274169921875, -0.3961000144481658935546875), vec2(0.751945972442626953125, 0.4533520042896270751953125), vec2(0.078707002103328704833984375, -0.715322971343994140625), vec2(-0.0758379995822906494140625, -0.529344022274017333984375), vec2(0.724479019641876220703125, -0.580797970294952392578125), vec2(0.2229990065097808837890625, -0.2151249945163726806640625), vec2(-0.46757400035858154296875, -0.405438005924224853515625), vec2(-0.24826799333095550537109375, -0.814752995967864990234375), vec2(0.35441100597381591796875, -0.88757002353668212890625), vec2(0.17581699788570404052734375, 0.382366001605987548828125), vec2(0.487471997737884521484375, -0.063082002103328704833984375), vec2(-0.08407799899578094482421875, 0.89831197261810302734375), vec2(0.48887598514556884765625, -0.783441007137298583984375), vec2(0.470016002655029296875, 0.217932999134063720703125), vec2(-0.69688999652862548828125, -0.54979097843170166015625), vec2(-0.14969299733638763427734375, 0.605762004852294921875), vec2(0.0342109985649585723876953125, 0.979979991912841796875), vec2(0.503098011016845703125, -0.308878004550933837890625), vec2(-0.01620499975979328155517578125, -0.872920989990234375), vec2(0.3857840001583099365234375, -0.393902003765106201171875), vec2(-0.14688600599765777587890625, -0.85924899578094482421875), vec2(0.64336097240447998046875, 0.1640979945659637451171875), vec2(0.634388029575347900390625, -0.049470998346805572509765625), vec2(-0.688893973827362060546875, 0.007842999882996082305908203125), vec2(0.4640339910984039306640625, -0.18881799280643463134765625), vec2(-0.4408400058746337890625, 0.13748599588871002197265625), vec2(0.36448299884796142578125, 0.511704027652740478515625), vec2(0.034028001129627227783203125, 0.3259679973125457763671875), vec2(0.0990940034389495849609375, -0.3080230057239532470703125), vec2(0.693960011005401611328125, -0.3662529885768890380859375), vec2(0.678884029388427734375, -0.20468799769878387451171875), vec2(0.001800999976694583892822265625, 0.780327975749969482421875), vec2(0.14517700672149658203125, -0.898984014987945556640625), vec2(0.0626550018787384033203125, -0.611865997314453125), vec2(0.3152259886264801025390625, -0.604296982288360595703125), vec2(-0.780144989490509033203125, 0.48625099658966064453125), vec2(-0.37186801433563232421875, 0.8821380138397216796875), vec2(0.20047600567340850830078125, 0.494430005550384521484375), vec2(-0.4945519864559173583984375, -0.71105098724365234375), vec2(0.61247599124908447265625, 0.705251991748809814453125), vec2(-0.57884502410888671875, -0.768791973590850830078125), vec2(-0.7724540233612060546875, -0.0909759998321533203125), vec2(0.504440009593963623046875, 0.3722949922084808349609375), vec2(0.1557359993457794189453125, 0.065157003700733184814453125), vec2(0.391521990299224853515625, 0.849605023860931396484375), vec2(-0.6201059818267822265625, -0.3281039893627166748046875), vec2(0.789238989353179931640625, -0.4199649989604949951171875), vec2(-0.54539597034454345703125, 0.53813302516937255859375), vec2(-0.17856399714946746826171875, -0.596056997776031494140625));

struct UBO
{
    float anim_noise;
};



struct Push
{
    uint FrameCount;
    float warpX;
    float warpY;
    float corner;
};



uniform sampler2D Pass9Texture;

in vec2 RA_VARYING_0;
out vec4 FragColor;

void main()
{
    vec2 _269 = (RA_VARYING_0 * 2.0) - vec2(1.0);
    vec2 _988;
    do
    {
        bool _676 = (warpX) == 0.0;
        bool _682;
        if (_676)
        {
            _682 = (warpY) == 0.0;
        }
        else
        {
            _682 = _676;
        }
        if (_682)
        {
            _988 = _269;
            break;
        }
        vec2 _687 = max(vec2(9.9999997473787516355514526367188e-05), vec2((warpX), (warpY)));
        vec3 _693 = vec3(_269 * _687, -2.0);
        float _696 = dot(_693, _693);
        float _709 = (4.0 / _696) - sqrt(max(0.0, (16.0 / (_696 * _696)) - (3.0 / _696)));
        vec2 _772 = (_693.xy * _709) / (vec2(2.0) + (_693.zz * _709));
        vec2 _775 = _772 * _772;
        vec3 _724 = vec3(_687, -2.0);
        vec2 _726 = _724.xz;
        vec2 _731 = _724.yz;
        vec2 _735 = vec2(dot(_726, _726), dot(_731, _731));
        vec2 _750 = (vec2(4.0) / _735) - sqrt(max(vec2(0.0), (vec2(16.0) / (_735 * _735)) - (vec2(3.0) / _735)));
        vec2 _791 = (_724.xy * _750) / (vec2(2.0) + (_724.zz * _750));
        vec2 _794 = _791 * _791;
        _988 = (_772 * (vec2(1.0) + (_775 * ((_775 * 0.20000000298023223876953125) - vec2(0.3333333432674407958984375))))) / (_791 * (vec2(1.0) + (_794 * ((_794 * 0.20000000298023223876953125) - vec2(0.3333333432674407958984375)))));
        break;
    } while(false);
    vec2 _992;
    do
    {
        if (true)
        {
            _992 = _988;
            break;
        }
        vec3 _845 = vec3(_988 * vec2(9.9999997473787516355514526367188e-05), -2.0);
        float _848 = dot(_845, _845);
        float _861 = (4.0 / _848) - sqrt(max(0.0, (16.0 / (_848 * _848)) - (3.0 / _848)));
        vec2 _924 = (_845.xy * _861) / (vec2(2.0) + (_845.zz * _861));
        vec2 _927 = _924 * _924;
        _992 = (_924 * (vec2(1.0) + (_927 * ((_927 * 0.20000000298023223876953125) - vec2(0.3333333432674407958984375))))) * vec2(20000.0);
        break;
    } while(false);
    vec2 _309 = (abs(_992) - vec2(1.0)) + vec2((corner));
    vec2 _326 = dFdx(_992);
    vec2 _328 = dFdy(_992);
    vec2 _348 = _988 * 1000.0;
    float _963 = fract((1.0 + (mod(float((uint(FrameCount))), 46375.0) * (anim_noise))) * 0.00099999993108212947845458984375);
    float _356 = fract(tan(fract(distance(_348, (vec2(_963 + 0.300000011920928955078125, 0.100000001490116119384765625) + vec2(1.0)) * 1000.0))) * distance(_348, (vec2(_963 + 0.100000001490116119384765625, _963 + 0.20000000298023223876953125) - vec2(2.0)) * 1000.0)) * 6.283185482025146484375;
    vec2 _364 = vec2(sin(_356), cos(_356)) * 1.414000034332275390625;
    vec2 _371 = vec2(-_364.y, _364.x);
    vec2 _375 = dFdx(_988);
    vec2 _379 = dFdx(_988);
    vec2 _381 = vec2(dot(_364, _375), dot(_371, _379));
    vec2 _385 = dFdy(_988);
    vec2 _389 = dFdy(_988);
    vec2 _391 = vec2(dot(_364, _385), dot(_371, _389));
    vec3 _1018;
    _1018 = vec3(0.0);
    for (int _1017 = 0; _1017 < 64; )
    {
        _1018 += texture(Pass9Texture, ((((_988 + (_381 * _606[_1017].x)) + (_391 * _606[_1017].y)) * 0.5) * 1.0) + vec2(0.5), -2.0).xyz;
        _1017++;
        continue;
    }
    FragColor = vec4(_1018 * vec3(0.015625), (max(abs(_269.x), abs(_269.y)) > 1.10000002384185791015625) ? 0.0 : (1.0 - smoothstep(-length(_326 + _328), 0.0, (min(max(_309.x, _309.y), 0.0) + length(max(_309, vec2(0.0)))) - (corner))));
}


#endif
