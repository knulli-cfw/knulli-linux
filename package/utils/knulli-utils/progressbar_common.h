// progressbar_common.h -- what progressbar and progressbar_rk share: the boot
// step labels and the progress model.  Only the way a frame reaches the panel
// differs between the two (SDL window vs. straight to /dev/fb0).
//
// The model.  rcS is NON-LINEAR (blocking and backgrounded scripts mixed), so
// /tmp/status.txt is not a usable progress signal: it is non-monotonic, it
// dwells on the blocking scripts (dbus, udev), and it keeps changing after the
// last foreground script.  Deriving the bar from the script number made it jump
// in big steps and stall.  Instead:
//
//  * the bar climbs smoothly with time to at most 90% (always moving, never
//    frozen);
//  * once the emulationstation PROCESS appears -- the real "about to take the
//    screen" event -- it fills to 100% before ES presents its first frame;
//  * status.txt only picks the label, until ES shows up.
#pragma once

#include <ctype.h>
#include <dirent.h>
#include <stdio.h>
#include <string.h>
#include <time.h>

typedef struct {
    const char *script_name;
    const char *description;
} ScriptMapping;

static const ScriptMapping script_descriptions[] = {
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

static const char *get_script_basename(const char *script_path) {
    const char *slash = strrchr(script_path, '/');
    return slash ? slash + 1 : script_path;
}

// The label for an rcS step, or NULL for a step that has none.
static const char *get_description(const char *script_path) {
    const char *script_name = get_script_basename(script_path);
    for (size_t i = 0; i < sizeof(script_descriptions) / sizeof(script_descriptions[0]); i++)
        if (strcmp(script_descriptions[i].script_name, script_name) == 0)
            return script_descriptions[i].description;
    return NULL;
}

// Milliseconds between two monotonic timestamps.
static double ms_between(const struct timespec *a, const struct timespec *b) {
    return (b->tv_sec - a->tv_sec) * 1000.0 + (b->tv_nsec - a->tv_nsec) / 1e6;
}

// Is EmulationStation running yet?  /proc/<pid>/comm is truncated to 15 chars.
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

class BootProgress {
public:
    // Call every TICK_MS; returns true when something visible changed.
    static const int TICK_MS = 50;

    BootProgress() { clock_gettime(CLOCK_MONOTONIC, &start_); }

    bool update() {
        if (!es_seen_) {
            read_label();
            // Scan /proc for ES ~4x/sec.
            if (++es_poll_ >= 5) {
                es_poll_ = 0;
                if (es_running()) {
                    es_seen_ = true;
                    clock_gettime(CLOCK_MONOTONIC, &es_ts_);
                    es_from_ = shown_;
                    description_ = get_description("S99userservices");
                }
            }
        }

        struct timespec now;
        clock_gettime(CLOCK_MONOTONIC, &now);
        double goal;
        if (es_seen_) {
            goal = es_from_ + (100.0 - es_from_) * (ms_between(&es_ts_, &now) / COMPLETION_MS);
        } else {
            goal = ms_between(&start_, &now) / PRECLIMB_MS * 90.0;
            if (goal > 90.0)
                goal = 90.0;
        }
        if (goal > 100.0)
            goal = 100.0;
        if (goal > shown_)
            shown_ = goal;                  // monotonic

        int pct = (int)(shown_ + 0.5);
        bool changed = pct != last_pct_ || description_ != last_desc_;
        last_pct_ = pct;
        last_desc_ = description_;
        return changed;
    }

    int percent() const { return last_pct_; }
    const char *description() const { return description_; }
    bool done() const { return es_seen_ && shown_ >= 100.0; }

private:
    static constexpr double PRECLIMB_MS   = 18000.0;  // climb to 90% over this while waiting for ES
    static constexpr double COMPLETION_MS = 250.0;    // fill to 100% before ES puts up its window

    // Label from the latest status.txt line (QUIT and unknown steps ignored).
    // The single file is polled: an inotify watch on /tmp is drowned by the
    // other early-boot writers there and misses updates.
    void read_label() {
        char line[256], cur[256] = "";
        FILE *f = fopen("/tmp/status.txt", "r");
        if (!f)
            return;
        while (fgets(line, sizeof(line), f))
            if (line[0] != '\0')
                snprintf(cur, sizeof(cur), "%s", line);
        fclose(f);
        if (cur[0] == '\0' || strcmp(cur, last_text_) == 0)
            return;
        snprintf(last_text_, sizeof(last_text_), "%s", cur);
        cur[strcspn(cur, "\n")] = '\0';
        if (strcmp(cur, "QUIT") == 0)
            return;
        const char *d = get_description(cur);
        if (d)
            description_ = d;
    }

    struct timespec start_, es_ts_;
    double shown_ = 0.0, es_from_ = 0.0;
    bool es_seen_ = false;
    int es_poll_ = 0;
    int last_pct_ = -1;
    const char *description_ = "Starting up...";
    const char *last_desc_ = NULL;
    char last_text_[256] = "";
};
