// Generated from crt/shaders/simple-crt/simple-color-correction.slang. See slang/upstream for licence/source.
#version 130
#pragma parameter SHARPNESS           "[IMG] Sharpness/Blur"            -0.25   -1.00  1.00   0.05 // < 0 sharpens, > 0 blurs
#pragma parameter COLOR_BRIGHTNESS    "[IMG] Brightness (Exposure)"      1.25    0.00  2.00   0.05 // multiplies color by this, affecting bright pixels more, black remains black
#pragma parameter COLOR_BRIGHTNESS_O  "[IMG] Brightness (Offset)"        0.00   -0.25  0.25   0.01 // < 0 drowns out dark details, > 0 makes black gray
#pragma parameter COLOR_SATURATION    "[IMG] Saturation"                 0.75   -2.00  2.00   0.05 // < 0 decrease saturation, > 0 increase saturation
#pragma parameter COLOR_CONTRAST_SIG  "[IMG] Contrast (sigmoid)"         0.20    0.00  1.00   0.05 // increase contrast in bright areas, high values may drown out light details
#pragma parameter COLOR_CONTRAST_SQR  "[IMG] Contrast (squared)"         1.10    0.00  2.00   0.05 // < 1 decrease contrast, > 1 increase contrast, affects color
#pragma parameter COLOR_CONTRAST_SQRL "[IMG] Contrast (squared) [luma]"  1.10    0.00  2.00   0.05 // < 1 decrease contrast, > 1 increase contrast, does not affect color
#pragma parameter COLOR_GAMMA         "[IMG] Gamma"                      1.10    0.00  2.00   0.05 // < 1 lighter, > 1 darker, for mid-tones
#pragma parameter COLOR_BMIN          "[IMG] Brightness min"             0.00    0.00  1.00   0.05 // used with max to limit the color values to a range of min..max
#pragma parameter COLOR_BMAX          "[IMG] Brightness max"             1.00    0.00  1.00   0.05 // see min
#pragma parameter VIGNETTE_STRENGTH   "[IMG] Vignette strength"          0.50    0.00  1.00   0.10 // 
#pragma parameter VIGNETTE_SIZE       "[IMG] Vignette size"              4.00    1.00  4.00   0.25 // 
#pragma parameter VIGNETTE_POW        "[IMG] Vignette hardness"          4.00    1.00  4.00   0.25 // 
#pragma parameter MAX_COLOR_BITS      "[IMG] Color bits"                 6.00    1.00  8.00   1.00 // 
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

uniform float COLOR_BMAX;
uniform float COLOR_BMIN;
uniform float COLOR_BRIGHTNESS;
uniform float COLOR_BRIGHTNESS_O;
uniform float COLOR_CONTRAST_SIG;
uniform float COLOR_CONTRAST_SQR;
uniform float COLOR_CONTRAST_SQRL;
uniform float COLOR_GAMMA;
uniform float COLOR_SATURATION;
uniform float MAX_COLOR_BITS;
uniform vec2 OutputSize;
uniform float SHARPNESS;
uniform float VIGNETTE_POW;
uniform float VIGNETTE_SIZE;
uniform float VIGNETTE_STRENGTH;
struct Push
{
    vec4 OutputSize;
    float SHARPNESS;
    float COLOR_BRIGHTNESS;
    float COLOR_BRIGHTNESS_O;
    float COLOR_SATURATION;
    float COLOR_CONTRAST_SIG;
    float COLOR_CONTRAST_SQR;
    float COLOR_CONTRAST_SQRL;
    float COLOR_GAMMA;
    float COLOR_BMIN;
    float COLOR_BMAX;
    float VIGNETTE_STRENGTH;
    float VIGNETTE_SIZE;
    float VIGNETTE_POW;
    float MAX_COLOR_BITS;
};



uniform sampler2D Texture;

in vec2 RA_VARYING_0;
out vec4 FragColor;

void main()
{
    vec4 _308 = texture(Texture, RA_VARYING_0);
    vec3 _328 = ((((_308 + textureOffset(Texture, RA_VARYING_0, ivec2(0, -1))) + textureOffset(Texture, RA_VARYING_0, ivec2(1, 0))) + textureOffset(Texture, RA_VARYING_0, ivec2(0, 1))) + textureOffset(Texture, RA_VARYING_0, ivec2(-1, 0))).xyz * 0.20000000298023223876953125;
    float _335 = dot(_328, vec3(0.2989999949932098388671875, 0.58700001239776611328125, 0.114000000059604644775390625));
    vec3 _197 = (vec4(mix(_308.xyz, _328, vec3((SHARPNESS))), _335).xyz * (COLOR_BRIGHTNESS)) + vec3((COLOR_BRIGHTNESS_O));
    vec3 _345 = mix(vec3(dot(_197, vec3(0.3333333432674407958984375))), _197, vec3((COLOR_SATURATION)));
    vec3 _354 = _345 / (vec3(0.5) + exp(_345 * (-((COLOR_CONTRAST_SIG) * (COLOR_CONTRAST_SIG)))));
    vec3 _360 = mix(_354, _354 * _354, vec3((COLOR_CONTRAST_SQR) - 1.0));
    float _237 = pow(2.0, (MAX_COLOR_BITS));
    vec3 _283 = (round(((pow(mix(_360, _360 * max(_360.x, max(_360.y, _360.z)), vec3((COLOR_CONTRAST_SQRL) - 1.0)), vec3((COLOR_GAMMA))) * ((COLOR_BMAX) - (COLOR_BMIN))) + vec3((COLOR_BMIN))) * _237) / vec3(_237)) * mix(1.0, 1.0 - smoothstep(0.0, (VIGNETTE_SIZE), pow(length(((gl_FragCoord.xy / (vec4(OutputSize, 1.0 / OutputSize)).xy) * 2.0) - vec2(1.0)), (VIGNETTE_POW))), (VIGNETTE_STRENGTH));
    FragColor = vec4(clamp(_283 / vec3(max(max(max(_283.x, _283.y), _283.z), 1.0)), vec3(0.0), vec3(1.0)), _335);
}


#endif
