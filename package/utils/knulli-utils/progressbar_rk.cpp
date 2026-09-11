// progressbar_rk — Rockchip (rk3566 et al.) variant of progressbar.
//
// Why a separate binary: on the Rockchip DRM stack SDL2 defaults to the KMSDRM
// video driver, which renders to its own DRM plane that is NOT scanned out
// during early boot (the fbcon/DRM-fbdev plane owns the CRTC). The result is a
// blank screen until EmulationStation takes over. The generic progressbar.cpp
// (SDL window + accelerated renderer) therefore shows nothing here.
//
// This variant renders EVERYTHING with SDL software surfaces and then blits the
// composed frame straight to /dev/fb0 (exactly like fbv does for the boot
// splash), which IS the on-screen surface during boot. It also:
//   * waits for /dev/fb0 to be ready (rcS can launch us before the panel is up),
//   * supports the dynamic per-resolution logos (bootlogo.bmp, else
//     logo_<W>x<H>.bmp).
// It intentionally does not create an SDL window/renderer, so it does not depend
// on KMSDRM/GLES being usable during boot.

#include <SDL2/SDL.h>
#include <SDL2/SDL_ttf.h>
#include <SDL2/SDL2_rotozoom.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <errno.h>
#include <ctype.h>
#include <linux/fb.h>
#include <sys/mman.h>
#include <time.h>
#include <dirent.h>

// Milliseconds between two monotonic timestamps.
static double ms_between(const struct timespec *a, const struct timespec *b) {
    return (b->tv_sec - a->tv_sec) * 1000.0 + (b->tv_nsec - a->tv_nsec) / 1e6;
}

// Is EmulationStation running yet? rcS is non-linear (background + linear
// scripts), so /tmp/status.txt is not a reliable "boot done" signal. The real
// event we care about — "ES is about to take the screen" — is best detected by
// the emulationstation process appearing. /proc/<pid>/comm is truncated to 15
// chars ("emulationstatio").
static bool es_running() {
    DIR *d = opendir("/proc");
    if (!d)
        return false;
    struct dirent *e;
    bool found = false;
    while (!found && (e = readdir(d))) {
        if (e->d_name[0] < '0' || e->d_name[0] > '9')
            continue;
        char path[286];
        snprintf(path, sizeof(path), "/proc/%s/comm", e->d_name);
        FILE *f = fopen(path, "r");
        if (!f)
            continue;
        char comm[64] = "";
        if (fgets(comm, sizeof(comm), f) && strncmp(comm, "emulationstatio", 15) == 0)
            found = true;
        fclose(f);
    }
    closedir(d);
    return found;
}
#include <iostream>
#include <fcntl.h>
#include <unistd.h>
#include <signal.h>
#include <sys/ioctl.h>
#include <limits.h>

const int MAX_SCRIPT_NUM = 99;

typedef struct {
    char *script_name;
    char *description;
} ScriptMapping;

int screenWidth = 0;
int screenHeight = 0;

