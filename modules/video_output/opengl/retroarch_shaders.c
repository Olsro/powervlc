/*****************************************************************************
 * retroarch_shaders.c: native RetroArch GLSL preset execution
 *****************************************************************************
 * This is an independent implementation of the public .glsl/.glslp format.
 * It deliberately does not reuse RetroArch's GPL parser. Shader files retain
 * their original copyright and licence notices in share/retroarch-shaders.
 *****************************************************************************/
#ifdef HAVE_CONFIG_H
# include "config.h"
#endif

#include <vlc_common.h>
#include <vlc_configuration.h>
#include <vlc_fs.h>
#include <vlc_image.h>
#include <vlc_opengl.h>
#include <vlc_url.h>
#include <vlc_variables.h>

#include "retroarch_shaders.h"

#ifndef GL_FRAMEBUFFER
# define GL_FRAMEBUFFER 0x8D40
#endif
#ifndef GL_COLOR_ATTACHMENT0
# define GL_COLOR_ATTACHMENT0 0x8CE0
#endif
#ifndef GL_FRAMEBUFFER_COMPLETE
# define GL_FRAMEBUFFER_COMPLETE 0x8CD5
#endif
#ifndef GL_FRAMEBUFFER_BINDING
# define GL_FRAMEBUFFER_BINDING 0x8CA6
#endif
#ifndef GL_BACK_LEFT
# define GL_BACK_LEFT 0x0402
#endif
#ifndef GL_RGBA8
# define GL_RGBA8 0x8058
#endif
#ifndef GL_RGBA16F
# define GL_RGBA16F 0x881A
#endif
#ifndef GL_SRGB8_ALPHA8
# define GL_SRGB8_ALPHA8 0x8C43
# define GL_FRAMEBUFFER_SRGB 0x8DB9
# define GL_FRAMEBUFFER_ATTACHMENT_COLOR_ENCODING 0x8210
# define GL_SRGB 0x8C40
#endif
#ifndef GL_CLAMP_TO_BORDER
# define GL_CLAMP_TO_BORDER 0x812D
#endif
#ifndef GL_MIRRORED_REPEAT
# define GL_MIRRORED_REPEAT 0x8370
#endif
#ifndef GL_LINEAR_MIPMAP_LINEAR
# define GL_LINEAR_MIPMAP_LINEAR 0x2703
#endif

#define RA_MAX_PARAMETERS 64
#define RA_MAX_PASSES 16
#define RA_MAX_TEXTURES 12
#define RA_MAX_HISTORY 8
#define RA_MAX_SHARED_LUTS 64

struct ra_parameter {
    char name[64];
    float value;
    GLint location;
};

enum ra_scale_type { RA_SCALE_SOURCE, RA_SCALE_VIEWPORT, RA_SCALE_ABSOLUTE };
enum ra_wrap_mode { RA_WRAP_BORDER, RA_WRAP_EDGE, RA_WRAP_REPEAT,
                    RA_WRAP_MIRRORED_REPEAT };

struct ra_program {
    char source[PATH_MAX];
    bool linear;
    bool srgb;
    bool floating;
    bool mipmap_input;
    enum ra_wrap_mode wrap_mode;
    enum ra_scale_type scale_type_x;
    enum ra_scale_type scale_type_y;
    float scale_x;
    float scale_y;
    char alias[64];
    GLuint id;
    GLint vertex_coord;
    GLint tex_coord;
    GLint color;
    GLint mvp;
    GLint texture;
    GLint input_size;
    GLint texture_size;
    GLint output_size;
    GLint frame_count;
    GLint frame_direction;
    struct ra_parameter parameters[RA_MAX_PARAMETERS];
    unsigned parameter_count;
};

struct ra_preset_template { const char *name; bool lightweight; };

/* Every top-level CRT preset is considered.  Packaged presets eligible for the
 * current driver are published without eagerly compiling the entire catalog.
 * Exact pass/resource validation happens on first use; rejected presets are
 * withdrawn immediately. */
static const struct ra_preset_template preset_templates[] = {
    { "CRT-beam", true }, { "GritsScanlines", false },
    { "crt-1tap", true }, { "crt-Cyclon", false },
    { "crt-aperture", false }, { "crt-blurPi", false },
    { "crt-blurPi-soft", false }, { "crt-caligari", false },
    { "crt-cgwg-fast", true }, { "crt-consumer", false },
    { "crt-consumer-1w-ntsc", false }, { "crt-consumer-arcade", false },
    { "crt-consumer-classic", false }, { "crt-easymode", false },
    { "crt-easymode-halation", false }, { "crt-gdv-mini", true },
    { "crt-geom", false }, { "crt-geom-mini", true },
    { "crt-guest-dr-venom", false }, { "crt-guest-dr-venom-fast", false },
    { "crt-guest-sm", false }, { "crt-hyllian", false },
    { "crt-hyllian-3d", false }, { "crt-hyllian-fast", true },
    { "crt-hyllian-glow", false }, { "crt-hyllian-multipass", false },
    { "crt-interlaced-halation", false }, { "crt-lottes", false },
    { "crt-lottes-fast", true }, { "crt-lottes-mini", true },
    { "crt-lottes-multipass", false }, { "crt-mattias", true },
    { "crt-nes-mini", true }, { "crt-nobody", true },
    { "crt-pi", true }, { "crt-pi-vertical", true },
    { "crt-potato-BVM", true }, { "crt-potato-cool", true },
    { "crt-potato-warm", true }, { "crt-royale", false },
    { "crt-royale-fake-bloom", false },
    { "crt-royale-fake-bloom-intel", false },
    { "crt-royale-ntsc-256px-composite", false },
    { "crt-royale-ntsc-256px-svideo", false },
    { "crt-royale-ntsc-320px-composite", false },
    { "crt-royale-ntsc-320px-svideo", false },
    { "crt-royale-pal-r57shell", false }, { "crt-sines", false },
    { "crt-torridgristle", false }, { "crt-yo6-KV-M1420B", false },
    { "crt-yo6-KV-M1420B-fast", false },
    { "crt-yo6-KV-M1420B-sharp", false },
    { "crtglow_gauss", false }, { "crtglow_gauss_ntsc_3phase", false },
    { "crtglow_lanczos", false }, { "crtsim", false },
    { "fake-CRT-Geom", false }, { "fake-CRT-Geom-potato", true },
    { "fakelottes", true }, { "fakelottes-geom", false },
    { "fakelottes-geom-mini", true }, { "gizmo-crt", false },
    { "gizmo-slotmask-crt", false }, { "gtuv50", true },
    { "mame_hlsl", false }, { "metacrt", false },
    { "phosphorlut", false }, { "smuberstep-glow", false },
    { "tvout-tweaks-linearized-multipass", false }, { "yee64", true },
    { "yeetron", true }, { "zfast-composite", true }, { "zfast-crt", true },
    { "zfast_crt_geo", true }, { "zfast_crt_geo_svideo", true },
    { "zfast_crt_nogeo", true }, { "zfast_crt_nogeo_svideo", true },
};

struct ra_target {
    GLuint framebuffer;
    GLuint texture;
    unsigned width, height;
    GLenum internal_format;
};

struct ra_lut {
    char name[64];
    char source[PATH_MAX];
    GLuint texture;
    unsigned width, height;
    bool linear;
    bool mipmap;
    enum ra_wrap_mode wrap_mode;
};

struct ra_preset {
    const char *name;
    bool lightweight;
    bool attempted;
    bool valid;
    unsigned pass_count;
    int feedback_pass;
    struct ra_target feedback;
    unsigned lut_count;
    struct ra_lut *luts[RA_MAX_TEXTURES];
    unsigned history_count;
    struct ra_program passes[RA_MAX_PASSES];
    struct ra_target targets[RA_MAX_PASSES];
};

struct vlc_ra_shader_engine {
    vlc_gl_t *gl;
    const opengl_vtable_t *vt;
    struct ra_target input;
    struct ra_target normalized;
    struct ra_target history[RA_MAX_HISTORY];
    unsigned history_count;
    GLuint vertex_buffer;
    GLuint texcoord_buffer;
    GLuint color_buffer;
    struct ra_program resampler;
    int viewport_x;
    int viewport_y;
    unsigned viewport_width;
    unsigned viewport_height;
    uint64_t frame_count;
    bool new_frame;
    bool have_frame_pts;
    vlc_tick_t frame_pts;
    struct ra_preset *active;
    char selected[128];
    GLint max_texture_units;
    unsigned glsl_version;
    bool allow_long_shaders;
    bool default_srgb;
    GLuint output_framebuffer;
    unsigned lut_count;
    struct ra_lut luts[RA_MAX_SHARED_LUTS];
    struct ra_preset presets[ARRAY_SIZE(preset_templates)];
};

static char *ReadTextFile(const char *path)
{
    FILE *file = vlc_fopen(path, "rb");
    if (!file)
        return NULL;
    if (fseek(file, 0, SEEK_END) || ftell(file) < 0) {
        fclose(file);
        return NULL;
    }
    long length = ftell(file);
    rewind(file);
    char *data = malloc((size_t)length + 1);
    if (data && fread(data, 1, (size_t)length, file) == (size_t)length)
        data[length] = '\0';
    else
        FREENULL(data);
    fclose(file);
    return data;
}

