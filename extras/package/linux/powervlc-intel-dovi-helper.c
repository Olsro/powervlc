/*
 * powervlc-intel-dovi-helper.c - narrowly scoped Intel HDMI Dolby Vision VSIF
 *
 * This helper deliberately has no arbitrary register read/write interface. It
 * accepts one active HDMI connector whose EDID advertises Dolby Vision, finds
 * the i915 transcoder below the desktop session, saves its AVI/vendor packets,
 * installs BT.2020 + Dolby Vision low-latency signalling, and restores the
 * exact bytes on exit. It therefore works equally below Xorg and Wayland.
 *
 * Run as root. The long-lived process retains the baseline in memory; killing
 * it with SIGINT or SIGTERM restores the display. --pid makes it restore when
 * the PowerVLC process exits. Unsupported layouts fail closed before a write.
 */

#define _GNU_SOURCE
#include <dirent.h>
#include <errno.h>
#include <fcntl.h>
#include <limits.h>
#include <signal.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/file.h>
#include <sys/mman.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <time.h>
#include <unistd.h>

#define ARRAY_SIZE(a) (sizeof(a) / sizeof((a)[0]))
#define INFOFRAME_DWORDS 8
#define AVI_ENABLE (1u << 12)
#define VENDOR_ENABLE (1u << 8)
#define MAP_SIZE (2u * 1024u * 1024u)

static volatile sig_atomic_t stopping;

static void stop_handler(int sig)
{
    (void)sig;
    stopping = 1;
}

static bool read_small_file(const char *path, void *out, size_t capacity,
                            size_t *length)
{
    int fd = open(path, O_RDONLY | O_CLOEXEC);
    if (fd < 0)
        return false;
    ssize_t got = read(fd, out, capacity);
    int saved = errno;
    close(fd);
    errno = saved;
    if (got < 0)
        return false;
    if (length)
        *length = (size_t)got;
    return true;
}

static bool text_equals(const char *path, const char *expected)
{
    char buf[64] = {0};
    size_t len = 0;
    if (!read_small_file(path, buf, sizeof(buf) - 1, &len))
        return false;
    while (len && (buf[len - 1] == '\n' || buf[len - 1] == '\r'))
        buf[--len] = 0;
    return strcmp(buf, expected) == 0;
}

static bool edid_has_dolby_vision(const char *path)
{
    uint8_t edid[4096];
    size_t len = 0;
    if (!read_small_file(path, edid, sizeof(edid), &len) || len < 128)
        return false;
    for (size_t i = 0; i + 2 < len; ++i)
        if (edid[i] == 0x46 && edid[i + 1] == 0xd0 && edid[i + 2] == 0x00)
            return true;
    return false;
}

struct output {
    char connector[PATH_MAX];
    char card[32];
    unsigned connector_id;
    char pipe;
    unsigned bpp;
};

static int find_dolby_output(struct output *out)
{
    DIR *dir = opendir("/sys/class/drm");
    if (!dir)
        return -1;
    int matches = 0;
    struct dirent *entry;
    while ((entry = readdir(dir))) {
        if (strncmp(entry->d_name, "card", 4) != 0 ||
            strstr(entry->d_name, "-HDMI-A-") == NULL)
            continue;
        char base[PATH_MAX], path[PATH_MAX];
        snprintf(base, sizeof(base), "/sys/class/drm/%s", entry->d_name);
        snprintf(path, sizeof(path), "%s/status", base);
        if (!text_equals(path, "connected"))
            continue;
        snprintf(path, sizeof(path), "%s/enabled", base);
        if (!text_equals(path, "enabled"))
            continue;
        snprintf(path, sizeof(path), "%s/edid", base);
        if (!edid_has_dolby_vision(path))
            continue;
        if (++matches != 1)
            continue;
        snprintf(out->connector, sizeof(out->connector), "%s", base);
        const char *dash = strchr(entry->d_name, '-');
        if (!dash || (size_t)(dash - entry->d_name) >= sizeof(out->card))
            continue;
        memcpy(out->card, entry->d_name, (size_t)(dash - entry->d_name));
        out->card[dash - entry->d_name] = 0;
        snprintf(path, sizeof(path), "%s/connector_id", base);
        char id[32] = {0};
        if (!read_small_file(path, id, sizeof(id) - 1, NULL))
            continue;
        out->connector_id = (unsigned)strtoul(id, NULL, 10);
    }
    closedir(dir);
    if (matches != 1) {
        fprintf(stderr, "Expected exactly one enabled Dolby Vision HDMI output; found %d\n",
                matches);
        return -1;
    }
    return 0;
}

