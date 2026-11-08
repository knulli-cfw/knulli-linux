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
#include <limits.h>

#include "progressbar_common.h"

int screenWidth = 0;
int screenHeight = 0;

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
    // one image for every board: the logo that matches the panel, if there is one
    char logoPath[64];
    snprintf(logoPath, sizeof(logoPath), "/boot/bootlogo-%ux%u.bmp", vinfo.xres, vinfo.yres);
    if (access(logoPath, R_OK) != 0)
        strcpy(logoPath, "/boot/bootlogo.bmp");
    SDL_Surface* bgSurface = SDL_LoadBMP(logoPath);
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
    SDL_Texture *text_texture = NULL;
    SDL_Rect text_location = {50, screenHeight - 90, 0, 0};
    const char *text_for = NULL;   // the label text_texture was rendered from

    // Logo, plus label and bar unless overlay is false (the last frame: a bare
    // logo is a cleaner hand-off to ES than a frozen 100% bar).
    auto render_frame = [&](const char *description, int pct, bool overlay = true) {
        SDL_SetRenderDrawColor(renderer, 0, 0, 0, 255);
        SDL_RenderClear(renderer);
        SDL_RenderCopy(renderer, bgTexture, NULL, NULL);
        if (overlay) {
            if (description != text_for) {
                if (text_texture) SDL_DestroyTexture(text_texture);
                text_texture = NULL;
                SDL_Surface *ts = TTF_RenderText_Solid(font, description, textColor);
                if (ts) {
                    text_texture = SDL_CreateTextureFromSurface(renderer, ts);
                    SDL_FreeSurface(ts);
                    SDL_QueryTexture(text_texture, NULL, NULL, &text_location.w, &text_location.h);
                }
                text_for = description;
            }
            if (text_texture)
                SDL_RenderCopy(renderer, text_texture, NULL, &text_location);
            draw_progress_bar(renderer, pct);
        }
        SDL_RenderPresent(renderer);
    };

    // Main loop: the progress model lives in progressbar_common.h.
    BootProgress progress;
    for (;;) {
        if (progress.update())
            render_frame(progress.description(), progress.percent());
        if (progress.done())
            break;
        SDL_Delay(BootProgress::TICK_MS);
    }
    render_frame(NULL, 0, false);

    if (text_texture) SDL_DestroyTexture(text_texture);
    SDL_DestroyTexture(bgTexture);
    SDL_DestroyRenderer(renderer);
    SDL_DestroyWindow(window);
    TTF_CloseFont(font);
    TTF_Quit();
    SDL_Quit();
    return 0;
}
