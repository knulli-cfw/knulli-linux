/*
 * knulli-devsel: first-boot device selection for the single H700 image.
 *
 * The boards cannot be told apart in hardware and the panels differ, so the
 * boot script cycles the extlinux default through the screen classes (one
 * reboot each) and this tool asks, on every pass, whether the screen can be
 * read: "press A", then "press B to confirm" (a late A from the previous
 * pass must not select the wrong class), then a menu of the devices in that
 * class.  Exit 0 with the chosen device on stdout, 2 to try the next class.
 *
 *   knulli-devsel <devices.conf> <current device>
 * devices.conf: "class|device|label" per line, classes in cycle order.
 */
#include <SDL/SDL.h>
#include <SDL/SDL_ttf.h>
#include <SDL/SDL_rotozoom.h>
#include <dirent.h>
#include <fcntl.h>
#include <linux/input.h>
#include <linux/fb.h>
#include <poll.h>
#include <string.h>
#include <sys/ioctl.h>
#include <unistd.h>
#include <fstream>
#include <algorithm>
#include <iostream>
#include <sstream>
#include <string>
#include <vector>

#define BTN_PAD_A BTN_EAST    /* 0x131, keya in the joypad node */
#define BTN_PAD_B BTN_SOUTH   /* 0x130 */
#define CONFIRM_MS 2000
#define LCD_PANEL "/sys/class/disp/disp/attr/lcd_panel"

struct Dev { std::string cls, name, label; };
struct Panel { std::string name, group, label; int w, h; std::vector<std::string> devices; };

static std::vector<int> open_inputs()
{
	std::vector<int> fds;
	DIR *d = opendir("/dev/input");
	struct dirent *e;
	while (d && (e = readdir(d))) {
		if (strncmp(e->d_name, "event", 5))
			continue;
		std::string p = std::string("/dev/input/") + e->d_name;
		int fd = open(p.c_str(), O_RDONLY | O_NONBLOCK);
		if (fd < 0)
			continue;
		unsigned long keys[KEY_MAX / 8 / sizeof(long) + 1] = {0};
		ioctl(fd, EVIOCGBIT(EV_KEY, sizeof(keys)), keys);
		/* anything with an A button */
		if (keys[BTN_PAD_A / (8 * sizeof(long))] & (1UL << (BTN_PAD_A % (8 * sizeof(long)))))
			fds.push_back(fd);
		else
			close(fd);
	}
	if (d)
		closedir(d);
	return fds;
}

enum { K_UP = 1000, K_DOWN, K_LEFT, K_RIGHT };

/* next key press: a button code, K_* for the d-pad, 0 on timeout */
static int wait_key(const std::vector<int> &fds, int timeout_ms)
{
	std::vector<pollfd> pf;
	for (int fd : fds)
		pf.push_back({fd, POLLIN, 0});
	for (;;) {
		int n = poll(pf.data(), pf.size(), timeout_ms);
		if (n == 0)
			return 0;
		if (n < 0)
			continue;
		for (auto &p : pf) {
			if (!(p.revents & POLLIN))
				continue;
			struct input_event ev;
			while (read(p.fd, &ev, sizeof(ev)) == (ssize_t)sizeof(ev)) {
				if (ev.type == EV_ABS && ev.code == ABS_HAT0Y && ev.value)
					return ev.value < 0 ? K_UP : K_DOWN;
				if (ev.type == EV_ABS && ev.code == ABS_HAT0X && ev.value)
					return ev.value < 0 ? K_LEFT : K_RIGHT;
				if (ev.type == EV_KEY && ev.value == 1) {
					if (ev.code == KEY_UP) return K_UP;
					if (ev.code == KEY_DOWN) return K_DOWN;
					if (ev.code == KEY_LEFT) return K_LEFT;
					if (ev.code == KEY_RIGHT) return K_RIGHT;
					return ev.code;
				}
			}
		}
	}
}

