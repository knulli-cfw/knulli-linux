#include <SDL/SDL.h>
#include <SDL/SDL_ttf.h>
#include <SDL/SDL_rotozoom.h>
#include <fcntl.h>
#include <linux/input.h>
#include <linux/fb.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <fstream>
#include <iostream>
#include <signal.h>
#include <stdbool.h>
#include <time.h>

#define POWER_SUPPLY_PATH "/sys/class/power_supply/axp2202-battery/" // Path to power supply files
#define INPUT_DEVICE "/dev/input/event0" // Power button input device
#define DISPLAY_TIME 4000 // Time to display the message before sleep (in milliseconds)

// Define return values for different events
enum ButtonPressResult {
    BUTTON_PRESSED,
    TIMEOUT,
    ERROR
};

void putDeviceToSleep() {
    std::ofstream suspendFile("/sys/power/state");
    if (suspendFile.is_open()) {
        std::cout << "System is going to sleep..." << std::endl;
        suspendFile << "mem";
        suspendFile.close();
    } else {
        std::cerr << "Failed to enter sleep mode\n";
    }    
}

void old_shutdownDevice() {
    int result = system("/usr/bin/poweroff.sh");
    if (result != 0) {
        std::cerr << "Failed to execute shutdown script." << std::endl;
        // Handle error
    }
}

void shutdownDevice() {
    // Block all signals to prevent interruption
    sigset_t mask;
    sigfillset(&mask);
    sigprocmask(SIG_BLOCK, &mask, NULL);

    sleep(2); // Give some time before shutdown

    // Check if the script exists and is executable
    std::cout << "Shutting down device..." << std::endl;
    
    // First try the script method
    if (access("/usr/bin/poweroff.sh", X_OK) == 0) {
        int result = system("/usr/bin/poweroff.sh");
        if (result == 0) {
            // Give the script time to work
            sleep(3);
        } else {
            std::cerr << "Script shutdown failed, trying direct method." << std::endl;
        }
    }
    
    // Fallback to direct system calls if script fails
    sync(); // Ensure filesystem is synced before shutdown
    
    // Try direct poweroff command
    if (system("poweroff") != 0) {
        // Last resort - use reboot syscall with LINUX_REBOOT_CMD_POWER_OFF
        if (system("reboot -p") != 0) {
            std::cerr << "All shutdown methods failed!" << std::endl;
        }
    }
    
    // Force exit of our program in case shutdown is delayed
    exit(EXIT_FAILURE);
}

bool checkChargerConnected() {
    char path[1024];
    FILE *fp;
    char buf[1024];
    
    // Check if charger is connected
    snprintf(path, sizeof(path), "%s%s", POWER_SUPPLY_PATH, "status");
    fp = fopen(path, "r");
    if (fp == NULL) {
        fprintf(stderr, "Failed to open status file\n");
        return false; // Assume not connected if we can't open the file
    }
    if (fgets(buf, sizeof(buf), fp) == NULL) {
        fprintf(stderr, "Failed to read status\n");
        fclose(fp);
        return false; // Assume not connected if we can't read the status
    }
    fclose(fp);

    // Check if the status indicates charging or full
    if (strstr(buf, "Charging") != NULL || strstr(buf, "Full") != NULL) {
        std::cout << "Charger connected with status " << buf << std::endl;
        return true;
    } else {
        std::cout << "Charger not connected with status " << buf << std::endl;
        return false;
    }
}

/* The system may be slow to detect the charger connection, so we need to put an initial value
and avoid exiting the program if there's no value. In those cases, use the default value, e.g. "Checking..."
*/
std::string getChargeStatus() {
    char path[1024];
    FILE *fp;
    char buf[1024];
    std::string chargeStatus = "Checking...";

    // Check if charger is connected
    snprintf(path, sizeof(path), "%s%s", POWER_SUPPLY_PATH, "status");
    if ((fp = fopen(path, "r")) == NULL) {
        perror("Failed to open present file");
        std::cout << "Failed to open present file" << std::endl;
        exit(EXIT_FAILURE);
    }

    if (fgets(buf, sizeof(buf), fp) == NULL) {
        perror("Failed to read present status");
        std::cout << "Failed to read present status" << std::endl;
        fclose(fp);
        exit(EXIT_FAILURE);
    }
    fclose(fp);

    buf[strcspn(buf, "\n")] = 0; // Remove newline character

    return std::string(buf) != "" ? std::string(buf) : chargeStatus;
}