static char *ShaderPath(const char *relative)
{
    char *data = config_GetDataDir();
    if (!data)
        return NULL;
    char *path;
    if (asprintf(&path, "%s/retroarch-shaders/%s", data, relative) < 0)
        path = NULL;
    free(data);
    return path;
}

/* RetroArch accepts a #version directive embedded after a licence comment.
 * Desktop OpenGL requires it to be the first directive. Preserve the version
 * requested by the shader, then remove its original directive so Compile()
 * can emit it first. Shader expressions and preprocessor branches otherwise
 * remain byte-for-byte intact. */
static unsigned ExtractAndRemoveVersion(char *source)
{
    unsigned version = 120;
    char *read = source;
    char *write = source;
    while (*read) {
        char *end = strchr(read, '\n');
        size_t length = end ? (size_t)(end - read + 1) : strlen(read);
        const char *content = read;
        while (content < read + length && (*content == ' ' || *content == '\t'))
            ++content;
        if (!strncmp(content, "#version", 8)) {
            char *endptr;
            unsigned requested = (unsigned)strtoul(content + 8, &endptr, 10);
            if (endptr != content + 8 && requested >= 110)
                version = requested;
        } else {
            memmove(write, read, length);
            write += length;
        }
        read += length;
    }
    *write = '\0';
    return version;
}

static void ParseParameters(struct ra_program *program, const char *source)
{
    const char *line = source;
    while (program->parameter_count < RA_MAX_PARAMETERS &&
           (line = strstr(line, "#pragma parameter ")) != NULL) {
        struct ra_parameter *parameter =
            &program->parameters[program->parameter_count];
        char label[128];
        float minimum, maximum, step;
        if (sscanf(line, "#pragma parameter %63s \"%127[^\"]\" %f %f %f %f",
                   parameter->name, label, &parameter->value, &minimum,
                   &maximum, &step) == 6)
            program->parameter_count++;
        line += strlen("#pragma parameter ");
    }
}

static void BackportRoyaleDeadVarying(char *source, bool resize_horizontal)
{
    /* Royale's mask pass carries TEX0 only as a vertex-stage temporary; the
     * fragment stage never consumes it. Apple's GL 2.1 linker still counts the
     * declaration against its eight-varying limit. Make that one declaration
     * stage-local. This is dead-interface elimination and does not alter any
     * value reaching the fragment calculation. Keep the replacement the same
     * length so compiler line numbers remain useful. */
    static const char texcoord[] = "COMPAT_VARYING vec4 TEX0;";
    for (char *p = source; (p = strstr(p, texcoord)) != NULL;
         p += sizeof(texcoord) - 1)
        memset(p, ' ', strlen("COMPAT_VARYING"));
    static const char input_tiles[] =
        "COMPAT_VARYING vec2 input_tiles_per_texture;";
    if (resize_horizontal)
        for (char *p = source; (p = strstr(p, input_tiles)) != NULL;
             p += sizeof(input_tiles) - 1)
            memset(p, ' ', strlen("COMPAT_VARYING"));

    /* The 1.30 compiler resolves this initializer to the interface variable;
     * Apple's 1.20 compiler treats it as a shadowing local and subsequently
     * reports that the fragment input was never written. Remove the redundant
     * local qualifier, preserving the assigned value exactly. */
    static const char texture_size[] = "const float2 texture_size_inv =";
    for (char *p = source; (p = strstr(p, texture_size)) != NULL;
         p += sizeof(texture_size) - 1)
        memset(p, ' ', strlen("const float2 "));
    static const char tile_uv[] = "const float2 tile_uv_wrap =";
    if (resize_horizontal)
        for (char *p = source; (p = strstr(p, tile_uv)) != NULL;
             p += sizeof(tile_uv) - 1)
            memset(p, ' ', strlen("const float2 "));
}

static GLuint Compile(vlc_ra_shader_engine_t *engine, GLenum type,
                      const char *stage, unsigned version, const char *source,
                      const char *name)
{
    char *header;
    /* Apple's compatibility context deliberately tops out at GLSL 1.20 even
     * on modern Macs. RetroArch backends expose the equivalent 1.30 operations
     * through ARB_shader_texture_lod on GL 2.1, so do the same semantic
     * backport rather than hiding CRT-Royale on otherwise capable hardware. */
    const bool backport_130 = version == 130 && engine->glsl_version < 130 &&
                              engine->glsl_version >= 120;
    if (backport_130) {
        if (asprintf(&header,
                     "#version 120\n"
                     "#extension GL_ARB_shader_texture_lod : enable\n"
                     "#define texture texture2D\n"
                     "#define textureLod texture2DLod\n"
                     "#define tanh(x) ((exp(2.0*(x))-1.0)/(exp(2.0*(x))+1.0))\n"
                     "#define round(x) (sign(x)*floor(abs(x)+0.5))\n"
                     "#define %s 1\n#define PARAMETER_UNIFORM 1\n",
                     stage) < 0)
            return 0;
    } else if (asprintf(&header,
                        "#version %u\n#define %s 1\n"
                        "#define PARAMETER_UNIFORM 1\n",
                        version, stage) < 0)
        return 0;
    const char *parts[] = { header, source };
    GLuint shader = engine->vt->CreateShader(type);
    engine->vt->ShaderSource(shader, 2, parts, NULL);
    msg_Dbg(engine->gl, "compiling RetroArch preset %s %s stage (GLSL %u)",
            name, stage, version);
    engine->vt->CompileShader(shader);
    free(header);

    GLint ok = GL_FALSE;
    engine->vt->GetShaderiv(shader, GL_COMPILE_STATUS, &ok);
    if (!ok) {
        GLint length = 0;
        engine->vt->GetShaderiv(shader, GL_INFO_LOG_LENGTH, &length);
        char *log = length > 1 ? malloc((size_t)length) : NULL;
        if (log) {
            GLsizei written;
            engine->vt->GetShaderInfoLog(shader, length, &written, log);
            msg_Dbg(engine->gl, "RetroArch preset %s rejected by GPU: %s", name, log);
            free(log);
        }
        engine->vt->DeleteShader(shader);
        return 0;
    }
    return shader;
}

static bool BuildProgram(vlc_ra_shader_engine_t *engine,
                         struct ra_program *program, const char *preset_name)
{
    char *path = ShaderPath(program->source);
    char *source = path ? ReadTextFile(path) : NULL;
    free(path);
    if (!source)
        return false;

    unsigned version = ExtractAndRemoveVersion(source);
    if (version == 130 && engine->glsl_version < 130 &&
        (strstr(program->source, "crt-royale-bloom-approx") != NULL ||
         strstr(program->source, "crt-royale-mask-resize-horizontal") != NULL ||
         strstr(program->source,
                "crt-royale-scanlines-horizontal-apply-mask") != NULL))
        BackportRoyaleDeadVarying(
            source, strstr(program->source,
                           "crt-royale-mask-resize-horizontal") != NULL);
    ParseParameters(program, source);
    GLuint vertex = Compile(engine, GL_VERTEX_SHADER, "VERTEX", version, source,
                            program->source);
    GLuint fragment = vertex ? Compile(engine, GL_FRAGMENT_SHADER, "FRAGMENT",
                                       version, source, program->source) : 0;
    free(source);
    if (!vertex || !fragment) {
        if (vertex) engine->vt->DeleteShader(vertex);
        return false;
    }

    program->id = engine->vt->CreateProgram();
    engine->vt->AttachShader(program->id, vertex);
    engine->vt->AttachShader(program->id, fragment);
    engine->vt->LinkProgram(program->id);
    engine->vt->DeleteShader(vertex);
    engine->vt->DeleteShader(fragment);
    GLint linked = GL_FALSE;
    engine->vt->GetProgramiv(program->id, GL_LINK_STATUS, &linked);
    if (!linked) {
        GLint length = 0;
        engine->vt->GetProgramiv(program->id, GL_INFO_LOG_LENGTH, &length);
        char *log = length > 1 ? malloc((size_t)length) : NULL;
        if (log) {
            GLsizei written;
            engine->vt->GetProgramInfoLog(program->id, length, &written, log);
            msg_Dbg(engine->gl,
                    "RetroArch preset %s pass %s rejected at link: %s",
                    preset_name, program->source, log);
            free(log);
        }
        engine->vt->DeleteProgram(program->id);
        program->id = 0;
        return false;
    }

    program->vertex_coord = engine->vt->GetAttribLocation(program->id, "VertexCoord");
    program->tex_coord = engine->vt->GetAttribLocation(program->id, "TexCoord");
    program->color = engine->vt->GetAttribLocation(program->id, "COLOR");
    program->mvp = engine->vt->GetUniformLocation(program->id, "MVPMatrix");
    program->texture = engine->vt->GetUniformLocation(program->id, "Texture");
    program->input_size = engine->vt->GetUniformLocation(program->id, "InputSize");
    program->texture_size = engine->vt->GetUniformLocation(program->id, "TextureSize");
    program->output_size = engine->vt->GetUniformLocation(program->id, "OutputSize");
    program->frame_count = engine->vt->GetUniformLocation(program->id, "FrameCount");
    program->frame_direction = engine->vt->GetUniformLocation(program->id, "FrameDirection");
    for (unsigned i = 0; i < program->parameter_count; ++i)
        program->parameters[i].location =
            engine->vt->GetUniformLocation(program->id,
                                           program->parameters[i].name);
    return program->vertex_coord >= 0 && program->tex_coord >= 0;
}