ScriptMapping oscript_descriptions[] = {
    {"S00bootcustom", "Running custom boot processes..."},
    {"S01date", "Setting up system date..."},
    {"S01dbus", "Starting D-Bus system message bus..."},
    {"S01syslogd", "Starting system logger..."},
    {"S02generate-capability", "Allocating Skill Points..."},
    {"S02ldconfig", "Updating shared library cache..."},
    {"S02resize", "Resizing filesystem..."},
    {"S02sysctl", "Applying system control parameters..."},
    {"S03modules", "Loading kernel modules..."},
    {"S03urandom", "Saving random seed..."},
    {"S04populate", "Populating system files..."},
    {"S05avahi-setup.sh", "Setting up Avahi daemon..."},
    {"S05udev", "Starting udev device manager..."},
    {"S06audio", "Initializing audio system..."},
    {"S06modprobe", "Loading system modules..."},
    {"S07network", "Setting up network configurations..."},
    {"S08connman", "Starting network manager..."},
    {"S09rg28xx", "Initializing RG28XX hardware..."},
    {"S11share", "Resizing SHARE partition..."},
    {"S12legacy-migrate", "Migrating legacy data..."},
    {"S12populateshare", "Populating SHARE partition..."},
    {"S18governor", "Configuring CPU governor..."},
    {"S19cpufreq", "Setting CPU frequency policy..."},
    {"S21batteryplus-daemon", "Starting battery daemon..."},
    {"S21batteryplus-state", "Restoring battery state..."},
    {"S25powerled", "Configuring power LED..."},
    {"S25silky-rgb", "Initializing RGB lighting..."},
    {"S26system", "Initializing system settings..."},
    {"S27audioconfig", "Configuring audio settings..."},
    {"S27brightness", "Adjusting screen brightness..."},
    {"S27debugmount", "Mounting debug filesystem..."},
    {"S27displaysettings", "Applying display settings..."},
    {"S28usbmode", "Configuring USB mode..."},
    {"S29namebluetooth", "Setting Bluetooth device name..."},
    {"S31emulationstation", "Launching Emulation Station..."},
    {"S31sixad", "Starting SixAxis controller daemon..."},
    {"S32bluetooth", "Starting Bluetooth service..."},
    {"S33rngd", "Starting hardware RNG daemon..."},
    {"S34hwclock", "Syncing hardware clock..."},
    {"S35securepasswd", "Securing system passwords..."},
    {"S49ntp", "Synchronizing network time..."},
    {"S50avahi-daemon", "Starting Avahi mDNS daemon..."},
    {"S50triggerhappy", "Starting input event daemon..."},
    {"S60nfs", "Starting NFS service..."},
    {"S65values4boot", "Applying boot-time values..."},
    {"S80dnsmasq", "Starting DNS/DHCP server..."},
    {"S96idlewatcher-daemon", "Starting idle watcher..."},
    {"S97stats", "Starting system stats collector..."},
    {"S99userservices", "Starting user services..."}
};

ScriptMapping script_descriptions[] = {
    {"S00bootcustom", "Checking for Game Genie..."},
    {"S01date", "Flushing the Chron-o-Johns..."},
    {"S01dbus", "Sending Paperboy on route..."},
    {"S01syslogd", "Clearing the skies for Lakitu..."},
    {"S02generate-capability", "Unlocking hidden character abilities..."},
    {"S02ldconfig", "Cataloguing the Goblin Library..."},
    {"S02resize", "Extending the Bridge to Zeal..."},
    {"S02sysctl", "Adjusting Mode 7 perspective..."},
    {"S03modules", "Summoning the Knights of Round..."},
    {"S03urandom", "Shuffling the Tetriminos..."},
    {"S04populate", "Deploying Kremlings..."},
    {"S05avahi-setup.sh", "Scanning for Shadaloo hideouts..."},
    {"S05udev", "Connecting the Power Glove..."},
    {"S06audio", "Drafting notes for Bobbin..."},
    {"S06modprobe", "Equipping the Master Sword..."},
    {"S07network", "Connecting Link Cable..."},
    {"S08connman", "Blowing the Warp Whistle..."},
    {"S09rg28xx", "Calibrating the Falcon Flyer..."},
    {"S11share", "Adjusting the borders of Enroth..."},
    {"S12legacy-migrate", "Transferring save data from cartridge..."},
    {"S12populateshare", "Hiding coins in Donut Plains..."},
    {"S18governor", "Re-electing Governor Marley..."},
    {"S19cpufreq", "Engaging Turbo Mode..."},
    {"S21batteryplus-daemon", "Synthesizing Chaos Emeralds..."},
    {"S21batteryplus-state", "Checking battery in the Arwing..."},
    {"S25powerled", "Lighting up the Triforce..."},
    {"S25silky-rgb", "Dispersing jam on Rainbow Road..."},
    {"S26system", "Saving at the Ink Ribbon..."},
    {"S27audioconfig", "Tuning the Codec..."},
    {"S27brightness", "Calibrating the Lens of Truth..."},
    {"S27debugmount", "Opening the Debug Menu..."},
    {"S27displaysettings", "Adjusting the viewfinder on Samus suit..."},
    {"S28usbmode", "Plugging in the ASCII Pad..."},
    {"S29namebluetooth", "Registering with the G-Diffuser system..."},
    {"S31emulationstation", "Welcome to the Fantasy Zone!"},
    {"S31sixad", "Syncing DualShock to Player 1..."},
    {"S32bluetooth", "Searching for Player 2 controller..."},
    {"S33rngd", "Consulting the Magic 8-Ball..."},
    {"S34hwclock", "Setting the clock in Termina..."},
    {"S35securepasswd", "Locking Bowser in his castle..."},
    {"S49ntp", "Syncing with the Epoch Clock Tower..."},
    {"S50avahi-daemon", "Broadcasting on all frequencies..."},
    {"S50triggerhappy", "Waiting for the button prompt..."},
    {"S60nfs", "Mounting the Hyrule Field map..."},
    {"S65values4boot", "Loading save file..."},
    {"S80dnsmasq", "Asking the Town Elder for directions..."},
    {"S96idlewatcher-daemon", "Watching for AFK players..."},
    {"S97stats", "Calculating final score..."},
    {"S99userservices", "Handing controller to Player 1..."}
};

