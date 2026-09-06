/*****************************************************************************
 * d3d11_ra_shaders.c: RetroArch Slang CRT execution for Direct3D 11
 *****************************************************************************
 * The Slang sources are compiled to SPIR-V, GLSL and HLSL at build time by
 * extras/tools/import-slang-shaders.py. This file independently executes the
 * generated public preset graph; it does not embed RetroArch's GPL parser.
 *****************************************************************************/
#ifdef HAVE_CONFIG_H
# include "config.h"
#endif

#include <vlc_common.h>
#include <vlc_block.h>
#include <vlc_configuration.h>
#include <vlc_fs.h>
#include <vlc_image.h>
#include <vlc_variables.h>

#include <limits.h>

#define COBJMACROS
#include <dxgi1_4.h>

#include "d3d11_ra_shaders.h"
#include "d3d11_shaders.h"

#define RA_D3D_MAX_PASSES 16
#define RA_D3D_MAX_TEXTURES 16
#define RA_D3D_MAX_MEMBERS 160
#define RA_D3D_MAX_PARAMETERS 96
#define RA_D3D_MAX_SHARED_LUTS 64
#define RA_D3D_PACK_MAX_ENTRIES 4096

static const uint8_t ra_pack_magic[8] = {
    'P', 'V', 'L', 'C', 'R', 'A', '1', '\0'
};

enum ra_d3d_scale_type {
    RA_D3D_SCALE_SOURCE, RA_D3D_SCALE_VIEWPORT, RA_D3D_SCALE_ABSOLUTE
};
enum ra_d3d_wrap_mode {
    RA_D3D_WRAP_BORDER, RA_D3D_WRAP_EDGE, RA_D3D_WRAP_REPEAT,
    RA_D3D_WRAP_MIRROR
};
enum ra_d3d_member_type {
    RA_D3D_MEMBER_FLOAT, RA_D3D_MEMBER_INT, RA_D3D_MEMBER_UINT,
    RA_D3D_MEMBER_VEC4, RA_D3D_MEMBER_MAT4
};

struct ra_d3d_member {
    char name[64];
    unsigned offset;
    enum ra_d3d_member_type type;
};

struct ra_d3d_binding {
    char name[64];
    unsigned slot;
};

struct ra_d3d_parameter {
    char name[64];
    float value;
};

struct ra_d3d_target {
    ID3D11Texture2D *texture;
    ID3D11RenderTargetView *rtv;
    ID3D11ShaderResourceView *srv;
    unsigned width, height;
    DXGI_FORMAT format;
    bool mipmaps;
};

struct ra_d3d_program {
    bool linear;
    bool srgb;
    bool floating;
    bool mipmap_input;
    enum ra_d3d_wrap_mode wrap_mode;
    enum ra_d3d_scale_type scale_type_x;
    enum ra_d3d_scale_type scale_type_y;
    float scale_x, scale_y;
    char alias[64];
    ID3D11VertexShader *vs;
    ID3D11PixelShader *ps;
    ID3D11InputLayout *layout;
    ID3D11Buffer *constant_buffers[2];
    unsigned buffer_sizes[2];
    struct ra_d3d_member members[2][RA_D3D_MAX_MEMBERS];
    unsigned member_count[2];
    struct ra_d3d_binding bindings[RA_D3D_MAX_TEXTURES];
    unsigned binding_count;
};

struct ra_d3d_lut {
    char name[64];
    char source[PATH_MAX];
    struct ra_d3d_target target;
    bool linear;
    bool mipmap;
    enum ra_d3d_wrap_mode wrap_mode;
};

struct ra_d3d_preset {
    const char *name;
    bool attempted;
    bool valid;
    unsigned pass_count;
    int feedback_pass;
    struct ra_d3d_program passes[RA_D3D_MAX_PASSES];
    struct ra_d3d_target targets[RA_D3D_MAX_PASSES];
    struct ra_d3d_target feedback;
    struct ra_d3d_lut *luts[RA_D3D_MAX_TEXTURES];
    unsigned lut_count;
    struct ra_d3d_parameter parameters[RA_D3D_MAX_PARAMETERS];
    unsigned parameter_count;
};

struct ra_d3d_preset_template {
    const char *name;
    bool lightweight;
    unsigned minimum_glsl;
};

static const struct ra_d3d_preset_template preset_templates[] = {
#include "../../../share/retroarch-shaders/crt/slang/catalog.h"
};

struct ra_d3d_pack_entry {
    char *path;
    uint64_t offset, size;
};

struct ra_d3d_pack {
    FILE *file;
    struct ra_d3d_pack_entry *entries;
    uint32_t count;
};

struct d3d11_ra_shader_engine {
    vout_display_t *vd;
    d3d11_handle_t *hd3d;
    d3d11_device_t *device;
    struct ra_d3d_pack pack;
    struct ra_d3d_target input;
    struct ra_d3d_preset *presets[ARRAY_SIZE(preset_templates)];
    struct ra_d3d_preset *active;
    char selected[128];
    struct ra_d3d_lut luts[RA_D3D_MAX_SHARED_LUTS];
    unsigned lut_count;
    ID3D11Buffer *vertices;
    ID3D11VertexShader *stock_vs;
    ID3D11PixelShader *stock_ps;
    ID3D11InputLayout *stock_layout;
    ID3D11SamplerState *samplers[2][4]; /* point/linear x wrap mode */
    unsigned viewport_width, viewport_height;
    uint64_t frame_count;
    bool advance;
    bool have_pts;
    vlc_tick_t pts;
    bool intel;
    bool royale_compat;
    unsigned last_raster_width, last_raster_height;
};

static uint16_t ReadLE16(const uint8_t *p)
{
    return (uint16_t)p[0] | (uint16_t)p[1] << 8;
}

static uint32_t ReadLE32(const uint8_t *p)
{
    return (uint32_t)p[0] | (uint32_t)p[1] << 8 |
           (uint32_t)p[2] << 16 | (uint32_t)p[3] << 24;
}

static uint64_t ReadLE64(const uint8_t *p)
{
    return (uint64_t)ReadLE32(p) | (uint64_t)ReadLE32(p + 4) << 32;
}

static void CloseResourcePack(struct ra_d3d_pack *pack)
{
    if (pack->file)
        fclose(pack->file);
    for (uint32_t i = 0; i < pack->count; ++i)
        free(pack->entries[i].path);
    free(pack->entries);
    memset(pack, 0, sizeof(*pack));
}

static bool OpenResourcePack(struct d3d11_ra_shader_engine *engine)
{
    char *data = config_GetDataDir();
    char *path = NULL;
    if (data && asprintf(&path, "%s/retroarch-shaders.pak", data) < 0)
        path = NULL;
    free(data);
    if (!path)
        return false;
    FILE *file = vlc_fopen(path, "rb");
    free(path);
    if (!file)
        return false;
    if (fseek(file, 0, SEEK_END)) {
        fclose(file);
        return false;
    }
    long length = ftell(file);
    if (length < 12 || fseek(file, 0, SEEK_SET)) {
        fclose(file);
        return false;
    }
    uint8_t header[12];
    if (fread(header, 1, sizeof(header), file) != sizeof(header) ||
        memcmp(header, ra_pack_magic, sizeof(ra_pack_magic))) {
        fclose(file);
        return false;
    }
    uint32_t count = ReadLE32(header + 8);
    if (!count || count > RA_D3D_PACK_MAX_ENTRIES) {
        fclose(file);
        return false;
    }
    struct ra_d3d_pack_entry *entries = calloc(count, sizeof(*entries));
    if (!entries) {
        fclose(file);
        return false;
    }
    engine->pack.file = file;
    engine->pack.entries = entries;
    engine->pack.count = count;
    for (uint32_t i = 0; i < count; ++i) {
        uint8_t raw[20];
        if (fread(raw, 1, sizeof(raw), file) != sizeof(raw))
            goto error;
        uint16_t path_length = ReadLE16(raw);
        uint16_t flags = ReadLE16(raw + 2);
        uint64_t offset = ReadLE64(raw + 4);
        uint64_t size = ReadLE64(raw + 12);
        if (!path_length || flags || offset > (uint64_t)length ||
            size > (uint64_t)length - offset)
            goto error;
        entries[i].path = malloc((size_t)path_length + 1);
        if (!entries[i].path ||
            fread(entries[i].path, 1, path_length, file) != path_length)
            goto error;
        entries[i].path[path_length] = '\0';
        if (memchr(entries[i].path, '\0', path_length) ||
            entries[i].path[0] == '/' || strchr(entries[i].path, '\\') ||
            strstr(entries[i].path, "../") ||
            (i && strcmp(entries[i - 1].path, entries[i].path) >= 0))
            goto error;
        entries[i].offset = offset;
        entries[i].size = size;
    }
    long index_end = ftell(file);
    if (index_end < 0)
        goto error;
    for (uint32_t i = 0; i < count; ++i)
        if (entries[i].offset < (uint64_t)index_end)
            goto error;
    msg_Info(engine->vd, "using packed Direct3D11 RetroArch catalogue (%u resources)",
             count);
    return true;
error:
    CloseResourcePack(&engine->pack);
    return false;
}