std::string getBatteryLevel() {
    char path[1024];
    FILE *fp;
    static char buf[1024];
    std::string batteryLevel = "Checking...";

    // Get battery level
    snprintf(path, sizeof(path), "%s%s", POWER_SUPPLY_PATH, "capacity");
    if ((fp = fopen(path, "r")) == NULL) {
        perror("Failed to open capacity file");
        std::cout << "Failed to open capacity file" << std::endl;
        exit(EXIT_FAILURE);
    }
    if (fgets(buf, sizeof(buf), fp) == NULL) {
        perror("Failed to read battery level");
        std::cout << "Failed to read battery level" << std::endl;
        fclose(fp);
        exit(EXIT_FAILURE);
    }
    fclose(fp);

    buf[strcspn(buf, "\n")] = 0; // Remove newline character
    return (std::string(buf) + "%") != "" ? std::string(buf) + "%" : batteryLevel;
}



ButtonPressResult waitForButtonPress(void) {
    int fd, retval;
    struct input_event ev;
    fd_set readfds;
    struct timeval tv;

    fd = open(INPUT_DEVICE, O_RDONLY | O_NONBLOCK);
    if (fd < 0) {
        perror("Failed to open input device");
        std::cout << "Failed to open input device" << std::endl;
        exit(EXIT_FAILURE);
    }

    FD_ZERO(&readfds);
    FD_SET(fd, &readfds);

    // Set timeout to 4 seconds
    tv.tv_sec = 4;
    tv.tv_usec = 0;

    printf("Press the power button to boot (4 seconds)...\n");
    retval = select(fd + 1, &readfds, NULL, NULL, &tv);

    if (retval == -1) {
        perror("select()");
        close(fd);
        std::cout << "error in select()" << std::endl;
        return ERROR;
    } else if (retval) {
        // Data available to read
        read(fd, &ev, sizeof(struct input_event));
        if (ev.type == EV_KEY && ev.code == KEY_POWER && ev.value == 1) {
            // Power button pressed
            std::cout << "Power button pressed. Booting..." << std::endl;
            close(fd);
            return BUTTON_PRESSED;
        }
    } else {
        // Timeout reached, no data
        std::cout << "No button press detected. System going to sleep.\n" << std::endl;
        close(fd);
        return TIMEOUT; // No button pressed within timeout
    }

    close(fd);
    return TIMEOUT; // Just to satisfy compiler, function should end in one of the above cases
}