const char* get_script_basename(const char *script_path) {
    const char *slash = strrchr(script_path, '/');  // Find the last '/' character
    if (slash) {
        return slash + 1;  // Return the substring after the last '/'
    }
    return script_path;  // Return the original path if no '/' found
}

int get_script_number(const char *script_path) {
    const char *script_name = get_script_basename(script_path);
    if (!isdigit(script_name[1]) || script_name[0] != 'S') {
        // Check that the script name starts with 'S' and is followed by a digit
        return -1;  // Return -1 to indicate an invalid script name
    }
    int number = 0;
    while (*script_name && !isdigit(*script_name)) ++script_name;
    sscanf(script_name, "%d", &number);
    return number;
}

float calculate_percentage(const char *script_path) {
    int script_number = get_script_number(script_path);
    if (script_number == -1) {
        return -1;  // Return -1 to indicate that the percentage should not be calculated
    }
    return script_number * 100.0 / MAX_SCRIPT_NUM;
}

const char* get_description(const char *script_path) {
    const char *script_name = get_script_basename(script_path);
    int num_scripts = sizeof(script_descriptions) / sizeof(script_descriptions[0]);
    for (int i = 0; i < num_scripts; i++) {
        if (strcmp(script_descriptions[i].script_name, script_name) == 0) {
            return script_descriptions[i].description;
        }
    }
    return "Unknown process...";
}

// Draw the progress bar onto a software surface (no SDL_Renderer here).
void draw_progress_bar(SDL_Surface *dst, int percentage) {
    int progressBarWidth = screenWidth - 100;
    int progressBarHeight = 10;
    int progressBarX = 50;
    int progressBarY = screenHeight - 60;

    // Background track (dark, full width)
    SDL_Rect track = {progressBarX, progressBarY, progressBarWidth, progressBarHeight};
    SDL_FillRect(dst, &track, SDL_MapRGB(dst->format, 40, 40, 40));

    // Filled bar
    SDL_Rect bar = {progressBarX, progressBarY, (progressBarWidth) * percentage / 100, progressBarHeight};
    SDL_FillRect(dst, &bar, SDL_MapRGB(dst->format, 82, 91, 24));
}

// Wait for the graphics/framebuffer to come up. On rk3566 the DRM fbdev
// (/dev/fb0) is created only after the display pipeline + panel have probed,
// which can happen AFTER rcS launches us. Poll until FBIOGET_VSCREENINFO
// returns a sane non-zero mode (best-effort with a generous timeout).
static bool wait_for_framebuffer(struct fb_var_screeninfo *vinfo) {
    const int max_wait_ms = 30000;
    const int step_ms     = 50;
    int waited = 0;

    for (;;) {
        int fbfd = open("/dev/fb0", O_RDWR);
        if (fbfd != -1) {
            if (ioctl(fbfd, FBIOGET_VSCREENINFO, vinfo) == 0 &&
                vinfo->xres > 0 && vinfo->yres > 0) {
                close(fbfd);
                return true;
            }
            close(fbfd);
        }
        if (waited >= max_wait_ms) {
            std::cerr << "Warning: /dev/fb0 not ready after " << max_wait_ms
                      << "ms; proceeding anyway." << std::endl;
            return false;
        }
        usleep(step_ms * 1000);
        waited += step_ms;
    }
}