static const struct ra_d3d_pack_entry *FindPackedResource(
    const struct ra_d3d_pack *pack, const char *relative)
{
    uint32_t first = 0, count = pack->count;
    while (count) {
        uint32_t step = count / 2, index = first + step;
        int order = strcmp(pack->entries[index].path, relative);
        if (order < 0) {
            first = index + 1;
            count -= step + 1;
        } else if (order > 0)
            count = step;
        else
            return &pack->entries[index];
    }
    return NULL;
}

static char *NormalizeResourcePath(const char *relative)
{
    if (!relative || !*relative || relative[0] == '/' ||
        strchr(relative, '\\'))
        return NULL;
    size_t length = strlen(relative), used = 0;
    char *normalized = malloc(length + 1);
    if (!normalized)
        return NULL;
    const char *cursor = relative;
    while (*cursor) {
        while (*cursor == '/') ++cursor;
        if (!*cursor) break;
        const char *end = strchr(cursor, '/');
        size_t segment = end ? (size_t)(end - cursor) : strlen(cursor);
        if (segment == 1 && cursor[0] == '.') {
        } else if (segment == 2 && cursor[0] == '.' && cursor[1] == '.') {
            if (!used) { free(normalized); return NULL; }
            while (used && normalized[used - 1] != '/') --used;
            if (used) --used;
        } else {
            if (used) normalized[used++] = '/';
            memcpy(normalized + used, cursor, segment);
            used += segment;
        }
        cursor = end ? end + 1 : cursor + segment;
    }
    if (!used) { free(normalized); return NULL; }
    normalized[used] = '\0';
    return normalized;
}

static void *ReadLooseResource(const char *relative, size_t *size)
{
    char *data = config_GetDataDir(), *path = NULL;
    if (data && asprintf(&path, "%s/retroarch-shaders/%s", data, relative) < 0)
        path = NULL;
    free(data);
    if (!path)
        return NULL;
    FILE *file = vlc_fopen(path, "rb");
    free(path);
    if (!file)
        return NULL;
    if (fseek(file, 0, SEEK_END) || ftell(file) < 0) {
        fclose(file);
        return NULL;
    }
    long length = ftell(file);
    rewind(file);
    if ((uintmax_t)length > SIZE_MAX - 1) {
        fclose(file);
        return NULL;
    }
    uint8_t *out = malloc((size_t)length + 1);
    if (!out || fread(out, 1, (size_t)length, file) != (size_t)length) {
        free(out);
        fclose(file);
        return NULL;
    }
    fclose(file);
    out[length] = '\0';
    if (size) *size = (size_t)length;
    return out;
}

static void *ReadResource(struct d3d11_ra_shader_engine *engine,
                          const char *relative, size_t *size)
{
    char *normalized = NormalizeResourcePath(relative);
    if (!normalized)
        return NULL;
    const struct ra_d3d_pack_entry *entry = engine->pack.file ?
        FindPackedResource(&engine->pack, normalized) : NULL;
    if (entry && entry->size <= SIZE_MAX - 1 && entry->offset <= LONG_MAX &&
        fseek(engine->pack.file, (long)entry->offset, SEEK_SET) == 0) {
        uint8_t *out = malloc((size_t)entry->size + 1);
        if (out && fread(out, 1, (size_t)entry->size,
                         engine->pack.file) == (size_t)entry->size) {
            out[entry->size] = '\0';
            if (size) *size = (size_t)entry->size;
            free(normalized);
            return out;
        }
        free(out);
    }
    void *out = ReadLooseResource(normalized, size);
    free(normalized);
    return out;
}

static char *PresetValue(const char *preset, const char *key)
{
    size_t key_length = strlen(key);
    const char *line = preset;
    while (*line) {
        const char *end = strchr(line, '\n');
        if (!end) end = line + strlen(line);
        const char *p = line;
        while (p < end && (*p == ' ' || *p == '\t')) ++p;
        if ((size_t)(end - p) > key_length &&
            !strncmp(p, key, key_length)) {
            const char *after = p + key_length;
            while (after < end && (*after == ' ' || *after == '\t')) ++after;
            if (after < end && *after == '=') {
                p = after + 1;
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
                    ++p; --tail;
                }
                return strndup(p, (size_t)(tail - p));
            }
        }
        line = *end ? end + 1 : end;
    }
    return NULL;
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

static enum ra_d3d_scale_type PresetScale(const char *preset, const char *key)
{
    char *value = PresetValue(preset, key);
    enum ra_d3d_scale_type result = RA_D3D_SCALE_SOURCE;
    if (value && !strcasecmp(value, "viewport")) result = RA_D3D_SCALE_VIEWPORT;
    else if (value && !strcasecmp(value, "absolute")) result = RA_D3D_SCALE_ABSOLUTE;
    free(value);
    return result;
}

static enum ra_d3d_wrap_mode PresetWrap(const char *preset, const char *key,
                                        enum ra_d3d_wrap_mode fallback)
{
    char *value = PresetValue(preset, key);
    enum ra_d3d_wrap_mode result = fallback;
    if (value && !strcasecmp(value, "clamp_to_edge")) result = RA_D3D_WRAP_EDGE;
    else if (value && !strcasecmp(value, "repeat")) result = RA_D3D_WRAP_REPEAT;
    else if (value && !strcasecmp(value, "mirrored_repeat")) result = RA_D3D_WRAP_MIRROR;
    else if (value && !strcasecmp(value, "clamp_to_border")) result = RA_D3D_WRAP_BORDER;
    free(value);
    return result;
}

static void ReleaseTarget(struct ra_d3d_target *target)
{
    if (target->srv) ID3D11ShaderResourceView_Release(target->srv);
    if (target->rtv) ID3D11RenderTargetView_Release(target->rtv);
    if (target->texture) ID3D11Texture2D_Release(target->texture);
    memset(target, 0, sizeof(*target));
}

static bool AllocateTarget(struct d3d11_ra_shader_engine *engine,
                           struct ra_d3d_target *target, unsigned width,
                           unsigned height, DXGI_FORMAT format, bool mipmaps)
{
    if (target->width == width && target->height == height &&
        target->format == format && target->mipmaps == mipmaps)
        return true;
    ReleaseTarget(target);
    D3D11_TEXTURE2D_DESC desc = { 0 };
    desc.Width = width;
    desc.Height = height;
    desc.MipLevels = mipmaps ? 0 : 1;
    desc.ArraySize = 1;
    desc.SampleDesc.Count = 1;
    desc.Usage = D3D11_USAGE_DEFAULT;
    desc.BindFlags = D3D11_BIND_RENDER_TARGET | D3D11_BIND_SHADER_RESOURCE;
    if (mipmaps) desc.MiscFlags = D3D11_RESOURCE_MISC_GENERATE_MIPS;
    DXGI_FORMAT resource_format = format;
    if (format == DXGI_FORMAT_R8G8B8A8_UNORM_SRGB)
        resource_format = DXGI_FORMAT_R8G8B8A8_TYPELESS;
    desc.Format = resource_format;
    HRESULT hr = ID3D11Device_CreateTexture2D(engine->device->d3ddevice,
                                               &desc, NULL, &target->texture);
    if (FAILED(hr)) goto error;
    D3D11_RENDER_TARGET_VIEW_DESC rtv = { 0 };
    rtv.Format = format;
    rtv.ViewDimension = D3D11_RTV_DIMENSION_TEXTURE2D;
    hr = ID3D11Device_CreateRenderTargetView(engine->device->d3ddevice,
        (ID3D11Resource *)target->texture, &rtv, &target->rtv);
    if (FAILED(hr)) goto error;
    D3D11_SHADER_RESOURCE_VIEW_DESC srv = { 0 };
    srv.Format = format;
    srv.ViewDimension = D3D11_SRV_DIMENSION_TEXTURE2D;
    srv.Texture2D.MipLevels = mipmaps ? UINT_MAX : 1;
    hr = ID3D11Device_CreateShaderResourceView(engine->device->d3ddevice,
        (ID3D11Resource *)target->texture, &srv, &target->srv);
    if (FAILED(hr)) goto error;
    target->width = width;
    target->height = height;
    target->format = format;
    target->mipmaps = mipmaps;
    return true;
error:
    msg_Err(engine->vd, "Direct3D11 RetroArch target %ux%u allocation failed (0x%lX)",
            width, height, hr);
    ReleaseTarget(target);
    return false;
}