struct Ui {
	SDL_Surface *screen = NULL, *canvas = NULL; /* canvas: landscape drawing surface when the fb is portrait */
	TTF_Font *font = NULL, *big = NULL;
	int w = 0, h = 0;
	/* (re)open the SDL surface at the size of the panel that is up now:
	 * SDL sets the fb geometry, the disp layer follows the fb.  A portrait
	 * panel (rg28xx) is drawn landscape and rotated 90 degrees left. */
	bool mode(int pw, int ph)
	{
		if (screen && pw == w && ph == h)
			return true;
		if (font) TTF_CloseFont(font);
		if (big) TTF_CloseFont(big);
		if (canvas) { SDL_FreeSurface(canvas); canvas = NULL; }
		screen = SDL_SetVideoMode(pw, ph, 32, SDL_SWSURFACE);
		if (!screen || screen->w != pw) {
			SDL_QuitSubSystem(SDL_INIT_VIDEO);
			SDL_InitSubSystem(SDL_INIT_VIDEO);
			SDL_ShowCursor(SDL_DISABLE);
			screen = SDL_SetVideoMode(pw, ph, 32, SDL_SWSURFACE);
		}
		w = pw; h = ph;
		if (screen && pw < ph)
			canvas = SDL_CreateRGBSurface(SDL_SWSURFACE, ph, pw, 32,
						      screen->format->Rmask, screen->format->Gmask,
						      screen->format->Bmask, 0);
		int lh = pw < ph ? pw : ph;
		font = TTF_OpenFont("/usr/share/fonts/dejavu/DejaVuSans.ttf", lh >= 640 ? 26 : 20);
		big = TTF_OpenFont("/usr/share/fonts/dejavu/DejaVuSans-Bold.ttf", lh >= 640 ? 34 : 26);
		return screen && font && big;
	}
	void draw(const std::vector<std::string> &lines, int highlight = -1)
	{
		SDL_Surface *dst = canvas ? canvas : screen;
		SDL_FillRect(dst, NULL, SDL_MapRGB(dst->format, 20, 20, 30));
		SDL_Color white = {255, 255, 255, 0}, yellow = {255, 220, 60, 0};
		int y = 30;
		for (size_t i = 0; i < lines.size(); i++) {
			TTF_Font *f = i == 0 ? big : font;
			if (lines[i].empty()) { y += 14; continue; }
			SDL_Surface *t = TTF_RenderUTF8_Blended(f, lines[i].c_str(), (int)i == highlight ? yellow : white);
			if (!t) continue;
			SDL_Rect r = {(Sint16)((dst->w - t->w) / 2), (Sint16)y, 0, 0};
			SDL_BlitSurface(t, NULL, dst, &r);
			y += t->h + 6;
			SDL_FreeSurface(t);
		}
		if (canvas) {
			SDL_Surface *rot = rotozoomSurface(canvas, 90, 1.0, 0); /* 90 = counter-clockwise */
			if (rot) {
				SDL_Rect r = {(Sint16)((screen->w - rot->w) / 2), (Sint16)((screen->h - rot->h) / 2), 0, 0};
				SDL_BlitSurface(rot, NULL, screen, &r);
				SDL_FreeSurface(rot);
			}
		}
		SDL_Flip(screen);
	}
};

static std::string sysfs_read(const char *path)
{
	std::ifstream f(path);
	std::string s;
	std::getline(f, s);
	return s;
}

/* re-init the lcd with another panel's timings and init table */
static bool set_panel(const std::string &name)
{
	std::ofstream f(LCD_PANEL);
	f << name << std::endl;
	f.close();
	if (!f) {
		std::cerr << "knulli-devsel: " << LCD_PANEL << " <- " << name << " failed\n";
		return false;
	}
	std::cerr << "knulli-devsel: panel " << name << "\n";
	return true;
}

static std::vector<std::string> split(const std::string &s, char sep)
{
	std::vector<std::string> v;
	std::stringstream ss(s);
	std::string x;
	while (std::getline(ss, x, sep))
		v.push_back(x);
	return v;
}