/*
 * Boot logo lookup, in preference order:
 *
 *   /boot/bootlogo.bmp        - what every other board ships
 *   /boot/logos/bootlogo.bmp
 *   <dir>/logo_<W>x<H>.bmp    - rk3326 keeps a per-panel set under logos/,
 *                               named by the panel's native resolution, which
 *                               is also the framebuffer geometry here
 *   <dir>/logo.bmp            - last resort; GO2 (320x480) and GO3 (480x854)
 *                               have no sized file, so they land on this one
 *                               and get scaled
 */
static SDL_Surface* load_boot_logo(int fbWidth, int fbHeight) {
    static const char *dirs[] = { "/boot", "/boot/logos" };
    const char *names[3];
    char sized[64];
    char path[PATH_MAX];

    snprintf(sized, sizeof(sized), "logo_%dx%d.bmp", fbWidth, fbHeight);
    names[0] = "bootlogo.bmp";
    names[1] = sized;
    names[2] = "logo.bmp";

    for (size_t n = 0; n < sizeof(names) / sizeof(names[0]); n++) {
        for (size_t d = 0; d < sizeof(dirs) / sizeof(dirs[0]); d++) {
            snprintf(path, sizeof(path), "%s/%s", dirs[d], names[n]);
            SDL_Surface* s = SDL_LoadBMP(path);
            if (s) {
                if (n != 0)
                    fprintf(stderr, "bootlogo.bmp not found; using %s\n", path);
                return s;
            }
        }
    }

    fprintf(stderr, "Could not load bootlogo.bmp, %s or logo.bmp "
            "from /boot or /boot/logos: %s\n", sized, SDL_GetError());
    return NULL;
}