static DXGI_FORMAT ProgramFormat(const struct d3d11_ra_shader_engine *engine,
                                 const struct ra_d3d_program *program)
{
    VLC_UNUSED(engine);
    /* Match RetroArch's D3D11 backend: sRGB passes use an sRGB view and
     * floating-point passes use FP16.  The output-merger hazard is handled
     * explicitly in DrawPass() rather than by changing colour formats. */
    if (program->floating)
        return DXGI_FORMAT_R16G16B16A16_FLOAT;
    if (program->srgb)
        return DXGI_FORMAT_R8G8B8A8_UNORM_SRGB;
    return DXGI_FORMAT_R8G8B8A8_UNORM;
}

static enum ra_d3d_member_type MemberType(const char *name)
{
    if (!strcmp(name, "float")) return RA_D3D_MEMBER_FLOAT;
    if (!strcmp(name, "int")) return RA_D3D_MEMBER_INT;
    if (!strcmp(name, "uint")) return RA_D3D_MEMBER_UINT;
    if (!strcmp(name, "vec4")) return RA_D3D_MEMBER_VEC4;
    if (!strcmp(name, "mat4")) return RA_D3D_MEMBER_MAT4;
    return -1;
}

static bool ParseMembers(struct ra_d3d_program *program, unsigned slot,
                         char *list)
{
    if (!list || !*list)
        return true;
    char *save = NULL;
    for (char *entry = strtok_r(list, ";", &save); entry;
         entry = strtok_r(NULL, ";", &save)) {
        if (program->member_count[slot] == RA_D3D_MAX_MEMBERS)
            return false;
        char *first = strchr(entry, ':');
        char *second = first ? strchr(first + 1, ':') : NULL;
        if (!first || !second)
            return false;
        *first++ = '\0';
        *second++ = '\0';
        char *end;
        unsigned long offset = strtoul(first, &end, 10);
        enum ra_d3d_member_type type = MemberType(second);
        if (end == first || *end || type < 0 || offset > UINT_MAX ||
            strlen(entry) >= sizeof(program->members[slot][0].name))
            return false;
        struct ra_d3d_member *member =
            &program->members[slot][program->member_count[slot]++];
        strlcpy(member->name, entry, sizeof(member->name));
        member->offset = (unsigned)offset;
        member->type = type;
    }
    return true;
}

static bool ParseBindings(struct ra_d3d_program *program, char *list)
{
    if (!list || !*list)
        return true;
    char *save = NULL;
    for (char *entry = strtok_r(list, ";", &save); entry;
         entry = strtok_r(NULL, ";", &save)) {
        if (program->binding_count == RA_D3D_MAX_TEXTURES)
            return false;
        char *separator = strrchr(entry, ':');
        if (!separator)
            return false;
        *separator++ = '\0';
        char *end;
        unsigned long slot = strtoul(separator, &end, 10);
        if (end == separator || *end || slot >= RA_D3D_MAX_TEXTURES ||
            strlen(entry) >= sizeof(program->bindings[0].name))
            return false;
        struct ra_d3d_binding *binding =
            &program->bindings[program->binding_count++];
        strlcpy(binding->name, entry, sizeof(binding->name));
        binding->slot = (unsigned)slot;
    }
    return true;
}

static struct ra_d3d_parameter *FindParameter(struct ra_d3d_preset *preset,
                                               const char *name)
{
    for (unsigned i = 0; i < preset->parameter_count; ++i)
        if (!strcmp(preset->parameters[i].name, name))
            return &preset->parameters[i];
    return NULL;
}

static bool ParseParameters(struct ra_d3d_preset *preset, char *list)
{
    if (!list || !*list)
        return true;
    char *save = NULL;
    for (char *entry = strtok_r(list, ";", &save); entry;
         entry = strtok_r(NULL, ";", &save)) {
        char *separator = strrchr(entry, ':');
        if (!separator)
            return false;
        *separator++ = '\0';
        char *end;
        float value = strtof(separator, &end);
        if (end == separator || *end ||
            strlen(entry) >= sizeof(preset->parameters[0].name))
            return false;
        struct ra_d3d_parameter *parameter = FindParameter(preset, entry);
        if (!parameter) {
            if (preset->parameter_count == RA_D3D_MAX_PARAMETERS)
                return false;
            parameter = &preset->parameters[preset->parameter_count++];
            strlcpy(parameter->name, entry, sizeof(parameter->name));
            parameter->value = value;
        }
    }
    return true;
}

static bool CreateConstantBuffer(struct d3d11_ra_shader_engine *engine,
                                 struct ra_d3d_program *program,
                                 unsigned slot, unsigned size)
{
    if (!size)
        return true;
    if (size > 65536 || (size & 15))
        return false;
    D3D11_BUFFER_DESC desc = { 0 };
    desc.ByteWidth = size;
    desc.Usage = D3D11_USAGE_DYNAMIC;
    desc.BindFlags = D3D11_BIND_CONSTANT_BUFFER;
    desc.CPUAccessFlags = D3D11_CPU_ACCESS_WRITE;
    HRESULT hr = ID3D11Device_CreateBuffer(engine->device->d3ddevice,
        &desc, NULL, &program->constant_buffers[slot]);
    if (FAILED(hr)) {
        msg_Err(engine->vd, "Direct3D11 RetroArch constant buffer creation failed (0x%lX)", hr);
        return false;
    }
    program->buffer_sizes[slot] = size;
    return true;
}

static bool BuildProgram(struct d3d11_ra_shader_engine *engine,
                         struct ra_d3d_preset *out, const char *preset,
                         unsigned index)
{
    struct ra_d3d_program *program = &out->passes[index];
    char key[64];
    snprintf(key, sizeof(key), "hlsl_vertex%u", index);
    char *vertex_path = PresetValue(preset, key);
    snprintf(key, sizeof(key), "hlsl_fragment%u", index);
    char *fragment_path = PresetValue(preset, key);
    if (!vertex_path || !fragment_path)
        goto error;
    char relative[PATH_MAX];
    if (snprintf(relative, sizeof(relative), "crt/%s", vertex_path) >=
        (int)sizeof(relative))
        goto error;
    char *vertex = ReadResource(engine, relative, NULL);
    if (snprintf(relative, sizeof(relative), "crt/%s", fragment_path) >=
        (int)sizeof(relative)) {
        free(vertex);
        goto error;
    }
    char *fragment = ReadResource(engine, relative, NULL);
    if (!vertex || !fragment) {
        free(vertex); free(fragment);
        goto error;
    }
    ID3DBlob *vs_blob = D3D11_CompileShader(engine->vd, engine->hd3d,
                                             engine->device, vertex, false);
    ID3DBlob *ps_blob = D3D11_CompileShader(engine->vd, engine->hd3d,
                                             engine->device, fragment, true);
    free(vertex); free(fragment);
    if (!vs_blob || !ps_blob) {
        if (vs_blob) ID3D10Blob_Release(vs_blob);
        if (ps_blob) ID3D10Blob_Release(ps_blob);
        goto error;
    }
    HRESULT hr = ID3D11Device_CreateVertexShader(engine->device->d3ddevice,
        ID3D10Blob_GetBufferPointer(vs_blob),
        ID3D10Blob_GetBufferSize(vs_blob), NULL, &program->vs);
    if (SUCCEEDED(hr))
        hr = ID3D11Device_CreatePixelShader(engine->device->d3ddevice,
            ID3D10Blob_GetBufferPointer(ps_blob),
            ID3D10Blob_GetBufferSize(ps_blob), NULL, &program->ps);
    D3D11_INPUT_ELEMENT_DESC layout[] = {
        { "TEXCOORD", 0, DXGI_FORMAT_R32G32B32A32_FLOAT, 0, 0,
          D3D11_INPUT_PER_VERTEX_DATA, 0 },
        { "TEXCOORD", 1, DXGI_FORMAT_R32G32_FLOAT, 0, 16,
          D3D11_INPUT_PER_VERTEX_DATA, 0 },
    };
    if (SUCCEEDED(hr))
        hr = ID3D11Device_CreateInputLayout(engine->device->d3ddevice,
            layout, ARRAY_SIZE(layout), ID3D10Blob_GetBufferPointer(vs_blob),
            ID3D10Blob_GetBufferSize(vs_blob), &program->layout);
    ID3D10Blob_Release(vs_blob);
    ID3D10Blob_Release(ps_blob);
    if (FAILED(hr)) {
        msg_Err(engine->vd, "Direct3D11 RetroArch shader object creation failed (0x%lX)", hr);
        goto error;
    }

    for (unsigned slot = 0; slot < 2; ++slot) {
        snprintf(key, sizeof(key), "hlsl_buffer%u_size%u", slot, index);
        char *raw_size = PresetValue(preset, key);
        unsigned size = raw_size ? (unsigned)strtoul(raw_size, NULL, 10) : 0;
        free(raw_size);
        snprintf(key, sizeof(key), "hlsl_buffer%u_members%u", slot, index);
        char *members = PresetValue(preset, key);
        bool ok = ParseMembers(program, slot, members) &&
                  CreateConstantBuffer(engine, program, slot, size);
        free(members);
        if (!ok) goto error;
    }
    snprintf(key, sizeof(key), "hlsl_textures%u", index);
    char *bindings = PresetValue(preset, key);
    bool bindings_ok = ParseBindings(program, bindings);
    free(bindings);
    if (!bindings_ok) goto error;
    snprintf(key, sizeof(key), "hlsl_parameters%u", index);
    char *parameters = PresetValue(preset, key);
    bool parameters_ok = ParseParameters(out, parameters);
    free(parameters);
    if (!parameters_ok) goto error;

    free(vertex_path); free(fragment_path);
    return true;
error:
    free(vertex_path); free(fragment_path);
    return false;
}

