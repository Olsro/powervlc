// Generated from crt/shaders/geom-deluxe/gaussy.slang. See slang/upstream for licence/source.
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
uniform vec2 TextureSize;
uniform float aspect_y;
uniform float width;
struct UBO
{
    vec4 SourceSize;
    mat4 MVP;
};



struct Push
{
    float width;
    float aspect_x;
    float aspect_y;
};



attribute vec4 VertexCoord;
varying vec2 RA_VARYING_0;
attribute vec2 TexCoord;
varying vec4 RA_VARYING_1;

void main()
{
    gl_Position = (MVPMatrix) * VertexCoord;
    RA_VARYING_0 = TexCoord;
    float _90 = ((width) * (vec4(TextureSize, 1.0 / TextureSize)).y) / (320.0 * (aspect_y));
    RA_VARYING_1 = exp(vec4(1.0, 4.0, 9.0, 16.0) * vec4(((-1.0) / _90) / _90));
}


#endif
#ifdef FRAGMENT

uniform vec2 TextureSize;
struct UBO
{
    vec4 SourceSize;
};



uniform sampler2D Texture;

varying vec2 RA_VARYING_0;
varying vec4 RA_VARYING_1;

void main()
{
    vec3 _94 = vec3(RA_VARYING_1.w);
    vec3 _111 = vec3(RA_VARYING_1.z);
    vec3 _127 = vec3(RA_VARYING_1.y);
    vec3 _144 = vec3(RA_VARYING_1.x);
    vec3 _217 = ((((((((pow(texture2D(Texture, RA_VARYING_0 + vec2(0.0, (-4.0) / (vec4(TextureSize, 1.0 / TextureSize)).y)).xyz, vec3(2.2000000476837158203125)) * _94) + (pow(texture2D(Texture, RA_VARYING_0 + vec2(0.0, (-3.0) / (vec4(TextureSize, 1.0 / TextureSize)).y)).xyz, vec3(2.2000000476837158203125)) * _111)) + (pow(texture2D(Texture, RA_VARYING_0 + vec2(0.0, (-2.0) / (vec4(TextureSize, 1.0 / TextureSize)).y)).xyz, vec3(2.2000000476837158203125)) * _127)) + (pow(texture2D(Texture, RA_VARYING_0 + vec2(0.0, (-1.0) / (vec4(TextureSize, 1.0 / TextureSize)).y)).xyz, vec3(2.2000000476837158203125)) * _144)) + pow(texture2D(Texture, RA_VARYING_0).xyz, vec3(2.2000000476837158203125))) + (pow(texture2D(Texture, RA_VARYING_0 + vec2(0.0, 1.0 / (vec4(TextureSize, 1.0 / TextureSize)).y)).xyz, vec3(2.2000000476837158203125)) * _144)) + (pow(texture2D(Texture, RA_VARYING_0 + vec2(0.0, 2.0 / (vec4(TextureSize, 1.0 / TextureSize)).y)).xyz, vec3(2.2000000476837158203125)) * _127)) + (pow(texture2D(Texture, RA_VARYING_0 + vec2(0.0, 3.0 / (vec4(TextureSize, 1.0 / TextureSize)).y)).xyz, vec3(2.2000000476837158203125)) * _111)) + (pow(texture2D(Texture, RA_VARYING_0 + vec2(0.0, 4.0 / (vec4(TextureSize, 1.0 / TextureSize)).y)).xyz, vec3(2.2000000476837158203125)) * _94);
    gl_FragData[0] = vec4(pow(_217 * vec3(1.0 / (1.0 + (2.0 * (((RA_VARYING_1.x + RA_VARYING_1.y) + RA_VARYING_1.z) + RA_VARYING_1.w)))), vec3(0.4545454680919647216796875)), 1.0);
}


#endif
