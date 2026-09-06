// Generated from crt/shaders/crtsim/composite.slang. See slang/upstream for licence/source.
#version 130
#pragma parameter Tuning_Sharp "Composite Sharp" 0.2 0.0 1.0 0.05
#pragma parameter Tuning_Persistence_R "Red Persistence" 0.065 0.0 1.0 0.01
#pragma parameter Tuning_Persistence_G "Green Persistence" 0.05 0.0 1.0 0.01
#pragma parameter Tuning_Persistence_B "Blue Persistence" 0.05 0.0 1.0 0.01
#pragma parameter Tuning_Bleed "Composite Bleed" 0.5 0.0 1.0 0.05
#pragma parameter Tuning_Artifacts "Composite Artifacts" 0.5 0.0 1.0 0.05
#pragma parameter NTSCLerp "NTSC Artifacts" 1.0 0.0 1.0 1.0
#pragma parameter NTSCArtifactScale "NTSC Artifact Scale" 255.0 0.0 1000.0 5.0
#pragma parameter animate_artifacts "Animate NTSC Artifacts" 1.0 0.0 1.0 1.0
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
uniform float NTSCArtifactScale;
uniform float NTSCLerp;
uniform vec2 TextureSize;
uniform float Tuning_Artifacts;
uniform float Tuning_Bleed;
uniform float Tuning_Persistence_B;
uniform float Tuning_Persistence_G;
uniform float Tuning_Persistence_R;
uniform float Tuning_Sharp;
uniform float animate_artifacts;
const float _211[3] = float[](1.0, -0.3162277042865753173828125, 0.100000001490116119384765625);

struct Push
{
    vec4 SourceSize;
    uint FrameCount;
    float Tuning_Sharp;
    float Tuning_Persistence_R;
    float Tuning_Persistence_G;
    float Tuning_Persistence_B;
    float Tuning_Bleed;
    float Tuning_Artifacts;
    float NTSCLerp;
    float NTSCArtifactScale;
    float animate_artifacts;
};



uniform sampler2D NTSCArtifactSampler;
uniform sampler2D Texture;
uniform sampler2D FeedbackTexture;

in vec2 RA_VARYING_0;
out vec4 FragColor;

void main()
{
    vec2 _47 = fract(((RA_VARYING_0 * 1.00010001659393310546875) * (vec4(TextureSize, 1.0 / TextureSize)).xy) / vec2((NTSCArtifactScale)));
    vec4 _55 = texture(NTSCArtifactSampler, _47);
    vec4 _66 = texture(NTSCArtifactSampler, _47 + vec2(0.0, 1.0 / (vec4(TextureSize, 1.0 / TextureSize)).y));
    float _292;
    if ((animate_artifacts) > 0.5)
    {
        _292 = mod(float((uint(FrameCount))), 2.0);
    }
    else
    {
        _292 = (NTSCLerp);
    }
    vec4 _96 = mix(_55, _66, vec4(1.0 - _292));
    vec2 _103 = vec2(1.0 / (vec4(TextureSize, 1.0 / TextureSize)).x, 0.0);
    vec2 _104 = RA_VARYING_0 - _103;
    vec2 _111 = RA_VARYING_0 + _103;
    vec4 _116 = texture(Texture, _104);
    vec4 _120 = texture(Texture, RA_VARYING_0);
    vec4 _124 = texture(Texture, _111);
    vec4 _135 = texture(FeedbackTexture, _104);
    vec4 _139 = texture(FeedbackTexture, RA_VARYING_0);
    vec4 _143 = texture(FeedbackTexture, _111);
    vec4 _157 = clamp(_120 + (((_116 - _120) + (_124 - _120)) * (_96 * (Tuning_Artifacts))), vec4(0.0), vec4(1.0));
    float _283 = dot(_157, vec4(0.2989999949932098388671875, 0.58700001239776611328125, 0.114000000059604644775390625, 0.0));
    float _297;
    _297 = 0.0;
    for (int _295 = 0; _295 < 3; )
    {
        int _177 = _295 + 1;
        vec2 _179 = vec2(0.00390625, 0.0) * float(_177);
        _297 += (((_283 - dot(texture(Texture, RA_VARYING_0 - _179), vec4(0.2989999949932098388671875, 0.58700001239776611328125, 0.114000000059604644775390625, 0.0))) + (_283 - dot(texture(Texture, RA_VARYING_0 + _179), vec4(0.2989999949932098388671875, 0.58700001239776611328125, 0.114000000059604644775390625, 0.0)))) * _211[_295]);
        _295 = _177;
        continue;
    }
    FragColor = clamp(max(clamp(_157 + (mix(vec4(1.0), _96, vec4((Tuning_Artifacts))) * (_297 * (Tuning_Sharp))), vec4(0.0), vec4(1.0)), (vec4((Tuning_Persistence_R), (Tuning_Persistence_G), (Tuning_Persistence_B), 1.0) * (10.0 / (1.0 + (2.0 * (Tuning_Bleed))))) * (_139 + ((_135 + _143) * (Tuning_Bleed)))), vec4(0.0), vec4(1.0));
}


#endif