static void ReleaseProgram(struct ra_d3d_program *program)
{
    if (program->layout) ID3D11InputLayout_Release(program->layout);
    if (program->ps) ID3D11PixelShader_Release(program->ps);
    if (program->vs) ID3D11VertexShader_Release(program->vs);
    for (unsigned i = 0; i < 2; ++i)
        if (program->constant_buffers[i])
            ID3D11Buffer_Release(program->constant_buffers[i]);
    memset(program, 0, sizeof(*program));
}

static struct ra_d3d_lut *LoadLut(struct d3d11_ra_shader_engine *engine,
                                  const char *preset, const char *name)
{
    char *source = PresetValue(preset, name);
    if (!source || !*source) { free(source); return NULL; }
    char relative[PATH_MAX];
    bool path_ok = snprintf(relative, sizeof(relative), "crt/%s", source) <
                   (int)sizeof(relative);
    free(source);
    if (!path_ok) return NULL;
    char key[96];
    snprintf(key, sizeof(key), "%s_linear", name);
    bool linear = PresetBool(preset, key, false);
    snprintf(key, sizeof(key), "%s_mipmap", name);
    bool mipmap = PresetBool(preset, key, false);
    snprintf(key, sizeof(key), "%s_wrap_mode", name);
    enum ra_d3d_wrap_mode wrap = PresetWrap(preset, key, RA_D3D_WRAP_BORDER);
    for (unsigned i = 0; i < engine->lut_count; ++i) {
        struct ra_d3d_lut *lut = &engine->luts[i];
        if (!strcmp(lut->name, name) && !strcmp(lut->source, relative) &&
            lut->linear == linear && lut->mipmap == mipmap &&
            lut->wrap_mode == wrap)
            return lut;
    }
    if (engine->lut_count == RA_D3D_MAX_SHARED_LUTS)
        return NULL;
    size_t encoded_size = 0;
    void *encoded = ReadResource(engine, relative, &encoded_size);
    if (!encoded || encoded_size > SSIZE_MAX) { free(encoded); return NULL; }
    block_t *block = block_Alloc(encoded_size);
    if (!block) { free(encoded); return NULL; }
    memcpy(block->p_buffer, encoded, encoded_size);
    free(encoded);
    video_format_t input, output;
    video_format_Init(&input, image_Ext2Fourcc(relative));
    video_format_Init(&output, VLC_CODEC_RGBA);
    image_handler_t *handler = image_HandlerCreate(engine->vd);
    picture_t *picture = handler ? image_Read(handler, block, &input, &output) : NULL;
    if (!handler) block_Release(block);
    if (handler) image_HandlerDelete(handler);
    video_format_Clean(&input);
    video_format_Clean(&output);
    if (!picture || picture->i_planes != 1) {
        if (picture) picture_Release(picture);
        return NULL;
    }
    unsigned width = picture->format.i_visible_width;
    unsigned height = picture->format.i_visible_height;
    size_t pitch = (size_t)width * 4;
    if (!width || !height || pitch / 4 != width || height > SIZE_MAX / pitch) {
        picture_Release(picture);
        return NULL;
    }
    uint8_t *pixels = malloc(pitch * height);
    if (!pixels) { picture_Release(picture); return NULL; }
    for (unsigned y = 0; y < height; ++y)
        memcpy(pixels + y * pitch,
               picture->p[0].p_pixels + y * picture->p[0].i_pitch, pitch);
    picture_Release(picture);

    struct ra_d3d_lut *lut = &engine->luts[engine->lut_count];
    if (!AllocateTarget(engine, &lut->target, width, height,
                        DXGI_FORMAT_R8G8B8A8_UNORM, mipmap)) {
        free(pixels);
        return NULL;
    }
    ID3D11DeviceContext_UpdateSubresource(engine->device->d3dcontext,
        (ID3D11Resource *)lut->target.texture, 0, NULL, pixels, (UINT)pitch, 0);
    if (mipmap)
        ID3D11DeviceContext_GenerateMips(engine->device->d3dcontext,
                                         lut->target.srv);
    free(pixels);
    strlcpy(lut->name, name, sizeof(lut->name));
    strlcpy(lut->source, relative, sizeof(lut->source));
    lut->linear = linear;
    lut->mipmap = mipmap;
    lut->wrap_mode = wrap;
    engine->lut_count++;
    return lut;
}

static bool LoadLuts(struct d3d11_ra_shader_engine *engine,
                     struct ra_d3d_preset *out, const char *preset,
                     char *list)
{
    if (!list || !*list) return true;
    char *save = NULL;
    for (char *name = strtok_r(list, ";", &save); name;
         name = strtok_r(NULL, ";", &save)) {
        while (*name == ' ' || *name == '\t') ++name;
        char *end = name + strlen(name);
        while (end > name && (end[-1] == ' ' || end[-1] == '\t')) *--end = 0;
        if (!*name) continue;
        if (out->lut_count == RA_D3D_MAX_TEXTURES)
            return false;
        struct ra_d3d_lut *lut = LoadLut(engine, preset, name);
        if (!lut) return false;
        out->luts[out->lut_count++] = lut;
    }
    return true;
}

static void DeletePreset(struct ra_d3d_preset *preset)
{
    for (unsigned i = 0; i < preset->pass_count; ++i) {
        ReleaseProgram(&preset->passes[i]);
        ReleaseTarget(&preset->targets[i]);
    }
    ReleaseTarget(&preset->feedback);
    preset->pass_count = 0;
    preset->valid = false;
}

static bool BuildPreset(struct d3d11_ra_shader_engine *engine,
                        struct ra_d3d_preset *out,
                        const struct ra_d3d_preset_template *info)
{
    out->name = info->name;
    out->attempted = true;
    const char *leaf = !strncmp(info->name, "slang/", 6) ? info->name + 6 :
                                                        info->name;
    char relative[PATH_MAX];
    if (snprintf(relative, sizeof(relative), "crt/slang/%s.glslp", leaf) >=
        (int)sizeof(relative))
        return false;
    char *preset = ReadResource(engine, relative, NULL);
    if (!preset)
        return false;
    char *textures = PresetValue(preset, "textures");
    if (textures && *textures && !LoadLuts(engine, out, preset, textures)) {
        free(textures); free(preset); DeletePreset(out); return false;
    }
    free(textures);
    char *feedback = PresetValue(preset, "feedback_pass");
    out->feedback_pass = feedback && *feedback ? (int)strtol(feedback, NULL, 10) : -1;
    free(feedback);
    char *count = PresetValue(preset, "shaders");
    unsigned pass_count = count ? (unsigned)strtoul(count, NULL, 10) : 0;
    free(count);
    if (!pass_count || pass_count > RA_D3D_MAX_PASSES) {
        free(preset); DeletePreset(out); return false;
    }
    out->pass_count = pass_count;
    for (unsigned i = 0; i < pass_count; ++i) {
        struct ra_d3d_program *program = &out->passes[i];
        char key[64];
        snprintf(key, sizeof(key), "filter_linear%u", i);
        program->linear = PresetBool(preset, key, false);
        snprintf(key, sizeof(key), "srgb_framebuffer%u", i);
        program->srgb = PresetBool(preset, key, false);
        snprintf(key, sizeof(key), "float_framebuffer%u", i);
        program->floating = PresetBool(preset, key, false);
        snprintf(key, sizeof(key), "mipmap_input%u", i);
        program->mipmap_input = PresetBool(preset, key, false);
        snprintf(key, sizeof(key), "wrap_mode%u", i);
        program->wrap_mode = PresetWrap(preset, key, RA_D3D_WRAP_BORDER);
        snprintf(key, sizeof(key), "texture_wrap_mode%u", i);
        program->wrap_mode = PresetWrap(preset, key, program->wrap_mode);
        snprintf(key, sizeof(key), "scale_type%u", i);
        enum ra_d3d_scale_type common_type = PresetScale(preset, key);
        snprintf(key, sizeof(key), "scale%u", i);
        float common_scale = PresetFloat(preset, key, 1.f);
        snprintf(key, sizeof(key), "scale_type_x%u", i);
        char *has_x = PresetValue(preset, key);
        program->scale_type_x = has_x ? PresetScale(preset, key) : common_type;
        free(has_x);
        snprintf(key, sizeof(key), "scale_type_y%u", i);
        char *has_y = PresetValue(preset, key);
        program->scale_type_y = has_y ? PresetScale(preset, key) : common_type;
        free(has_y);
        snprintf(key, sizeof(key), "scale_x%u", i);
        program->scale_x = PresetFloat(preset, key, common_scale);
        snprintf(key, sizeof(key), "scale_y%u", i);
        program->scale_y = PresetFloat(preset, key, common_scale);
        snprintf(key, sizeof(key), "alias%u", i);
        char *alias = PresetValue(preset, key);
        if (alias) {
            strlcpy(program->alias, alias, sizeof(program->alias));
            free(alias);
        }
        if (!BuildProgram(engine, out, preset, i)) {
            msg_Warn(engine->vd, "Direct3D11 rejected RetroArch preset %s pass %u",
                     info->name, i);
            free(preset); DeletePreset(out); return false;
        }
    }
    if (out->feedback_pass < 0 ||
        out->feedback_pass >= (int)out->pass_count - 1)
        out->feedback_pass = -1;
    for (unsigned i = 0; i < out->parameter_count; ++i) {
        char *override = PresetValue(preset, out->parameters[i].name);
        if (!override) continue;
        char *end;
        float value = strtof(override, &end);
        if (end != override)
            out->parameters[i].value = value;
        free(override);
    }
    free(preset);
    out->valid = true;
    return true;
}

