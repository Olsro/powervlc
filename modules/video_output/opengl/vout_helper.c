/*****************************************************************************
 * vout_helper.c: OpenGL and OpenGL ES output common code
 *****************************************************************************
 * Copyright (C) 2004-2016 VLC authors and VideoLAN
 * Copyright (C) 2009, 2011 Laurent Aimar
 *
 * Authors: Laurent Aimar <fenrir _AT_ videolan _DOT_ org>
 *          Ilkka Ollakka <ileoo@videolan.org>
 *          Rémi Denis-Courmont
 *          Adrien Maglo <magsoft at videolan dot org>
 *          Felix Paul Kühne <fkuehne at videolan dot org>
 *          Pierre d'Herbemont <pdherbemont at videolan dot org>
 *
 * This program is free software; you can redistribute it and/or modify it
 * under the terms of the GNU Lesser General Public License as published by
 * the Free Software Foundation; either version 2.1 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
 * GNU Lesser General Public License for more details.
 *
 * You should have received a copy of the GNU Lesser General Public License
 * along with this program; if not, write to the Free Software Foundation,
 * Inc., 51 Franklin Street, Fifth Floor, Boston MA 02110-1301, USA.
 *****************************************************************************/
#ifdef HAVE_CONFIG_H
# include "config.h"
#endif

#include <assert.h>
#include <math.h>

#include <vlc_common.h>
#include <vlc_picture_pool.h>
#include <vlc_subpicture.h>
#include <vlc_opengl.h>
#include <vlc_memory.h>
#include <vlc_modules.h>
#include <vlc_vout.h>
#include <vlc_viewpoint.h>

#include "vout_helper.h"
#include "internal.h"
#include "retroarch_shaders.h"
#ifdef HAVE_LIBPLACEBO_NEXT
# include "dovi_renderer.h"
#endif

#ifndef GL_CLAMP_TO_EDGE
# define GL_CLAMP_TO_EDGE 0x812F
#endif

#define SPHERE_RADIUS 1.f

/* FIXME: GL_ASSERT_NOERROR disabled for now because:
 * Proper GL error handling need to be implemented
 * glClear(GL_COLOR_BUFFER_BIT) throws a GL_INVALID_FRAMEBUFFER_OPERATION on macOS
 * assert fails on vout_display_opengl_Delete on iOS
 */
#if 0
# define HAVE_GL_ASSERT_NOERROR
#endif

#ifdef HAVE_GL_ASSERT_NOERROR
# define GL_ASSERT_NOERROR() do { \
    GLenum glError = vgl->vt.GetError(); \
    switch (glError) \
    { \
        case GL_NO_ERROR: break; \
        case GL_INVALID_ENUM: assert(!"GL_INVALID_ENUM"); \
        case GL_INVALID_VALUE: assert(!"GL_INVALID_VALUE"); \
        case GL_INVALID_OPERATION: assert(!"GL_INVALID_OPERATION"); \
        case GL_INVALID_FRAMEBUFFER_OPERATION: assert(!"GL_INVALID_FRAMEBUFFER_OPERATION"); \
        case GL_OUT_OF_MEMORY: assert(!"GL_OUT_OF_MEMORY"); \
        default: assert(!"GL_UNKNOWN_ERROR"); \
    } \
} while(0)
#else
# define GL_ASSERT_NOERROR()
#endif

typedef struct {
    GLuint   texture;
    GLsizei  width;
    GLsizei  height;

    float    alpha;

    float    top;
    float    left;
    float    bottom;
    float    right;

    float    tex_width;
    float    tex_height;

    int      stereo_offset;
    bool     subtitle;
} gl_region_t;

struct prgm
{
    GLuint id;
    opengl_tex_converter_t *tc;

    struct {
        GLfloat OrientationMatrix[16];
        GLfloat ProjectionMatrix[16];
        GLfloat ZRotMatrix[16];
        GLfloat YRotMatrix[16];
        GLfloat XRotMatrix[16];
        GLfloat ZoomMatrix[16];
    } var;

    struct { /* UniformLocation */
        GLint OrientationMatrix;
        GLint ProjectionMatrix;
        GLint ZRotMatrix;
        GLint YRotMatrix;
        GLint XRotMatrix;
        GLint ZoomMatrix;
    } uloc;
    struct { /* AttribLocation */
        GLint MultiTexCoord[3];
        GLint VertexPosition;
    } aloc;
};

struct vout_display_opengl_t {

    vlc_gl_t   *gl;
#ifdef HAVE_LIBPLACEBO_NEXT
    vlc_dovi_renderer_t *dovi;
#endif
    opengl_vtable_t vt;
    vlc_ra_shader_engine_t *retroarch;

    video_format_t fmt;

    /* The coded packing and the scanout packing are deliberately distinct.
     * MVC already arrives as two full-height stacked views. SBS/TB keeps its
     * compact decoded texture and is expanded to HDMI frame packing entirely
     * by the geometry below. */
    video_multiview_mode_t source_multiview_mode;
    bool output_framepacked;
    unsigned output_eye_width;
    unsigned output_eye_height;
    unsigned viewport_width;
    unsigned viewport_height;

    GLsizei    tex_width[PICTURE_PLANE_MAX];
    GLsizei    tex_height[PICTURE_PLANE_MAX];

    GLuint     texture[PICTURE_PLANE_MAX];

    int         region_count;
    gl_region_t *region;


    picture_pool_t *pool;

    /* One YUV program and one RGBA program (for subpics) */
    struct prgm prgms[2];
    struct prgm *prgm; /* Main program */
    struct prgm *sub_prgm; /* Subpicture program */
    vlc_fourcc_t subpicture_chromas[2];

    unsigned nb_indices;
    GLuint vertex_buffer_object;
    GLuint index_buffer_object;
    GLuint texture_buffer_object[PICTURE_PLANE_MAX];

    GLuint *subpicture_buffer_object;
    int    subpicture_buffer_object_count;

    struct {
        unsigned int i_x_offset;
        unsigned int i_y_offset;
        unsigned int i_visible_width;
        unsigned int i_visible_height;
    } last_source;

    /* Non-power-of-2 texture size support */
    bool supports_npot;

    /* Fixed-function fallback: the GL engine is pre-2.0 and its advertised
     * GLSL is not actually executable, so draw with the fixed-function
     * pipeline instead of shaders (see the detection in vout_display_opengl_New). */
    bool fixed_function;

    /* The fragment pipeline can hold a long program: libplacebo's HDR tone
     * mapper may be appended to the conversion shader (see the detection in
     * vout_display_opengl_New). */
    bool supports_long_shaders;

    /* View point */
    float f_teta;
    float f_phi;
    float f_roll;
    float f_fovx; /* f_fovx and f_fovy are linked but we keep both */
    float f_fovy; /* to avoid recalculating them when needed.      */
    float f_z;    /* Position of the camera on the shpere radius vector */
    float f_z_min;
    float f_sar;
};

static const GLfloat identity[] = {
    1.0f, 0.0f, 0.0f, 0.0f,
    0.0f, 1.0f, 0.0f, 0.0f,
    0.0f, 0.0f, 1.0f, 0.0f,
    0.0f, 0.0f, 0.0f, 1.0f
};

/* rotation around the Z axis */
static void getZRotMatrix(float theta, GLfloat matrix[static 16])
{
    float st, ct;

    sincosf(theta, &st, &ct);

    const GLfloat m[] = {
    /*  x    y    z    w */
        ct,  -st, 0.f, 0.f,
        st,  ct,  0.f, 0.f,
        0.f, 0.f, 1.f, 0.f,
        0.f, 0.f, 0.f, 1.f
    };

    memcpy(matrix, m, sizeof(m));
}

/* rotation around the Y axis */
static void getYRotMatrix(float theta, GLfloat matrix[static 16])
{
    float st, ct;

    sincosf(theta, &st, &ct);

    const GLfloat m[] = {
    /*  x    y    z    w */
        ct,  0.f, -st, 0.f,
        0.f, 1.f, 0.f, 0.f,
        st,  0.f, ct,  0.f,
        0.f, 0.f, 0.f, 1.f
    };

    memcpy(matrix, m, sizeof(m));
}

/* rotation around the X axis */
static void getXRotMatrix(float phi, GLfloat matrix[static 16])
{
    float sp, cp;

    sincosf(phi, &sp, &cp);

    const GLfloat m[] = {
    /*  x    y    z    w */
        1.f, 0.f, 0.f, 0.f,
        0.f, cp,  sp,  0.f,
        0.f, -sp, cp,  0.f,
        0.f, 0.f, 0.f, 1.f
    };

    memcpy(matrix, m, sizeof(m));
}

static void getZoomMatrix(float zoom, GLfloat matrix[static 16]) {

    const GLfloat m[] = {
        /* x   y     z     w */
        1.0f, 0.0f, 0.0f, 0.0f,
        0.0f, 1.0f, 0.0f, 0.0f,
        0.0f, 0.0f, 1.0f, 0.0f,
        0.0f, 0.0f, zoom, 1.0f
    };

    memcpy(matrix, m, sizeof(m));
}

/* perspective matrix see https://www.opengl.org/sdk/docs/man2/xhtml/gluPerspective.xml */
static void getProjectionMatrix(float sar, float fovy, GLfloat matrix[static 16]) {

    float zFar  = 1000;
    float zNear = 0.01;

    float f = 1.f / tanf(fovy / 2.f);

    const GLfloat m[] = {
        f / sar, 0.f,                   0.f,                0.f,
        0.f,     f,                     0.f,                0.f,
        0.f,     0.f,     (zNear + zFar) / (zNear - zFar), -1.f,
        0.f,     0.f, (2 * zNear * zFar) / (zNear - zFar),  0.f};

     memcpy(matrix, m, sizeof(m));
}

static void getViewpointMatrixes(vout_display_opengl_t *vgl,
                                 video_projection_mode_t projection_mode,
                                 struct prgm *prgm)
{
    if (projection_mode == PROJECTION_MODE_EQUIRECTANGULAR
        || projection_mode == PROJECTION_MODE_CUBEMAP_LAYOUT_STANDARD)
    {
        float sar = (float) vgl->f_sar;
        getProjectionMatrix(sar, vgl->f_fovy, prgm->var.ProjectionMatrix);
        getYRotMatrix(vgl->f_teta, prgm->var.YRotMatrix);
        getXRotMatrix(vgl->f_phi, prgm->var.XRotMatrix);
        getZRotMatrix(vgl->f_roll, prgm->var.ZRotMatrix);
        getZoomMatrix(vgl->f_z, prgm->var.ZoomMatrix);
    }
    else
    {
        memcpy(prgm->var.ProjectionMatrix, identity, sizeof(identity));
        memcpy(prgm->var.ZRotMatrix, identity, sizeof(identity));
        memcpy(prgm->var.YRotMatrix, identity, sizeof(identity));
        memcpy(prgm->var.XRotMatrix, identity, sizeof(identity));
        memcpy(prgm->var.ZoomMatrix, identity, sizeof(identity));
    }
}

static void getOrientationTransformMatrix(video_orientation_t orientation,
                                          GLfloat matrix[static 16])
{
    memcpy(matrix, identity, sizeof(identity));

    const int k_cos_pi = -1;
    const int k_cos_pi_2 = 0;
    const int k_cos_n_pi_2 = 0;

    const int k_sin_pi = 0;
    const int k_sin_pi_2 = 1;
    const int k_sin_n_pi_2 = -1;

    switch (orientation) {

        case ORIENT_ROTATED_90:
            matrix[0 * 4 + 0] = k_cos_pi_2;
            matrix[0 * 4 + 1] = -k_sin_pi_2;
            matrix[1 * 4 + 0] = k_sin_pi_2;
            matrix[1 * 4 + 1] = k_cos_pi_2;
            matrix[3 * 4 + 1] = 1;
            break;
        case ORIENT_ROTATED_180:
            matrix[0 * 4 + 0] = k_cos_pi;
            matrix[0 * 4 + 1] = -k_sin_pi;
            matrix[1 * 4 + 0] = k_sin_pi;
            matrix[1 * 4 + 1] = k_cos_pi;
            matrix[3 * 4 + 0] = 1;
            matrix[3 * 4 + 1] = 1;
            break;
        case ORIENT_ROTATED_270:
            matrix[0 * 4 + 0] = k_cos_n_pi_2;
            matrix[0 * 4 + 1] = -k_sin_n_pi_2;
            matrix[1 * 4 + 0] = k_sin_n_pi_2;
            matrix[1 * 4 + 1] = k_cos_n_pi_2;
            matrix[3 * 4 + 0] = 1;
            break;
        case ORIENT_HFLIPPED:
            matrix[0 * 4 + 0] = -1;
            matrix[3 * 4 + 0] = 1;
            break;
        case ORIENT_VFLIPPED:
            matrix[1 * 4 + 1] = -1;
            matrix[3 * 4 + 1] = 1;
            break;
        case ORIENT_TRANSPOSED:
            matrix[0 * 4 + 0] = 0;
            matrix[1 * 4 + 1] = 0;
            matrix[2 * 4 + 2] = -1;
            matrix[0 * 4 + 1] = 1;
            matrix[1 * 4 + 0] = 1;
            break;
        case ORIENT_ANTI_TRANSPOSED:
            matrix[0 * 4 + 0] = 0;
            matrix[1 * 4 + 1] = 0;
            matrix[2 * 4 + 2] = -1;
            matrix[0 * 4 + 1] = -1;
            matrix[1 * 4 + 0] = -1;
            matrix[3 * 4 + 0] = 1;
            matrix[3 * 4 + 1] = 1;
            break;
        default:
            break;
    }
}