static char *PresetValue(const char *preset, const char *key)
{
    const size_t key_len = strlen(key);
    for (const char *line = preset; line && *line; ) {
        const char *end = strchr(line, '\n');
        if (!end) end = line + strlen(line);
        const char *p = line;
        while (p < end && (*p == ' ' || *p == '\t')) ++p;
        if ((size_t)(end - p) > key_len && !strncmp(p, key, key_len)) {
            p += key_len;
            while (p < end && (*p == ' ' || *p == '\t')) ++p;
            if (p < end && *p == '=') {
                ++p;
                while (p < end && (*p == ' ' || *p == '\t')) ++p;
                const char *tail = end;
                bool quoted = false;
                for (const char *scan = p; scan < tail; ++scan) {
                    if (*scan == '"') quoted = !quoted;
                    else if (*scan == '#' && !quoted) { tail = scan; break; }
                }
                while (tail > p && (tail[-1] == ' ' || tail[-1] == '\t' ||
                                    tail[-1] == '\r')) --tail;
                if (tail > p + 1 && *p == '"' && tail[-1] == '"') {
                    ++p;
                    --tail;
                }
                return strndup(p, (size_t)(tail - p));
            }
        }
        line = *end ? end + 1 : end;
    }
    return NULL;
}

static bool PresetBool(const char *, const char *, bool);
static enum ra_wrap_mode PresetWrap(const char *, const char *,
                                    enum ra_wrap_mode);
static GLenum WrapEnum(enum ra_wrap_mode);

static struct ra_lut *LoadLut(vlc_ra_shader_engine_t *engine,
                              const char *preset, const char *name)
{
    char *relative = PresetValue(preset, name);
    if (!relative || !*relative) { free(relative); return NULL; }
    char shader_relative[PATH_MAX];
    bool path_ok = snprintf(shader_relative, sizeof(shader_relative), "crt/%s",
                            relative) < (int)sizeof(shader_relative);
    free(relative);
    if (!path_ok) return NULL;

    char key[96];
    snprintf(key, sizeof(key), "%s_linear", name);
    bool linear = PresetBool(preset, key, false);
    snprintf(key, sizeof(key), "%s_mipmap", name);
    bool mipmap = PresetBool(preset, key, false);
    snprintf(key, sizeof(key), "%s_wrap_mode", name);
    enum ra_wrap_mode wrap_mode = PresetWrap(preset, key, RA_WRAP_BORDER);
    for (unsigned i = 0; i < engine->lut_count; ++i) {
        struct ra_lut *cached = &engine->luts[i];
        if (!strcmp(cached->name, name) &&
            !strcmp(cached->source, shader_relative) &&
            cached->linear == linear && cached->mipmap == mipmap &&
            cached->wrap_mode == wrap_mode)
            return cached;
    }
    if (engine->lut_count == RA_MAX_SHARED_LUTS ||
        (mipmap && !engine->vt->GenerateMipmap))
        return NULL;

    struct ra_lut *lut = &engine->luts[engine->lut_count];
    char *path = path_ok ? ShaderPath(shader_relative) : NULL;
    char *uri = path ? vlc_path2uri(path, NULL) : NULL;
    free(path);
    if (!uri) return NULL;

    video_format_t input, output;
    video_format_Init(&input, 0);
    video_format_Init(&output, VLC_CODEC_RGBA);
    image_handler_t *handler = image_HandlerCreate(engine->gl);
    picture_t *picture = handler ? image_ReadUrl(handler, uri, &input, &output) : NULL;
    free(uri);
    if (handler) image_HandlerDelete(handler);
    video_format_Clean(&input);
    video_format_Clean(&output);
    if (!picture || picture->i_planes != 1) {
        if (picture) picture_Release(picture);
        return NULL;
    }

    lut->width = picture->format.i_visible_width;
    lut->height = picture->format.i_visible_height;
    size_t pitch = (size_t)lut->width * 4;
    if (!lut->width || !lut->height || pitch / 4 != lut->width ||
        lut->height > SIZE_MAX / pitch) {
        picture_Release(picture);
        return NULL;
    }
    uint8_t *pixels = malloc(pitch * lut->height);
    if (!pixels) { picture_Release(picture); return NULL; }
    for (unsigned y = 0; y < lut->height; ++y)
        memcpy(pixels + y * pitch,
               picture->p[0].p_pixels + y * picture->p[0].i_pitch, pitch);
    picture_Release(picture);

    strlcpy(lut->name, name, sizeof(lut->name));
    strlcpy(lut->source, shader_relative, sizeof(lut->source));
    lut->linear = linear;
    lut->mipmap = mipmap;
    lut->wrap_mode = wrap_mode;

    engine->vt->GenTextures(1, &lut->texture);
    engine->vt->BindTexture(GL_TEXTURE_2D, lut->texture);
    engine->vt->TexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S,
                              WrapEnum(lut->wrap_mode));
    engine->vt->TexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T,
                              WrapEnum(lut->wrap_mode));
    engine->vt->TexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER,
                              lut->linear ? GL_LINEAR : GL_NEAREST);
    engine->vt->TexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER,
                              lut->mipmap ? GL_LINEAR_MIPMAP_LINEAR :
                              lut->linear ? GL_LINEAR : GL_NEAREST);
    engine->vt->TexImage2D(GL_TEXTURE_2D, 0, GL_RGBA8, lut->width, lut->height,
                           0, GL_RGBA, GL_UNSIGNED_BYTE, pixels);
    if (lut->mipmap) engine->vt->GenerateMipmap(GL_TEXTURE_2D);
    free(pixels);
    engine->lut_count++;
    return lut;
}

static bool LoadLuts(vlc_ra_shader_engine_t *engine, struct ra_preset *out,
                     const char *preset, char *list)
{
    if (!list || !*list) return true;
    char *save = NULL;
    for (char *name = strtok_r(list, ";", &save); name;
         name = strtok_r(NULL, ";", &save)) {
        while (*name == ' ' || *name == '\t') ++name;
        char *end = name + strlen(name);
        while (end > name && (end[-1] == ' ' || end[-1] == '\t')) *--end = 0;
        if (!*name) continue;
        if (out->lut_count == RA_MAX_TEXTURES)
            return false;
        struct ra_lut *lut = LoadLut(engine, preset, name);
        if (!lut) return false;
        out->luts[out->lut_count] = lut;
        out->lut_count++;
    }
    return true;
}

static bool PresetBool(const char *preset, const char *key, bool fallback)
{
    char *value = PresetValue(preset, key);
    if (!value) return fallback;
    bool result = !strcasecmp(value, "true") || !strcmp(value, "1");
    free(value);
    return result;
}

static float PresetFloat(const char *preset, const char *key, float fallback)
{
    char *value = PresetValue(preset, key);
    if (!value) return fallback;
    char *end;
    float result = strtof(value, &end);
    if (end == value) result = fallback;
    free(value);
    return result;
}

static enum ra_scale_type PresetScale(const char *preset, const char *key)
{
    char *value = PresetValue(preset, key);
    enum ra_scale_type result = RA_SCALE_SOURCE;
    if (value && !strcasecmp(value, "viewport")) result = RA_SCALE_VIEWPORT;
    else if (value && !strcasecmp(value, "absolute")) result = RA_SCALE_ABSOLUTE;
    free(value);
    return result;
}

static enum ra_wrap_mode PresetWrap(const char *preset, const char *key,
                                    enum ra_wrap_mode fallback)
{
    char *value = PresetValue(preset, key);
    enum ra_wrap_mode result = fallback;
    if (value && !strcasecmp(value, "clamp_to_border")) result = RA_WRAP_BORDER;
    else if (value && !strcasecmp(value, "clamp_to_edge")) result = RA_WRAP_EDGE;
    else if (value && !strcasecmp(value, "repeat")) result = RA_WRAP_REPEAT;
    else if (value && !strcasecmp(value, "mirrored_repeat"))
        result = RA_WRAP_MIRRORED_REPEAT;
    free(value);
    return result;
}

static GLenum WrapEnum(enum ra_wrap_mode mode)
{
    switch (mode) {
        case RA_WRAP_EDGE: return GL_CLAMP_TO_EDGE;
        case RA_WRAP_REPEAT: return GL_REPEAT;
        case RA_WRAP_MIRRORED_REPEAT: return GL_MIRRORED_REPEAT;
        default: return GL_CLAMP_TO_BORDER;
    }
}

static void DeleteTarget(vlc_ra_shader_engine_t *engine, struct ra_target *target)
{
    if (target->framebuffer)
        engine->vt->DeleteFramebuffers(1, &target->framebuffer);
    if (target->texture)
        engine->vt->DeleteTextures(1, &target->texture);
    memset(target, 0, sizeof(*target));
}