static void PublishCapabilities(struct d3d11_ra_shader_engine *engine)
{
    char *available = strdup("");
    if (!available)
        return;
    for (size_t i = 0; i < ARRAY_SIZE(preset_templates); ++i) {
        /* These two upstream Intel-labelled Royale graphs render a fully
         * black frame on the tested Iris Xe D3D11 driver. Keep them visible
         * on other vendors, but do not offer a known-broken choice here. */
        if (engine->intel &&
            (!strcmp(preset_templates[i].name, "slang/crt-royale-intel") ||
             !strcmp(preset_templates[i].name,
                     "slang/crt-royale-fake-bloom-intel")))
            continue;
        struct ra_d3d_preset *preset = engine->presets[i];
        if (preset && preset->attempted && !preset->valid)
            continue;
        const char *leaf = preset_templates[i].name + 6;
        char relative[PATH_MAX];
        if (snprintf(relative, sizeof(relative), "crt/slang/%s.glslp", leaf) >=
            (int)sizeof(relative))
            continue;
        char *resource = ReadResource(engine, relative, NULL);
        if (!resource)
            continue;
        free(resource);
        char *next;
        if (asprintf(&next, "%s%s%s", available, *available ? ";" : "",
                     preset_templates[i].name) < 0)
            continue;
        free(available);
        available = next;
    }
    vlc_object_t *root = VLC_OBJECT(engine->vd->obj.libvlc);
    var_Create(root, "crt-retroarch-available", VLC_VAR_STRING);
    var_SetString(root, "crt-retroarch-available", available);
    var_Create(root, "crt-retroarch-backend", VLC_VAR_STRING);
    var_SetString(root, "crt-retroarch-backend",
                  *available ? "direct3d11-retroarch-slang-hlsl" : "cpu-legacy");
    var_Create(root, "crt-retroarch-owner", VLC_VAR_ADDRESS);
    var_SetAddress(root, "crt-retroarch-owner", engine);
    char *preset = var_InheritString(engine->vd, "crt-retroarch-preset");
    bool enabled = var_InheritBool(engine->vd, "crt-retroarch-enabled");
    var_Create(root, "crt-retroarch-enabled", VLC_VAR_BOOL);
    var_SetBool(root, "crt-retroarch-enabled", enabled);
    var_Create(root, "crt-retroarch-preset", VLC_VAR_STRING);
    var_SetString(root, "crt-retroarch-preset", preset ? preset : "crt-easymode");
    free(preset);
    char *raster = var_InheritString(engine->vd, "crt-retroarch-raster");
    var_Create(root, "crt-retroarch-raster", VLC_VAR_STRING);
    var_SetString(root, "crt-retroarch-raster", raster ? raster : "auto");
    free(raster);
    msg_Info(engine->vd, "Direct3D11 RetroArch Slang shaders supported: %s",
             *available ? available : "none");
    free(available);
}

static bool CreateSamplers(struct d3d11_ra_shader_engine *engine)
{
    static const D3D11_TEXTURE_ADDRESS_MODE addresses[] = {
        D3D11_TEXTURE_ADDRESS_BORDER, D3D11_TEXTURE_ADDRESS_CLAMP,
        D3D11_TEXTURE_ADDRESS_WRAP, D3D11_TEXTURE_ADDRESS_MIRROR,
    };
    for (unsigned linear = 0; linear < 2; ++linear)
        for (unsigned wrap = 0; wrap < ARRAY_SIZE(addresses); ++wrap) {
            D3D11_SAMPLER_DESC desc = { 0 };
            desc.Filter = linear ? D3D11_FILTER_MIN_MAG_MIP_LINEAR :
                                   D3D11_FILTER_MIN_MAG_MIP_POINT;
            desc.AddressU = desc.AddressV = desc.AddressW = addresses[wrap];
            desc.MaxLOD = D3D11_FLOAT32_MAX;
            HRESULT hr = ID3D11Device_CreateSamplerState(
                engine->device->d3ddevice, &desc,
                &engine->samplers[linear][wrap]);
            if (FAILED(hr))
                return false;
        }
    return true;
}

struct ra_d3d_vertex {
    float position[4];
    float texcoord[2];
};

static bool CreateVertices(struct d3d11_ra_shader_engine *engine)
{
    static const struct ra_d3d_vertex vertices[] = {
        { { 0, 0, 0, 1 }, { 0, 0 } },
        { { 1, 0, 0, 1 }, { 1, 0 } },
        { { 0, 1, 0, 1 }, { 0, 1 } },
        { { 1, 1, 0, 1 }, { 1, 1 } },
    };
    D3D11_BUFFER_DESC desc = { 0 };
    desc.ByteWidth = sizeof(vertices);
    desc.Usage = D3D11_USAGE_IMMUTABLE;
    desc.BindFlags = D3D11_BIND_VERTEX_BUFFER;
    D3D11_SUBRESOURCE_DATA initial = { vertices, 0, 0 };
    return SUCCEEDED(ID3D11Device_CreateBuffer(engine->device->d3ddevice,
        &desc, &initial, &engine->vertices));
}

static bool CreateStockProgram(struct d3d11_ra_shader_engine *engine)
{
    static const char vertex[] =
        "struct I{float4 p:TEXCOORD0;float2 uv:TEXCOORD1;};"
        "struct O{float4 p:SV_POSITION;float2 uv:TEXCOORD0;};"
        "O main(I i){O o;o.p=float4(i.p.x*2-1,1-i.p.y*2,0,1);"
        "o.uv=i.uv;return o;}";
    static const char pixel[] =
        "Texture2D<float4> Texture:register(t0);"
        "SamplerState TextureSampler:register(s0);"
        "struct I{float4 p:SV_POSITION;float2 uv:TEXCOORD0;};"
        "float4 main(I i):SV_TARGET{return Texture.Sample(TextureSampler,i.uv);}";
    ID3DBlob *vs = D3D11_CompileShader(engine->vd, engine->hd3d,
                                       engine->device, vertex, false);
    ID3DBlob *ps = D3D11_CompileShader(engine->vd, engine->hd3d,
                                       engine->device, pixel, true);
    if (!vs || !ps) {
        if (vs) ID3D10Blob_Release(vs);
        if (ps) ID3D10Blob_Release(ps);
        return false;
    }
    HRESULT hr = ID3D11Device_CreateVertexShader(engine->device->d3ddevice,
        ID3D10Blob_GetBufferPointer(vs), ID3D10Blob_GetBufferSize(vs), NULL,
        &engine->stock_vs);
    if (SUCCEEDED(hr))
        hr = ID3D11Device_CreatePixelShader(engine->device->d3ddevice,
            ID3D10Blob_GetBufferPointer(ps), ID3D10Blob_GetBufferSize(ps),
            NULL, &engine->stock_ps);
    D3D11_INPUT_ELEMENT_DESC layout[] = {
        { "TEXCOORD", 0, DXGI_FORMAT_R32G32B32A32_FLOAT, 0, 0,
          D3D11_INPUT_PER_VERTEX_DATA, 0 },
        { "TEXCOORD", 1, DXGI_FORMAT_R32G32_FLOAT, 0, 16,
          D3D11_INPUT_PER_VERTEX_DATA, 0 },
    };
    if (SUCCEEDED(hr))
        hr = ID3D11Device_CreateInputLayout(engine->device->d3ddevice,
            layout, ARRAY_SIZE(layout), ID3D10Blob_GetBufferPointer(vs),
            ID3D10Blob_GetBufferSize(vs), &engine->stock_layout);
    ID3D10Blob_Release(vs);
    ID3D10Blob_Release(ps);
    return SUCCEEDED(hr);
}