static inline GLsizei GetAlignedSize(unsigned size)
{
    /* Return the smallest larger or equal power of 2 */
    unsigned align = 1 << (8 * sizeof (unsigned) - clz(size));
    return ((align >> 1) == size) ? size : align;
}

static GLuint BuildVertexShader(const opengl_tex_converter_t *tc,
                                unsigned plane_count)
{
    /* Basic vertex shader */
    static const char *template =
        "#version %u\n"
        "varying vec2 TexCoord0;\n"
        "attribute vec4 MultiTexCoord0;\n"
        "%s%s"
        "attribute vec3 VertexPosition;\n"
        "uniform mat4 OrientationMatrix;\n"
        "uniform mat4 ProjectionMatrix;\n"
        "uniform mat4 XRotMatrix;\n"
        "uniform mat4 YRotMatrix;\n"
        "uniform mat4 ZRotMatrix;\n"
        "uniform mat4 ZoomMatrix;\n"
        "void main() {\n"
        " TexCoord0 = vec4(OrientationMatrix * MultiTexCoord0).st;\n"
        "%s%s"
        " gl_Position = ProjectionMatrix * ZoomMatrix * ZRotMatrix * XRotMatrix * YRotMatrix * vec4(VertexPosition, 1.0);\n"
        "}";

    const char *coord1_header = plane_count > 1 ?
        "varying vec2 TexCoord1;\nattribute vec4 MultiTexCoord1;\n" : "";
    const char *coord1_code = plane_count > 1 ?
        " TexCoord1 = vec4(OrientationMatrix * MultiTexCoord1).st;\n" : "";
    const char *coord2_header = plane_count > 2 ?
        "varying vec2 TexCoord2;\nattribute vec4 MultiTexCoord2;\n" : "";
    const char *coord2_code = plane_count > 2 ?
        " TexCoord2 = vec4(OrientationMatrix * MultiTexCoord2).st;\n" : "";

    char *code;
    if (asprintf(&code, template, tc->glsl_version, coord1_header, coord2_header,
                 coord1_code, coord2_code) < 0)
        return 0;

    GLuint shader = tc->vt->CreateShader(GL_VERTEX_SHADER);
    tc->vt->ShaderSource(shader, 1, (const char **) &code, NULL);
    if (tc->b_dump_shaders)
        msg_Dbg(tc->gl, "\n=== Vertex shader for fourcc: %4.4s ===\n%s\n",
                (const char *)&tc->fmt.i_chroma, code);
    tc->vt->CompileShader(shader);
    free(code);
    return shader;
}