static bool AllocateTarget(vlc_ra_shader_engine_t *engine,
                           struct ra_target *target, unsigned width,
                           unsigned height, GLenum internal_format)
{
    if (target->width == width && target->height == height &&
        target->internal_format == internal_format)
        return true;
    GLint previous_framebuffer = 0;
    engine->vt->GetIntegerv(GL_FRAMEBUFFER_BINDING, &previous_framebuffer);
    if (!target->texture)
        engine->vt->GenTextures(1, &target->texture);
    engine->vt->BindTexture(GL_TEXTURE_2D, target->texture);
    engine->vt->TexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
    engine->vt->TexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
    GLenum type = internal_format == GL_RGBA16F ? GL_FLOAT : GL_UNSIGNED_BYTE;
    engine->vt->TexImage2D(GL_TEXTURE_2D, 0, internal_format, width, height, 0,
                           GL_RGBA, type, NULL);
    if (!target->framebuffer)
        engine->vt->GenFramebuffers(1, &target->framebuffer);
    engine->vt->BindFramebuffer(GL_FRAMEBUFFER, target->framebuffer);
    engine->vt->FramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0,
                                     GL_TEXTURE_2D, target->texture, 0);
    bool complete = engine->vt->CheckFramebufferStatus(GL_FRAMEBUFFER) ==
                    GL_FRAMEBUFFER_COMPLETE;
    engine->vt->BindFramebuffer(GL_FRAMEBUFFER, (GLuint)previous_framebuffer);
    if (!complete) {
        DeleteTarget(engine, target);
        return false;
    }
    target->width = width;
    target->height = height;
    target->internal_format = internal_format;
    return true;
}

static void DeletePreset(vlc_ra_shader_engine_t *engine, struct ra_preset *preset)
{
    for (unsigned i = 0; i < preset->pass_count; ++i) {
        if (preset->passes[i].id)
            engine->vt->DeleteProgram(preset->passes[i].id);
        DeleteTarget(engine, &preset->targets[i]);
    }
    DeleteTarget(engine, &preset->feedback);
    preset->lut_count = 0;
    preset->valid = false;
}

static unsigned ProgramHistoryCount(vlc_ra_shader_engine_t *engine, GLuint id)
{
    unsigned count = 0;
    char uniform[64];
    for (unsigned i = 0; i < RA_MAX_HISTORY; ++i) {
        snprintf(uniform, sizeof(uniform), i ? "Prev%uTexture" : "PrevTexture",
                 i);
        if (engine->vt->GetUniformLocation(id, uniform) >= 0) count = i + 1;
    }
    return count;
}

static bool PresetFitsTextureUnits(vlc_ra_shader_engine_t *engine,
                                   const struct ra_preset *preset)
{
    char uniform[96];
    for (unsigned pass_index = 0; pass_index < preset->pass_count;
         ++pass_index) {
        GLuint id = preset->passes[pass_index].id;
        unsigned units = 1; /* The current pass input always occupies unit 0. */

        for (unsigned history = 0; history < pass_index; ++history) {
            const unsigned back = pass_index - history;
            snprintf(uniform, sizeof(uniform), "Pass%uTexture", history + 1);
            bool used = engine->vt->GetUniformLocation(id, uniform) >= 0;
            if (preset->passes[history].alias[0]) {
                snprintf(uniform, sizeof(uniform), "%sTexture",
                         preset->passes[history].alias);
                used |= engine->vt->GetUniformLocation(id, uniform) >= 0;
            }
            snprintf(uniform, sizeof(uniform), "PassPrev%uTexture", back);
            used |= engine->vt->GetUniformLocation(id, uniform) >= 0;
            if (used && history + 1 != pass_index)
                ++units;
        }
        if (pass_index) {
            snprintf(uniform, sizeof(uniform), "PassPrev%uTexture",
                     pass_index + 1);
            if (engine->vt->GetUniformLocation(id, "OrigTexture") >= 0 ||
                engine->vt->GetUniformLocation(id, uniform) >= 0)
                ++units;
        }
        for (unsigned i = 0; i < preset->history_count; ++i) {
            snprintf(uniform, sizeof(uniform), i ? "Prev%uTexture" :
                                                  "PrevTexture", i);
            if (engine->vt->GetUniformLocation(id, uniform) >= 0)
                ++units;
        }
        for (unsigned i = 0; i < preset->lut_count; ++i)
            if (engine->vt->GetUniformLocation(id,
                                               preset->luts[i]->name) >= 0)
                ++units;
        if (engine->vt->GetUniformLocation(id, "FeedbackTexture") >= 0) {
            if (preset->feedback_pass < 0)
                return false;
            ++units;
        }
        if (units > (unsigned)engine->max_texture_units) {
            msg_Dbg(engine->gl,
                    "RetroArch preset %s rejected: pass %u needs %u texture "
                    "units, GPU exposes %d",
                    preset->name, pass_index, units,
                    engine->max_texture_units);
            return false;
        }
    }
    return true;
}

static void PropagatePresetParameters(vlc_ra_shader_engine_t *engine,
                                      struct ra_preset *preset)
{
    /* RetroArch parameters belong to the preset, not to the source file that
     * carries their #pragma declarations. CRT-Royale declares the complete
     * parameter block in its final pass while earlier passes consume the same
     * uniforms. OpenGL initializes an unset uniform to zero, which turns the
     * mask/beam stages black, so propagate each declared value to every pass
     * that exposes the corresponding uniform. */
    struct ra_parameter parameters[RA_MAX_PARAMETERS];
    unsigned count = 0;
    for (unsigned pass = 0; pass < preset->pass_count; ++pass) {
        struct ra_program *program = &preset->passes[pass];
        for (unsigned i = 0; i < program->parameter_count; ++i) {
            bool known = false;
            for (unsigned p = 0; p < count; ++p)
                if (!strcmp(parameters[p].name,
                            program->parameters[i].name)) {
                    known = true;
                    break;
                }
            if (!known && count < ARRAY_SIZE(parameters))
                parameters[count++] = program->parameters[i];
        }
    }

    for (unsigned pass = 0; pass < preset->pass_count; ++pass) {
        struct ra_program *program = &preset->passes[pass];
        for (unsigned p = 0; p < count; ++p) {
            bool known = false;
            for (unsigned i = 0; i < program->parameter_count; ++i)
                if (!strcmp(program->parameters[i].name,
                            parameters[p].name)) {
                    /* A preset override parsed in another pass is global too. */
                    program->parameters[i].value = parameters[p].value;
                    known = true;
                    break;
                }
            if (known || program->parameter_count == RA_MAX_PARAMETERS)
                continue;
            GLint location = engine->vt->GetUniformLocation(
                program->id, parameters[p].name);
            if (location < 0)
                continue;
            struct ra_parameter *parameter =
                &program->parameters[program->parameter_count++];
            *parameter = parameters[p];
            parameter->location = location;
        }
    }

}

