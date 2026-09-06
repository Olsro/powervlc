/* Compile/link the generated Slang programs on the real driver, without UI.
 * macOS: cc -Wno-deprecated-declarations test/check_slang_gpu.c -framework OpenGL -o /tmp/check-slang-gpu
 * Linux: cc test/check_slang_gpu.c -lEGL -lGL -o /tmp/check-slang-gpu
 * Windows (interactive desktop): cc test/check_slang_gpu.c -lopengl32 -lgdi32 -o check-slang-gpu.exe
 * Usage: /tmp/check-slang-gpu <generated-program.glsl> [more programs...]
 */
#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <string.h>
#ifdef __APPLE__
#define GL_SILENCE_DEPRECATION
#include <OpenGL/OpenGL.h>
#include <OpenGL/gl.h>
#elif defined(_WIN32)
#include <windows.h>
#include <GL/gl.h>
#include <GL/glext.h>
#define GL_FUNCTIONS(X) \
    X(PFNGLCREATESHADERPROC, glCreateShader) \
    X(PFNGLSHADERSOURCEPROC, glShaderSource) \
    X(PFNGLCOMPILESHADERPROC, glCompileShader) \
    X(PFNGLGETSHADERIVPROC, glGetShaderiv) \
    X(PFNGLGETSHADERINFOLOGPROC, glGetShaderInfoLog) \
    X(PFNGLDELETESHADERPROC, glDeleteShader) \
    X(PFNGLCREATEPROGRAMPROC, glCreateProgram) \
    X(PFNGLATTACHSHADERPROC, glAttachShader) \
    X(PFNGLLINKPROGRAMPROC, glLinkProgram) \
    X(PFNGLGETPROGRAMIVPROC, glGetProgramiv) \
    X(PFNGLGETPROGRAMINFOLOGPROC, glGetProgramInfoLog) \
    X(PFNGLDELETEPROGRAMPROC, glDeleteProgram)
#define DECLARE_GL(type, name) static type name;
GL_FUNCTIONS(DECLARE_GL)
#undef DECLARE_GL
#else
#define GL_GLEXT_PROTOTYPES
#include <EGL/egl.h>
#include <GL/gl.h>
#include <GL/glext.h>
#endif

static GLuint compile(GLenum type, const char *source, const char *name)
{
    const char *body = strchr(source, '\n');
    if (!body) return 0;
    char header[128];
    snprintf(header, sizeof(header), "%.*s\n#define %s 1\n",
             (int)(body - source), source,
             type == GL_VERTEX_SHADER ? "VERTEX" : "FRAGMENT");
    const char *parts[] = { header, body };
    GLuint shader = glCreateShader(type);
    glShaderSource(shader, 2, parts, NULL);
    glCompileShader(shader);
    GLint ok;
    glGetShaderiv(shader, GL_COMPILE_STATUS, &ok);
    if (!ok) {
        char log[16384];
        glGetShaderInfoLog(shader, sizeof(log), NULL, log);
        fprintf(stderr, "%s %s: %s\n", name,
                type == GL_VERTEX_SHADER ? "vertex" : "fragment", log);
        glDeleteShader(shader);
        return 0;
    }
    return shader;
}

