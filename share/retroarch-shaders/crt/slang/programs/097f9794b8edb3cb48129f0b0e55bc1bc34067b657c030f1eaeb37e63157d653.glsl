// Generated from crt/shaders/geom-deluxe/phosphor_update.slang. See slang/upstream for licence/source.
#version 120
#pragma parameter mask_type "Mask Pattern" 1.0 1.0 20.0 1.0
#pragma parameter aperture_strength "Shadow mask strength" 0.4 0.0 1.0 0.05
#pragma parameter aperture_brightboost "Shadow mask brightness boost" 0.4 0.0 1.0 0.05
#pragma parameter phosphor_power "Phosphor decay power" 1.2 0.5 3.0 0.05
#pragma parameter phosphor_amplitude "Phosphor persistence amplitude" 0.04 0.0 0.2 0.01
#pragma parameter CRTgamma "Gamma of simulated CRT" 2.4 0.7 4.0 0.05
#pragma parameter rasterbloom "Raster bloom amplitude" 0.1 0.0 1.0 0.01
#pragma parameter halation "Halation amplitude" 0.1 0.0 0.3 0.01
#pragma parameter width "Halation blur width" 2.0 0.1 4.0 0.1
#pragma parameter curvature "Enable Curvature" 1.0 0.0 1.0 1.0
#pragma parameter R "Radius of curvature" 3.5 0.5 10.0 0.1
#pragma parameter d "Distance to screen" 2.0 0.1 10.0 0.1
#pragma parameter angle_x "Tilt X" 0.0 -1.0 1.0 0.01
#pragma parameter angle_y "Tilt Y" 0.0 -1.0 1.0 0.01
#pragma parameter cornersize "Rounded corner size" 0.01 0.00 0.10 0.01
#pragma parameter cornersmooth "Border smoothness" 1000.0 100.0 2000.0 100.0
#pragma parameter overscan_x "Overscan X" 1.0 0.8 1.2 0.005
#pragma parameter overscan_y "Overscan Y" 1.0 0.8 1.2 0.005
#pragma parameter monitorgamma "Gamma of output display" 2.2 0.7 4.0 0.05
#pragma parameter aspect_x "Aspect ratio X" 1.0 0.3 1.0 0.01
#pragma parameter aspect_y "Aspect ratio Y" 0.75 0.3 1.0 0.01
#pragma parameter scanline_weight "CRTGeom Scanline Weight" 0.3 0.1 0.5 0.01
#pragma parameter geom_lum "CRTGeom Luminance" 0.0 0.0 1.0 0.01
#pragma parameter interlace_detect "CRTGeom Interlacing Simulation" 1.0 0.0 1.0 1.0
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

uniform float phosphor_power;
struct Push
{
    float phosphor_power;
};



uniform sampler2D Texture;
uniform sampler2D FeedbackTexture;

varying vec2 RA_VARYING_0;

void main()
{
    vec4 _61 = texture2D(Texture, RA_VARYING_0);
    vec4 _66 = texture2D(FeedbackTexture, RA_VARYING_0);
    float _103 = _66.z * 63.75;
    float _107 = (1.0 + (255.0 * _66.w)) + (fract(_103) * 1024.0);
    float _177;
    if (_107 > 1023.0)
    {
        _177 = 0.0;
    }
    else
    {
        _177 = dot(pow(_66.xyz, vec3(2.2000000476837158203125)), vec3(0.2989999949932098388671875, 0.58700001239776611328125, 0.114000000059604644775390625)) * pow(_107, -(phosphor_power));
    }
    vec4 _180;
    if (dot(pow(_61.xyz, vec3(2.2000000476837158203125)), vec3(0.2989999949932098388671875, 0.58700001239776611328125, 0.114000000059604644775390625)) >= _177)
    {
        _180 = vec4(_61.xy, floor(_61.z * 63.75) * 0.01568627543747425079345703125, 0.0039215688593685626983642578125);
    }
    else
    {
        float _158 = _107 * 0.00390625;
        _180 = vec4(_66.xy, ((floor(_103) * 4.0) + floor(_158)) * 0.0039215688593685626983642578125, fract(_158) * 1.00392162799835205078125);
    }
    gl_FragData[0] = _180;
}


#endif