static bool BuildPreset(vlc_ra_shader_engine_t *engine,
                        struct ra_preset *out,
                        const struct ra_preset_template *info)
{
    out->name = info->name;
    out->lightweight = info->lightweight;
    out->attempted = true;
    char relative[PATH_MAX];
    if (snprintf(relative, sizeof(relative), "crt/%s.glslp", info->name) >=
        (int)sizeof(relative))
        return false;
    char *path = ShaderPath(relative);
    char *preset = path ? ReadTextFile(path) : NULL;
    free(path);
    if (!preset) return false;

    /* External textures are loaded only when every declared resource can be
     * decoded.  Do not silently substitute a shader-generated approximation. */
    char *textures = PresetValue(preset, "textures");
    char *feedback = PresetValue(preset, "feedback_pass");
    if (textures && *textures && !LoadLuts(engine, out, preset, textures)) {
        free(textures); free(feedback); free(preset); DeletePreset(engine, out);
        return false;
    }
    free(textures);
    out->feedback_pass = feedback && *feedback ? (int)strtol(feedback, NULL, 10) : -1;
    free(feedback);
    char *count = PresetValue(preset, "shaders");
    unsigned pass_count = count ? (unsigned)strtoul(count, NULL, 10) : 0;
    free(count);
    if (!pass_count || pass_count > RA_MAX_PASSES) {
        free(preset); DeletePreset(engine, out);
        return false;
    }
    out->pass_count = pass_count;

    for (unsigned i = 0; i < pass_count; ++i) {
        struct ra_program *program = &out->passes[i];
        char key[64];
        snprintf(key, sizeof(key), "shader%u", i);
        char *shader = PresetValue(preset, key);
        if (!shader || snprintf(program->source, sizeof(program->source),
                                "crt/%s", shader) >=
                       (int)sizeof(program->source)) {
            free(shader); free(preset); DeletePreset(engine, out); return false;
        }
        free(shader);
        snprintf(key, sizeof(key), "filter_linear%u", i);
        program->linear = PresetBool(preset, key, false);
        snprintf(key, sizeof(key), "srgb_framebuffer%u", i);
        program->srgb = PresetBool(preset, key, false);
        snprintf(key, sizeof(key), "float_framebuffer%u", i);
        program->floating = PresetBool(preset, key, false);
        snprintf(key, sizeof(key), "mipmap_input%u", i);
        program->mipmap_input = PresetBool(preset, key, false);
        snprintf(key, sizeof(key), "wrap_mode%u", i);
        program->wrap_mode = PresetWrap(preset, key, RA_WRAP_BORDER);
        snprintf(key, sizeof(key), "texture_wrap_mode%u", i);
        program->wrap_mode = PresetWrap(preset, key, program->wrap_mode);
        snprintf(key, sizeof(key), "scale_type%u", i);
        enum ra_scale_type common_scale_type = PresetScale(preset, key);
        snprintf(key, sizeof(key), "scale%u", i);
        float common_scale = PresetFloat(preset, key, 1.f);
        snprintf(key, sizeof(key), "scale_type_x%u", i);
        char *has_x_type = PresetValue(preset, key);
        program->scale_type_x = has_x_type ? PresetScale(preset, key) :
                                             common_scale_type;
        free(has_x_type);
        snprintf(key, sizeof(key), "scale_type_y%u", i);
        char *has_y_type = PresetValue(preset, key);
        program->scale_type_y = has_y_type ? PresetScale(preset, key) :
                                             common_scale_type;
        free(has_y_type);
        snprintf(key, sizeof(key), "scale_x%u", i);
        program->scale_x = PresetFloat(preset, key, common_scale);
        snprintf(key, sizeof(key), "scale_y%u", i);
        program->scale_y = PresetFloat(preset, key, common_scale);
        snprintf(key, sizeof(key), "alias%u", i);
        char *alias = PresetValue(preset, key);
        if (alias) { strlcpy(program->alias, alias, sizeof(program->alias)); free(alias); }
        if (!BuildProgram(engine, program, info->name)) {
            free(preset); DeletePreset(engine, out); return false;
        }
        unsigned history_count = ProgramHistoryCount(engine, program->id);
        if (history_count > out->history_count)
            out->history_count = history_count;
        for (unsigned p = 0; p < program->parameter_count; ++p) {
            char *override = PresetValue(preset, program->parameters[p].name);
            if (override) {
                char *end;
                float value = strtof(override, &end);
                if (end != override) program->parameters[p].value = value;
                free(override);
            }
        }
        /* RetroArch inserts a stock presentation pass when a final shader has
         * an explicit off-screen scale. */
        snprintf(key, sizeof(key), "scale_type%u", i);
        char *last_common = PresetValue(preset, key);
        snprintf(key, sizeof(key), "scale_type_x%u", i);
        char *last_x = PresetValue(preset, key);
        snprintf(key, sizeof(key), "scale_type_y%u", i);
        char *last_y = PresetValue(preset, key);
        bool scaled_final = i + 1 == pass_count &&
                            (last_common || last_x || last_y);
        free(last_common); free(last_x); free(last_y);
        if (scaled_final) {
            if (pass_count == RA_MAX_PASSES) {
                free(preset); DeletePreset(engine, out); return false;
            }
            GLenum format = program->floating ? GL_RGBA16F :
                            program->srgb ? GL_SRGB8_ALPHA8 : GL_RGBA8;
            if (!AllocateTarget(engine, &out->targets[i], 16, 16, format)) {
                free(preset); DeletePreset(engine, out); return false;
            }
            struct ra_program *stock = &out->passes[pass_count];
            strlcpy(stock->source, "crt/../stock.glsl", sizeof(stock->source));
            stock->linear = program->linear;
            stock->wrap_mode = RA_WRAP_BORDER;
            stock->scale_x = stock->scale_y = 1.f;
            if (!BuildProgram(engine, stock, info->name)) {
                free(preset); DeletePreset(engine, out); return false;
            }
            out->pass_count++;
        } else if (i + 1 < pass_count) {
            GLenum format = program->floating ? GL_RGBA16F :
                            program->srgb ? GL_SRGB8_ALPHA8 : GL_RGBA8;
            if (!AllocateTarget(engine, &out->targets[i], 16, 16, format)) {
                free(preset); DeletePreset(engine, out); return false;
            }
        } else if (program->srgb && !engine->default_srgb) {
            free(preset); DeletePreset(engine, out); return false;
        }
    }
    if (out->feedback_pass >= (int)out->pass_count - 1)
        out->feedback_pass = -1;
    free(preset);
    PropagatePresetParameters(engine, out);
    if (!PresetFitsTextureUnits(engine, out)) {
        DeletePreset(engine, out);
        return false;
    }
    out->valid = true;
    return true;
}

static void PublishCapabilities(vlc_ra_shader_engine_t *engine,
                                bool allow_long_shaders)
{
    char *available = strdup("");
    if (!available)
        return;
    for (size_t i = 0; i < ARRAY_SIZE(engine->presets); ++i) {
        struct ra_preset *preset = &engine->presets[i];
        if ((!allow_long_shaders && !preset_templates[i].lightweight) ||
            (preset->attempted && !preset->valid))
            continue;
        /* Do not compile the complete catalogue while opening a video.  Some
         * virtual and older drivers take tens of seconds to compile all CRT
         * passes, starving VLC's decoder before its first frame.  A missing
         * packaged preset is still excluded cheaply; actual GPU compilation
         * happens once, when the user selects it. */
        char relative[PATH_MAX];
        if (snprintf(relative, sizeof(relative), "crt/%s.glslp",
                     preset_templates[i].name) >= (int)sizeof(relative))
            continue;
        char *path = ShaderPath(relative);
        char *source = path ? ReadTextFile(path) : NULL;
        free(path);
        if (!source)
            continue;
        free(source);
        preset->name = preset_templates[i].name;
        preset->lightweight = preset_templates[i].lightweight;
        char *next;
        if (asprintf(&next, "%s%s%s", available, *available ? ";" : "",
                     preset->name) < 0)
            continue;
        free(available);
        available = next;
    }
    vlc_object_t *root = VLC_OBJECT(engine->gl->obj.libvlc);
    var_Create(root, "crt-retroarch-available", VLC_VAR_STRING);
    var_SetString(root, "crt-retroarch-available", available);
    var_Create(root, "crt-retroarch-backend", VLC_VAR_STRING);
    var_SetString(root, "crt-retroarch-backend",
                  *available ? "opengl-retroarch-glsl" : "cpu-legacy");
    var_Create(root, "crt-retroarch-owner", VLC_VAR_ADDRESS);
    var_SetAddress(root, "crt-retroarch-owner", engine);
    char *preset = var_InheritString(engine->gl, "crt-retroarch-preset");
    bool enabled = var_InheritBool(engine->gl, "crt-retroarch-enabled");
    var_Create(root, "crt-retroarch-enabled", VLC_VAR_BOOL);
    var_SetBool(root, "crt-retroarch-enabled", enabled);
    var_Create(root, "crt-retroarch-preset", VLC_VAR_STRING);
    var_SetString(root, "crt-retroarch-preset",
                  preset ? preset : "crt-easymode");
    free(preset);
    char *raster = var_InheritString(engine->gl, "crt-retroarch-raster");
    var_Create(root, "crt-retroarch-raster", VLC_VAR_STRING);
    var_SetString(root, "crt-retroarch-raster", raster ? raster : "auto");
    free(raster);
    msg_Info(engine->gl, "RetroArch CRT shaders supported by this GPU: %s",
             *available ? available : "none");
    free(available);
}

vlc_ra_shader_engine_t *vlc_ra_shader_engine_Create(vlc_gl_t *gl,
                                                     const opengl_vtable_t *vt,
                                                     bool allow_long_shaders)
{
    if (!vt->BindFramebuffer || !vt->CheckFramebufferStatus ||
        !vt->DeleteFramebuffers || !vt->FramebufferTexture2D ||
        !vt->GenFramebuffers)
        return NULL;
    vlc_ra_shader_engine_t *engine = calloc(1, sizeof(*engine));
    if (!engine)
        return NULL;
    engine->gl = gl;
    engine->vt = vt;
    engine->allow_long_shaders = allow_long_shaders;
    const char *glsl = (const char *)vt->GetString(GL_SHADING_LANGUAGE_VERSION);
    unsigned major = 1, minor = 20;
    if (glsl && sscanf(glsl, "%u.%u", &major, &minor) == 2)
        engine->glsl_version = major * 100 + minor;
    else
        engine->glsl_version = 120;
    vt->GetIntegerv(GL_MAX_TEXTURE_IMAGE_UNITS, &engine->max_texture_units);
    if (engine->max_texture_units < 2) { free(engine); return NULL; }
    if (vt->GetFramebufferAttachmentParameteriv) {
        GLint framebuffer = 0;
        GLint encoding = 0;
        vt->GetIntegerv(GL_FRAMEBUFFER_BINDING, &framebuffer);
        vt->GetFramebufferAttachmentParameteriv(GL_FRAMEBUFFER,
            framebuffer ? GL_COLOR_ATTACHMENT0 : GL_BACK_LEFT,
            GL_FRAMEBUFFER_ATTACHMENT_COLOR_ENCODING, &encoding);
        engine->default_srgb = encoding == GL_SRGB;
    }
    static const GLfloat positions[] = { -1,-1, 1,-1, -1,1, 1,1 };
    static const GLfloat texcoords[] = { 0,0, 1,0, 0,1, 1,1 };
    static const GLfloat colors[] = { 1,1,1,1, 1,1,1,1,
                                      1,1,1,1, 1,1,1,1 };
    vt->GenBuffers(1, &engine->vertex_buffer);
    vt->BindBuffer(GL_ARRAY_BUFFER, engine->vertex_buffer);
    vt->BufferData(GL_ARRAY_BUFFER, sizeof(positions), positions, GL_STATIC_DRAW);
    vt->GenBuffers(1, &engine->texcoord_buffer);
    vt->BindBuffer(GL_ARRAY_BUFFER, engine->texcoord_buffer);
    vt->BufferData(GL_ARRAY_BUFFER, sizeof(texcoords), texcoords, GL_STATIC_DRAW);
    vt->GenBuffers(1, &engine->color_buffer);
    vt->BindBuffer(GL_ARRAY_BUFFER, engine->color_buffer);
    vt->BufferData(GL_ARRAY_BUFFER, sizeof(colors), colors, GL_STATIC_DRAW);
    strlcpy(engine->resampler.source, "crt/../stock.glsl",
            sizeof(engine->resampler.source));
    engine->resampler.linear = true;
    engine->resampler.wrap_mode = RA_WRAP_EDGE;
    engine->resampler.scale_x = engine->resampler.scale_y = 1.f;
    if (!BuildProgram(engine, &engine->resampler, "raster-normalizer"))
        msg_Warn(engine->gl, "RetroArch raster normalization unavailable");
    PublishCapabilities(engine, allow_long_shaders);
    return engine;
}