int main(int argc, char **argv)
{
#ifdef __APPLE__
    CGLPixelFormatAttribute attributes[] = { kCGLPFAAccelerated, 0 };
    CGLPixelFormatObj format;
    CGLContextObj context;
    GLint count;
    if (CGLChoosePixelFormat(attributes, &format, &count) != kCGLNoError || !count)
        return 77;
    CGLError error = CGLCreateContext(format, NULL, &context);
    CGLDestroyPixelFormat(format);
    if (error != kCGLNoError || CGLSetCurrentContext(context) != kCGLNoError)
        return 77;
#elif defined(_WIN32)
    HWND window = CreateWindowA("STATIC", "PowerVLC shader validation", WS_POPUP,
                                0, 0, 16, 16, NULL, NULL, GetModuleHandle(NULL), NULL);
    if (!window) return 77;
    HDC display = GetDC(window);
    PIXELFORMATDESCRIPTOR format = {0};
    format.nSize = sizeof(format);
    format.nVersion = 1;
    format.dwFlags = PFD_DRAW_TO_WINDOW | PFD_SUPPORT_OPENGL | PFD_DOUBLEBUFFER;
    format.iPixelType = PFD_TYPE_RGBA;
    format.cColorBits = 32;
    int pixel_format = ChoosePixelFormat(display, &format);
    if (!pixel_format || !SetPixelFormat(display, pixel_format, &format)) return 77;
    HGLRC context = wglCreateContext(display);
    if (!context || !wglMakeCurrent(display, context)) return 77;
#else
    EGLDisplay display = eglGetDisplay(EGL_DEFAULT_DISPLAY);
    if (!eglInitialize(display, NULL, NULL) || !eglBindAPI(EGL_OPENGL_API)) return 77;
    EGLint attributes[] = { EGL_SURFACE_TYPE, EGL_PBUFFER_BIT,
        EGL_RENDERABLE_TYPE, EGL_OPENGL_BIT, EGL_NONE };
    EGLConfig config;
    EGLint count;
    if (!eglChooseConfig(display, attributes, &config, 1, &count) || !count) return 77;
    EGLint size[] = { EGL_WIDTH, 16, EGL_HEIGHT, 16, EGL_NONE };
    EGLSurface surface = eglCreatePbufferSurface(display, config, size);
    EGLContext context = eglCreateContext(display, config, EGL_NO_CONTEXT, NULL);
    if (!eglMakeCurrent(display, surface, surface, context)) return 77;
#endif
    unsigned major = 0, minor = 0, passed = 0, skipped = 0, failed = 0;
    const char *language = (const char *)glGetString(GL_SHADING_LANGUAGE_VERSION);
    printf("GL: %s; version: %s; GLSL: %s\n", glGetString(GL_RENDERER),
           glGetString(GL_VERSION), language ? language : "unavailable");
    if (!language || sscanf(language, "%u.%u", &major, &minor) != 2) return 77;
#ifdef _WIN32
#define LOAD_GL(type, name) \
    name = (type)wglGetProcAddress(#name); \
    if (!name || (uintptr_t)name <= 3 || (intptr_t)name == -1) return 77;
    GL_FUNCTIONS(LOAD_GL)
#undef LOAD_GL
#endif
    unsigned supported = major * 100 + minor;
    for (int i = 1; i < argc; ++i) {
        FILE *file = fopen(argv[i], "rb");
        if (!file) { failed++; continue; }
        fseek(file, 0, SEEK_END);
        long length = ftell(file);
        rewind(file);
        char *text = length >= 0 ? calloc(1, (size_t)length + 1) : NULL;
        if (!text || fread(text, 1, length, file) != (size_t)length) {
            free(text); fclose(file); failed++; continue;
        }
        fclose(file);
        char *source = strstr(text, "#version ");
        unsigned version;
        if (!source || sscanf(source, "#version %u", &version) != 1) {
            free(text); failed++; continue;
        }
        if (version > supported) { skipped++; free(text); continue; }
        GLuint vertex = compile(GL_VERTEX_SHADER, source, argv[i]);
        GLuint fragment = compile(GL_FRAGMENT_SHADER, source, argv[i]);
        GLint linked = 0;
        if (vertex && fragment) {
            GLuint program = glCreateProgram();
            glAttachShader(program, vertex);
            glAttachShader(program, fragment);
            glLinkProgram(program);
            glGetProgramiv(program, GL_LINK_STATUS, &linked);
            if (!linked) {
                char log[16384];
                glGetProgramInfoLog(program, sizeof(log), NULL, log);
                fprintf(stderr, "%s link: %s\n", argv[i], log);
            }
            glDeleteProgram(program);
        }
        if (vertex) glDeleteShader(vertex);
        if (fragment) glDeleteShader(fragment);
        if (linked) passed++; else failed++;
        free(text);
    }
    printf("Programs: %u passed, %u language-incompatible skipped, %u failed\n",
           passed, skipped, failed);
#ifdef __APPLE__
    CGLSetCurrentContext(NULL);
    CGLDestroyContext(context);
#elif defined(_WIN32)
    wglMakeCurrent(NULL, NULL);
    wglDeleteContext(context);
    ReleaseDC(window, display);
    DestroyWindow(window);
#else
    eglMakeCurrent(display, EGL_NO_SURFACE, EGL_NO_SURFACE, EGL_NO_CONTEXT);
    eglDestroyContext(display, context);
    eglDestroySurface(display, surface);
    eglTerminate(display);
#endif
    return failed ? 1 : 0;
}