struct d3d11_ra_shader_engine *D3D11_RA_Create(vout_display_t *vd,
                                                d3d11_handle_t *hd3d,
                                                d3d11_device_t *device)
{
    struct d3d11_ra_shader_engine *engine = calloc(1, sizeof(*engine));
    if (!engine)
        return NULL;
    engine->vd = vd;
    engine->hd3d = hd3d;
    engine->device = device;
    OpenResourcePack(engine);
    IDXGIAdapter *adapter = D3D11DeviceAdapter(device->d3ddevice);
    if (adapter) {
        DXGI_ADAPTER_DESC desc;
        if (SUCCEEDED(IDXGIAdapter_GetDesc(adapter, &desc)))
            engine->intel = desc.VendorId == 0x8086;
        IDXGIAdapter_Release(adapter);
    }
    if (!CreateVertices(engine) || !CreateSamplers(engine) ||
        !CreateStockProgram(engine)) {
        D3D11_RA_Destroy(engine);
        return NULL;
    }
    PublishCapabilities(engine);
    return engine;
}

void D3D11_RA_Destroy(struct d3d11_ra_shader_engine *engine)
{
    if (!engine) return;
    vlc_object_t *root = VLC_OBJECT(engine->vd->obj.libvlc);
    if (var_GetAddress(root, "crt-retroarch-owner") == engine) {
        var_SetAddress(root, "crt-retroarch-owner", NULL);
        var_SetString(root, "crt-retroarch-available", "");
        var_SetString(root, "crt-retroarch-backend", "cpu-legacy");
    }
    for (size_t i = 0; i < ARRAY_SIZE(engine->presets); ++i) {
        if (engine->presets[i])
            DeletePreset(engine->presets[i]);
        free(engine->presets[i]);
    }
    for (unsigned i = 0; i < engine->lut_count; ++i)
        ReleaseTarget(&engine->luts[i].target);
    ReleaseTarget(&engine->input);
    if (engine->vertices) ID3D11Buffer_Release(engine->vertices);
    if (engine->stock_layout) ID3D11InputLayout_Release(engine->stock_layout);
    if (engine->stock_ps) ID3D11PixelShader_Release(engine->stock_ps);
    if (engine->stock_vs) ID3D11VertexShader_Release(engine->stock_vs);
    for (unsigned linear = 0; linear < 2; ++linear)
        for (unsigned wrap = 0; wrap < 4; ++wrap)
            if (engine->samplers[linear][wrap])
                ID3D11SamplerState_Release(engine->samplers[linear][wrap]);
    CloseResourcePack(&engine->pack);
    free(engine);
}

static struct ra_d3d_preset *FindPreset(
    struct d3d11_ra_shader_engine *engine, const char *requested,
    const char **effective)
{
    char alias[128];
    const char *name = requested;
    if (engine->intel && requested &&
        (!strcmp(requested, "crt-royale") ||
         !strcmp(requested, "slang/crt-royale")))
        name = "slang/crt-royale-fast";
    else if (requested && strncmp(requested, "slang/", 6)) {
        if (snprintf(alias, sizeof(alias), "slang/%s", requested) >=
            (int)sizeof(alias))
            return NULL;
        name = alias;
    }
    if (engine->intel && name &&
        (!strcmp(name, "slang/crt-royale-intel") ||
         !strcmp(name, "slang/crt-royale-fake-bloom-intel")))
        return NULL;
    for (size_t i = 0; name && i < ARRAY_SIZE(preset_templates); ++i)
        if (!strcmp(preset_templates[i].name, name)) {
            struct ra_d3d_preset *preset = engine->presets[i];
            if (preset && preset->attempted && !preset->valid)
                return NULL;
            if (!preset) {
                preset = calloc(1, sizeof(*preset));
                if (!preset) return NULL;
                engine->presets[i] = preset;
            }
            if (!preset->valid && !BuildPreset(engine, preset,
                                                &preset_templates[i])) {
                PublishCapabilities(engine);
                return NULL;
            }
            *effective = preset_templates[i].name;
            return preset;
        }
    return NULL;
}

static bool ParseIndexed(const char *name, const char *prefix, unsigned *index)
{
    int used = 0;
    if (sscanf(name, "%*[^0-9]%u%n", index, &used) != 1)
        return false;
    return !strncmp(name, prefix, strlen(prefix)) && name[used] == '\0';
}

static struct ra_d3d_lut *PresetLut(struct ra_d3d_preset *preset,
                                    const char *name)
{
    for (unsigned i = 0; i < preset->lut_count; ++i)
        if (!strcmp(preset->luts[i]->name, name))
            return preset->luts[i];
    return NULL;
}

static struct ra_d3d_target *TextureTarget(struct ra_d3d_preset *preset,
                                           struct ra_d3d_target *source,
                                           struct ra_d3d_target *original,
                                           const char *name)
{
    if (!strcmp(name, "Texture")) return source;
    if (!strcmp(name, "OrigTexture")) return original;
    if (!strcmp(name, "FeedbackTexture")) return &preset->feedback;
    unsigned number;
    int used = 0;
    if (sscanf(name, "Pass%uTexture%n", &number, &used) == 1 &&
        name[used] == '\0' && number > 0 && number <= preset->pass_count)
        return &preset->targets[number - 1];
    struct ra_d3d_lut *lut = PresetLut(preset, name);
    return lut ? &lut->target : NULL;
}

static bool SizeForMember(struct d3d11_ra_shader_engine *engine,
                          struct ra_d3d_preset *preset,
                          struct ra_d3d_target *source,
                          struct ra_d3d_target *original,
                          unsigned output_width, unsigned output_height,
                          const char *name, float value[4])
{
    unsigned width = 0, height = 0, index;
    if (!strcmp(name, "OutputSize")) {
        width = output_width; height = output_height;
    } else if (!strcmp(name, "FinalViewportSize")) {
        width = engine->viewport_width; height = engine->viewport_height;
    } else if (!strcmp(name, "SourceSize")) {
        width = source->width; height = source->height;
    } else if (!strcmp(name, "OriginalSize")) {
        width = original->width; height = original->height;
    } else if (ParseIndexed(name, "PassOutputSize", &index) &&
               index < preset->pass_count) {
        width = preset->targets[index].width;
        height = preset->targets[index].height;
    } else if (ParseIndexed(name, "PassFeedbackSize", &index) &&
               index < preset->pass_count) {
        width = preset->feedback.width; height = preset->feedback.height;
    } else if (ParseIndexed(name, "OriginalHistorySize", &index)) {
        width = original->width; height = original->height;
    } else if (ParseIndexed(name, "UserSize", &index) &&
               index < preset->lut_count) {
        width = preset->luts[index]->target.width;
        height = preset->luts[index]->target.height;
    } else {
        size_t length = strlen(name);
        if (length <= 4 || strcmp(name + length - 4, "Size"))
            return false;
        char base[64];
        if (length - 4 >= sizeof(base)) return false;
        memcpy(base, name, length - 4);
        base[length - 4] = '\0';
        struct ra_d3d_lut *lut = PresetLut(preset, base);
        if (lut) {
            width = lut->target.width; height = lut->target.height;
        } else {
            for (unsigned i = 0; i < preset->pass_count; ++i)
                if (preset->passes[i].alias[0] &&
                    !strcmp(preset->passes[i].alias, base)) {
                    width = preset->targets[i].width;
                    height = preset->targets[i].height;
                    break;
                }
        }
    }
    if (!width || !height)
        return false;
    value[0] = width;
    value[1] = height;
    value[2] = 1.f / width;
    value[3] = 1.f / height;
    return true;
}