void vlc_ra_shader_engine_Delete(vlc_ra_shader_engine_t *engine)
{
    if (!engine) return;
    vlc_object_t *root = VLC_OBJECT(engine->gl->obj.libvlc);
    if (var_GetAddress(root, "crt-retroarch-owner") == engine) {
        var_SetAddress(root, "crt-retroarch-owner", NULL);
        var_SetString(root, "crt-retroarch-available", "");
        var_SetString(root, "crt-retroarch-backend", "cpu-legacy");
        /* A hardware-decoder negotiation can destroy a provisional OpenGL
         * output and create another one immediately.  Keep the user's enabled
         * state across that hand-off; clearing it here silently disabled the
         * shader on the final Windows output. */
    }
    for (size_t i = 0; i < ARRAY_SIZE(engine->presets); ++i)
        DeletePreset(engine, &engine->presets[i]);
    DeleteTarget(engine, &engine->input);
    DeleteTarget(engine, &engine->normalized);
    for (unsigned i = 0; i < RA_MAX_HISTORY; ++i)
        DeleteTarget(engine, &engine->history[i]);
    for (unsigned i = 0; i < engine->lut_count; ++i)
        if (engine->luts[i].texture)
            engine->vt->DeleteTextures(1, &engine->luts[i].texture);
    if (engine->vertex_buffer)
        engine->vt->DeleteBuffers(1, &engine->vertex_buffer);
    if (engine->texcoord_buffer)
        engine->vt->DeleteBuffers(1, &engine->texcoord_buffer);
    if (engine->color_buffer)
        engine->vt->DeleteBuffers(1, &engine->color_buffer);
    if (engine->resampler.id)
        engine->vt->DeleteProgram(engine->resampler.id);
    free(engine);
}

void vlc_ra_shader_engine_SetViewport(vlc_ra_shader_engine_t *engine,
                                     int x, int y, unsigned width,
                                     unsigned height)
{
    if (!engine) return;
    engine->viewport_x = x;
    engine->viewport_y = y;
    engine->viewport_width = width;
    engine->viewport_height = height;
}

void vlc_ra_shader_engine_NewFrame(vlc_ra_shader_engine_t *engine,
                                   vlc_tick_t pts)
{
    if (!engine)
        return;

    /* Some outputs prepare the same decoded picture again for redraws. A
     * Prepare() call alone therefore does not imply a new RetroArch frame. */
    if (pts != VLC_TICK_INVALID &&
        (!engine->have_frame_pts || pts != engine->frame_pts))
        engine->new_frame = true;
    else if (pts == VLC_TICK_INVALID && !engine->have_frame_pts)
        engine->new_frame = true;

    if (pts != VLC_TICK_INVALID) {
        engine->frame_pts = pts;
        engine->have_frame_pts = true;
    }
}

static struct ra_preset *FindPreset(vlc_ra_shader_engine_t *engine,
                                    const char *name)
{
    for (size_t i = 0; i < ARRAY_SIZE(engine->presets); ++i)
        if (!strcmp(preset_templates[i].name, name)) {
            struct ra_preset *preset = &engine->presets[i];
            if ((!engine->allow_long_shaders &&
                 !preset_templates[i].lightweight) ||
                (preset->attempted && !preset->valid))
                return NULL;
            if (!preset->valid &&
                !BuildPreset(engine, preset, &preset_templates[i])) {
                PublishCapabilities(engine, engine->allow_long_shaders);
                return NULL;
            }
            return preset;
        }
    return NULL;
}

static bool ResetHistory(vlc_ra_shader_engine_t *engine, unsigned count,
                         unsigned width, unsigned height)
{
    for (unsigned i = 0; i < RA_MAX_HISTORY; ++i)
        DeleteTarget(engine, &engine->history[i]);
    engine->history_count = 0;
    GLint previous = 0;
    engine->vt->GetIntegerv(GL_FRAMEBUFFER_BINDING, &previous);
    for (unsigned i = 0; i < count; ++i) {
        if (!AllocateTarget(engine, &engine->history[i], width, height, GL_RGBA8)) {
            engine->vt->BindFramebuffer(GL_FRAMEBUFFER, (GLuint)previous);
            return false;
        }
        engine->vt->BindFramebuffer(GL_FRAMEBUFFER,
                                     engine->history[i].framebuffer);
        engine->vt->Clear(GL_COLOR_BUFFER_BIT);
    }
    engine->vt->BindFramebuffer(GL_FRAMEBUFFER, (GLuint)previous);
    engine->history_count = count;
    return true;
}

bool vlc_ra_shader_engine_Begin(vlc_ra_shader_engine_t *engine,
                               unsigned input_width, unsigned input_height)
{
    if (!engine || !var_InheritBool(engine->gl, "crt-retroarch-enabled"))
        return false;
    GLint output_framebuffer = 0;
    engine->vt->GetIntegerv(GL_FRAMEBUFFER_BINDING, &output_framebuffer);
    engine->output_framebuffer = (GLuint)output_framebuffer;
    bool input_changed = engine->input.width != input_width ||
                         engine->input.height != input_height;
    char *name = var_InheritString(engine->gl, "crt-retroarch-preset");
    struct ra_preset *preset = name ? FindPreset(engine, name) : NULL;
    if (!preset || !engine->viewport_width || !engine->viewport_height ||
        !AllocateTarget(engine, &engine->input, input_width, input_height,
                        GL_RGBA8)) {
        free(name);
        return false;
    }
    bool selection_changed = strcmp(engine->selected, name) != 0;
    bool history_changed = engine->history_count != preset->history_count ||
        (preset->history_count &&
         (engine->history[0].width != input_width ||
          engine->history[0].height != input_height));
    if (selection_changed || history_changed) {
        if (!ResetHistory(engine, preset->history_count, input_width,
                          input_height)) {
            free(name);
            return false;
        }
        if (selection_changed) {
            DeleteTarget(engine, &preset->feedback);
            engine->frame_count = 0;
            strlcpy(engine->selected, name, sizeof(engine->selected));
            msg_Info(engine->gl, "using exact RetroArch CRT preset %s", name);
        }
    }
    if (input_changed && !selection_changed)
        DeleteTarget(engine, &preset->feedback);
    free(name);
    engine->active = preset;
    engine->vt->BindFramebuffer(GL_FRAMEBUFFER, engine->input.framebuffer);
    engine->vt->Viewport(0, 0, input_width, input_height);
    engine->vt->Clear(GL_COLOR_BUFFER_BIT);
    return true;
}

/* Video releases are often stored after a 240p/480p master has already been
 * enlarged to 720p/1080p. RetroArch cores instead feed CRT presets their
 * native raster; several shaders deliberately treat every input row as a CRT
 * scanline. Restore a native-like raster before the original preset runs.
 * A mipmapped GPU pass suppresses moire without a CPU round-trip. */
static unsigned RetroArchRasterHeight(vlc_ra_shader_engine_t *engine,
                                      const struct ra_preset *preset)
{
    if (preset->history_count || !engine->resampler.id)
        return 0;

    char *mode = var_InheritString(engine->gl, "crt-retroarch-raster");
    unsigned height = 0;
    if (mode && !strcmp(mode, "240p"))
        height = 240;
    else if (mode && !strcmp(mode, "480p"))
        height = 480;
    else if ((!mode || !strcmp(mode, "auto")) && engine->input.height > 576)
        height = 480;
    free(mode);
    return height == engine->input.height ? 0 : height;
}