static int find_i915_pipe(struct output *out)
{
    unsigned card_number;
    if (sscanf(out->card, "card%u", &card_number) != 1)
        return -1;
    char path[PATH_MAX];
    snprintf(path, sizeof(path), "/sys/kernel/debug/dri/%u/i915_display_info",
             card_number);
    FILE *file = fopen(path, "r");
    if (!file) {
        fprintf(stderr, "Cannot read %s: %s\n", path, strerror(errno));
        return -1;
    }
    char line[2048];
    char current_pipe = 0;
    unsigned current_bpp = 0;
    bool found = false;
    while (fgets(line, sizeof(line), file)) {
        char pipe;
        if (sscanf(line, "[CRTC:%*u:pipe %c]", &pipe) == 1) {
            current_pipe = pipe;
            current_bpp = 0;
            continue;
        }
        char *bpp = strstr(line, "bpp=");
        if (current_pipe && bpp)
            current_bpp = (unsigned)strtoul(bpp + 4, NULL, 10);
        unsigned connector_id;
        if (current_pipe && sscanf(line, " [CONNECTOR:%u:", &connector_id) == 1 &&
            connector_id == out->connector_id) {
            out->pipe = current_pipe;
            out->bpp = current_bpp;
            found = true;
            break;
        }
    }
    fclose(file);
    if (!found || out->pipe < 'A' || out->pipe > 'D') {
        fprintf(stderr, "Cannot associate connector %u with an active i915 pipe\n",
                out->connector_id);
        return -1;
    }
    if (out->bpp < 30) {
        fprintf(stderr, "Refusing Dolby Vision on %u-bpp scanout (30 bpp required)\n",
                out->bpp);
        return -1;
    }
    return 0;
}

static int resource_path(const struct output *out, char path[PATH_MAX])
{
    char device[PATH_MAX], resolved[PATH_MAX], vendor[PATH_MAX], value[32] = {0};
    snprintf(device, sizeof(device), "/sys/class/drm/%s/device", out->card);
    if (!realpath(device, resolved))
        return -1;
    snprintf(vendor, sizeof(vendor), "%s/vendor", resolved);
    if (!read_small_file(vendor, value, sizeof(value) - 1, NULL) ||
        strtoul(value, NULL, 0) != 0x8086) {
        fprintf(stderr, "Active HDMI output is not driven by an Intel GPU\n");
        return -1;
    }
    snprintf(path, PATH_MAX, "%s/resource0", resolved);
    return 0;
}

static inline uint32_t mmio_read(volatile uint8_t *mmio, unsigned reg)
{
    uint32_t value = *(volatile uint32_t *)(mmio + reg);
    __sync_synchronize();
    return value;
}

static inline void mmio_write(volatile uint8_t *mmio, unsigned reg,
                              uint32_t value)
{
    *(volatile uint32_t *)(mmio + reg) = value;
    __sync_synchronize();
    (void)*(volatile uint32_t *)(mmio + reg);
}

static uint8_t avi_checksum(uint32_t packet[INFOFRAME_DWORDS])
{
    uint8_t *bytes = (uint8_t *)packet;
    unsigned sum = bytes[0] + bytes[1] + bytes[2];
    for (unsigned i = 0; i < 13; ++i)
        sum += bytes[5 + i];
    return (uint8_t)(0u - sum);
}

static bool process_alive(pid_t pid)
{
    return pid <= 0 || kill(pid, 0) == 0 || errno == EPERM;
}