static bool UpdateConstantBuffer(struct d3d11_ra_shader_engine *engine,
                                 struct ra_d3d_preset *preset,
                                 struct ra_d3d_program *program, unsigned slot,
                                 struct ra_d3d_target *source,
                                 struct ra_d3d_target *original,
                                 unsigned output_width,
                                 unsigned output_height)
{
    if (!program->constant_buffers[slot])
        return true;
    D3D11_MAPPED_SUBRESOURCE mapped;
    HRESULT hr = ID3D11DeviceContext_Map(engine->device->d3dcontext,
        (ID3D11Resource *)program->constant_buffers[slot], 0,
        D3D11_MAP_WRITE_DISCARD, 0, &mapped);
    if (FAILED(hr))
        return false;
    memset(mapped.pData, 0, program->buffer_sizes[slot]);
    bool valid = true;
    for (unsigned i = 0; i < program->member_count[slot]; ++i) {
        struct ra_d3d_member *member = &program->members[slot][i];
        unsigned size = member->type == RA_D3D_MEMBER_MAT4 ? 64 :
                        member->type == RA_D3D_MEMBER_VEC4 ? 16 : 4;
        if (member->offset > program->buffer_sizes[slot] ||
            size > program->buffer_sizes[slot] - member->offset) {
            valid = false;
            break;
        }
        uint8_t *destination = (uint8_t *)mapped.pData + member->offset;
        if (!strcmp(member->name, "MVP") &&
            member->type == RA_D3D_MEMBER_MAT4) {
            static const float mvp[] = {
                2, 0, 0, 0,
                0,-2, 0, 0,
                0, 0, 1, 0,
               -1, 1, 0, 1,
            };
            memcpy(destination, mvp, sizeof(mvp));
        } else if (!strcmp(member->name, "FrameCount") &&
                   (member->type == RA_D3D_MEMBER_UINT ||
                    member->type == RA_D3D_MEMBER_INT)) {
            uint32_t frame = (uint32_t)(engine->frame_count & 0x7fffffff);
            memcpy(destination, &frame, sizeof(frame));
        } else if (!strcmp(member->name, "FrameDirection") &&
                   (member->type == RA_D3D_MEMBER_UINT ||
                    member->type == RA_D3D_MEMBER_INT)) {
            uint32_t direction = 1;
            memcpy(destination, &direction, sizeof(direction));
        } else if (member->type == RA_D3D_MEMBER_VEC4) {
            float dimensions[4];
            if (!SizeForMember(engine, preset, source, original,
                               output_width, output_height, member->name,
                               dimensions)) {
                valid = false;
                break;
            }
            memcpy(destination, dimensions, sizeof(dimensions));
        } else if (member->type == RA_D3D_MEMBER_FLOAT) {
            struct ra_d3d_parameter *parameter =
                FindParameter(preset, member->name);
            if (!parameter) {
                valid = false;
                break;
            }
            float value = parameter->value;
            /* Royale-fast intentionally defaults to a dim 0.671875 level.
             * The compatibility alias represents the user-facing Royale
             * choice, so preserve the algorithm but restore its neutral
             * display level. Explicit royale-fast keeps the upstream value. */
            if (engine->royale_compat &&
                !strcmp(member->name, "levels_contrast"))
                value = 1.f;
            memcpy(destination, &value, sizeof(value));
        } else {
            valid = false;
            break;
        }
    }
    ID3D11DeviceContext_Unmap(engine->device->d3dcontext,
        (ID3D11Resource *)program->constant_buffers[slot], 0);
    return valid;
}

static void PassSize(const struct d3d11_ra_shader_engine *engine,
                     const struct ra_d3d_program *program,
                     unsigned input_width, unsigned input_height,
                     unsigned *output_width, unsigned *output_height)
{
    if (program->scale_type_x == RA_D3D_SCALE_VIEWPORT)
        *output_width = (unsigned)(engine->viewport_width * program->scale_x);
    else if (program->scale_type_x == RA_D3D_SCALE_ABSOLUTE)
        *output_width = (unsigned)program->scale_x;
    else
        *output_width = (unsigned)(input_width * program->scale_x);
    if (program->scale_type_y == RA_D3D_SCALE_VIEWPORT)
        *output_height = (unsigned)(engine->viewport_height * program->scale_y);
    else if (program->scale_type_y == RA_D3D_SCALE_ABSOLUTE)
        *output_height = (unsigned)program->scale_y;
    else
        *output_height = (unsigned)(input_height * program->scale_y);
    if (!*output_width) *output_width = 1;
    if (!*output_height) *output_height = 1;
}

static bool EnsureFeedback(struct d3d11_ra_shader_engine *engine,
                           struct ra_d3d_preset *preset)
{
    if (preset->feedback_pass < 0)
        return true;
    unsigned width = engine->input.width, height = engine->input.height;
    for (int i = 0; i <= preset->feedback_pass; ++i) {
        unsigned next_width, next_height;
        PassSize(engine, &preset->passes[i], width, height,
                 &next_width, &next_height);
        width = next_width; height = next_height;
    }
    struct ra_d3d_program *program = &preset->passes[preset->feedback_pass];
    bool mipmaps = preset->feedback_pass + 1 < (int)preset->pass_count &&
                   preset->passes[preset->feedback_pass + 1].mipmap_input;
    bool fresh = !preset->feedback.texture || preset->feedback.width != width ||
                 preset->feedback.height != height ||
                 preset->feedback.format != ProgramFormat(engine, program) ||
                 preset->feedback.mipmaps != mipmaps;
    if (!AllocateTarget(engine, &preset->feedback, width, height,
                        ProgramFormat(engine, program), mipmaps))
        return false;
    if (fresh) {
        static const float black[4] = { 0, 0, 0, 1 };
        ID3D11DeviceContext_ClearRenderTargetView(engine->device->d3dcontext,
                                                  preset->feedback.rtv, black);
    }
    return true;
}

bool D3D11_RA_Begin(struct d3d11_ra_shader_engine *engine,
                    unsigned source_width, unsigned source_height,
                    unsigned viewport_width, unsigned viewport_height,
                    vlc_tick_t pts, ID3D11RenderTargetView **target,
                    unsigned *target_width, unsigned *target_height)
{
    if (!engine || !target || !target_width || !target_height ||
        !source_width || !source_height || !viewport_width || !viewport_height ||
        !var_InheritBool(engine->vd, "crt-retroarch-enabled"))
        return false;
    char *requested = var_InheritString(engine->vd, "crt-retroarch-preset");
    engine->royale_compat = engine->intel && requested &&
        (!strcmp(requested, "crt-royale") ||
         !strcmp(requested, "slang/crt-royale"));
    const char *effective = NULL;
    struct ra_d3d_preset *preset = requested ?
        FindPreset(engine, requested, &effective) : NULL;
    if (!preset) {
        free(requested);
        return false;
    }
    bool selection_changed = strcmp(engine->selected, effective) != 0;
    if (selection_changed) {
        ReleaseTarget(&preset->feedback);
        engine->frame_count = 0;
        strlcpy(engine->selected, effective, sizeof(engine->selected));
        if (engine->royale_compat)
            msg_Info(engine->vd, "using Intel-validated Direct3D11 Royale fast compatibility profile");
        msg_Info(engine->vd, "using exact Direct3D11 RetroArch Slang preset %s",
                 effective);
    }
    free(requested);
    engine->viewport_width = viewport_width;
    engine->viewport_height = viewport_height;
    unsigned width = source_width, height = source_height;
    char *raster = var_InheritString(engine->vd, "crt-retroarch-raster");
    unsigned raster_height = 0;
    if (raster && !strcmp(raster, "240p")) raster_height = 240;
    else if (raster && !strcmp(raster, "480p")) raster_height = 480;
    else if ((!raster || !strcmp(raster, "auto")) && source_height > 576)
        raster_height = 480;
    free(raster);
    if (raster_height && raster_height != source_height) {
        uint64_t scaled = (uint64_t)source_width * raster_height +
                          source_height / 2;
        width = (unsigned)(scaled / source_height);
        if (width > 1) width = (width + 1) & ~1u;
        height = raster_height;
    }
    if (engine->last_raster_width != width ||
        engine->last_raster_height != height) {
        msg_Info(engine->vd, "Direct3D11 normalizing RetroArch CRT source raster from %ux%u to %ux%u",
                 source_width, source_height, width, height);
        engine->last_raster_width = width;
        engine->last_raster_height = height;
    }
    bool input_changed = engine->input.width != width ||
                         engine->input.height != height;
    if (!AllocateTarget(engine, &engine->input, width, height,
                        DXGI_FORMAT_R8G8B8A8_UNORM,
                        preset->passes[0].mipmap_input))
        return false;
    if (input_changed && !selection_changed)
        ReleaseTarget(&preset->feedback);
    ID3D11ShaderResourceView *nulls[RA_D3D_MAX_TEXTURES] = { 0 };
    ID3D11DeviceContext_PSSetShaderResources(engine->device->d3dcontext, 0,
                                             ARRAY_SIZE(nulls), nulls);
    static const float black[4] = { 0, 0, 0, 1 };
    ID3D11DeviceContext_ClearRenderTargetView(engine->device->d3dcontext,
                                              engine->input.rtv, black);
    engine->advance = pts == VLC_TICK_INVALID ? !engine->have_pts :
                      (!engine->have_pts || pts != engine->pts);
    if (pts != VLC_TICK_INVALID) {
        engine->pts = pts;
        engine->have_pts = true;
    }
    engine->active = preset;
    *target = engine->input.rtv;
    *target_width = width;
    *target_height = height;
    return true;
}