static bool NormalizeRetroArchRaster(vlc_ra_shader_engine_t *engine,
                                     unsigned height)
{
    const opengl_vtable_t *vt = engine->vt;
    const uint64_t scaled = (uint64_t)engine->input.width * height +
                            engine->input.height / 2;
    unsigned width = (unsigned)(scaled / engine->input.height);
    if (width > 1)
        width = (width + 1) & ~1u;
    const bool changed = engine->normalized.width != width ||
                         engine->normalized.height != height;
    if (!width || !AllocateTarget(engine, &engine->normalized, width, height,
                                  GL_RGBA8))
        return false;
    if (changed)
        msg_Info(engine->gl, "normalizing RetroArch CRT source raster from "
                 "%ux%u to %ux%u for preset %s", engine->input.width,
                 engine->input.height, width, height, engine->selected);

    struct ra_program *program = &engine->resampler;
    vt->BindFramebuffer(GL_FRAMEBUFFER, engine->normalized.framebuffer);
    vt->Viewport(0, 0, width, height);
    vt->Disable(GL_FRAMEBUFFER_SRGB);
    vt->UseProgram(program->id);
    vt->ActiveTexture(GL_TEXTURE0);
    vt->BindTexture(GL_TEXTURE_2D, engine->input.texture);
    vt->TexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER,
                      vt->GenerateMipmap ? GL_LINEAR_MIPMAP_LINEAR : GL_LINEAR);
    vt->TexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
    vt->TexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
    vt->TexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
    if (vt->GenerateMipmap)
        vt->GenerateMipmap(GL_TEXTURE_2D);
    if (program->texture >= 0)
        vt->Uniform1i(program->texture, 0);
    if (program->input_size >= 0)
        vt->Uniform2f(program->input_size, engine->input.width,
                      engine->input.height);
    if (program->texture_size >= 0)
        vt->Uniform2f(program->texture_size, engine->input.width,
                      engine->input.height);
    if (program->output_size >= 0)
        vt->Uniform2f(program->output_size, width, height);
    if (program->mvp >= 0) {
        static const GLfloat identity[] = { 1,0,0,0, 0,1,0,0,
                                            0,0,1,0, 0,0,0,1 };
        vt->UniformMatrix4fv(program->mvp, 1, GL_FALSE, identity);
    }
    vt->BindBuffer(GL_ARRAY_BUFFER, engine->vertex_buffer);
    vt->EnableVertexAttribArray(program->vertex_coord);
    vt->VertexAttribPointer(program->vertex_coord, 2, GL_FLOAT, GL_FALSE, 0, 0);
    vt->BindBuffer(GL_ARRAY_BUFFER, engine->texcoord_buffer);
    vt->EnableVertexAttribArray(program->tex_coord);
    vt->VertexAttribPointer(program->tex_coord, 2, GL_FLOAT, GL_FALSE, 0, 0);
    if (program->color >= 0) {
        vt->BindBuffer(GL_ARRAY_BUFFER, engine->color_buffer);
        vt->EnableVertexAttribArray(program->color);
        vt->VertexAttribPointer(program->color, 4, GL_FLOAT, GL_FALSE, 0, 0);
    }
    vt->DrawArrays(GL_TRIANGLE_STRIP, 0, 4);
    return true;
}

