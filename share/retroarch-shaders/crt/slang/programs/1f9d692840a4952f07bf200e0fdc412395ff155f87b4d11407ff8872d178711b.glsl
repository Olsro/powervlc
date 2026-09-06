// Generated from crt/shaders/gtu-v050/pass1.slang. See slang/upstream for licence/source.
#version 120
#pragma parameter compositeConnection "Composite Connection Enable" 0.0 0.0 1.0 1.0
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
    RA_VARYING_0 = TexCoord;
}


#endif
#ifdef FRAGMENT

uniform float compositeConnection;
struct Push
{
    float compositeConnection;
};



uniform sampler2D Texture;

varying vec2 RA_VARYING_0;

void main()
{
    vec4 _19 = texture2D(Texture, RA_VARYING_0);
    vec4 _77;
    if ((compositeConnection) > 0.0)
    {
        vec3 _50 = _19.xyz * mat3(vec3(0.2989999949932098388671875, 0.595715999603271484375, 0.211456000804901123046875), vec3(0.58700001239776611328125, -0.2744530141353607177734375, -0.52259099483489990234375), vec3(0.114000000059604644775390625, -0.3212629854679107666015625, 0.311134994029998779296875));
        vec4 _70 = _19;
        _70.x = _50.x;
        _70.y = _50.y;
        _70.z = _50.z;
        _77 = _70;
    }
    else
    {
        _77 = _19;
    }
    gl_FragData[0] = _77;
}


#endif