static int
GenTextures(const opengl_tex_converter_t *tc,
            const GLsizei *tex_width, const GLsizei *tex_height,
            GLuint *textures)
{
    tc->vt->GenTextures(tc->tex_count, textures);

    for (unsigned i = 0; i < tc->tex_count; i++)
    {
        tc->vt->BindTexture(tc->tex_target, textures[i]);

#if !defined(USE_OPENGL_ES2)
        /* Set the texture parameters */
        tc->vt->TexParameterf(tc->tex_target, GL_TEXTURE_PRIORITY, 1.0);
        tc->vt->TexEnvf(GL_TEXTURE_ENV, GL_TEXTURE_ENV_MODE, GL_MODULATE);
#endif

        tc->vt->TexParameteri(tc->tex_target, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
        tc->vt->TexParameteri(tc->tex_target, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
        tc->vt->TexParameteri(tc->tex_target, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
        tc->vt->TexParameteri(tc->tex_target, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
    }

    if (tc->pf_allocate_textures != NULL)
    {
        int ret = tc->pf_allocate_textures(tc, textures, tex_width, tex_height);
        if (ret != VLC_SUCCESS)
        {
            tc->vt->DeleteTextures(tc->tex_count, textures);
            memset(textures, 0, tc->tex_count * sizeof(GLuint));
            return ret;
        }
    }
    return VLC_SUCCESS;
}

static void
DelTextures(const opengl_tex_converter_t *tc, GLuint *textures)
{
    tc->vt->DeleteTextures(tc->tex_count, textures);
    memset(textures, 0, tc->tex_count * sizeof(GLuint));
}

static int
opengl_link_program(struct prgm *prgm)
{
    opengl_tex_converter_t *tc = prgm->tc;

    if (tc->fixed_function)
    {
        /* No GLSL program on this hardware: the picture is drawn with the
         * fixed-function pipeline. Drop the fragment shader the converter
         * created (it would never be used) and leave prgm->id at 0. */
        if (tc->fshader != 0)
            tc->vt->DeleteShader(tc->fshader);
        tc->fshader = 0;
        prgm->id = 0;
        return VLC_SUCCESS;
    }

    GLuint vertex_shader = BuildVertexShader(tc, tc->tex_count);
    GLuint shaders[] = { tc->fshader, vertex_shader };

    /* Check shaders messages */
    for (unsigned i = 0; i < 2; i++) {
        int infoLength;
        tc->vt->GetShaderiv(shaders[i], GL_INFO_LOG_LENGTH, &infoLength);
        if (infoLength <= 1)
            continue;

        char *infolog = malloc(infoLength);
        if (infolog != NULL)
        {
            int charsWritten;
            tc->vt->GetShaderInfoLog(shaders[i], infoLength, &charsWritten,
                                      infolog);
            msg_Err(tc->gl, "shader %d: %s", i, infolog);
            free(infolog);
        }
    }

    prgm->id = tc->vt->CreateProgram();
    tc->vt->AttachShader(prgm->id, tc->fshader);
    tc->vt->AttachShader(prgm->id, vertex_shader);
    tc->vt->LinkProgram(prgm->id);

    tc->vt->DeleteShader(vertex_shader);
    tc->vt->DeleteShader(tc->fshader);

    /* Check program messages */
    int infoLength = 0;
    tc->vt->GetProgramiv(prgm->id, GL_INFO_LOG_LENGTH, &infoLength);
    if (infoLength > 1)
    {
        char *infolog = malloc(infoLength);
        if (infolog != NULL)
        {
            int charsWritten;
            tc->vt->GetProgramInfoLog(prgm->id, infoLength, &charsWritten,
                                       infolog);
            msg_Err(tc->gl, "shader program: %s", infolog);
            free(infolog);
        }

        /* If there is some message, better to check linking is ok */
        GLint link_status = GL_TRUE;
        tc->vt->GetProgramiv(prgm->id, GL_LINK_STATUS, &link_status);
        if (link_status == GL_FALSE)
        {
            msg_Err(tc->gl, "Unable to use program");
            goto error;
        }
    }

    /* Fetch UniformLocations and AttribLocations */
#define GET_LOC(type, x, str) do { \
    x = tc->vt->Get##type##Location(prgm->id, str); \
    assert(x != -1); \
    if (x == -1) { \
        msg_Err(tc->gl, "Unable to Get"#type"Location(%s)\n", str); \
        goto error; \
    } \
} while (0)
#define GET_ULOC(x, str) GET_LOC(Uniform, prgm->uloc.x, str)
#define GET_ALOC(x, str) GET_LOC(Attrib, prgm->aloc.x, str)
    GET_ULOC(OrientationMatrix, "OrientationMatrix");
    GET_ULOC(ProjectionMatrix, "ProjectionMatrix");
    GET_ULOC(ZRotMatrix, "ZRotMatrix");
    GET_ULOC(YRotMatrix, "YRotMatrix");
    GET_ULOC(XRotMatrix, "XRotMatrix");
    GET_ULOC(ZoomMatrix, "ZoomMatrix");

    GET_ALOC(VertexPosition, "VertexPosition");
    GET_ALOC(MultiTexCoord[0], "MultiTexCoord0");
    /* MultiTexCoord 1 and 2 can be optimized out if not used */
    if (prgm->tc->tex_count > 1)
        GET_ALOC(MultiTexCoord[1], "MultiTexCoord1");
    else
        prgm->aloc.MultiTexCoord[1] = -1;
    if (prgm->tc->tex_count > 2)
        GET_ALOC(MultiTexCoord[2], "MultiTexCoord2");
    else
        prgm->aloc.MultiTexCoord[2] = -1;
#undef GET_LOC
#undef GET_ULOC
#undef GET_ALOC
    int ret = prgm->tc->pf_fetch_locations(prgm->tc, prgm->id);
    assert(ret == VLC_SUCCESS);
    if (ret != VLC_SUCCESS)
    {
        msg_Err(tc->gl, "Unable to get locations from tex_conv");
        goto error;
    }

    return VLC_SUCCESS;

error:
    tc->vt->DeleteProgram(prgm->id);
    prgm->id = 0;
    return VLC_EGENERIC;
}

static void
opengl_deinit_program(vout_display_opengl_t *vgl, struct prgm *prgm)
{
    opengl_tex_converter_t *tc = prgm->tc;
    if (tc->p_module != NULL)
        module_unneed(tc, tc->p_module);
    else if (tc->priv != NULL)
        opengl_tex_converter_generic_deinit(tc);
    if (prgm->id != 0)
        vgl->vt.DeleteProgram(prgm->id);

#ifdef HAVE_LIBPLACEBO
    FREENULL(tc->uloc.pl_vars);
    if (tc->pl_ctx)
        pl_context_destroy(&tc->pl_ctx);
#endif

    vlc_object_release(tc);
}

#ifdef HAVE_LIBPLACEBO
static void
log_cb(void *priv, enum pl_log_level level, const char *msg)
{
    opengl_tex_converter_t *tc = priv;
    switch (level) {
    case PL_LOG_FATAL: // fall through
    case PL_LOG_ERR:  msg_Err(tc->gl, "%s", msg); break;
    case PL_LOG_WARN: msg_Warn(tc->gl,"%s", msg); break;
    case PL_LOG_INFO: msg_Info(tc->gl,"%s", msg); break;
    default: break;
    }
}
#endif

static int
opengl_init_program(vout_display_opengl_t *vgl, struct prgm *prgm,
                    const char *glexts, const video_format_t *fmt, bool subpics,
                    bool b_dump_shaders)
{
    opengl_tex_converter_t *tc =
        vlc_object_create(vgl->gl, sizeof(opengl_tex_converter_t));
    if (tc == NULL)
        return VLC_ENOMEM;

    tc->gl = vgl->gl;
    tc->vt = &vgl->vt;
    tc->b_dump_shaders = b_dump_shaders;
    tc->pf_fragment_shader_init = opengl_fragment_shader_init_impl;
    tc->glexts = glexts;
    tc->fixed_function = vgl->fixed_function;
#if defined(USE_OPENGL_ES2)
    tc->is_gles = true;
    tc->glsl_version = 100;
    tc->glsl_precision_header = "precision highp float;\n";
#else
    tc->is_gles = false;
    tc->glsl_version = 120;
    tc->glsl_precision_header = "";
#endif
    tc->fmt = *fmt;

#ifdef HAVE_LIBPLACEBO
    // create the main libplacebo context
    if (!subpics && vgl->supports_long_shaders)
    {
#if defined(__linux__) && !defined(USE_OPENGL_ES2)
        /* Mesa's libplacebo shaders need the boolean-vector mix() overload
         * from desktop GLSL 1.30. Keep 1.20 on genuinely old contexts. */
        const char *reported = (const char *)
            tc->vt->GetString(GL_SHADING_LANGUAGE_VERSION);
        unsigned major = 0, minor = 0;
        if (reported && sscanf(reported, "%u.%u", &major, &minor) == 2 &&
            major * 100 + minor >= 130)
            tc->glsl_version = 130;
#endif
        tc->pl_ctx = pl_context_create(PL_API_VER, &(struct pl_context_params) {
            .log_cb    = log_cb,
            .log_priv  = tc,
            .log_level = PL_LOG_INFO,
        });
        if (tc->pl_ctx) {
#   if PL_API_VER >= 20
            tc->pl_sh = pl_shader_alloc(tc->pl_ctx, &(struct pl_shader_params) {
                .glsl.version = tc->glsl_version,
                .glsl.gles = tc->is_gles,
            });
#   elif PL_API_VER >= 6
            tc->pl_sh = pl_shader_alloc(tc->pl_ctx, NULL, 0);
#   else
            tc->pl_sh = pl_shader_alloc(tc->pl_ctx, NULL, 0, 0);
#   endif
        }
    }
#endif

    int ret;
    if (subpics)
    {
        /* Normal orientation and no projection for subtitles */
        tc->fmt.orientation = ORIENT_NORMAL;
        tc->fmt.projection_mode = PROJECTION_MODE_RECTANGULAR;
        tc->fmt.primaries = COLOR_PRIMARIES_UNDEF;
        tc->fmt.transfer = TRANSFER_FUNC_UNDEF;
        tc->fmt.space = COLOR_SPACE_UNDEF;

        /* BD-J supplies its ARGB canvas in BGRA byte order on little-endian
         * machines. Desktop OpenGL can upload that layout directly with
         * GL_BGRA; asking the SPU core for RGBA instead made swscale convert
         * the complete 1920x1080 menu canvas for every video frame (about
         * 40 ms on Apple Silicon, already longer than a 23.976 fps period).
         * Prefer the native layout when the GL implementation accepts it.
         * GLES and big-endian hosts retain the universally available RGBA
         * path; small text/PGS regions are converted as before. */
#if !defined(USE_OPENGL_ES2) && !defined(WORDS_BIGENDIAN)
        tc->fmt.i_chroma = VLC_CODEC_BGRA;
        ret = opengl_tex_converter_generic_init(tc, false);
        if (ret != VLC_SUCCESS)
#endif
        {
            tc->fmt.i_chroma = VLC_CODEC_RGB32;
            ret = opengl_tex_converter_generic_init(tc, false);
        }
    }
    else
    {
        const vlc_chroma_description_t *desc =
            vlc_fourcc_GetChromaDescription(fmt->i_chroma);

        if (desc == NULL)
        {
            vlc_object_release(tc);
            return VLC_EGENERIC;
        }
        if (desc->plane_count == 0)
        {
            /* Opaque chroma: load a module to handle it */
            tc->p_module = module_need(tc, "glconv", "$glconv", true);
        }

        if (tc->p_module != NULL)
            ret = VLC_SUCCESS;
        else
        {
            /* Software chroma or gl hw converter failed: use a generic
             * converter */
            ret = opengl_tex_converter_generic_init(tc, true);
        }
    }

    if (ret != VLC_SUCCESS)
    {
        vlc_object_release(tc);
        return VLC_EGENERIC;
    }

    assert(tc->fshader != 0 && tc->tex_target != 0 && tc->tex_count > 0 &&
           tc->pf_update != NULL && tc->pf_fetch_locations != NULL &&
           tc->pf_prepare_shader != NULL);

    prgm->tc = tc;

    ret = opengl_link_program(prgm);
    if (ret != VLC_SUCCESS)
    {
        opengl_deinit_program(vgl, prgm);
        return VLC_EGENERIC;
    }

    getOrientationTransformMatrix(tc->fmt.orientation,
                                  prgm->var.OrientationMatrix);
    getViewpointMatrixes(vgl, tc->fmt.projection_mode, prgm);

    return VLC_SUCCESS;
}

static void
ResizeFormatToGLMaxTexSize(video_format_t *fmt, unsigned int max_tex_size)
{
    if (fmt->i_width > fmt->i_height)
    {
        unsigned int const  vis_w = fmt->i_visible_width;
        unsigned int const  vis_h = fmt->i_visible_height;
        unsigned int const  nw_w = max_tex_size;
        unsigned int const  nw_vis_w = nw_w * vis_w / fmt->i_width;

        fmt->i_height = nw_w * fmt->i_height / fmt->i_width;
        fmt->i_width = nw_w;
        fmt->i_visible_height = nw_vis_w * vis_h / vis_w;
        fmt->i_visible_width = nw_vis_w;
    }
    else
    {
        unsigned int const  vis_w = fmt->i_visible_width;
        unsigned int const  vis_h = fmt->i_visible_height;
        unsigned int const  nw_h = max_tex_size;
        unsigned int const  nw_vis_h = nw_h * vis_h / fmt->i_height;

        fmt->i_width = nw_h * fmt->i_width / fmt->i_height;
        fmt->i_height = nw_h;
        fmt->i_visible_width = nw_vis_h * vis_w / vis_h;
        fmt->i_visible_height = nw_vis_h;
    }
}

bool vout_display_opengl_IsSoftware(vlc_gl_t *gl)
{
    PFNGLGETSTRINGPROC GetStringFn = vlc_gl_GetProcAddress(gl, "glGetString");
    if (GetStringFn == NULL)
        return false; /* cannot tell: assume hardware, i.e. do not interfere */

    const char *renderer = (const char *)GetStringFn(GL_RENDERER);
    if (renderer == NULL)
        return false;

    /* Mesa's software rasterisers. llvmpipe reports e.g.
     * "llvmpipe (LLVM 19.1.7, 128 bits)"; softpipe and swrast name themselves
     * likewise. No hardware driver advertises these names, so a substring
     * match is safe and survives version churn. */
    static const char *const soft[] = { "llvmpipe", "softpipe", "swrast" };
    for (size_t i = 0; i < sizeof (soft) / sizeof (soft[0]); i++)
        if (strstr(renderer, soft[i]) != NULL)
            return true;

    return false;
}

vout_display_opengl_t *vout_display_opengl_New(video_format_t *fmt,
                                               const vlc_fourcc_t **subpicture_chromas,
                                               vlc_gl_t *gl,
                                               const vlc_viewpoint_t *viewpoint)
{
    if (gl->getProcAddress == NULL) {
        msg_Err(gl, "getProcAddress not implemented, bailing out\n");
        return NULL;
    }

    vout_display_opengl_t *vgl = calloc(1, sizeof(*vgl));
    if (!vgl)
        return NULL;

    vgl->gl = gl;
    vgl->supports_long_shaders = true;

#ifdef HAVE_LIBPLACEBO_NEXT
    /* The VLC 3 OpenGL shader adapter predates parsed Dolby Vision metadata
     * and cannot combine a Profile 7 enhancement layer. Keep this as a
     * separate renderer owning the same, already-current GL context. */
    bool needs_hdr_renderer = vout_display_opengl_RequiresHDRRenderer(fmt);
#ifdef __linux__
    /* Profile 8 may expose only its HLG-compatible base layer before the
     * first decoded picture carries the RPU. The explicit Linux transport
     * request is an additional renderer hint in that short interval. */
    needs_hdr_renderer |= var_InheritBool(gl, "gl-dovi-hdmi") &&
        (fmt->transfer == TRANSFER_FUNC_SMPTE_ST2084 ||
         fmt->transfer == TRANSFER_FUNC_HLG ||
         fmt->primaries == COLOR_PRIMARIES_BT2020);
#endif
    if (needs_hdr_renderer)
    {
        /* Download hardware surfaces without losing ten-bit precision.
         * cvpx already implements CVPX_P010 -> I420_10L. */
        switch (fmt->i_chroma)
        {
            case VLC_CODEC_CVPX_P010:
            case VLC_CODEC_P010:
                fmt->i_chroma = VLC_CODEC_I420_10L;
                break;
            case VLC_CODEC_CVPX_NV12:
            case VLC_CODEC_CVPX_I420:
            case VLC_CODEC_NV12:
                fmt->i_chroma = VLC_CODEC_I420;
                break;
            case VLC_CODEC_CVPX_BGRA:
                fmt->i_chroma = VLC_CODEC_BGRA;
                break;
        }
        vgl->dovi = vlc_dovi_renderer_Create(gl, fmt);
        if (!vgl->dovi)
        {
            msg_Err(gl, "cannot initialize the Dolby Vision/HDR renderer");
            free(vgl);
            return NULL;
        }
        vgl->fmt = *fmt;
        if (subpicture_chromas)
        {
            vgl->subpicture_chromas[0] = VLC_CODEC_RGBA;
            vgl->subpicture_chromas[1] = 0;
            *subpicture_chromas = vgl->subpicture_chromas;
        }
        return vgl;
    }
#endif

#if defined(USE_OPENGL_ES2) || defined(HAVE_GL_CORE_SYMBOLS)
#define GET_PROC_ADDR_CORE(name) vgl->vt.name = gl##name
#else
#define GET_PROC_ADDR_CORE(name) GET_PROC_ADDR_EXT(name, true)
#endif
#define GET_PROC_ADDR_EXT(name, critical) do { \
    vgl->vt.name = vlc_gl_GetProcAddress(gl, "gl"#name); \
    if (vgl->vt.name == NULL && critical) { \
        msg_Err(gl, "gl"#name" symbol not found, bailing out\n"); \
        free(vgl); \
        return NULL; \
    } \
} while(0)
#if defined(USE_OPENGL_ES2)
#define GET_PROC_ADDR(name) GET_PROC_ADDR_CORE(name)
#define GET_PROC_ADDR_CORE_GL(name) GET_PROC_ADDR_EXT(name, false) /* optional for GLES */
#else
#define GET_PROC_ADDR(name) GET_PROC_ADDR_EXT(name, true)
#define GET_PROC_ADDR_CORE_GL(name) GET_PROC_ADDR_CORE(name)
#endif
#define GET_PROC_ADDR_OPTIONAL(name) GET_PROC_ADDR_EXT(name, false) /* GL 3 or more */

    GET_PROC_ADDR_CORE(BindTexture);
    GET_PROC_ADDR_CORE(BlendFunc);
    GET_PROC_ADDR_CORE(Clear);
    GET_PROC_ADDR_CORE(ClearColor);
    GET_PROC_ADDR_CORE(ColorMask);
    GET_PROC_ADDR_CORE(DeleteTextures);
    GET_PROC_ADDR_CORE(DepthMask);
    GET_PROC_ADDR_CORE(Disable);
    GET_PROC_ADDR_CORE(DrawArrays);
    GET_PROC_ADDR_CORE(DrawElements);
    GET_PROC_ADDR_CORE(Enable);
    GET_PROC_ADDR_CORE(Finish);
    GET_PROC_ADDR_CORE(Flush);
    GET_PROC_ADDR_CORE(GenTextures);
    GET_PROC_ADDR_CORE(GetError);
    GET_PROC_ADDR_CORE(GetIntegerv);
    GET_PROC_ADDR_CORE(GetString);
    GET_PROC_ADDR_CORE(PixelStorei);
    GET_PROC_ADDR_CORE(TexImage2D);
    GET_PROC_ADDR_CORE(TexParameterf);
    GET_PROC_ADDR_CORE(TexParameteri);
    GET_PROC_ADDR_CORE(TexSubImage2D);
    GET_PROC_ADDR_CORE(Viewport);

    GET_PROC_ADDR_CORE_GL(GetTexLevelParameteriv);
    GET_PROC_ADDR_CORE_GL(TexEnvf);

#if !defined(USE_OPENGL_ES2)
    /* Fixed-function pipeline (optional; only used when GLSL is unusable). */
    GET_PROC_ADDR_OPTIONAL(MatrixMode);
    GET_PROC_ADDR_OPTIONAL(LoadIdentity);
    GET_PROC_ADDR_OPTIONAL(LoadMatrixf);
    GET_PROC_ADDR_OPTIONAL(EnableClientState);
    GET_PROC_ADDR_OPTIONAL(DisableClientState);
    GET_PROC_ADDR_OPTIONAL(VertexPointer);
    GET_PROC_ADDR_OPTIONAL(TexCoordPointer);
    GET_PROC_ADDR_OPTIONAL(Color4f);
#endif

    GET_PROC_ADDR(CreateShader);
    GET_PROC_ADDR(ShaderSource);
    GET_PROC_ADDR(CompileShader);
    GET_PROC_ADDR(AttachShader);
    GET_PROC_ADDR(DeleteShader);

    GET_PROC_ADDR(GetProgramiv);
    GET_PROC_ADDR(GetShaderiv);
    GET_PROC_ADDR(GetProgramInfoLog);
    GET_PROC_ADDR(GetShaderInfoLog);

    GET_PROC_ADDR(GetUniformLocation);
    GET_PROC_ADDR(GetAttribLocation);
    GET_PROC_ADDR(VertexAttribPointer);
    GET_PROC_ADDR(EnableVertexAttribArray);
    GET_PROC_ADDR(UniformMatrix4fv);
    GET_PROC_ADDR(UniformMatrix3fv);
    GET_PROC_ADDR(UniformMatrix2fv);
    GET_PROC_ADDR(Uniform4fv);
    GET_PROC_ADDR(Uniform4f);
    GET_PROC_ADDR(Uniform3f);
    GET_PROC_ADDR(Uniform2f);
    GET_PROC_ADDR(Uniform1f);
    GET_PROC_ADDR(Uniform1i);

    GET_PROC_ADDR(CreateProgram);
    GET_PROC_ADDR(LinkProgram);
    GET_PROC_ADDR(UseProgram);
    GET_PROC_ADDR(DeleteProgram);

    GET_PROC_ADDR(ActiveTexture);

    GET_PROC_ADDR(GenBuffers);
    GET_PROC_ADDR(BindBuffer);
    GET_PROC_ADDR(BufferData);
    GET_PROC_ADDR(DeleteBuffers);

    GET_PROC_ADDR_OPTIONAL(GetFramebufferAttachmentParameteriv);
    GET_PROC_ADDR_OPTIONAL(BindFramebuffer);
    GET_PROC_ADDR_OPTIONAL(CheckFramebufferStatus);
    GET_PROC_ADDR_OPTIONAL(DeleteFramebuffers);
    GET_PROC_ADDR_OPTIONAL(FramebufferTexture2D);
    GET_PROC_ADDR_OPTIONAL(GenFramebuffers);
    GET_PROC_ADDR_OPTIONAL(GenerateMipmap);
    GET_PROC_ADDR_OPTIONAL(BlitFramebuffer);

    GET_PROC_ADDR_OPTIONAL(BufferSubData);
    GET_PROC_ADDR_OPTIONAL(BufferStorage);
    GET_PROC_ADDR_OPTIONAL(MapBufferRange);
    GET_PROC_ADDR_OPTIONAL(FlushMappedBufferRange);
    GET_PROC_ADDR_OPTIONAL(UnmapBuffer);
    GET_PROC_ADDR_OPTIONAL(FenceSync);
    GET_PROC_ADDR_OPTIONAL(DeleteSync);
    GET_PROC_ADDR_OPTIONAL(ClientWaitSync);
#undef GET_PROC_ADDR

    GL_ASSERT_NOERROR();

    const char *extensions = (const char *)vgl->vt.GetString(GL_EXTENSIONS);
    assert(extensions);
    if (!extensions)
    {
        msg_Err(gl, "glGetString returned NULL\n");
        free(vgl);
        return NULL;
    }

    /* Name the engine in the log. The fixed-function output does it and it has
     * been the one useful line in every bug report about a black or garbled
     * picture; the shader output stayed mute, so a report from it could not
     * even tell which GPU had drawn the frame. */
    const char *gl_renderer = (const char *)vgl->vt.GetString(GL_RENDERER);
    const char *gl_version  = (const char *)vgl->vt.GetString(GL_VERSION);
    const char *gl_glsl = (const char *)vgl->vt.GetString(GL_SHADING_LANGUAGE_VERSION);
    msg_Dbg(gl, "GL renderer: %s | %s | GLSL %s",
            gl_renderer ? gl_renderer : "?", gl_version ? gl_version : "?",
            gl_glsl ? gl_glsl : "none");

#if !defined(USE_OPENGL_ES2)
    // Check for OpenGL < 2.0
    const unsigned char *ogl_version = vgl->vt.GetString(GL_VERSION);
    if (strverscmp((const char *)ogl_version, "2.0") < 0) {
        // Even with OpenGL < 2.0 we might have GLSL support,
        // so check the GLSL version before finally giving up:
        const unsigned char *glsl_version = vgl->vt.GetString(GL_SHADING_LANGUAGE_VERSION);
        if (!glsl_version || strverscmp((const char *)glsl_version, "1.10") < 0) {
            msg_Err(gl, "shaders not supported, bailing out\n");
            free(vgl);
            return NULL;
        }
        /* A GLSL version is advertised, but on a pre-2.0 engine it is often not
         * actually executable (e.g. the ATI Radeon 9200 under Mac OS X 10.5
         * reports GLSL 1.20 on a GL 1.3 engine: shaders link yet render black).
         * Fall back to the fixed-function pipeline when its entry points are
         * available rather than showing a black picture. */
        if (vgl->vt.MatrixMode != NULL && vgl->vt.LoadIdentity != NULL
         && vgl->vt.LoadMatrixf != NULL && vgl->vt.EnableClientState != NULL
         && vgl->vt.DisableClientState != NULL && vgl->vt.VertexPointer != NULL
         && vgl->vt.TexCoordPointer != NULL && vgl->vt.Color4f != NULL) {
            vgl->fixed_function = true;
            msg_Warn(gl, "OpenGL %s engine advertises GLSL %s but likely cannot "
                         "run it; using the fixed-function pipeline",
                     (const char *)ogl_version, (const char *)glsl_version);
        }
    }

    /* Tone mapping (libplacebo) appends a hundred-odd instructions to the
     * conversion shader. Shader-Model-2 hardware caps the fragment pipeline
     * far below that -- the ATI R300 family (Radeon 9550/9600/9700, i.e. every
     * GPU an AGP-era PowerBook/iMac G4 or G5 shipped with) allows 64 ALU
     * instructions -- and its drivers do not always report the overflow: the
     * program links and then draws BLACK, which is what an HDR (BT.2020/PQ/HLG)
     * clip looks like there while SDR clips, whose shader stays short, play
     * fine. ARB_fragment_program exposes that budget, so ask for it and keep
     * the tone mapper only for engines that can actually run it. A driver that
     * no longer advertises the extension (core profiles) is modern enough. */
    if (HasExtension(extensions, "GL_ARB_fragment_program"))
    {
#ifndef GL_FRAGMENT_PROGRAM_ARB
#   define GL_FRAGMENT_PROGRAM_ARB 0x8804
#endif
#ifndef GL_MAX_PROGRAM_NATIVE_ALU_INSTRUCTIONS_ARB
#   define GL_MAX_PROGRAM_NATIVE_ALU_INSTRUCTIONS_ARB 0x88AB
#endif
        /* Not in the vtable: ARB_fragment_program is desktop-only and this is
         * the single place that needs it. */
        void (APIENTRY *GetProgramivARB)(GLenum, GLenum, GLint *) =
            vlc_gl_GetProcAddress(gl, "glGetProgramivARB");
        GLint max_alu = 0;
        if (GetProgramivARB != NULL)
            GetProgramivARB(GL_FRAGMENT_PROGRAM_ARB,
                            GL_MAX_PROGRAM_NATIVE_ALU_INSTRUCTIONS_ARB,
                            &max_alu);
        /* Swallow the GL_INVALID_* an engine without a bound program object
         * may raise here: it must not trip the GL_ASSERT_NOERROR() below. */
        while (vgl->vt.GetError() != GL_NO_ERROR)
            ;
        if (max_alu > 0 && max_alu < 256)
        {
            vgl->supports_long_shaders = false;
            msg_Warn(gl, "fragment pipeline limited to %d ALU instructions: "
                         "HDR tone mapping disabled (it would render black)",
                     (int)max_alu);
        }
        else
            msg_Dbg(gl, "fragment pipeline: %d ALU instructions", (int)max_alu);
    }
#endif

#ifdef HAVE_LIBPLACEBO
    /* Manual override, for the engines the probe above cannot judge: a driver
     * that hides ARB_fragment_program, or one whose reported budget does not
     * match what it will actually run. */
    if (vgl->supports_long_shaders && !var_InheritBool(gl, "tone-mapping-enable"))
    {
        vgl->supports_long_shaders = false;
        msg_Dbg(gl, "HDR tone mapping disabled by tone-mapping-enable");
    }
#endif

    /* Resize the format if it is greater than the maximum texture size
     * supported by the hardware */
    GLint       max_tex_size;
    vgl->vt.GetIntegerv(GL_MAX_TEXTURE_SIZE, &max_tex_size);

    if ((GLint)fmt->i_width > max_tex_size ||
        (GLint)fmt->i_height > max_tex_size)
        ResizeFormatToGLMaxTexSize(fmt, max_tex_size);

#if defined(USE_OPENGL_ES2)
    /* OpenGL ES 2 includes support for non-power of 2 textures by specification
     * so checks for extensions are bound to fail. Check for OpenGL ES version instead. */
    vgl->supports_npot = true;
#else
    vgl->supports_npot = HasExtension(extensions, "GL_ARB_texture_non_power_of_two") ||
                         HasExtension(extensions, "GL_APPLE_texture_2D_limited_npot");
#endif

    bool b_dump_shaders = var_InheritInteger(gl, "verbose") >= 4;

    vgl->prgm = &vgl->prgms[0];
    vgl->sub_prgm = &vgl->prgms[1];

    GL_ASSERT_NOERROR();
    int ret;
    ret = opengl_init_program(vgl, vgl->prgm, extensions, fmt, false,
                              b_dump_shaders);
    if (ret != VLC_SUCCESS)
    {
        msg_Warn(gl, "could not init tex converter for %4.4s",
                 (const char *) &fmt->i_chroma);
        free(vgl);
        return NULL;
    }

    GL_ASSERT_NOERROR();
    ret = opengl_init_program(vgl, vgl->sub_prgm, extensions, fmt, true,
                              b_dump_shaders);
    if (ret != VLC_SUCCESS)
    {
        msg_Warn(gl, "could not init subpictures tex converter for %4.4s",
                 (const char *) &fmt->i_chroma);
        opengl_deinit_program(vgl, vgl->prgm);
        free(vgl);
        return NULL;
    }
    GL_ASSERT_NOERROR();
    /* Update the fmt to main program one */
    vgl->fmt = vgl->prgm->tc->fmt;
    vgl->source_multiview_mode = fmt->multiview_mode;
    /* A packed source is not necessarily being sent to a 3D sink.  Keep the
     * normal one-eye preview until the platform vout confirms that a real
     * frame-packing display mode was selected. */
    vgl->output_framepacked = false;
    /* The orientation is handled by the orientation matrix */
    vgl->fmt.orientation = fmt->orientation;

    /* Texture size */
    const opengl_tex_converter_t *tc = vgl->prgm->tc;
    for (unsigned j = 0; j < tc->tex_count; j++) {
        const GLsizei w = vgl->fmt.i_visible_width  * tc->texs[j].w.num
                        / tc->texs[j].w.den;
        const GLsizei h = vgl->fmt.i_visible_height * tc->texs[j].h.num
                        / tc->texs[j].h.den;
        if (vgl->supports_npot) {
            vgl->tex_width[j]  = w;
            vgl->tex_height[j] = h;
        } else {
            vgl->tex_width[j]  = GetAlignedSize(w);
            vgl->tex_height[j] = GetAlignedSize(h);
        }
    }

    /* Allocates our textures */
    assert(!vgl->sub_prgm->tc->handle_texs_gen);

    if (!vgl->prgm->tc->handle_texs_gen)
    {
        ret = GenTextures(vgl->prgm->tc, vgl->tex_width, vgl->tex_height,
                          vgl->texture);
        if (ret != VLC_SUCCESS)
        {
            vout_display_opengl_Delete(vgl);
            return NULL;
        }
    }

    /* */
    vgl->vt.Disable(GL_BLEND);
    vgl->vt.Disable(GL_DEPTH_TEST);
    vgl->vt.DepthMask(GL_FALSE);
    vgl->vt.Enable(GL_CULL_FACE);
    vgl->vt.ClearColor(0.0f, 0.0f, 0.0f, 1.0f);
    vgl->vt.Clear(GL_COLOR_BUFFER_BIT);

    vgl->vt.GenBuffers(1, &vgl->vertex_buffer_object);
    vgl->vt.GenBuffers(1, &vgl->index_buffer_object);
    vgl->vt.GenBuffers(vgl->prgm->tc->tex_count, vgl->texture_buffer_object);

    /* Initial number of allocated buffer objects for subpictures, will grow dynamically. */
    int subpicture_buffer_object_count = 8;
    vgl->subpicture_buffer_object = vlc_alloc(subpicture_buffer_object_count, sizeof(GLuint));
    if (!vgl->subpicture_buffer_object) {
        vout_display_opengl_Delete(vgl);
        return NULL;
    }
    vgl->subpicture_buffer_object_count = subpicture_buffer_object_count;
    vgl->vt.GenBuffers(vgl->subpicture_buffer_object_count, vgl->subpicture_buffer_object);

    /* RetroArch presets are a vout post-process, intentionally after colour
     * conversion and before SPU composition. The engine probes every preset
     * on the current driver and publishes only programs that really link. */
    if (!vgl->fixed_function)
        vgl->retroarch = vlc_ra_shader_engine_Create(gl, &vgl->vt,
                                                     vgl->supports_long_shaders);

    /* */
    vgl->region_count = 0;
    vgl->region = NULL;
    vgl->pool = NULL;

    if (vgl->fmt.projection_mode != PROJECTION_MODE_RECTANGULAR
     && vout_display_opengl_SetViewpoint(vgl, viewpoint) != VLC_SUCCESS)
    {
        vout_display_opengl_Delete(vgl);
        return NULL;
    }

    *fmt = vgl->fmt;
    if (subpicture_chromas) {
        vgl->subpicture_chromas[0] = vgl->sub_prgm->tc->fmt.i_chroma;
        /* RGB32 is the platform-native alias used to initialize the GL
         * converter; SPU regions use the explicit RGBA fourcc. */
        if (vgl->subpicture_chromas[0] == VLC_CODEC_RGB32)
            vgl->subpicture_chromas[0] = VLC_CODEC_RGBA;
        vgl->subpicture_chromas[1] = 0;
        msg_Dbg(gl, "OpenGL subpicture upload chroma: %4.4s",
                (const char *)&vgl->subpicture_chromas[0]);
        *subpicture_chromas = vgl->subpicture_chromas;
    }

    GL_ASSERT_NOERROR();
    return vgl;
}

void vout_display_opengl_SetFramePackingOutput(vout_display_opengl_t *vgl,
                                               bool enabled,
                                               unsigned eye_width,
                                               unsigned eye_height)
{
#ifdef HAVE_LIBPLACEBO_NEXT
    if (vgl->dovi)
        return;
#endif
    vgl->output_framepacked = enabled;
    vgl->output_eye_width = eye_width;
    vgl->output_eye_height = eye_height;

    /* Force the next Display() to rebuild both vertex and texture buffers. */
    vgl->last_source.i_visible_width = 0;
    vgl->last_source.i_visible_height = 0;
}

void vout_display_opengl_Delete(vout_display_opengl_t *vgl)
{
#ifdef HAVE_LIBPLACEBO_NEXT
    if (vgl->dovi)
    {
        vlc_dovi_renderer_Delete(vgl->dovi);
        free(vgl);
        return;
    }
#endif
    GL_ASSERT_NOERROR();

    /* */
    vgl->vt.Finish();
    vgl->vt.Flush();

    vlc_ra_shader_engine_Delete(vgl->retroarch);

    const size_t main_tex_count = vgl->prgm->tc->tex_count;
    const bool main_del_texs = !vgl->prgm->tc->handle_texs_gen;

    if (vgl->pool)
        picture_pool_Release(vgl->pool);
    opengl_deinit_program(vgl, vgl->prgm);
    opengl_deinit_program(vgl, vgl->sub_prgm);

    vgl->vt.DeleteBuffers(1, &vgl->vertex_buffer_object);
    vgl->vt.DeleteBuffers(1, &vgl->index_buffer_object);
    vgl->vt.DeleteBuffers(main_tex_count, vgl->texture_buffer_object);

    if (vgl->subpicture_buffer_object_count > 0)
        vgl->vt.DeleteBuffers(vgl->subpicture_buffer_object_count,
                              vgl->subpicture_buffer_object);
    free(vgl->subpicture_buffer_object);

    if (main_del_texs)
        vgl->vt.DeleteTextures(main_tex_count, vgl->texture);

    for (int i = 0; i < vgl->region_count; i++)
    {
        if (vgl->region[i].texture)
            vgl->vt.DeleteTextures(1, &vgl->region[i].texture);
    }
    free(vgl->region);
    GL_ASSERT_NOERROR();

    free(vgl);
}

static void UpdateZ(vout_display_opengl_t *vgl)
{
    /* Do trigonometry to calculate the minimal z value
     * that will allow us to zoom out without seeing the outside of the
     * sphere (black borders). */
    float tan_fovx_2 = tanf(vgl->f_fovx / 2);
    float tan_fovy_2 = tanf(vgl->f_fovy / 2);
    float z_min = - SPHERE_RADIUS / sinf(atanf(sqrtf(
                    tan_fovx_2 * tan_fovx_2 + tan_fovy_2 * tan_fovy_2)));

    /* The FOV value above which z is dynamically calculated. */
    const float z_thresh = 90.f;

    if (vgl->f_fovx <= z_thresh * M_PI / 180)
        vgl->f_z = 0;
    else
    {
        float f = z_min / ((FIELD_OF_VIEW_DEGREES_MAX - z_thresh) * M_PI / 180);
        vgl->f_z = f * vgl->f_fovx - f * z_thresh * M_PI / 180;
        if (vgl->f_z < z_min)
            vgl->f_z = z_min;
    }
}

static void UpdateFOVy(vout_display_opengl_t *vgl)
{
    vgl->f_fovy = 2 * atanf(tanf(vgl->f_fovx / 2) / vgl->f_sar);
}

int vout_display_opengl_SetViewpoint(vout_display_opengl_t *vgl,
                                     const vlc_viewpoint_t *p_vp)
{
#ifdef HAVE_LIBPLACEBO_NEXT
    if (vgl->dovi)
        return VLC_SUCCESS;
#endif
#define RAD(d) ((float) ((d) * M_PI / 180.f))
    float f_fovx = RAD(p_vp->fov);
    if (f_fovx > FIELD_OF_VIEW_DEGREES_MAX * M_PI / 180 + 0.001f
        || f_fovx < -0.001f)
        return VLC_EBADVAR;

    vgl->f_teta = RAD(p_vp->yaw) - (float) M_PI_2;
    vgl->f_phi  = RAD(p_vp->pitch);
    vgl->f_roll = RAD(p_vp->roll);


    if (fabsf(f_fovx - vgl->f_fovx) >= 0.001f)
    {
        /* FOVx has changed. */
        vgl->f_fovx = f_fovx;
        UpdateFOVy(vgl);
        UpdateZ(vgl);
    }
    getViewpointMatrixes(vgl, vgl->fmt.projection_mode, vgl->prgm);

    return VLC_SUCCESS;
#undef RAD
}


void vout_display_opengl_SetFramebuffer(vout_display_opengl_t *vgl, unsigned fbo)
{
#ifdef HAVE_LIBPLACEBO_NEXT
    if (vgl->dovi)
        vlc_dovi_renderer_SetFramebuffer(vgl->dovi, fbo);
#else
    VLC_UNUSED(vgl);
    VLC_UNUSED(fbo);
#endif
}

void vout_display_opengl_SetWindowAspectRatio(vout_display_opengl_t *vgl,
                                              float f_sar)
{
#ifdef HAVE_LIBPLACEBO_NEXT
    if (vgl->dovi)
        return;
#endif
    /* Each time the window size changes, we must recompute the minimum zoom
     * since the aspect ration changes.
     * We must also set the new current zoom value. */
    vgl->f_sar = f_sar;
    UpdateFOVy(vgl);
    UpdateZ(vgl);
    getViewpointMatrixes(vgl, vgl->fmt.projection_mode, vgl->prgm);
}

void vout_display_opengl_Viewport(vout_display_opengl_t *vgl, int x, int y,
                                  unsigned width, unsigned height)
{
#ifdef HAVE_LIBPLACEBO_NEXT
    if (vgl->dovi)
    {
        vlc_dovi_renderer_SetViewport(vgl->dovi, x, y, width, height);
        return;
    }
#endif
    vgl->vt.Viewport(x, y, width, height);
    vgl->viewport_width = width;
    vgl->viewport_height = height;
    vlc_ra_shader_engine_SetViewport(vgl->retroarch, x, y, width, height);
}

void vout_display_opengl_SetDrawableSize(vout_display_opengl_t *vgl,
                                         unsigned width, unsigned height)
{
#ifdef HAVE_LIBPLACEBO_NEXT
    if (vgl->dovi)
        vlc_dovi_renderer_SetDrawableSize(vgl->dovi, width, height);
#else
    VLC_UNUSED(vgl);
    VLC_UNUSED(width);
    VLC_UNUSED(height);
#endif
}

void vout_display_opengl_SetDisplayHeadroom(vout_display_opengl_t *vgl,
                                            float headroom)
{
#ifdef HAVE_LIBPLACEBO_NEXT
    if (vgl->dovi)
        vlc_dovi_renderer_SetDisplayHeadroom(vgl->dovi, headroom);
#else
    VLC_UNUSED(vgl);
    VLC_UNUSED(headroom);
#endif
}

picture_pool_t *vout_display_opengl_GetPool(vout_display_opengl_t *vgl, unsigned requested_count)
{
#ifdef HAVE_LIBPLACEBO_NEXT
    if (vgl->dovi)
        return vlc_dovi_renderer_GetPool(vgl->dovi, requested_count);
#endif
    GL_ASSERT_NOERROR();

    if (vgl->pool)
        return vgl->pool;

    opengl_tex_converter_t *tc = vgl->prgm->tc;
    requested_count = __MIN(VLCGL_PICTURE_MAX, requested_count);
    /* Allocate with tex converter pool callback if it exists */
    if (tc->pf_get_pool != NULL)
    {
        vgl->pool = tc->pf_get_pool(tc, requested_count);
        if (!vgl->pool)
            goto error;
        return vgl->pool;
    }

    /* Allocate our pictures */
    picture_t *picture[VLCGL_PICTURE_MAX] = {NULL, };
    unsigned count;
    for (count = 0; count < requested_count; count++)
    {
        picture[count] = picture_NewFromFormat(&vgl->fmt);
        if (!picture[count])
            break;
    }
    if (count <= 0)
        goto error;

    /* Wrap the pictures into a pool */
    vgl->pool = picture_pool_New(count, picture);
    if (!vgl->pool)
    {
        for (unsigned i = 0; i < count; i++)
            picture_Release(picture[i]);
        goto error;
    }

    GL_ASSERT_NOERROR();
    return vgl->pool;

error:
    DelTextures(tc, vgl->texture);
    return NULL;
}

int vout_display_opengl_Prepare(vout_display_opengl_t *vgl,
                                picture_t *picture, subpicture_t *subpicture)
{
#ifdef HAVE_LIBPLACEBO_NEXT
    if (vgl->dovi)
        return vlc_dovi_renderer_Prepare(vgl->dovi, picture, subpicture);
#endif
    GL_ASSERT_NOERROR();

    opengl_tex_converter_t *tc = vgl->prgm->tc;

    /* Update the texture */
    int ret = tc->pf_update(tc, vgl->texture, vgl->tex_width, vgl->tex_height,
                            picture, NULL);
    if (ret != VLC_SUCCESS)
        return ret;

    vlc_ra_shader_engine_NewFrame(vgl->retroarch, picture->date);

    int         last_count = vgl->region_count;
    gl_region_t *last = vgl->region;

    vgl->region_count = 0;
    vgl->region       = NULL;

    tc = vgl->sub_prgm->tc;
    if (subpicture) {

        int count = 0;
        for (subpicture_region_t *r = subpicture->p_region; r; r = r->p_next)
            count++;

        vgl->region_count = count;
        vgl->region       = calloc(count, sizeof(*vgl->region));

        int i = 0;
        for (subpicture_region_t *r = subpicture->p_region;
             r && ret == VLC_SUCCESS; r = r->p_next, i++) {
            gl_region_t *glr = &vgl->region[i];

            glr->width  = r->fmt.i_visible_width;
            glr->height = r->fmt.i_visible_height;
            if (!vgl->supports_npot) {
                glr->width  = GetAlignedSize(glr->width);
                glr->height = GetAlignedSize(glr->height);
                glr->tex_width  = (float) r->fmt.i_visible_width  / glr->width;
                glr->tex_height = (float) r->fmt.i_visible_height / glr->height;
            } else {
                glr->tex_width  = 1.0;
                glr->tex_height = 1.0;
            }
            glr->alpha  = (float)subpicture->i_alpha * r->i_alpha / 255 / 255;
            glr->left   =  2.0 * (r->i_x                          ) / subpicture->i_original_picture_width  - 1.0;
            glr->top    = -2.0 * (r->i_y                          ) / subpicture->i_original_picture_height + 1.0;
            glr->right  =  2.0 * (r->i_x + r->fmt.i_visible_width ) / subpicture->i_original_picture_width  - 1.0;
            glr->bottom = -2.0 * (r->i_y + r->fmt.i_visible_height) / subpicture->i_original_picture_height + 1.0;
            glr->stereo_offset = r->i_stereo_offset;
            glr->subtitle = subpicture->b_subtitle;

            glr->texture = 0;
            /* Try to recycle the textures allocated by the previous
               call to this function. */
            for (int j = 0; j < last_count; j++) {
                if (last[j].texture &&
                    last[j].width  == glr->width &&
                    last[j].height == glr->height) {
                    glr->texture = last[j].texture;
                    memset(&last[j], 0, sizeof(last[j]));
                    break;
                }
            }

            const size_t pixels_offset =
                r->fmt.i_y_offset * r->p_picture->p->i_pitch +
                r->fmt.i_x_offset * r->p_picture->p->i_pixel_pitch;
            if (!glr->texture)
            {
                /* Could not recycle a previous texture, generate a new one. */
                ret = GenTextures(tc, &glr->width, &glr->height, &glr->texture);
                if (ret != VLC_SUCCESS)
                    continue;
            }
            /* Use the visible pitch of the region */
            r->p_picture->p[0].i_visible_pitch = r->fmt.i_visible_width
                                               * r->p_picture->p[0].i_pixel_pitch;
            ret = tc->pf_update(tc, &glr->texture, &glr->width, &glr->height,
                                r->p_picture, &pixels_offset);
        }
    }
    for (int i = 0; i < last_count; i++) {
        if (last[i].texture)
            DelTextures(tc, &last[i].texture);
    }
    free(last);

    VLC_UNUSED(subpicture);

    GL_ASSERT_NOERROR();
    return ret;
}

static int BuildSphere(unsigned nbPlanes,
                        GLfloat **vertexCoord, GLfloat **textureCoord, unsigned *nbVertices,
                        GLushort **indices, unsigned *nbIndices,
                        const float *left, const float *top,
                        const float *right, const float *bottom)
{
    unsigned nbLatBands = 128;
    unsigned nbLonBands = 128;

    *nbVertices = (nbLatBands + 1) * (nbLonBands + 1);
    *nbIndices = nbLatBands * nbLonBands * 3 * 2;

    *vertexCoord = vlc_alloc(*nbVertices * 3, sizeof(GLfloat));
    if (*vertexCoord == NULL)
        return VLC_ENOMEM;
    *textureCoord = vlc_alloc(nbPlanes * *nbVertices * 2, sizeof(GLfloat));
    if (*textureCoord == NULL)
    {
        free(*vertexCoord);
        return VLC_ENOMEM;
    }
    *indices = vlc_alloc(*nbIndices, sizeof(GLushort));
    if (*indices == NULL)
    {
        free(*textureCoord);
        free(*vertexCoord);
        return VLC_ENOMEM;
    }

    for (unsigned lat = 0; lat <= nbLatBands; lat++) {
        float theta = lat * (float) M_PI / nbLatBands;
        float sinTheta, cosTheta;

        sincosf(theta, &sinTheta, &cosTheta);

        for (unsigned lon = 0; lon <= nbLonBands; lon++) {
            float phi = lon * 2 * (float) M_PI / nbLonBands;
            float sinPhi, cosPhi;

            sincosf(phi, &sinPhi, &cosPhi);

            float x = cosPhi * sinTheta;
            float y = cosTheta;
            float z = sinPhi * sinTheta;

            unsigned off1 = (lat * (nbLonBands + 1) + lon) * 3;
            (*vertexCoord)[off1] = SPHERE_RADIUS * x;
            (*vertexCoord)[off1 + 1] = SPHERE_RADIUS * y;
            (*vertexCoord)[off1 + 2] = SPHERE_RADIUS * z;

            for (unsigned p = 0; p < nbPlanes; ++p)
            {
                unsigned off2 = (p * (nbLatBands + 1) * (nbLonBands + 1)
                                + lat * (nbLonBands + 1) + lon) * 2;
                float width = right[p] - left[p];
                float height = bottom[p] - top[p];
                float u = (float)lon / nbLonBands * width;
                float v = (float)lat / nbLatBands * height;
                (*textureCoord)[off2] = u;
                (*textureCoord)[off2 + 1] = v;
            }
        }
    }

    for (unsigned lat = 0; lat < nbLatBands; lat++) {
        for (unsigned lon = 0; lon < nbLonBands; lon++) {
            unsigned first = (lat * (nbLonBands + 1)) + lon;
            unsigned second = first + nbLonBands + 1;

            unsigned off = (lat * nbLatBands + lon) * 3 * 2;

            (*indices)[off] = first;
            (*indices)[off + 1] = second;
            (*indices)[off + 2] = first + 1;

            (*indices)[off + 3] = second;
            (*indices)[off + 4] = second + 1;
            (*indices)[off + 5] = first + 1;
        }
    }

    return VLC_SUCCESS;
}


static int BuildCube(unsigned nbPlanes,
                     float padW, float padH,
                     GLfloat **vertexCoord, GLfloat **textureCoord, unsigned *nbVertices,
                     GLushort **indices, unsigned *nbIndices,
                     const float *left, const float *top,
                     const float *right, const float *bottom)
{
    *nbVertices = 4 * 6;
    *nbIndices = 6 * 6;

    *vertexCoord = vlc_alloc(*nbVertices * 3, sizeof(GLfloat));
    if (*vertexCoord == NULL)
        return VLC_ENOMEM;
    *textureCoord = vlc_alloc(nbPlanes * *nbVertices * 2, sizeof(GLfloat));
    if (*textureCoord == NULL)
    {
        free(*vertexCoord);
        return VLC_ENOMEM;
    }
    *indices = vlc_alloc(*nbIndices, sizeof(GLushort));
    if (*indices == NULL)
    {
        free(*textureCoord);
        free(*vertexCoord);
        return VLC_ENOMEM;
    }

    static const GLfloat coord[] = {
        -1.0,    1.0,    -1.0f, // front
        -1.0,    -1.0,   -1.0f,
        1.0,     1.0,    -1.0f,
        1.0,     -1.0,   -1.0f,

        -1.0,    1.0,    1.0f, // back
        -1.0,    -1.0,   1.0f,
        1.0,     1.0,    1.0f,
        1.0,     -1.0,   1.0f,

        -1.0,    1.0,    -1.0f, // left
        -1.0,    -1.0,   -1.0f,
        -1.0,     1.0,    1.0f,
        -1.0,     -1.0,   1.0f,

        1.0f,    1.0,    -1.0f, // right
        1.0f,   -1.0,    -1.0f,
        1.0f,   1.0,     1.0f,
        1.0f,   -1.0,    1.0f,

        -1.0,    -1.0,    1.0f, // bottom
        -1.0,    -1.0,   -1.0f,
        1.0,     -1.0,    1.0f,
        1.0,     -1.0,   -1.0f,

        -1.0,    1.0,    1.0f, // top
        -1.0,    1.0,   -1.0f,
        1.0,     1.0,    1.0f,
        1.0,     1.0,   -1.0f,
    };

    memcpy(*vertexCoord, coord, *nbVertices * 3 * sizeof(GLfloat));

    for (unsigned p = 0; p < nbPlanes; ++p)
    {
        float width = right[p] - left[p];
        float height = bottom[p] - top[p];

        float col[] = {left[p],
                       left[p] + width * 1.f/3,
                       left[p] + width * 2.f/3,
                       left[p] + width};

        float row[] = {top[p],
                       top[p] + height * 1.f/2,
                       top[p] + height};

        const GLfloat tex[] = {
            col[1] + padW, row[1] + padH, // front
            col[1] + padW, row[2] - padH,
            col[2] - padW, row[1] + padH,
            col[2] - padW, row[2] - padH,

            col[3] - padW, row[1] + padH, // back
            col[3] - padW, row[2] - padH,
            col[2] + padW, row[1] + padH,
            col[2] + padW, row[2] - padH,

            col[2] - padW, row[0] + padH, // left
            col[2] - padW, row[1] - padH,
            col[1] + padW, row[0] + padH,
            col[1] + padW, row[1] - padH,

            col[0] + padW, row[0] + padH, // right
            col[0] + padW, row[1] - padH,
            col[1] - padW, row[0] + padH,
            col[1] - padW, row[1] - padH,

            col[0] + padW, row[2] - padH, // bottom
            col[0] + padW, row[1] + padH,
            col[1] - padW, row[2] - padH,
            col[1] - padW, row[1] + padH,

            col[2] + padW, row[0] + padH, // top
            col[2] + padW, row[1] - padH,
            col[3] - padW, row[0] + padH,
            col[3] - padW, row[1] - padH,
        };

        memcpy(*textureCoord + p * *nbVertices * 2, tex,
               *nbVertices * 2 * sizeof(GLfloat));
    }

    const GLushort ind[] = {
        0, 1, 2,       2, 1, 3, // front
        6, 7, 4,       4, 7, 5, // back
        10, 11, 8,     8, 11, 9, // left
        12, 13, 14,    14, 13, 15, // right
        18, 19, 16,    16, 19, 17, // bottom
        20, 21, 22,    22, 21, 23, // top
    };

    memcpy(*indices, ind, *nbIndices * sizeof(GLushort));

    return VLC_SUCCESS;
}

static unsigned FramePackingBlankingLines(unsigned eye_height)
{
    /* CEA-861 HDMI frame-packing active-space separation. Blu-ray 3D uses
     * 1080p24 or 720p50/60. */
    return eye_height == 720 ? 30 : 45;
}

static int BuildFramePackedRectangle(unsigned nbPlanes,
                                     GLfloat **vertexCoord,
                                     GLfloat **textureCoord,
                                     unsigned *nbVertices,
                                     GLushort **indices,
                                     unsigned *nbIndices,
                                     const float *left, const float *top,
                                     const float *right, const float *bottom,
                                     unsigned eye_height,
                                     video_multiview_mode_t source_mode)
{
    *nbVertices = 8;
    *nbIndices = 12;

    *vertexCoord = vlc_alloc(*nbVertices * 3, sizeof(GLfloat));
    if (*vertexCoord == NULL)
        return VLC_ENOMEM;
    *textureCoord = vlc_alloc(nbPlanes * *nbVertices * 2, sizeof(GLfloat));
    if (*textureCoord == NULL)
    {
        free(*vertexCoord);
        return VLC_ENOMEM;
    }
    *indices = vlc_alloc(*nbIndices, sizeof(GLushort));
    if (*indices == NULL)
    {
        free(*textureCoord);
        free(*vertexCoord);
        return VLC_ENOMEM;
    }

    const unsigned blanking = FramePackingBlankingLines(eye_height);
    const float edge = (float)blanking / (2.f * eye_height + blanking);
    const GLfloat coord[] = {
       -1.f,  1.f,  -1.f,
       -1.f,  edge, -1.f,
        1.f,  1.f,  -1.f,
        1.f,  edge, -1.f,
       -1.f, -edge, -1.f,
       -1.f, -1.f,  -1.f,
        1.f, -edge, -1.f,
        1.f, -1.f,  -1.f,
    };
    memcpy(*vertexCoord, coord, sizeof(coord));

    for (unsigned p = 0; p < nbPlanes; ++p)
    {
        const float middle_x = (left[p] + right[p]) * .5f;
        const float middle_y = (top[p] + bottom[p]) * .5f;
        GLfloat tex[16];

        if (source_mode == MULTIVIEW_2D)
        {
            /* Keep an already-established HDMI 3D session alive across 2D
             * Blu-ray menus and interstitials: present the complete 2D frame
             * to both eyes instead of splitting it like a top/bottom source. */
            const GLfloat duplicated[] = {
                left[p], top[p], left[p], bottom[p],
                right[p], top[p], right[p], bottom[p],
                left[p], top[p], left[p], bottom[p],
                right[p], top[p], right[p], bottom[p],
            };
            memcpy(tex, duplicated, sizeof(tex));
        }
        else if (source_mode == MULTIVIEW_STEREO_SBS ||
            source_mode == MULTIVIEW_STEREO_SBS_RIGHT_FIRST)
        {
            const bool right_first =
                source_mode == MULTIVIEW_STEREO_SBS_RIGHT_FIRST;
            const float l0 = right_first ? middle_x : left[p];
            const float r0 = right_first ? right[p] : middle_x;
            const float l1 = right_first ? left[p] : middle_x;
            const float r1 = right_first ? middle_x : right[p];
            const GLfloat packed[] = {
                l0, top[p], l0, bottom[p], r0, top[p], r0, bottom[p],
                l1, top[p], l1, bottom[p], r1, top[p], r1, bottom[p],
            };
            memcpy(tex, packed, sizeof(tex));
        }
        else
        {
            const bool bottom_first =
                source_mode == MULTIVIEW_STEREO_TB_RIGHT_FIRST;
            const float t0 = bottom_first ? middle_y : top[p];
            const float b0 = bottom_first ? bottom[p] : middle_y;
            const float t1 = bottom_first ? top[p] : middle_y;
            const float b1 = bottom_first ? middle_y : bottom[p];
            /* Match the vertex order: TL, BL, TR, BR for each eye. */
            const GLfloat ordered[] = {
                left[p], t0, left[p], b0, right[p], t0, right[p], b0,
                left[p], t1, left[p], b1, right[p], t1, right[p], b1,
            };
            memcpy(tex, ordered, sizeof(tex));
        }
        memcpy(*textureCoord + p * *nbVertices * 2, tex, sizeof(tex));
    }

    const GLushort ind[] = {
        0, 1, 2, 2, 1, 3,
        4, 5, 6, 6, 5, 7,
    };
    memcpy(*indices, ind, sizeof(ind));
    return VLC_SUCCESS;
}

static int BuildRectangle(unsigned nbPlanes,
                          GLfloat **vertexCoord, GLfloat **textureCoord, unsigned *nbVertices,
                          GLushort **indices, unsigned *nbIndices,
                          const float *left, const float *top,
                          const float *right, const float *bottom)
{
    *nbVertices = 4;
    *nbIndices = 6;

    *vertexCoord = vlc_alloc(*nbVertices * 3, sizeof(GLfloat));
    if (*vertexCoord == NULL)
        return VLC_ENOMEM;
    *textureCoord = vlc_alloc(nbPlanes * *nbVertices * 2, sizeof(GLfloat));
    if (*textureCoord == NULL)
    {
        free(*vertexCoord);
        return VLC_ENOMEM;
    }
    *indices = vlc_alloc(*nbIndices, sizeof(GLushort));
    if (*indices == NULL)
    {
        free(*textureCoord);
        free(*vertexCoord);
        return VLC_ENOMEM;
    }

    static const GLfloat coord[] = {
       -1.0,    1.0,    -1.0f,
       -1.0,    -1.0,   -1.0f,
       1.0,     1.0,    -1.0f,
       1.0,     -1.0,   -1.0f
    };

    memcpy(*vertexCoord, coord, *nbVertices * 3 * sizeof(GLfloat));

    for (unsigned p = 0; p < nbPlanes; ++p)
    {
        const GLfloat tex[] = {
            left[p],  top[p],
            left[p],  bottom[p],
            right[p], top[p],
            right[p], bottom[p]
        };

        memcpy(*textureCoord + p * *nbVertices * 2, tex,
               *nbVertices * 2 * sizeof(GLfloat));
    }

    const GLushort ind[] = {
        0, 1, 2,
        2, 1, 3
    };

    memcpy(*indices, ind, *nbIndices * sizeof(GLushort));

    return VLC_SUCCESS;
}

static int SetupCoords(vout_display_opengl_t *vgl,
                       const float *left, const float *top,
                       const float *right, const float *bottom)
{
    GLfloat *vertexCoord, *textureCoord;
    GLushort *indices;
    unsigned nbVertices, nbIndices;

    int i_ret;
    switch (vgl->fmt.projection_mode)
    {
    case PROJECTION_MODE_RECTANGULAR:
        if (vgl->output_framepacked)
        {
            msg_Dbg(vgl->gl,
                    "HDMI frame-pack geometry: source mode %d, visible %ux%u, eye %ux%u",
                    vgl->source_multiview_mode,
                    vgl->fmt.i_visible_width, vgl->fmt.i_visible_height,
                    vgl->output_eye_width, vgl->output_eye_height);
            i_ret = BuildFramePackedRectangle(vgl->prgm->tc->tex_count,
                              &vertexCoord, &textureCoord, &nbVertices,
                              &indices, &nbIndices, left, top, right, bottom,
                              vgl->output_eye_height,
                              vgl->source_multiview_mode);
        }
        else
            i_ret = BuildRectangle(vgl->prgm->tc->tex_count,
                                   &vertexCoord, &textureCoord, &nbVertices,
                                   &indices, &nbIndices,
                                   left, top, right, bottom);
        break;
    case PROJECTION_MODE_EQUIRECTANGULAR:
        i_ret = BuildSphere(vgl->prgm->tc->tex_count,
                            &vertexCoord, &textureCoord, &nbVertices,
                            &indices, &nbIndices,
                            left, top, right, bottom);
        break;
    case PROJECTION_MODE_CUBEMAP_LAYOUT_STANDARD:
        i_ret = BuildCube(vgl->prgm->tc->tex_count,
                          (float)vgl->fmt.i_cubemap_padding / vgl->fmt.i_width,
                          (float)vgl->fmt.i_cubemap_padding / vgl->fmt.i_height,
                          &vertexCoord, &textureCoord, &nbVertices,
                          &indices, &nbIndices,
                          left, top, right, bottom);
        break;
    default:
        i_ret = VLC_EGENERIC;
        break;
    }

    if (i_ret != VLC_SUCCESS)
        return i_ret;

    for (unsigned j = 0; j < vgl->prgm->tc->tex_count; j++)
    {
        vgl->vt.BindBuffer(GL_ARRAY_BUFFER, vgl->texture_buffer_object[j]);
        vgl->vt.BufferData(GL_ARRAY_BUFFER, nbVertices * 2 * sizeof(GLfloat),
                           textureCoord + j * nbVertices * 2, GL_STATIC_DRAW);
    }

    vgl->vt.BindBuffer(GL_ARRAY_BUFFER, vgl->vertex_buffer_object);
    vgl->vt.BufferData(GL_ARRAY_BUFFER, nbVertices * 3 * sizeof(GLfloat),
                       vertexCoord, GL_STATIC_DRAW);

    vgl->vt.BindBuffer(GL_ELEMENT_ARRAY_BUFFER, vgl->index_buffer_object);
    vgl->vt.BufferData(GL_ELEMENT_ARRAY_BUFFER, nbIndices * sizeof(GLushort),
                       indices, GL_STATIC_DRAW);

    free(textureCoord);
    free(vertexCoord);
    free(indices);

    vgl->nb_indices = nbIndices;

    return VLC_SUCCESS;
}

#if !defined(USE_OPENGL_ES2)
/* out = a * b, column-major 4x4 (same multiplication order the vertex shader
 * applies: OrientationMatrix * ProjectionMatrix * VertexPosition). */
static void MatrixMultiply4(GLfloat *out, const GLfloat *a, const GLfloat *b)
{
    for (int i = 0; i < 4; i++)
        for (int j = 0; j < 4; j++)
        {
            GLfloat s = 0.f;
            for (int k = 0; k < 4; k++)
                s += a[k * 4 + i] * b[j * 4 + k];
            out[j * 4 + i] = s;
        }
}

/* Fixed-function counterpart of DrawWithShaders, for a single RGBA texture on
 * hardware without a usable GLSL pipeline. Reuses the vertex/texture-coordinate
 * buffer objects already filled by SetupCoords; the fragment sampler and the
 * orientation/projection transform the GLSL program would apply are replaced
 * by fixed-function texturing plus the modelview/projection matrices. */
static void DrawFixedFunction(vout_display_opengl_t *vgl, struct prgm *prgm)
{
    const opengl_tex_converter_t *tc = prgm->tc;
    GLfloat mvp[16];
    MatrixMultiply4(mvp, prgm->var.OrientationMatrix, prgm->var.ProjectionMatrix);

    vgl->vt.MatrixMode(GL_PROJECTION);
    vgl->vt.LoadIdentity();
    vgl->vt.MatrixMode(GL_MODELVIEW);
    vgl->vt.LoadMatrixf(mvp);
    vgl->vt.Color4f(1.f, 1.f, 1.f, 1.f);

    vgl->vt.ActiveTexture(GL_TEXTURE0);
    vgl->vt.BindTexture(tc->tex_target, vgl->texture[0]);
    vgl->vt.Enable(GL_TEXTURE_2D);

    vgl->vt.BindBuffer(GL_ARRAY_BUFFER, vgl->texture_buffer_object[0]);
    vgl->vt.EnableClientState(GL_TEXTURE_COORD_ARRAY);
    vgl->vt.TexCoordPointer(2, GL_FLOAT, 0, 0);

    vgl->vt.BindBuffer(GL_ARRAY_BUFFER, vgl->vertex_buffer_object);
    vgl->vt.EnableClientState(GL_VERTEX_ARRAY);
    vgl->vt.VertexPointer(3, GL_FLOAT, 0, 0);

    vgl->vt.BindBuffer(GL_ELEMENT_ARRAY_BUFFER, vgl->index_buffer_object);
    vgl->vt.DrawElements(GL_TRIANGLES, vgl->nb_indices, GL_UNSIGNED_SHORT, 0);

    vgl->vt.DisableClientState(GL_VERTEX_ARRAY);
    vgl->vt.DisableClientState(GL_TEXTURE_COORD_ARRAY);
    vgl->vt.Disable(GL_TEXTURE_2D);
    vgl->vt.BindBuffer(GL_ARRAY_BUFFER, 0);
    vgl->vt.BindBuffer(GL_ELEMENT_ARRAY_BUFFER, 0);
}

/* Fixed-function draw of one subpicture region (RGBA texture, alpha-blended),
 * using client-side arrays. */
static void DrawFixedFunctionRegion(vout_display_opengl_t *vgl,
                                    const opengl_tex_converter_t *tc,
                                    const gl_region_t *glr)
{
    const GLfloat vertexCoord[] = {
        glr->left,  glr->top,
        glr->left,  glr->bottom,
        glr->right, glr->top,
        glr->right, glr->bottom,
    };
    const GLfloat textureCoord[] = {
        0.0f,           0.0f,
        0.0f,           glr->tex_height,
        glr->tex_width, 0.0f,
        glr->tex_width, glr->tex_height,
    };

    vgl->vt.MatrixMode(GL_PROJECTION);
    vgl->vt.LoadIdentity();
    vgl->vt.MatrixMode(GL_MODELVIEW);
    vgl->vt.LoadIdentity();
    vgl->vt.Color4f(1.f, 1.f, 1.f, glr->alpha);

    vgl->vt.BindTexture(tc->tex_target, glr->texture);
    vgl->vt.Enable(GL_TEXTURE_2D);

    vgl->vt.BindBuffer(GL_ARRAY_BUFFER, 0);
    vgl->vt.EnableClientState(GL_TEXTURE_COORD_ARRAY);
    vgl->vt.TexCoordPointer(2, GL_FLOAT, 0, textureCoord);
    vgl->vt.EnableClientState(GL_VERTEX_ARRAY);
    vgl->vt.VertexPointer(2, GL_FLOAT, 0, vertexCoord);

    vgl->vt.DrawArrays(GL_TRIANGLE_STRIP, 0, 4);

    vgl->vt.DisableClientState(GL_VERTEX_ARRAY);
    vgl->vt.DisableClientState(GL_TEXTURE_COORD_ARRAY);
    vgl->vt.Disable(GL_TEXTURE_2D);
}
#endif

/* Map a normal 2D overlay into one eye of a full-resolution top/bottom MVC
 * picture.  PGS subtitles and BD-J graphics are authored once for the movie;
 * duplicating their geometry here keeps them at zero parallax and therefore
 * readable in both eyes. */
static void MapRegionToFramePackedEye(gl_region_t *dst,
                                      const gl_region_t *src, unsigned eye,
                                      unsigned eye_width, unsigned eye_height,
                                      int depth)
{
    *dst = *src;
    const float scale = (float)eye_height /
                        (2.f * eye_height +
                         FramePackingBlankingLines(eye_height));
    const float offset = eye == 0 ? 1.f - scale : -1.f + scale;
    dst->top = src->top * scale + offset;
    dst->bottom = src->bottom * scale + offset;

    /* A positive value produces crossed disparity (the left-eye copy moves
     * right and the right-eye copy moves left), bringing the overlay towards
     * the viewer. At the endpoints the total disparity is four percent of
     * the eye width, large enough to be useful without making text painful
     * to fuse. The configured list normally bounds this already; clamp here
     * as well for command-line and old preference files. */
    if (depth < -100)
        depth = -100;
    else if (depth > 100)
        depth = 100;
    const float user_parallax = (float)depth / 100.f * .04f;
    /* BD-J HGraphicsConfigurationS3D expresses the graphics-plane offset in
     * pixels.  The value is the disparity between both eye images, so split
     * it symmetrically: in normalized GL coordinates each eye moves by
     * offset / eye_width. */
    const float authored_parallax = eye_width > 0
        ? (float)src->stereo_offset / (float)eye_width : 0.f;
    const float parallax = user_parallax + authored_parallax;
    const float shift = eye == 0 ? parallax : -parallax;
    dst->left += shift;
    dst->right += shift;

    /* A BD-J plane is commonly a full-eye ARGB canvas containing both the
     * foreground controls and a translucent dimming veil.  Translating that
     * canvas for depth used to uncover a bright strip at the left edge of one
     * eye and the right edge of the other.  Extend full-width planes on the
     * clipped side while preserving their translated centre; OpenGL clips the
     * excess and the dialog keeps exactly the authored disparity. */
    if (src->left <= -0.999f && src->right >= 0.999f)
    {
        if (shift > 0.f)
        {
            dst->left = -1.f;
            dst->right += shift;
        }
        else if (shift < 0.f)
        {
            dst->left += shift;
            dst->right = 1.f;
        }
    }
}

static void DrawWithShaders(vout_display_opengl_t *vgl, struct prgm *prgm)
{
    opengl_tex_converter_t *tc = prgm->tc;
    tc->pf_prepare_shader(tc, vgl->tex_width, vgl->tex_height, 1.0f);

    for (unsigned j = 0; j < vgl->prgm->tc->tex_count; j++) {
        assert(vgl->texture[j] != 0);
        vgl->vt.ActiveTexture(GL_TEXTURE0+j);
        vgl->vt.BindTexture(tc->tex_target, vgl->texture[j]);

        vgl->vt.BindBuffer(GL_ARRAY_BUFFER, vgl->texture_buffer_object[j]);

        assert(prgm->aloc.MultiTexCoord[j] != -1);
        vgl->vt.EnableVertexAttribArray(prgm->aloc.MultiTexCoord[j]);
        vgl->vt.VertexAttribPointer(prgm->aloc.MultiTexCoord[j], 2, GL_FLOAT,
                                     0, 0, 0);
    }

    vgl->vt.BindBuffer(GL_ARRAY_BUFFER, vgl->vertex_buffer_object);
    vgl->vt.BindBuffer(GL_ELEMENT_ARRAY_BUFFER, vgl->index_buffer_object);
    vgl->vt.EnableVertexAttribArray(prgm->aloc.VertexPosition);
    vgl->vt.VertexAttribPointer(prgm->aloc.VertexPosition, 3, GL_FLOAT, 0, 0, 0);

    vgl->vt.UniformMatrix4fv(prgm->uloc.OrientationMatrix, 1, GL_FALSE,
                             prgm->var.OrientationMatrix);
    vgl->vt.UniformMatrix4fv(prgm->uloc.ProjectionMatrix, 1, GL_FALSE,
                             prgm->var.ProjectionMatrix);
    vgl->vt.UniformMatrix4fv(prgm->uloc.ZRotMatrix, 1, GL_FALSE,
                             prgm->var.ZRotMatrix);
    vgl->vt.UniformMatrix4fv(prgm->uloc.YRotMatrix, 1, GL_FALSE,
                             prgm->var.YRotMatrix);
    vgl->vt.UniformMatrix4fv(prgm->uloc.XRotMatrix, 1, GL_FALSE,
                             prgm->var.XRotMatrix);
    vgl->vt.UniformMatrix4fv(prgm->uloc.ZoomMatrix, 1, GL_FALSE,
                             prgm->var.ZoomMatrix);

    vgl->vt.DrawElements(GL_TRIANGLES, vgl->nb_indices, GL_UNSIGNED_SHORT, 0);
}


static void GetTextureCropParamsForStereo(unsigned i_nbTextures,
                                          const float *stereoCoefs,
                                          const float *stereoOffsets,
                                          float *left, float *top,
                                          float *right, float *bottom)
{
    for (unsigned i = 0; i < i_nbTextures; ++i)
    {
        float f_2eyesWidth = right[i] - left[i];
        left[i] = left[i] + f_2eyesWidth * stereoOffsets[0];
        right[i] = left[i] + f_2eyesWidth * stereoCoefs[0];

        float f_2eyesHeight = bottom[i] - top[i];
        top[i] = top[i] + f_2eyesHeight * stereoOffsets[1];
        bottom[i] = top[i] + f_2eyesHeight * stereoCoefs[1];
    }
}

static void TextureCropForStereo(vout_display_opengl_t *vgl,
                                 float *left, float *top,
                                 float *right, float *bottom)
{
    float stereoCoefs[2];
    float stereoOffsets[2];

    switch (vgl->source_multiview_mode)
    {
    case MULTIVIEW_STEREO_FRAMEPACKED:
    case MULTIVIEW_STEREO_FRAMEPACKED_RIGHT_BASE:
    case MULTIVIEW_STEREO_TB:
        // Display only the left eye.
        stereoCoefs[0] = 1; stereoCoefs[1] = 0.5;
        stereoOffsets[0] = 0; stereoOffsets[1] = 0;
        GetTextureCropParamsForStereo(vgl->prgm->tc->tex_count,
                                      stereoCoefs, stereoOffsets,
                                      left, top, right, bottom);
        break;
    case MULTIVIEW_STEREO_TB_RIGHT_FIRST:
        // Display only the left eye, stored in the bottom half.
        stereoCoefs[0] = 1; stereoCoefs[1] = 0.5;
        stereoOffsets[0] = 0; stereoOffsets[1] = 0.5;
        GetTextureCropParamsForStereo(vgl->prgm->tc->tex_count,
                                      stereoCoefs, stereoOffsets,
                                      left, top, right, bottom);
        break;
    case MULTIVIEW_STEREO_SBS:
        // Display only the left eye.
        stereoCoefs[0] = 0.5; stereoCoefs[1] = 1;
        stereoOffsets[0] = 0; stereoOffsets[1] = 0;
        GetTextureCropParamsForStereo(vgl->prgm->tc->tex_count,
                                      stereoCoefs, stereoOffsets,
                                      left, top, right, bottom);
        break;
    case MULTIVIEW_STEREO_SBS_RIGHT_FIRST:
        // Display only the left eye, stored in the right half.
        stereoCoefs[0] = 0.5; stereoCoefs[1] = 1;
        stereoOffsets[0] = 0.5; stereoOffsets[1] = 0;
        GetTextureCropParamsForStereo(vgl->prgm->tc->tex_count,
                                      stereoCoefs, stereoOffsets,
                                      left, top, right, bottom);
        break;
    default:
        break;
    }
}

int vout_display_opengl_Display(vout_display_opengl_t *vgl,
                                const video_format_t *source)
{
#ifdef HAVE_LIBPLACEBO_NEXT
    if (vgl->dovi)
    {
        VLC_UNUSED(source);
        return vlc_dovi_renderer_Display(vgl->dovi);
    }
#endif
    GL_ASSERT_NOERROR();

    /* Why drawing here and not in Render()? Because this way, the
       OpenGL providers can call vout_display_opengl_Display to force redraw.
       Currently, the OS X provider uses it to get a smooth window resizing */
    vgl->vt.Clear(GL_COLOR_BUFFER_BIT);

    const bool retroarch_active = vlc_ra_shader_engine_Begin(
        vgl->retroarch, source->i_visible_width, source->i_visible_height);

    if (!vgl->fixed_function)
        vgl->vt.UseProgram(vgl->prgm->id);

    if (source->i_x_offset != vgl->last_source.i_x_offset
     || source->i_y_offset != vgl->last_source.i_y_offset
     || source->i_visible_width != vgl->last_source.i_visible_width
     || source->i_visible_height != vgl->last_source.i_visible_height)
    {
        float left[PICTURE_PLANE_MAX];
        float top[PICTURE_PLANE_MAX];
        float right[PICTURE_PLANE_MAX];
        float bottom[PICTURE_PLANE_MAX];
        const opengl_tex_converter_t *tc = vgl->prgm->tc;
        for (unsigned j = 0; j < tc->tex_count; j++)
        {
            float scale_w = (float)tc->texs[j].w.num / tc->texs[j].w.den
                          / vgl->tex_width[j];
            float scale_h = (float)tc->texs[j].h.num / tc->texs[j].h.den
                          / vgl->tex_height[j];

            /* Warning: if NPOT is not supported a larger texture is
               allocated. This will cause right and bottom coordinates to
               land on the edge of two texels with the texels to the
               right/bottom uninitialized by the call to
               glTexSubImage2D. This might cause a green line to appear on
               the right/bottom of the display.
               There are two possible solutions:
               - Manually mirror the edges of the texture.
               - Add a "-1" when computing right and bottom, however the
               last row/column might not be displayed at all.
            */
            left[j]   = (source->i_x_offset +                       0 ) * scale_w;
            top[j]    = (source->i_y_offset +                       0 ) * scale_h;
            right[j]  = (source->i_x_offset + source->i_visible_width ) * scale_w;
            bottom[j] = (source->i_y_offset + source->i_visible_height) * scale_h;
        }

        if (!vgl->output_framepacked)
            TextureCropForStereo(vgl, left, top, right, bottom);
        int ret = SetupCoords(vgl, left, top, right, bottom);
        if (ret != VLC_SUCCESS)
            return ret;

        vgl->last_source.i_x_offset = source->i_x_offset;
        vgl->last_source.i_y_offset = source->i_y_offset;
        vgl->last_source.i_visible_width = source->i_visible_width;
        vgl->last_source.i_visible_height = source->i_visible_height;
    }
#if !defined(USE_OPENGL_ES2)
    if (vgl->fixed_function)
        DrawFixedFunction(vgl, vgl->prgm);
    else
#endif
        DrawWithShaders(vgl, vgl->prgm);

    if (retroarch_active)
        vlc_ra_shader_engine_End(vgl->retroarch);

    /* Draw the subpictures */
    struct prgm *prgm = vgl->sub_prgm;
    opengl_tex_converter_t *tc = prgm->tc;

    vgl->vt.Enable(GL_BLEND);
    vgl->vt.BlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA);
    vgl->vt.ActiveTexture(GL_TEXTURE0 + 0);

#if !defined(USE_OPENGL_ES2)
    if (vgl->fixed_function)
    {
        const int overlay_depth = var_InheritInteger(
            vgl->gl, "stereo3d-overlay-depth");
        for (int i = 0; i < vgl->region_count; i++)
        {
            if (vgl->output_framepacked)
            {
                for (unsigned eye = 0; eye < 2; ++eye)
                {
                    gl_region_t stereo_region;
                    MapRegionToFramePackedEye(&stereo_region,
                                              &vgl->region[i], eye,
                                              vgl->output_eye_width,
                                              vgl->output_eye_height,
                                              overlay_depth);
                    DrawFixedFunctionRegion(vgl, tc, &stereo_region);
                }
            }
            else
                DrawFixedFunctionRegion(vgl, tc, &vgl->region[i]);
        }
    }
    else
#endif
    {
    // Change the program for overlays
    vgl->vt.UseProgram(prgm->id);

    /* We need two buffer objects for each region: for vertex and texture coordinates. */
    if (2 * vgl->region_count > vgl->subpicture_buffer_object_count) {
        if (vgl->subpicture_buffer_object_count > 0)
            vgl->vt.DeleteBuffers(vgl->subpicture_buffer_object_count,
                                  vgl->subpicture_buffer_object);
        vgl->subpicture_buffer_object_count = 0;

        int new_count = 2 * vgl->region_count;
        vgl->subpicture_buffer_object = realloc_or_free(vgl->subpicture_buffer_object, new_count * sizeof(GLuint));
        if (!vgl->subpicture_buffer_object)
            return VLC_ENOMEM;

        vgl->subpicture_buffer_object_count = new_count;
        vgl->vt.GenBuffers(vgl->subpicture_buffer_object_count,
                           vgl->subpicture_buffer_object);
    }

    for (int i = 0; i < vgl->region_count; i++) {
        gl_region_t *glr = &vgl->region[i];
        const GLfloat textureCoord[] = {
            0.0, 0.0,
            0.0, glr->tex_height,
            glr->tex_width, 0.0,
            glr->tex_width, glr->tex_height,
        };

        assert(glr->texture != 0);
        vgl->vt.BindTexture(tc->tex_target, glr->texture);

        const unsigned eye_count = vgl->output_framepacked ? 2 : 1;
        const int overlay_depth = var_InheritInteger(
            vgl->gl, "stereo3d-overlay-depth");
        for (unsigned eye = 0; eye < eye_count; ++eye)
        {
            gl_region_t mapped;
            const gl_region_t *draw_region = glr;
            if (eye_count == 2)
            {
                MapRegionToFramePackedEye(&mapped, glr, eye,
                                          vgl->output_eye_width,
                                          vgl->output_eye_height,
                                          overlay_depth);
                draw_region = &mapped;
            }
            const GLfloat vertexCoord[] = {
                draw_region->left,  draw_region->top,
                draw_region->left,  draw_region->bottom,
                draw_region->right, draw_region->top,
                draw_region->right, draw_region->bottom,
            };

            vgl->vt.BindBuffer(GL_ARRAY_BUFFER, vgl->subpicture_buffer_object[2 * i]);
            vgl->vt.BufferData(GL_ARRAY_BUFFER, sizeof(textureCoord), textureCoord, GL_STATIC_DRAW);
            vgl->vt.EnableVertexAttribArray(prgm->aloc.MultiTexCoord[0]);
            vgl->vt.VertexAttribPointer(prgm->aloc.MultiTexCoord[0], 2, GL_FLOAT,
                                        0, 0, 0);

            vgl->vt.BindBuffer(GL_ARRAY_BUFFER, vgl->subpicture_buffer_object[2 * i + 1]);
            vgl->vt.BufferData(GL_ARRAY_BUFFER, sizeof(vertexCoord), vertexCoord, GL_STATIC_DRAW);
            vgl->vt.EnableVertexAttribArray(prgm->aloc.VertexPosition);
            vgl->vt.VertexAttribPointer(prgm->aloc.VertexPosition, 2, GL_FLOAT,
                                        0, 0, 0);

            vgl->vt.UniformMatrix4fv(prgm->uloc.OrientationMatrix, 1, GL_FALSE,
                                     prgm->var.OrientationMatrix);
            vgl->vt.UniformMatrix4fv(prgm->uloc.ProjectionMatrix, 1, GL_FALSE,
                                     prgm->var.ProjectionMatrix);
            vgl->vt.UniformMatrix4fv(prgm->uloc.ZRotMatrix, 1, GL_FALSE,
                                     prgm->var.ZRotMatrix);
            vgl->vt.UniformMatrix4fv(prgm->uloc.YRotMatrix, 1, GL_FALSE,
                                     prgm->var.YRotMatrix);
            vgl->vt.UniformMatrix4fv(prgm->uloc.XRotMatrix, 1, GL_FALSE,
                                     prgm->var.XRotMatrix);
            vgl->vt.UniformMatrix4fv(prgm->uloc.ZoomMatrix, 1, GL_FALSE,
                                     prgm->var.ZoomMatrix);

            /* The CRT picture deliberately contains high-frequency scanlines
             * and phosphor cells. Subpictures are composited after that image,
             * so the shader never touches their pixels, but authored grey or
             * translucent PGS glyphs can still lose contrast against it. Add
             * a small black safety halo behind movie subtitles only. The
             * original colour, alpha, antialiasing and bitmap remain intact;
             * OSD, logos, and interactive disc menus are not changed. */
            if (retroarch_active && glr->subtitle &&
                vgl->viewport_width && vgl->viewport_height)
            {
                static const int offsets[8][2] = {
                    {-1, 0}, {1, 0}, {0, -1}, {0, 1},
                    {-1,-1}, {1,-1}, {-1, 1}, {1, 1},
                };
                const float radius = fmaxf(2.f,
                    2.f * (float)vgl->viewport_height / 1080.f);
                const float dx = 2.f * radius / vgl->viewport_width;
                const float dy = 2.f * radius / vgl->viewport_height;

                tc->pf_prepare_shader(tc, &glr->width, &glr->height,
                                      draw_region->alpha);
                vgl->vt.Uniform4f(tc->uloc.FillColor, 0.f, 0.f, 0.f,
                                  draw_region->alpha * .55f);
                for (unsigned h = 0; h < ARRAY_SIZE(offsets); ++h)
                {
                    const float ox = offsets[h][0] * dx;
                    const float oy = offsets[h][1] * dy;
                    const GLfloat haloVertexCoord[] = {
                        draw_region->left  + ox, draw_region->top    + oy,
                        draw_region->left  + ox, draw_region->bottom + oy,
                        draw_region->right + ox, draw_region->top    + oy,
                        draw_region->right + ox, draw_region->bottom + oy,
                    };
                    vgl->vt.BufferData(GL_ARRAY_BUFFER,
                                       sizeof(haloVertexCoord),
                                       haloVertexCoord, GL_STATIC_DRAW);
                    vgl->vt.DrawArrays(GL_TRIANGLE_STRIP, 0, 4);
                }
            }

            tc->pf_prepare_shader(tc, &glr->width, &glr->height,
                                  draw_region->alpha);
            vgl->vt.BufferData(GL_ARRAY_BUFFER, sizeof(vertexCoord),
                               vertexCoord, GL_STATIC_DRAW);

            vgl->vt.DrawArrays(GL_TRIANGLE_STRIP, 0, 4);
        }
    }
    } /* end of the shader subpicture path */
    vgl->vt.Disable(GL_BLEND);

    /* Display */
    vlc_gl_Swap(vgl->gl);

    GL_ASSERT_NOERROR();

    return VLC_SUCCESS;
}