void vlc_ra_shader_engine_End(vlc_ra_shader_engine_t *engine)
{
    struct ra_preset *preset = engine ? engine->active : NULL;
    if (!preset) return;
    engine->active = NULL;
    const opengl_vtable_t *vt = engine->vt;
    /* Display() may be called repeatedly without Prepare(), notably while a
     * video is paused or while a window is being resized. RetroArch advances
     * FrameCount, feedback, and history once per core video frame, not once
     * per presentation redraw. Keep all temporal shader state frozen until
     * the video output supplies another picture. */
    const bool advance = engine->new_frame;
    engine->new_frame = false;
    const uint64_t frame = engine->frame_count;
    struct ra_target *original = &engine->input;
    unsigned raster_height = RetroArchRasterHeight(engine, preset);
    if (raster_height && NormalizeRetroArchRaster(engine, raster_height))
        original = &engine->normalized;
    unsigned input_width = original->width;
    unsigned input_height = original->height;

    /* FeedbackTexture is the previous frame's output from feedback_pass.
     * RetroArch exposes a black texture on the first frame, so allocate and
     * clear it before any pass can sample it. */
    if (preset->feedback_pass >= 0 && !preset->feedback.texture) {
        unsigned width = input_width, height = input_height;
        for (int i = 0; i <= preset->feedback_pass; ++i) {
            struct ra_program *program = &preset->passes[i];
            if (program->scale_type_x == RA_SCALE_VIEWPORT)
                width = (unsigned)(engine->viewport_width * program->scale_x);
            else if (program->scale_type_x == RA_SCALE_ABSOLUTE)
                width = (unsigned)program->scale_x;
            else
                width = (unsigned)(width * program->scale_x);
            if (program->scale_type_y == RA_SCALE_VIEWPORT)
                height = (unsigned)(engine->viewport_height * program->scale_y);
            else if (program->scale_type_y == RA_SCALE_ABSOLUTE)
                height = (unsigned)program->scale_y;
            else
                height = (unsigned)(height * program->scale_y);
            if (!width) width = 1;
            if (!height) height = 1;
        }
        struct ra_program *feedback =
            &preset->passes[preset->feedback_pass];
        GLenum format = feedback->floating ? GL_RGBA16F :
                        feedback->srgb ? GL_SRGB8_ALPHA8 : GL_RGBA8;
        if (!AllocateTarget(engine, &preset->feedback, width, height, format))
            return;
        vt->BindFramebuffer(GL_FRAMEBUFFER, preset->feedback.framebuffer);
        vt->Clear(GL_COLOR_BUFFER_BIT);
        vt->BindFramebuffer(GL_FRAMEBUFFER, engine->output_framebuffer);
    }

    for (unsigned pass_index = 0; pass_index < preset->pass_count; ++pass_index) {
        struct ra_program *program = &preset->passes[pass_index];
        unsigned output_width = input_width, output_height = input_height;
        if (program->scale_type_x == RA_SCALE_VIEWPORT)
            output_width = (unsigned)(engine->viewport_width * program->scale_x);
        else if (program->scale_type_x == RA_SCALE_ABSOLUTE)
            output_width = (unsigned)program->scale_x;
        else
            output_width = (unsigned)(input_width * program->scale_x);
        if (program->scale_type_y == RA_SCALE_VIEWPORT)
            output_height = (unsigned)(engine->viewport_height * program->scale_y);
        else if (program->scale_type_y == RA_SCALE_ABSOLUTE)
            output_height = (unsigned)program->scale_y;
        else
            output_height = (unsigned)(input_height * program->scale_y);
        if (!output_width) output_width = 1;
        if (!output_height) output_height = 1;

        const bool final = pass_index + 1 == preset->pass_count;
        if (final) {
            output_width = engine->viewport_width;
            output_height = engine->viewport_height;
            vt->BindFramebuffer(GL_FRAMEBUFFER, engine->output_framebuffer);
            vt->Viewport(engine->viewport_x, engine->viewport_y,
                         output_width, output_height);
        } else {
            GLenum format = program->floating ? GL_RGBA16F :
                            program->srgb ? GL_SRGB8_ALPHA8 : GL_RGBA8;
            if (!AllocateTarget(engine, &preset->targets[pass_index],
                                output_width, output_height, format)) {
                msg_Err(engine->gl, "RetroArch preset %s pass %u target allocation failed",
                        preset->name, pass_index);
                return;
            }
            vt->BindFramebuffer(GL_FRAMEBUFFER,
                                preset->targets[pass_index].framebuffer);
            vt->Viewport(0, 0, output_width, output_height);
        }
        if (program->srgb) vt->Enable(GL_FRAMEBUFFER_SRGB);
        else vt->Disable(GL_FRAMEBUFFER_SRGB);
        vt->UseProgram(program->id);

        struct ra_target *source = pass_index ?
            &preset->targets[pass_index - 1] : original;
        vt->ActiveTexture(GL_TEXTURE0);
        vt->BindTexture(GL_TEXTURE_2D, source->texture);
        vt->TexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER,
                          program->mipmap_input ? GL_LINEAR_MIPMAP_LINEAR :
                          program->linear ? GL_LINEAR : GL_NEAREST);
        vt->TexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER,
                          program->linear ? GL_LINEAR : GL_NEAREST);
        vt->TexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S,
                          WrapEnum(program->wrap_mode));
        vt->TexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T,
                          WrapEnum(program->wrap_mode));
        if (program->mipmap_input) {
            if (!vt->GenerateMipmap) {
                msg_Err(engine->gl, "RetroArch preset %s pass %u needs mipmaps",
                        preset->name, pass_index);
                return;
            }
            vt->GenerateMipmap(GL_TEXTURE_2D);
        }
        if (program->texture >= 0) vt->Uniform1i(program->texture, 0);

        unsigned unit = 1;
        char uniform[96];
        for (unsigned history = 0; history < pass_index; ++history) {
            struct ra_target *target = &preset->targets[history];
            snprintf(uniform, sizeof(uniform), "Pass%uTexture", history + 1);
            GLint pass_location = vt->GetUniformLocation(program->id, uniform);
            GLint alias_location = -1;
            if (preset->passes[history].alias[0]) {
                snprintf(uniform, sizeof(uniform), "%sTexture",
                         preset->passes[history].alias);
                alias_location = vt->GetUniformLocation(program->id, uniform);
            }
            const unsigned back = pass_index - history;
            snprintf(uniform, sizeof(uniform), "PassPrev%uTexture", back);
            GLint previous_location = vt->GetUniformLocation(program->id, uniform);
            unsigned target_unit = history + 1 == pass_index ? 0 : unit;
            if ((pass_location >= 0 || alias_location >= 0 ||
                 previous_location >= 0) && target_unit != 0) {
                if (unit >= (unsigned)engine->max_texture_units) {
                    msg_Err(engine->gl, "RetroArch preset %s pass %u exhausted texture units",
                            preset->name, pass_index);
                    return;
                }
                vt->ActiveTexture(GL_TEXTURE0 + target_unit);
                vt->BindTexture(GL_TEXTURE_2D, target->texture);
                ++unit;
            }
            if (pass_location >= 0) vt->Uniform1i(pass_location, target_unit);
            if (alias_location >= 0) vt->Uniform1i(alias_location, target_unit);
            if (previous_location >= 0)
                vt->Uniform1i(previous_location, target_unit);

            snprintf(uniform, sizeof(uniform), "Pass%uTextureSize", history + 1);
            GLint location = vt->GetUniformLocation(program->id, uniform);
            if (location >= 0) vt->Uniform2f(location, target->width, target->height);
            snprintf(uniform, sizeof(uniform), "Pass%uInputSize", history + 1);
            location = vt->GetUniformLocation(program->id, uniform);
            /* RetroArch's fbo_info[N].input_size is the valid image area
             * stored in pass N's output texture, not the source consumed by
             * pass N.  Confusing the two is usually invisible for 1:1
             * passes, but stretches CRT-Royale's scanline and mask lookup
             * coordinates when a pass scales to the viewport or to 320x240. */
            if (location >= 0) vt->Uniform2f(location, target->width,
                                             target->height);
            if (preset->passes[history].alias[0]) {
                snprintf(uniform, sizeof(uniform), "%sTextureSize",
                         preset->passes[history].alias);
                location = vt->GetUniformLocation(program->id, uniform);
                if (location >= 0)
                    vt->Uniform2f(location, target->width, target->height);
                snprintf(uniform, sizeof(uniform), "%sInputSize",
                         preset->passes[history].alias);
                location = vt->GetUniformLocation(program->id, uniform);
                if (location >= 0)
                    vt->Uniform2f(location, target->width, target->height);
            }
            snprintf(uniform, sizeof(uniform), "PassPrev%uTextureSize", back);
            location = vt->GetUniformLocation(program->id, uniform);
            if (location >= 0) vt->Uniform2f(location, target->width, target->height);
            snprintf(uniform, sizeof(uniform), "PassPrev%uInputSize", back);
            location = vt->GetUniformLocation(program->id, uniform);
            if (location >= 0) vt->Uniform2f(location, target->width,
                                             target->height);
        }
        GLint orig_location = vt->GetUniformLocation(program->id, "OrigTexture");
        snprintf(uniform, sizeof(uniform), "PassPrev%uTexture", pass_index + 1);
        GLint oldest_location = vt->GetUniformLocation(program->id, uniform);
        if (orig_location >= 0 || oldest_location >= 0) {
            unsigned original_unit = 0;
            if (pass_index == 0)
                original_unit = 0;
            else {
                if (unit >= (unsigned)engine->max_texture_units) {
                    msg_Err(engine->gl, "RetroArch preset %s pass %u exhausted texture units",
                            preset->name, pass_index);
                    return;
                }
                vt->ActiveTexture(GL_TEXTURE0 + unit);
                vt->BindTexture(GL_TEXTURE_2D, original->texture);
                original_unit = unit++;
            }
            if (orig_location >= 0)
                vt->Uniform1i(orig_location, original_unit);
            if (oldest_location >= 0)
                vt->Uniform1i(oldest_location, original_unit);
        }
        GLint location = vt->GetUniformLocation(program->id, "OrigTextureSize");
        if (location >= 0) vt->Uniform2f(location, original->width,
                                         original->height);
        location = vt->GetUniformLocation(program->id, "OrigInputSize");
        if (location >= 0) vt->Uniform2f(location, original->width,
                                         original->height);
        snprintf(uniform, sizeof(uniform), "PassPrev%uTextureSize",
                 pass_index + 1);
        location = vt->GetUniformLocation(program->id, uniform);
        if (location >= 0) vt->Uniform2f(location, original->width,
                                         original->height);
        snprintf(uniform, sizeof(uniform), "PassPrev%uInputSize",
                 pass_index + 1);
        location = vt->GetUniformLocation(program->id, uniform);
        if (location >= 0) vt->Uniform2f(location, original->width,
                                         original->height);

        for (unsigned i = 0; i < preset->history_count; ++i) {
            snprintf(uniform, sizeof(uniform), i ? "Prev%uTexture" :
                                                  "PrevTexture", i);
            location = vt->GetUniformLocation(program->id, uniform);
            if (location < 0) continue;
            if (i >= engine->history_count ||
                unit >= (unsigned)engine->max_texture_units) {
                msg_Err(engine->gl, "RetroArch preset %s pass %u cannot bind history texture",
                        preset->name, pass_index);
                return;
            }
            vt->ActiveTexture(GL_TEXTURE0 + unit);
            vt->BindTexture(GL_TEXTURE_2D, engine->history[i].texture);
            vt->Uniform1i(location, unit++);
            snprintf(uniform, sizeof(uniform), i ? "Prev%uTextureSize" :
                                                  "PrevTextureSize", i);
            location = vt->GetUniformLocation(program->id, uniform);
            if (location >= 0)
                vt->Uniform2f(location, engine->history[i].width,
                              engine->history[i].height);
            snprintf(uniform, sizeof(uniform), i ? "Prev%uInputSize" :
                                                  "PrevInputSize", i);
            location = vt->GetUniformLocation(program->id, uniform);
            if (location >= 0)
                vt->Uniform2f(location, engine->history[i].width,
                              engine->history[i].height);
        }

        for (unsigned i = 0; i < preset->lut_count; ++i) {
            struct ra_lut *lut = preset->luts[i];
            location = vt->GetUniformLocation(program->id, lut->name);
            if (location < 0) continue;
            if (unit >= (unsigned)engine->max_texture_units) {
                msg_Err(engine->gl, "RetroArch preset %s pass %u cannot bind LUT %s",
                        preset->name, pass_index, lut->name);
                return;
            }
            vt->ActiveTexture(GL_TEXTURE0 + unit);
            vt->BindTexture(GL_TEXTURE_2D, lut->texture);
            vt->Uniform1i(location, unit++);
            snprintf(uniform, sizeof(uniform), "%sSize", lut->name);
            location = vt->GetUniformLocation(program->id, uniform);
            if (location >= 0) vt->Uniform2f(location, lut->width, lut->height);
        }

        location = vt->GetUniformLocation(program->id, "FeedbackTexture");
        if (location >= 0) {
            if (preset->feedback_pass < 0 || !preset->feedback.texture ||
                unit >= (unsigned)engine->max_texture_units) {
                msg_Err(engine->gl, "RetroArch preset %s pass %u cannot bind feedback",
                        preset->name, pass_index);
                return;
            }
            vt->ActiveTexture(GL_TEXTURE0 + unit);
            vt->BindTexture(GL_TEXTURE_2D, preset->feedback.texture);
            vt->Uniform1i(location, unit++);
        }
        location = vt->GetUniformLocation(program->id, "FeedbackTextureSize");
        if (location >= 0)
            vt->Uniform2f(location, preset->feedback.width,
                          preset->feedback.height);
        location = vt->GetUniformLocation(program->id, "FeedbackInputSize");
        if (location >= 0)
            vt->Uniform2f(location, preset->feedback.width,
                          preset->feedback.height);

        if (program->mvp >= 0) {
            static const GLfloat identity[] = { 1,0,0,0, 0,1,0,0,
                                                0,0,1,0, 0,0,0,1 };
            vt->UniformMatrix4fv(program->mvp, 1, GL_FALSE, identity);
        }
        if (program->input_size >= 0)
            vt->Uniform2f(program->input_size, input_width, input_height);
        if (program->texture_size >= 0)
            vt->Uniform2f(program->texture_size, source->width, source->height);
        if (program->output_size >= 0)
            vt->Uniform2f(program->output_size, output_width, output_height);
        if (program->frame_count >= 0)
            vt->Uniform1i(program->frame_count, (int)(frame & 0x7fffffff));
        if (program->frame_direction >= 0) vt->Uniform1i(program->frame_direction, 1);
        for (unsigned i = 0; i < program->parameter_count; ++i)
            if (program->parameters[i].location >= 0)
                vt->Uniform1f(program->parameters[i].location,
                              program->parameters[i].value);
        vt->BindBuffer(GL_ARRAY_BUFFER, engine->vertex_buffer);
        vt->EnableVertexAttribArray(program->vertex_coord);
        vt->VertexAttribPointer(program->vertex_coord, 2, GL_FLOAT, GL_FALSE, 0, 0);
        vt->BindBuffer(GL_ARRAY_BUFFER, engine->texcoord_buffer);
        vt->EnableVertexAttribArray(program->tex_coord);
        vt->VertexAttribPointer(program->tex_coord, 2, GL_FLOAT, GL_FALSE, 0, 0);
        if (program->color >= 0) {
            vt->BindBuffer(GL_ARRAY_BUFFER, engine->color_buffer);
            vt->EnableVertexAttribArray(program->color);
            vt->VertexAttribPointer(program->color, 4, GL_FLOAT, GL_FALSE, 0, 0);
        }
        vt->DrawArrays(GL_TRIANGLE_STRIP, 0, 4);

        input_width = output_width;
        input_height = output_height;
    }
    if (advance)
        engine->frame_count++;
    if (advance && preset->feedback_pass >= 0) {
        struct ra_target swap = preset->feedback;
        preset->feedback = preset->targets[preset->feedback_pass];
        preset->targets[preset->feedback_pass] = swap;
    }
    if (advance && engine->history_count) {
        struct ra_target oldest = engine->history[engine->history_count - 1];
        for (unsigned i = engine->history_count - 1; i > 0; --i)
            engine->history[i] = engine->history[i - 1];
        engine->history[0] = engine->input;
        engine->input = oldest;
    }
    vt->Disable(GL_FRAMEBUFFER_SRGB);
}
