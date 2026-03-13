#include <SDL2/SDL.h>
#include <SDL2/SDL_ttf.h>
#include <SDL2/SDL2_rotozoom.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <ctype.h>
#include <linux/fb.h>
#include <iostream>
#include <fcntl.h>
#include <unistd.h>
#include <signal.h>
#include <sys/ioctl.h>
#include <sys/inotify.h>
#include <sys/select.h>
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

void draw_progress_bar(SDL_Renderer *renderer, int percentage) {
    int progressBarWidth = screenWidth - 100;
    int progressBarHeight = 10;
    int progressBarX = 50;
    int progressBarY = screenHeight - 60;

    // Background track (dark, full width)
    SDL_Rect track = {progressBarX, progressBarY, progressBarWidth, progressBarHeight};
    SDL_SetRenderDrawColor(renderer, 40, 40, 40, 255);
    SDL_RenderFillRect(renderer, &track);

    // Filled bar
    SDL_Rect bar = {progressBarX, progressBarY, (progressBarWidth) * percentage / 100, progressBarHeight};
    SDL_SetRenderDrawColor(renderer, 82, 91, 24, 255);
    SDL_RenderFillRect(renderer, &bar);
}

int main(int argc, char *argv[]) {
    if (SDL_Init(SDL_INIT_VIDEO) < 0) {
        fprintf(stderr, "Could not initialize SDL: %s\n", SDL_GetError());
        return 1;
    }

    if (TTF_Init() == -1) {
        fprintf(stderr, "Could not initialize SDL_ttf: %s\n", TTF_GetError());
        SDL_Quit();
        return 1;
    }

    // Get the framebuffer resolution
    int fbfd = open("/dev/fb0", O_RDWR);
    if (fbfd == -1) {
        std::cerr << "Error: cannot open framebuffer device." << std::endl;
        TTF_Quit();
        SDL_Quit();
        exit(EXIT_FAILURE);
    }

    struct fb_var_screeninfo vinfo;
    if (ioctl(fbfd, FBIOGET_VSCREENINFO, &vinfo)) {
        std::cerr << "Error: reading variable information." << std::endl;
        close(fbfd);
        TTF_Quit();
        SDL_Quit();
        exit(EXIT_FAILURE);
    }

    close(fbfd);

    screenWidth = vinfo.xres;
    screenHeight = vinfo.yres;

    // For rotated displays the framebuffer is portrait but SDL2 handles the
    // rotation at the driver level. We just need to swap w/h so the window
    // matches the logical landscape dimensions SDL will render into.
    if (vinfo.xres < vinfo.yres) {
        screenWidth = vinfo.yres;
        screenHeight = vinfo.xres;
    }

    SDL_SetHint(SDL_HINT_VIDEO_MINIMIZE_ON_FOCUS_LOSS, "0");
    SDL_Window *window = SDL_CreateWindow("Progress Bar", SDL_WINDOWPOS_UNDEFINED, SDL_WINDOWPOS_UNDEFINED, screenWidth, screenHeight, SDL_WINDOW_SHOWN | SDL_WINDOW_FULLSCREEN_DESKTOP | SDL_WINDOW_BORDERLESS);
    if (window == NULL) {
        fprintf(stderr, "Could not create window: %s\n", SDL_GetError());
        TTF_Quit();
        SDL_Quit();
        return 1;
    }

    SDL_Renderer *renderer = SDL_CreateRenderer(window, -1, SDL_RENDERER_ACCELERATED);
    if (renderer == NULL) {
        fprintf(stderr, "Could not create renderer: %s\n", SDL_GetError());
        SDL_DestroyWindow(window);
        TTF_Quit();
        SDL_Quit();
        return 1;
    }

    // Load the background image
    SDL_Surface* bgSurface = SDL_LoadBMP("/boot/bootlogo.bmp");
    if (bgSurface == NULL) {
        fprintf(stderr, "Could not load background image: %s\n", SDL_GetError());
        SDL_DestroyRenderer(renderer);
        SDL_DestroyWindow(window);
        TTF_Quit();
        SDL_Quit();
        return 1;
    }

    // Rotate the surface 90 degrees counter-clockwise on portrait framebuffers.
    // rotozoomSurface may produce a surface slightly larger than the target due
    // to rotation padding, so we blit it centered into a clean surface of the
    // exact target dimensions to avoid any border artifacts.
    if (vinfo.xres < vinfo.yres) {
        SDL_Surface* rotatedSurface = rotozoomSurface(bgSurface, -90, 1.0, 0);
        SDL_FreeSurface(bgSurface);
        bgSurface = NULL;
        if (rotatedSurface == NULL) {
            fprintf(stderr, "Could not rotate surface: %s\n", SDL_GetError());
            SDL_DestroyRenderer(renderer);
            SDL_DestroyWindow(window);
            TTF_Quit();
            SDL_Quit();
            return 1;
        }

        // Blit into a clean surface of exactly screenWidth x screenHeight
        SDL_Surface* clippedSurface = SDL_CreateRGBSurface(0, screenWidth, screenHeight,
            rotatedSurface->format->BitsPerPixel,
            rotatedSurface->format->Rmask,
            rotatedSurface->format->Gmask,
            rotatedSurface->format->Bmask,
            rotatedSurface->format->Amask);
        if (clippedSurface == NULL) {
            fprintf(stderr, "Could not create clipped surface: %s\n", SDL_GetError());
            SDL_FreeSurface(rotatedSurface);
            SDL_DestroyRenderer(renderer);
            SDL_DestroyWindow(window);
            TTF_Quit();
            SDL_Quit();
            return 1;
        }

        // Center the rotated surface in case of any size mismatch
        SDL_Rect dstRect = {
            (screenWidth  - rotatedSurface->w) / 2,
            (screenHeight - rotatedSurface->h) / 2,
            rotatedSurface->w,
            rotatedSurface->h
        };
        SDL_BlitSurface(rotatedSurface, NULL, clippedSurface, &dstRect);
        SDL_FreeSurface(rotatedSurface);
        bgSurface = clippedSurface;
    }

    SDL_Texture* bgTexture = SDL_CreateTextureFromSurface(renderer, bgSurface);
    SDL_FreeSurface(bgSurface);
    if (bgTexture == NULL) {
        fprintf(stderr, "Could not create texture from surface: %s\n", SDL_GetError());
        SDL_DestroyRenderer(renderer);
        SDL_DestroyWindow(window);
        TTF_Quit();
        SDL_Quit();
        return 1;
    }

    TTF_Font *font = TTF_OpenFont("/usr/share/fonts/dejavu/DejaVuSans-Bold.ttf", 18);
    if (!font) {
        fprintf(stderr, "Failed to open font: %s\n", TTF_GetError());
        SDL_DestroyTexture(bgTexture);
        SDL_DestroyRenderer(renderer);
        SDL_DestroyWindow(window);
        TTF_Quit();
        SDL_Quit();
        return 1;
    }

    SDL_Color textColor = {255, 255, 255};
    SDL_Surface *text_surface = NULL;
    SDL_Texture *text_texture = NULL;
    SDL_Rect text_location = {50, screenHeight - 90, 0, 0};

    char text[240];
    int percentage;
    char line[256];
    FILE *file;
    int running = 1;

    // --- inotify setup ---
    // We watch the /tmp directory rather than the file directly. Watching the
    // directory with IN_CLOSE_WRITE | IN_MOVED_TO catches both in-place writes
    // and atomic rename-based writes (write to tmp, then rename into place).
    int inotify_fd = inotify_init1(IN_NONBLOCK);
    if (inotify_fd < 0) {
        perror("inotify_init1");
    }

    int inotify_wd = -1;
    if (inotify_fd >= 0) {
        inotify_wd = inotify_add_watch(inotify_fd, "/tmp",
                                       IN_CLOSE_WRITE | IN_MOVED_TO);
        if (inotify_wd < 0) {
            perror("inotify_add_watch");
            close(inotify_fd);
            inotify_fd = -1;
        }
    }

    // Read and render every line currently in status.txt.
    // Returns false when the main loop should stop.
    auto process_status_file = [&]() -> bool {
        file = fopen("/tmp/status.txt", "r");
        if (file == NULL) return true; // not ready yet, keep waiting

        while (fgets(line, sizeof(line), file)) {
            if (strcmp(line, "QUIT\n") == 0) {
                fclose(file);
                return false;
            }

            if (sscanf(line, "%239[^\n]", text) == 1) {
                percentage = calculate_percentage(text);
                if (percentage == -1) continue;

                const char *description = get_description((const char*)text);
                printf("FOUND LINE: %d: %s\n", percentage, description);
                if (strcmp(description, "Unknown process...") == 0) continue;

                SDL_SetRenderDrawColor(renderer, 0, 0, 0, 255);
                SDL_RenderClear(renderer);
                SDL_RenderCopy(renderer, bgTexture, NULL, NULL);

                if (text_texture) SDL_DestroyTexture(text_texture);
                text_surface = TTF_RenderText_Solid(font, description, textColor);
                text_texture = SDL_CreateTextureFromSurface(renderer, text_surface);
                SDL_FreeSurface(text_surface);
                SDL_QueryTexture(text_texture, NULL, NULL, &text_location.w, &text_location.h);
                SDL_RenderCopy(renderer, text_texture, NULL, &text_location);

                draw_progress_bar(renderer, percentage);
                SDL_RenderPresent(renderer);

                if (percentage >= 100) {
                    fclose(file);
                    return false;
                }
            }
        }
        fclose(file);
        return true;
    };

    // Process whatever lines are already present before entering the wait loop.
    running = process_status_file();

    while (running) {
        if (inotify_fd >= 0) {
            // Block until /tmp sees a write event, with a 2s safety timeout so
            // we never freeze permanently if a notification is somehow missed.
            fd_set read_fds;
            FD_ZERO(&read_fds);
            FD_SET(inotify_fd, &read_fds);
            struct timeval timeout = {2, 0};

            int ret = select(inotify_fd + 1, &read_fds, NULL, NULL, &timeout);
            if (ret > 0) {
                // Drain all pending inotify events and check if any relate to
                // status.txt specifically (ignore chatter from other files).
                char event_buf[sizeof(struct inotify_event) + NAME_MAX + 1];
                bool relevant = false;
                ssize_t len;
                while ((len = read(inotify_fd, event_buf, sizeof(event_buf))) > 0) {
                    struct inotify_event *ev = (struct inotify_event*)event_buf;
                    if (ev->len > 0 && strcmp(ev->name, "status.txt") == 0) {
                        relevant = true;
                    }
                }
                if (!relevant) continue; // spurious event on another /tmp file
            }
            // On timeout (ret == 0) or error (ret < 0) fall through and
            // re-read the file anyway as a safety net.
        } else {
            // inotify unavailable: fall back to original 100ms polling.
            SDL_Delay(100);
        }

        running = process_status_file();
    }

    // Cleanup inotify
    if (inotify_fd >= 0) {
        if (inotify_wd >= 0) inotify_rm_watch(inotify_fd, inotify_wd);
        close(inotify_fd);
    }

    if (text_texture) SDL_DestroyTexture(text_texture);
    SDL_DestroyTexture(bgTexture);
    SDL_DestroyRenderer(renderer);
    SDL_DestroyWindow(window);
    TTF_CloseFont(font);
    TTF_Quit();
    SDL_Quit();
    return 0;
}