void displayMessage(const std::string& chargeStatus, const std::string& batteryLevel) {
    if (SDL_Init(SDL_INIT_VIDEO) != 0) {
        fprintf(stderr, "Could not initialize SDL: %s\n", SDL_GetError());
        exit(EXIT_FAILURE);
    }

    if (TTF_Init() < 0) {
        std::cout << "SDL_ttf initialization failed: " << TTF_GetError() << std::endl;
        SDL_Quit();
        exit(EXIT_FAILURE);
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

    int screenWidth = vinfo.xres;
    int screenHeight = vinfo.yres;

    // For rotated displays where SDL2 already implements rotation, we need to swap w/h
    if (vinfo.xres < vinfo.yres) {
	    screenWidth = vinfo.yres;
	    screenHeight = vinfo.xres;
    }

    SDL_Surface *screen = SDL_SetVideoMode(screenWidth, screenHeight, 32, SDL_SWSURFACE);
    if (screen == NULL) {
        fprintf(stderr, "Could not set video mode: %s\n", SDL_GetError());
        TTF_Quit();
        SDL_Quit();
        exit(EXIT_FAILURE);
    }

    // Load the background image
    SDL_Surface* bgSurface = SDL_LoadBMP("/boot/bootlogo.bmp");
    if (bgSurface == NULL) {
        fprintf(stderr, "Could not load background image: %s\n", SDL_GetError());
        TTF_Quit();
        SDL_Quit();
        exit(EXIT_FAILURE);
    }

    // If the display is rotated but SDL2 already handles that, rotate the pre-rotated logo (e.g. RG28xx)
    if (vinfo.xres < vinfo.yres) {
	SDL_Surface* rotatedSurface = rotozoomSurface(bgSurface, -90, 1.0, 1);
        if (rotatedSurface == NULL) {
            fprintf(stderr, "Could not rotate surface: %s\n", SDL_GetError());
            SDL_FreeSurface(bgSurface);
            SDL_Quit();
            exit(EXIT_FAILURE);
        }
        SDL_FreeSurface(bgSurface);
	SDL_BlitSurface(rotatedSurface, NULL, screen, NULL);
    } else {
        SDL_BlitSurface(bgSurface, NULL, screen, NULL);
    }

    TTF_Font* font = TTF_OpenFont("/usr/share/fonts/dejavu/DejaVuSans-Bold.ttf", 24); // Update font path
    if (font == NULL) {
        std::cout << "Failed to load font: " << TTF_GetError() << std::endl;
        TTF_Quit();
        SDL_Quit();
        exit(EXIT_FAILURE);
    }

    

    SDL_Color textColor = {255, 255, 255};
    SDL_Surface* bottomTextSurface;
    SDL_Surface* centerTextSurface;
    if (chargeStatus.empty()) {
        // If chargeStatus is empty, display only the batteryLevel as a message
        centerTextSurface = TTF_RenderText_Blended(font, batteryLevel.c_str(), textColor);
    } else {
        // Normal case - display the full battery status message
        bottomTextSurface = TTF_RenderText_Blended(font, ("Battery Level: " + batteryLevel + " - " + " Status: " + chargeStatus).c_str(), textColor);
        centerTextSurface = TTF_RenderText_Blended(font, "Press Power Button to Boot...", textColor);
    }

    if (bottomTextSurface == NULL || centerTextSurface == NULL) {
        std::cout << "Failed to create text surface: " << TTF_GetError() << std::endl;
        TTF_CloseFont(font);
        TTF_Quit();
        SDL_Quit();
        exit(EXIT_FAILURE);
    }

    // Centering the bottom text
    int bottomTextX = (screen->w - bottomTextSurface->w) / 2;
    int bottomTextY = screen->h - bottomTextSurface->h - 30; // 10 pixels from the bottom

    // Centering the center text
    int centerTextX = (screen->w - centerTextSurface->w) / 2;
    int centerTextY = screen->h - centerTextSurface->h - 70; //30 pixels from the bottom

    SDL_Rect bottomTextRect = {bottomTextX, bottomTextY, bottomTextSurface->w, bottomTextSurface->h};
    SDL_Rect centerTextRect = {centerTextX, centerTextY, centerTextSurface->w, centerTextSurface->h};

    SDL_BlitSurface(bottomTextSurface, NULL, screen, &bottomTextRect);
    SDL_BlitSurface(centerTextSurface, NULL, screen, &centerTextRect);

    SDL_Flip(screen); // Update the screen

    if (chargeStatus.empty()) {
        SDL_Delay(DISPLAY_TIME); // Display for a fixed time
    } 

    SDL_FreeSurface(bottomTextSurface);
    SDL_FreeSurface(centerTextSurface);
    TTF_CloseFont(font);
    TTF_Quit();
    SDL_Quit();
}

volatile bool keepRunning = true;
bool inChargerMode = false;

void signalHandler(int dummy) {
    keepRunning = false;
}

int main(void) {
    signal(SIGINT, signalHandler);

    // Check initial charger status.
    inChargerMode = checkChargerConnected();
    
    // If booting without a charger, proceed normally off battery.
    if (!inChargerMode) {
        std::cout << "No charger detected. Booting normally on battery." << std::endl;
        return 0;
    }

    // Display initial status when running on external power.
    displayMessage(getChargeStatus(), getBatteryLevel());

    while (keepRunning) {
        // Continuously check the charger status.
        inChargerMode = checkChargerConnected();
        if (!inChargerMode) {
            std::cout << "Charger disconnected. Shutting down." << std::endl;
            displayMessage("", "Power supply disconnected. Shutting down...");
            shutdownDevice();
            // break;
        }
    
        // Refresh the display
        displayMessage(getChargeStatus(), getBatteryLevel());
    
        ButtonPressResult result = waitForButtonPress();
        if (result == BUTTON_PRESSED) {
            std::cout << "Power button pressed. Booting normally." << std::endl;
            displayMessage("", "Booting up...");
            exit(EXIT_SUCCESS);
        } else if (result == TIMEOUT) {
            // Re-check charger state after timeout.
            inChargerMode = checkChargerConnected();
            if (!inChargerMode) {
                std::cout << "Charger disconnected during timeout. Shutting down." << std::endl;
                displayMessage("", "Power supply disconnected. Shutting down...");
                shutdownDevice();
                exit(EXIT_FAILURE);
                break;
            } else {
                putDeviceToSleep();
                displayMessage(getChargeStatus(), getBatteryLevel());
            }
        } else if (result == ERROR) {
            std::cerr << "Error during button press handling. Shutting down." << std::endl;
            displayMessage("", "Power supply disconnected. Shutting down...");
            shutdownDevice();
            exit(EXIT_FAILURE);
            break;
        }
    }
    
    return 0;
}
