// Generated from crt/shaders/cathode-retro/cathode-retro-util-copy.slang. See slang/upstream for licence/source.
#version 120
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



attribute vec4 VertexCoord;
varying vec2 RA_VARYING_0;
attribute vec2 TexCoord;

void main()
{
    gl_Position = (MVPMatrix) * VertexCoord;
    RA_VARYING_0 = vec2(TexCoord.x, TexCoord.y) * 1.00010001659393310546875;
}


#endif
#ifdef FRAGMENT


uniform sampler2D Texture;

varying vec2 RA_VARYING_0;

void main()
{
    gl_FragData[0] = texture2D(Texture, RA_VARYING_0);
}


#endif
