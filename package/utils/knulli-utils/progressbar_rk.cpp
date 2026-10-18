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
#include <SDL2/SDL_image.h>
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

#include <iostream>
#include <fcntl.h>
#include <unistd.h>
#include <signal.h>
#include <sys/ioctl.h>
#include <limits.h>

#include "progressbar_common.h"

int screenWidth = 0;
int screenHeight = 0;

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
 *   /usr/share/knulli/splash/boot-logo-<W>x<H>.png, then boot-logo.png
 *                             - the system-splash images, for boards whose boot
 *                               partition carries no BMP (the Qualcomm ones)
 *
 * --logo <path> (any format SDL_image reads) overrides all of the above.
 */
static const char *logo_override = NULL;

static SDL_Surface* load_boot_logo(int fbWidth, int fbHeight) {
    if (logo_override) {
        SDL_Surface* s = IMG_Load(logo_override);
        if (s)
            return s;
        fprintf(stderr, "Could not load --logo %s: %s\n", logo_override, IMG_GetError());
    }
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

    snprintf(path, sizeof(path), "/usr/share/knulli/splash/boot-logo-%dx%d.png", fbWidth, fbHeight);
    SDL_Surface* png = IMG_Load(path);
    if (!png)
        png = IMG_Load("/usr/share/knulli/splash/boot-logo.png");
    if (png)
        return png;

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
    // --pan: present every frame with FBIOPAN_DISPLAY, for DRM fbdevs whose
    // scanout copy is only refreshed on a commit (the TSP-S kernel rotation).
    int extra_deg = 0;
    bool pan_every_frame = false;
    for (int i = 1; i < argc; i++) {
        if (strcmp(argv[i], "--rotate") == 0 && i + 1 < argc)
            extra_deg = atoi(argv[++i]);
        else if (strncmp(argv[i], "--rotate=", 9) == 0)
            extra_deg = atoi(argv[i] + 9);
        else if (strcmp(argv[i], "--logo") == 0 && i + 1 < argc)
            logo_override = argv[++i];
        else if (strncmp(argv[i], "--logo=", 7) == 0)
            logo_override = argv[i] + 7;
        else if (strcmp(argv[i], "--pan") == 0)
            pan_every_frame = true;
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

    // Rotation from our logical frame to the physical panel:
    //   present_rot = base (90 for portrait panels, 0 otherwise) + the extra
    //                 per-board correction from --rotate.
    // The logo BMP is authored physical-oriented (a direct blit looks correct), so
    // pre-rotate it by the inverse of present_rot: after the present rotation the
    // logo nets back to correct while the overlay (bar/text) picks up present_rot.
    const bool portrait_fb = (vinfo.xres < vinfo.yres);
    const int present_rot = (((portrait_fb ? 90 : 0) + extra_deg) % 360 + 360) % 360;
    const int logo_rot     = (360 - present_rot) % 360;

    // Logical dimensions we compose in: the framebuffer's, swapped when the
    // finished frame is turned by 90/270 (a portrait panel in a landscape
    // device).  A device held upright (--rotate cancelling the base 90)
    // composes portrait.
    const bool swap_dims = (present_rot % 180) != 0;
    screenWidth  = swap_dims ? vinfo.yres : vinfo.xres;
    screenHeight = swap_dims ? vinfo.xres : vinfo.yres;

    // Build the background logo, pre-scaled to the logical dimensions.
    SDL_Surface *logo = NULL;
    {
        SDL_Surface *raw = load_boot_logo(vinfo.xres, vinfo.yres);
        if (raw) {
            SDL_Surface *oriented = raw;
            // A logo whose aspect does not match the framebuffer is the generic
            // landscape fallback (boot-logo.png), already in our logical
            // orientation: present it as-is instead of pre-rotating it.
            const bool logo_physical = ((raw->w < raw->h) == portrait_fb);
            if (logo_rot != 0 && logo_physical) {
                SDL_Surface *r = rotozoomSurface(raw, logo_rot, 1.0, 0);
                if (r) oriented = r;
            }
            logo = SDL_CreateRGBSurfaceWithFormat(0, screenWidth, screenHeight, 32,
                                                  SDL_PIXELFORMAT_ARGB8888);
            if (logo) {
                SDL_FillRect(logo, NULL, SDL_MapRGB(logo->format, 0, 0, 0));
                if ((oriented->w < oriented->h) == (screenWidth < screenHeight)) {
                    SDL_BlitScaled(oriented, NULL, logo, NULL);
                } else {
                    // landscape logo on a portrait frame (or the reverse):
                    // fit it, centred, instead of stretching it
                    SDL_Rect dst;
                    if ((long)screenWidth * oriented->h <= (long)screenHeight * oriented->w) {
                        dst.w = screenWidth;
                        dst.h = (int)((long)oriented->h * screenWidth / oriented->w);
                    } else {
                        dst.h = screenHeight;
                        dst.w = (int)((long)oriented->w * screenHeight / oriented->h);
                    }
                    dst.x = (screenWidth - dst.w) / 2;
                    dst.y = (screenHeight - dst.h) / 2;
                    SDL_BlitScaled(oriented, NULL, logo, &dst);
                }
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

    int running = 1;

    // When U-Boot hands its splash over to the kernel (drm-logo route
    // properties), the kernel keeps scanning out U-Boot's framebuffer and the
    // fbdev buffer we draw into is not on the plane until some DRM commit puts
    // it there -- which used to be ES, minutes later.  One FBIOPAN_DISPLAY at
    // offset 0 is that commit: a plane flip from the logo buffer to ours, on a
    // CRTC and panel that stay exactly as they are.  Our first frame is the same
    // logo, so the flip is invisible.  Harmless when there was no handover.
    bool fb_claimed = false;
    const bool drm_fb = strstr(finfo.id, "drmfb") != NULL;

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

        // Allwinner disp2 fbdev (not DRM): fsync does nothing and a frame only
        // reaches the panel on a pan -- with G2D rotation that is where the
        // rotated copy is made -- so pan every frame there.
        if (!fb_claimed || !drm_fb || pan_every_frame) {
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

    // Main loop: the progress model lives in progressbar_common.h.
    BootProgress progress;
    while (running) {
        if (progress.update())
            render_frame(progress.description(), progress.percent());
        if (progress.done())
            break;
        usleep(BootProgress::TICK_MS * 1000);
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