int main(int argc, char **argv)
{
    pid_t watched_pid = 0;
    unsigned duration = 0;
    for (int i = 1; i < argc; ++i) {
        if (!strcmp(argv[i], "--pid") && i + 1 < argc)
            watched_pid = (pid_t)strtol(argv[++i], NULL, 10);
        else if (!strcmp(argv[i], "--duration") && i + 1 < argc)
            duration = (unsigned)strtoul(argv[++i], NULL, 10);
        else {
            fprintf(stderr, "Usage: %s [--pid PID] [--duration SECONDS]\n", argv[0]);
            return 2;
        }
    }
    if (geteuid() != 0) {
        fprintf(stderr, "This narrowly scoped display helper must run as root\n");
        return 1;
    }

    int lock_fd = open("/run/powervlc-intel-dovi.lock",
                       O_RDWR | O_CREAT | O_CLOEXEC, 0600);
    if (lock_fd < 0 || flock(lock_fd, LOCK_EX | LOCK_NB) != 0) {
        fprintf(stderr, "Another PowerVLC Dolby Vision helper is active\n");
        return 1;
    }

    struct output output = {0};
    if (find_dolby_output(&output) || find_i915_pipe(&output))
        return 1;

    char resource[PATH_MAX];
    if (resource_path(&output, resource))
        return 1;
    int fd = open(resource, O_RDWR | O_SYNC | O_CLOEXEC);
    if (fd < 0) {
        fprintf(stderr, "Cannot open Intel display MMIO: %s\n", strerror(errno));
        return 1;
    }
    volatile uint8_t *mmio = mmap(NULL, MAP_SIZE, PROT_READ | PROT_WRITE,
                                  MAP_SHARED, fd, 0);
    if (mmio == MAP_FAILED) {
        fprintf(stderr, "Cannot map Intel display MMIO: %s\n", strerror(errno));
        close(fd);
        return 1;
    }

    unsigned delta = (unsigned)(output.pipe - 'A') * 0x1000u;
    unsigned ctl_reg = 0x60200u + delta;
    unsigned avi_reg = 0x60220u + delta;
    unsigned vs_reg = 0x60260u + delta;
    uint32_t saved_ctl = mmio_read(mmio, ctl_reg);
    uint32_t saved_avi[INFOFRAME_DWORDS], saved_vs[INFOFRAME_DWORDS];
    for (unsigned i = 0; i < INFOFRAME_DWORDS; ++i) {
        saved_avi[i] = mmio_read(mmio, avi_reg + i * 4);
        saved_vs[i] = mmio_read(mmio, vs_reg + i * 4);
    }
    if ((saved_ctl & (AVI_ENABLE | VENDOR_ENABLE)) !=
        (AVI_ENABLE | VENDOR_ENABLE) ||
        (saved_avi[0] & 0x00ffffffu) != 0x000d0282u ||
        (saved_vs[0] & 0x0000ffffu) != 0x00000181u) {
        fprintf(stderr, "Unsupported Intel HDMI InfoFrame layout; no register was written\n");
        munmap((void *)mmio, MAP_SIZE);
        close(fd);
        return 1;
    }

    uint32_t avi[INFOFRAME_DWORDS];
    memcpy(avi, saved_avi, sizeof(avi));
    uint8_t *avi_bytes = (uint8_t *)avi;
    avi_bytes[6] |= 0xc0u; /* extended colorimetry; preserve aspect/range */
    avi_bytes[7] |= 0x60u; /* BT.2020 RGB; preserve quantization/content */
    avi_bytes[4] = 0;
    avi_bytes[4] = avi_checksum(avi);

    const uint32_t dolby_vs[INFOFRAME_DWORDS] = {
        0x001b0181u, 0x00d0464au, 0x00000003u, 0, 0, 0, 0, 0
    };

    signal(SIGINT, stop_handler);
    signal(SIGTERM, stop_handler);
    signal(SIGHUP, stop_handler);

    mmio_write(mmio, ctl_reg, saved_ctl & ~(AVI_ENABLE | VENDOR_ENABLE));
    for (unsigned i = 0; i < INFOFRAME_DWORDS; ++i) {
        mmio_write(mmio, avi_reg + i * 4, avi[i]);
        mmio_write(mmio, vs_reg + i * 4, dolby_vs[i]);
    }
    mmio_write(mmio, ctl_reg, saved_ctl);

    printf("READY connector=%s pipe=%c bpp=%u mode=DolbyVisionLowLatency\n",
           output.connector, output.pipe, output.bpp);
    fflush(stdout);

    time_t deadline = duration ? time(NULL) + duration : 0;
    struct timespec pause = { .tv_sec = 0, .tv_nsec = 200000000 };
    while (!stopping && process_alive(watched_pid) &&
           (!deadline || time(NULL) < deadline))
        nanosleep(&pause, NULL);

    mmio_write(mmio, ctl_reg, saved_ctl & ~(AVI_ENABLE | VENDOR_ENABLE));
    for (unsigned i = 0; i < INFOFRAME_DWORDS; ++i) {
        mmio_write(mmio, avi_reg + i * 4, saved_avi[i]);
        mmio_write(mmio, vs_reg + i * 4, saved_vs[i]);
    }
    mmio_write(mmio, ctl_reg, saved_ctl);
    printf("RESTORED connector=%s pipe=%c\n", output.connector, output.pipe);

    munmap((void *)mmio, MAP_SIZE);
    close(fd);
    close(lock_fd);
    return 0;
}