int main(int argc, char *argv[]) {
    // Optional extra rotation (degrees, one of 0/90/180/270) applied to the whole
    // composed frame, on top of the automatic portrait handling. Some panels are
    // mounted rotated relative to how the framebuffer scans out AND ship a boot
    // logo BMP that is pre-rotated to compensate (so a direct blit looks correct),
    // while our programmatically-drawn bar/text are not — e.g. the RG ARC-S, whose
    // logo is upright but whose bar comes out upside down (needs --rotate 180).
    // We fold the extra rotation into the present step and pre-rotate the logo by
    // the inverse so the logo stays correct and only the overlay is re-oriented.
    // rcS knows the board, so it passes the right value per device.
    int extra_deg = 0;
    for (int i = 1; i < argc; i++) {
        if (strcmp(argv[i], "--rotate") == 0 && i + 1 < argc)
            extra_deg = atoi(argv[++i]);
        else if (strncmp(argv[i], "--rotate=", 9) == 0)
            extra_deg = atoi(argv[i] + 9);
    }
    extra_deg = ((extra_deg % 360) + 360) % 360;
    if (extra_deg % 90 != 0) {
        fprintf(stderr, "--rotate must be 0/90/180/270; ignoring %d\n", extra_deg);
        extra_deg = 0;
    }

    // We only use SDL for offscreen surface composition (BMP/TTF/rotozoom) and
    // blit the result to /dev/fb0 ourselves, so we do NOT initialize the video
    // subsystem. That is deliberate: this SDL2 build has no usable headless
    // video driver (no "dummy"), and the real ones (KMSDRM) don't scan out during
    // early boot. SDL_Init(0) gives us surfaces/blitting without any display.
    if (SDL_Init(0) < 0) {
        fprintf(stderr, "Could not initialize SDL: %s\n", SDL_GetError());
        return 1;
    }

    // Wait for the framebuffer to be ready and read its geometry.
    struct fb_var_screeninfo vinfo;
    memset(&vinfo, 0, sizeof(vinfo));
    wait_for_framebuffer(&vinfo);

    if (TTF_Init() == -1) {
        fprintf(stderr, "Could not initialize SDL_ttf: %s\n", TTF_GetError());
        SDL_Quit();
        return 1;
    }

    // Open + mmap /dev/fb0 for direct blitting.
    int fbfd = open("/dev/fb0", O_RDWR);
    if (fbfd == -1) {
        std::cerr << "Error: cannot open framebuffer device." << std::endl;
        TTF_Quit();
        SDL_Quit();
        return 1;
    }

    struct fb_fix_screeninfo finfo;
    if (ioctl(fbfd, FBIOGET_VSCREENINFO, &vinfo) ||
        ioctl(fbfd, FBIOGET_FSCREENINFO, &finfo)) {
        std::cerr << "Error: reading framebuffer information." << std::endl;
        close(fbfd);
        TTF_Quit();
        SDL_Quit();
        return 1;
    }

    const int fb_bpp = vinfo.bits_per_pixel / 8;
    size_t fb_size = (size_t)finfo.line_length * vinfo.yres;
    unsigned char *fbmem = (unsigned char*)mmap(NULL, fb_size,
                                                PROT_READ | PROT_WRITE, MAP_SHARED, fbfd, 0);
    if (fbmem == MAP_FAILED) {
        std::cerr << "Error: cannot mmap framebuffer." << std::endl;
        close(fbfd);
        TTF_Quit();
        SDL_Quit();
        return 1;
    }

    // Logical (landscape) dimensions we compose in. For portrait panels the
    // physical framebuffer is taller than wide; we compose landscape then rotate
    // the finished frame to physical orientation before blitting.
    const bool portrait_fb = (vinfo.xres < vinfo.yres);
    screenWidth  = portrait_fb ? vinfo.yres : vinfo.xres;
    screenHeight = portrait_fb ? vinfo.xres : vinfo.yres;

    // Rotation from our logical (landscape) frame to the physical panel:
    //   present_rot = base (90 for portrait panels, 0 otherwise) + the extra
    //                 per-board correction from --rotate.
    // The logo BMP is authored physical-oriented (a direct blit looks correct), so
    // pre-rotate it by the inverse of present_rot: after the present rotation the
    // logo nets back to correct while the overlay (bar/text) picks up present_rot.
    const int present_rot = (((portrait_fb ? 90 : 0) + extra_deg) % 360 + 360) % 360;
    const int logo_rot     = (360 - present_rot) % 360;

    // Build the background logo, pre-scaled to the logical dimensions.
    SDL_Surface *logo = NULL;
    {
        SDL_Surface *raw = load_boot_logo(vinfo.xres, vinfo.yres);
        if (raw) {
            SDL_Surface *oriented = raw;
            if (logo_rot != 0) {
                SDL_Surface *r = rotozoomSurface(raw, logo_rot, 1.0, 0);
                if (r) oriented = r;
            }
            logo = SDL_CreateRGBSurfaceWithFormat(0, screenWidth, screenHeight, 32,
                                                  SDL_PIXELFORMAT_ARGB8888);
            if (logo) {
                SDL_FillRect(logo, NULL, SDL_MapRGB(logo->format, 0, 0, 0));
                SDL_BlitScaled(oriented, NULL, logo, NULL);
            }
            if (oriented != raw) SDL_FreeSurface(oriented);
            SDL_FreeSurface(raw);
        }
    }

    // The frame we compose each update into (logical orientation).
    SDL_Surface *frame = SDL_CreateRGBSurfaceWithFormat(0, screenWidth, screenHeight, 32,
                                                        SDL_PIXELFORMAT_ARGB8888);
    if (!frame) {
        fprintf(stderr, "Could not create frame surface: %s\n", SDL_GetError());
        if (logo) SDL_FreeSurface(logo);
        munmap(fbmem, fb_size);
        close(fbfd);
        TTF_Quit();
        SDL_Quit();
        return 1;
    }

    TTF_Font *font = TTF_OpenFont("/usr/share/fonts/dejavu/DejaVuSans-Bold.ttf", 18);
    if (!font) {
        fprintf(stderr, "Failed to open font: %s\n", TTF_GetError());
        SDL_FreeSurface(frame);
        if (logo) SDL_FreeSurface(logo);
        munmap(fbmem, fb_size);
        close(fbfd);
        TTF_Quit();
        SDL_Quit();
        return 1;
    }

    SDL_Color textColor = {255, 255, 255};

    char text[240];
    char line[256];
    FILE *file;
    int running = 1;

    // When U-Boot hands its splash over to the kernel (drm-logo route
    // properties), the kernel keeps scanning out U-Boot's framebuffer and the
    // fbdev buffer we draw into is not on the plane until some DRM commit puts
    // it there -- which used to be ES, minutes later.  One FBIOPAN_DISPLAY at
    // offset 0 is that commit: a plane flip from the logo buffer to ours, on a
    // CRTC and panel that stay exactly as they are.  Our first frame is the same
    // logo, so the flip is invisible.  Harmless when there was no handover.
    bool fb_claimed = false;

    // Copy a physical-oriented surface straight into the mmap'd framebuffer,
    // honouring the line stride and x/y pan offsets.
    auto blit_to_fb = [&](SDL_Surface *phys) {
        if (SDL_LockSurface(phys) != 0) return;
        unsigned int rows = (vinfo.yres < (unsigned)phys->h) ? vinfo.yres : (unsigned)phys->h;
        unsigned int cols = (vinfo.xres < (unsigned)phys->w) ? vinfo.xres : (unsigned)phys->w;
        size_t row_bytes = (size_t)cols * fb_bpp;
        for (unsigned int y = 0; y < rows; ++y) {
            unsigned char *dst = fbmem
                + (size_t)(y + vinfo.yoffset) * finfo.line_length
                + (size_t)vinfo.xoffset * fb_bpp;
            unsigned char *src = (unsigned char*)phys->pixels + (size_t)y * phys->pitch;
            memcpy(dst, src, row_bytes);
        }
        SDL_UnlockSurface(phys);

        // Present. This DRM fbdev uses deferred-IO: mmap writes land in a shadow
        // buffer that is only pushed to the panel when the deferred work runs.
        // fsync() on the fb fd triggers fb_deferred_io_fsync(), which flushes our
        // dirty pages to the display immediately — per frame, and WITHOUT
        // disturbing the mmap (FBIOPAN_DISPLAY is a no-op on this single-buffer
        // fb, and FBIOPUT_VSCREENINFO reallocates the buffer and breaks mmap).
        fsync(fbfd);

        if (!fb_claimed) {
            fb_claimed = true;
            if (ioctl(fbfd, FBIOPAN_DISPLAY, &vinfo) != 0)
                std::cerr << "Warning: FBIOPAN_DISPLAY failed: "
                          << strerror(errno) << std::endl;
        }
    };

    // Compose the logical frame (logo [+ text + bar]) and present it to /dev/fb0,
    // rotating to physical orientation first on portrait panels. With overlay ==
    // false only the logo is drawn (no text, no bar) — used for the final frame so
    // the framebuffer is left showing a clean splash while ES/RetroArch take over.
    auto render_frame = [&](const char *description, int pct, bool overlay = true) {
        SDL_FillRect(frame, NULL, SDL_MapRGB(frame->format, 0, 0, 0));
        if (logo)
            SDL_BlitSurface(logo, NULL, frame, NULL);

        if (overlay) {
            SDL_Surface *ts = TTF_RenderText_Solid(font, description, textColor);
            if (ts) {
                SDL_Rect tl = {50, screenHeight - 90, 0, 0};
                SDL_BlitSurface(ts, NULL, frame, &tl);
                SDL_FreeSurface(ts);
            }

            draw_progress_bar(frame, pct);
        }

        if (present_rot != 0) {
            SDL_Surface *rot = rotozoomSurface(frame, present_rot, 1.0, 0);
            if (rot) {
                SDL_Surface *phys = SDL_CreateRGBSurfaceWithFormat(0, vinfo.xres, vinfo.yres,
                                                                   32, SDL_PIXELFORMAT_ARGB8888);
                if (phys) {
                    SDL_FillRect(phys, NULL, SDL_MapRGB(phys->format, 0, 0, 0));
                    SDL_Rect dr = {((int)vinfo.xres - rot->w) / 2,
                                   ((int)vinfo.yres - rot->h) / 2, rot->w, rot->h};
                    SDL_BlitSurface(rot, NULL, phys, &dr);
                    blit_to_fb(phys);
                    SDL_FreeSurface(phys);
                }
                SDL_FreeSurface(rot);
            }
        } else {
            blit_to_fb(frame);
        }
    };

    // Main loop.
    //
    // We POLL /tmp/status.txt (not inotify-on-/tmp): during early boot /tmp is
    // flooded with writes from other services, which drowns a directory watch and
    // makes us miss status.txt updates. Polling the single file is immune to that.
    //
    // rcS is NON-LINEAR (mix of blocking and backgrounded scripts), so
    // /tmp/status.txt is not a reliable progress signal: it is non-monotonic, it
    // dwells only on the blocking scripts (dbus, udev), and QUIT is written by the
    // linear flow while backgrounded scripts are still updating status after it.
    // So we do NOT drive the bar from status.txt.
    //
    //  * Bar position: a smooth time climb to at most 90% (always moving, never
    //    frozen), then eased to 100% once EmulationStation is actually launching.
    //  * Completion is keyed on the emulationstation PROCESS appearing (the real
    //    "about to take the screen" event), then a short ease over its load ->
    //    display window, so 100% "Handing controller to Player 1..." lands right
    //    about when ES appears regardless of how uneven the boot was.
    //  * status.txt is used ONLY for the flavour label until ES shows up.
    const double PRECLIMB_MS   = 18000.0;  // climb to 90% over this while waiting for ES
    const double COMPLETION_MS = 2500.0;   // ease to 100% over ES load->display window

    struct timespec start;
    clock_gettime(CLOCK_MONOTONIC, &start);

    double shown = 0.0;                        // currently displayed percentage
    const char *description = "Starting up..."; // flavour text
    char last_text[256] = "";
    bool es_seen = false;                       // emulationstation process detected
    struct timespec es_ts;                      // when ES was first detected
    double es_from = -1.0;                      // shown value captured at that moment
    int es_poll = 0;                            // throttles the /proc scan
    int last_shown_int = -1;
    const char *last_desc = NULL;

    while (running) {
        // Flavour label from the latest status.txt line (ignore QUIT). Once ES is
        // detected we stop tracking status.txt and keep the final message.
        if (!es_seen) {
            char cur[256] = "";
            file = fopen("/tmp/status.txt", "r");
            if (file) {
                while (fgets(line, sizeof(line), file))
                    if (line[0] != '\0')
                        snprintf(cur, sizeof(cur), "%s", line);
                fclose(file);
            }
            if (cur[0] != '\0' && strcmp(cur, last_text) != 0) {
                snprintf(last_text, sizeof(last_text), "%s", cur);
                if (strcmp(cur, "QUIT\n") != 0 && sscanf(cur, "%239[^\n]", text) == 1) {
                    const char *d = get_description((const char*)text);
                    if (strcmp(d, "Unknown process...") != 0)
                        description = d;
                }
            }

            // Poll for ES ~4x/sec.
            if (++es_poll >= 5) {
                es_poll = 0;
                if (es_running()) {
                    es_seen = true;
                    clock_gettime(CLOCK_MONOTONIC, &es_ts);
                    description = get_description("S99userservices");
                }
            }
        }

        struct timespec now;
        clock_gettime(CLOCK_MONOTONIC, &now);

        double goal;
        if (es_seen) {
            if (es_from < 0.0)
                es_from = shown;
            double since = ms_between(&es_ts, &now);
            goal = es_from + (100.0 - es_from) * (since / COMPLETION_MS);
            if (goal > 100.0)
                goal = 100.0;
        } else {
            goal = ms_between(&start, &now) / PRECLIMB_MS * 90.0;
            if (goal > 90.0)
                goal = 90.0;
        }
        if (goal > shown)
            shown = goal;                       // monotonic

        int si = (int)(shown + 0.5);
        if (si != last_shown_int || description != last_desc) {
            render_frame(description, si);
            last_shown_int = si;
            last_desc = description;
        }

        if (es_seen && shown >= 100.0)
            break;

        usleep(50 * 1000);  // 50 ms
    }

    // Leave the panel showing just the splash logo (no text, no progress bar).
    // We rendered directly to /dev/fb0, so whatever we drew last persists in the
    // framebuffer and is visible during the hand-off to ES/RetroArch until they
    // present their own first frame. A bare logo is a much cleaner transition
    // than a frozen "100% — Handing controller to Player 1..." bar.
    render_frame(NULL, 0, false);

    if (logo) SDL_FreeSurface(logo);
    SDL_FreeSurface(frame);
    munmap(fbmem, fb_size);
    close(fbfd);
    TTF_CloseFont(font);
    TTF_Quit();
    SDL_Quit();
    return 0;
}