static bool DrawPass(struct d3d11_ra_shader_engine *engine,
                     struct ra_d3d_preset *preset,
                     struct ra_d3d_program *program,
                     struct ra_d3d_target *source,
                     struct ra_d3d_target *original,
                     ID3D11RenderTargetView *target,
                     unsigned output_width, unsigned output_height)
{
    /* The previous pass (or VLC's RGB conversion pass for pass zero) leaves
     * its texture bound to the output merger. D3D11 does not permit that
     * texture to be read simultaneously as an SRV: PSSetShaderResources()
     * may silently bind NULL. RetroArch's D3D11 runner breaks the hazard
     * before generating mipmaps or binding any input textures. */
    ID3D11ShaderResourceView *unbound_srvs[RA_D3D_MAX_TEXTURES] = { 0 };
    ID3D11RenderTargetView *unbound_target = NULL;
    ID3D11DeviceContext_PSSetShaderResources(engine->device->d3dcontext, 0,
                                             ARRAY_SIZE(unbound_srvs),
                                             unbound_srvs);
    ID3D11DeviceContext_OMSetRenderTargets(engine->device->d3dcontext, 1,
                                           &unbound_target, NULL);
    if (program->mipmap_input) {
        if (!source->mipmaps)
            return false;
        ID3D11DeviceContext_GenerateMips(engine->device->d3dcontext,
                                         source->srv);
    }
    for (unsigned slot = 0; slot < 2; ++slot)
        if (!UpdateConstantBuffer(engine, preset, program, slot, source,
                                  original, output_width, output_height)) {
            msg_Err(engine->vd, "Direct3D11 RetroArch uniform binding failed for %s",
                    preset->name);
            return false;
        }

    ID3D11ShaderResourceView *resources[RA_D3D_MAX_TEXTURES] = { 0 };
    ID3D11SamplerState *samplers[RA_D3D_MAX_TEXTURES] = { 0 };
    for (unsigned i = 0; i < program->binding_count; ++i) {
        struct ra_d3d_binding *binding = &program->bindings[i];
        struct ra_d3d_target *texture = TextureTarget(
            preset, source, original, binding->name);
        if (!texture || !texture->srv) {
            msg_Err(engine->vd, "Direct3D11 RetroArch texture %s unavailable in %s",
                    binding->name, preset->name);
            return false;
        }
        resources[binding->slot] = texture->srv;
        bool linear = program->linear;
        enum ra_d3d_wrap_mode wrap = program->wrap_mode;
        struct ra_d3d_lut *lut = PresetLut(preset, binding->name);
        if (lut) {
            linear = lut->linear;
            wrap = lut->wrap_mode;
        }
        samplers[binding->slot] = engine->samplers[linear ? 1 : 0][wrap];
    }

    D3D11_VIEWPORT viewport = {
        .TopLeftX = 0, .TopLeftY = 0,
        .Width = output_width, .Height = output_height,
        .MinDepth = 0, .MaxDepth = 1,
    };
    static const float black[4] = { 0, 0, 0, 1 };
    ID3D11DeviceContext_OMSetRenderTargets(engine->device->d3dcontext, 1,
                                           &target, NULL);
    ID3D11DeviceContext_RSSetViewports(engine->device->d3dcontext, 1,
                                       &viewport);
    ID3D11DeviceContext_ClearRenderTargetView(engine->device->d3dcontext,
                                              target, black);
    UINT stride = sizeof(struct ra_d3d_vertex), offset = 0;
    ID3D11DeviceContext_IASetVertexBuffers(engine->device->d3dcontext, 0, 1,
                                           &engine->vertices, &stride, &offset);
    ID3D11DeviceContext_IASetInputLayout(engine->device->d3dcontext,
                                         program->layout);
    ID3D11DeviceContext_IASetPrimitiveTopology(engine->device->d3dcontext,
                                               D3D11_PRIMITIVE_TOPOLOGY_TRIANGLESTRIP);
    ID3D11DeviceContext_VSSetShader(engine->device->d3dcontext, program->vs,
                                    NULL, 0);
    ID3D11DeviceContext_PSSetShader(engine->device->d3dcontext, program->ps,
                                    NULL, 0);
    ID3D11DeviceContext_VSSetConstantBuffers(engine->device->d3dcontext, 0, 2,
                                             program->constant_buffers);
    ID3D11DeviceContext_PSSetConstantBuffers(engine->device->d3dcontext, 0, 2,
                                             program->constant_buffers);
    ID3D11DeviceContext_PSSetShaderResources(engine->device->d3dcontext, 0,
                                             ARRAY_SIZE(resources), resources);
    ID3D11DeviceContext_PSSetSamplers(engine->device->d3dcontext, 0,
                                     ARRAY_SIZE(samplers), samplers);
    ID3D11DeviceContext_Draw(engine->device->d3dcontext, 4, 0);
    ID3D11ShaderResourceView *nulls[RA_D3D_MAX_TEXTURES] = { 0 };
    ID3D11DeviceContext_PSSetShaderResources(engine->device->d3dcontext, 0,
                                             ARRAY_SIZE(nulls), nulls);
    return true;
}

static void DrawStock(struct d3d11_ra_shader_engine *engine,
                      struct ra_d3d_target *source,
                      ID3D11RenderTargetView *target,
                      const D3D11_VIEWPORT *viewport)
{
    ID3D11DeviceContext_OMSetRenderTargets(engine->device->d3dcontext, 1,
                                           &target, NULL);
    ID3D11DeviceContext_RSSetViewports(engine->device->d3dcontext, 1, viewport);
    UINT stride = sizeof(struct ra_d3d_vertex), offset = 0;
    ID3D11DeviceContext_IASetVertexBuffers(engine->device->d3dcontext, 0, 1,
                                           &engine->vertices, &stride, &offset);
    ID3D11DeviceContext_IASetInputLayout(engine->device->d3dcontext,
                                         engine->stock_layout);
    ID3D11DeviceContext_IASetPrimitiveTopology(engine->device->d3dcontext,
                                               D3D11_PRIMITIVE_TOPOLOGY_TRIANGLESTRIP);
    ID3D11DeviceContext_VSSetShader(engine->device->d3dcontext,
                                    engine->stock_vs, NULL, 0);
    ID3D11DeviceContext_PSSetShader(engine->device->d3dcontext,
                                    engine->stock_ps, NULL, 0);
    ID3D11Buffer *null_buffers[2] = { NULL, NULL };
    ID3D11DeviceContext_VSSetConstantBuffers(engine->device->d3dcontext, 0, 2,
                                             null_buffers);
    ID3D11DeviceContext_PSSetConstantBuffers(engine->device->d3dcontext, 0, 2,
                                             null_buffers);
    ID3D11DeviceContext_PSSetShaderResources(engine->device->d3dcontext, 0, 1,
                                             &source->srv);
    ID3D11SamplerState *sampler = engine->samplers[1][RA_D3D_WRAP_EDGE];
    ID3D11DeviceContext_PSSetSamplers(engine->device->d3dcontext, 0, 1,
                                     &sampler);
    ID3D11DeviceContext_Draw(engine->device->d3dcontext, 4, 0);
    ID3D11ShaderResourceView *null = NULL;
    ID3D11DeviceContext_PSSetShaderResources(engine->device->d3dcontext, 0, 1,
                                             &null);
}

bool D3D11_RA_Render(struct d3d11_ra_shader_engine *engine,
                     ID3D11RenderTargetView *output,
                     const D3D11_VIEWPORT *viewport)
{
    struct ra_d3d_preset *preset = engine ? engine->active : NULL;
    if (!preset || !output || !viewport)
        return false;
    engine->active = NULL;
    if (!EnsureFeedback(engine, preset))
        return false;
    struct ra_d3d_target *original = &engine->input;
    unsigned input_width = original->width, input_height = original->height;
    for (unsigned i = 0; i < preset->pass_count; ++i) {
        struct ra_d3d_program *program = &preset->passes[i];
        unsigned width, height;
        PassSize(engine, program, input_width, input_height, &width, &height);
        if (i + 1 == preset->pass_count) {
            width = engine->viewport_width;
            height = engine->viewport_height;
        }
        bool mipmaps = i + 1 < preset->pass_count &&
                       preset->passes[i + 1].mipmap_input;
        if (!AllocateTarget(engine, &preset->targets[i], width, height,
                            ProgramFormat(engine, program), mipmaps))
            return false;
        struct ra_d3d_target *source = i ? &preset->targets[i - 1] : original;
        if (!DrawPass(engine, preset, program, source, original,
                      preset->targets[i].rtv, width, height))
            return false;
        input_width = width;
        input_height = height;
    }
    struct ra_d3d_target *last = &preset->targets[preset->pass_count - 1];
    DrawStock(engine, last, output, viewport);
    if (engine->advance)
        engine->frame_count++;
    if (engine->advance && preset->feedback_pass >= 0) {
        struct ra_d3d_target swap = preset->feedback;
        preset->feedback = preset->targets[preset->feedback_pass];
        preset->targets[preset->feedback_pass] = swap;
    }
    return true;
}