int main(int argc, char **argv)
{
	if (argc < 3) {
		std::cerr << "usage: knulli-devsel <panels.conf> <devices.conf>\n";
		return 1;
	}
	std::vector<Panel> panels;
	std::ifstream pconf(argv[1]);
	std::string line;
	while (std::getline(pconf, line)) {
		if (line.empty() || line[0] == '#')
			continue;
		auto f = split(line, '|');
		if (f.size() < 5)
			continue;
		Panel p;
		p.name = f[0]; p.group = f[1]; p.label = f[3]; p.devices = split(f[4], ',');
		if (sscanf(f[2].c_str(), "%dx%d", &p.w, &p.h) != 2)
			continue;
		panels.push_back(p);
	}
	std::vector<Dev> devs;
	std::ifstream dconf(argv[2]);
	while (std::getline(dconf, line)) {
		if (line.empty() || line[0] == '#')
			continue;
		auto f = split(line, '|');
		if (f.size() >= 3)
			devs.push_back({f[0], f[1], f[2]});
	}
	if (panels.empty()) {
		std::cerr << "knulli-devsel: no panels in " << argv[1] << "\n";
		return 1;
	}

	std::vector<int> fds = open_inputs();
	if (fds.empty()) {
		std::cerr << "knulli-devsel: no input device with an A button\n";
		return 1;
	}
	if (SDL_Init(SDL_INIT_VIDEO) < 0 || TTF_Init() < 0) {
		std::cerr << "SDL init failed: " << SDL_GetError() << "\n";
		return 1;
	}
	SDL_ShowCursor(SDL_DISABLE);

	/* the panel that is up now: the lcd0 node of the select DT (= the first
	 * entry, with the id pin deciding the variant) unless already switched */
	std::string applied = sysfs_read(LCD_PANEL);
	size_t cur = 0;
	for (size_t i = 0; i < panels.size(); i++)
		if (panels[i].name == applied)
			cur = i;
	Ui ui;
	int fb = open("/dev/fb0", O_RDONLY);
	struct fb_var_screeninfo vinfo = {};
	if (fb >= 0) { ioctl(fb, FBIOGET_VSCREENINFO, &vinfo); close(fb); }
	if (!ui.mode(vinfo.xres ? vinfo.xres : 640, vinfo.yres ? vinfo.yres : 480)) {
		std::cerr << "SDL video/font failed: " << SDL_GetError() << "\n";
		return 1;
	}

	for (;;) {
		/* 1. step through every panel (one flat list: a board whose second
		 * controller is the one fitted must be reachable by Left/Right alone) */
		int code;
		for (;;) {
			const Panel &p = panels[cur];
			ui.draw({"KNULLI first boot", "",
				 "Screen " + std::to_string(cur + 1) + "/" + std::to_string(panels.size()) + ":",
				 p.label, "",
				 "Can you read this?  Press A", "",
				 "Left/Right: try another screen"});
			code = wait_key(fds, -1);
			if (code == BTN_PAD_A)
				break;
			if (code == K_LEFT || code == K_UP) cur = (cur + panels.size() - 1) % panels.size();
			else if (code == K_RIGHT || code == K_DOWN) cur = (cur + 1) % panels.size();
			else continue;
			const Panel &n = panels[cur];
			if (n.name != applied && set_panel(n.name))
				applied = n.name;
			ui.mode(n.w, n.h);
		}

		/* 2. confirm (an A meant for a screen that was not readable) */
		ui.draw({"KNULLI first boot", "", "Screen readable?", "Press A again to confirm.", "",
			 "(" + std::to_string(CONFIRM_MS / 1000) + " s)"});
		if (wait_key(fds, CONFIRM_MS) != BTN_PAD_A)
			continue;

		/* 3. which of the devices with this panel */
		const Panel &p = panels[cur];
		std::vector<Dev> menu;
		for (auto &name : p.devices) {
			Dev d = {"", name, name};
			for (auto &x : devs)
				if (x.name == name)
					d = x;
			menu.push_back(d);
		}
		size_t sel = 0;
		bool back = false;
		for (;;) {
			std::vector<std::string> lines = {"Which device is this?", ""};
			for (auto &d : menu)
				lines.push_back(d.label);
			lines.push_back("");
			lines.push_back("Up/Down: choose    A: confirm    B: back");
			ui.draw(lines, 2 + (int)sel);
			code = wait_key(fds, -1);
			if (code == K_UP && sel > 0) sel--;
			else if (code == K_DOWN && sel + 1 < menu.size()) sel++;
			else if (code == BTN_PAD_A) break;
			else if (code == BTN_PAD_B) { back = true; break; }
		}
		if (back)
			continue;
		ui.draw({"Saving...", "", menu[sel].label});
		std::cout << menu[sel].name << std::endl;
		TTF_Quit();
		SDL_Quit();
		return 0;
	}
}
