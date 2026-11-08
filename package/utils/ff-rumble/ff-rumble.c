// ff-rumble.c
// Usage: ff-rumble <seconds 0.1-10.0> [magnitude 10-100] [eventX | /dev/input/eventX]
// build: aarch64-linux-gnu-gcc -O3 -pipe -ffunction-sections -fdata-sections -Wl,--gc-sections -s -o ff-rumble ff-rumble.c

#include <ctype.h>
#include <errno.h>
#include <fcntl.h>
#include <glob.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <unistd.h>

#include <linux/input.h>
#include <sys/ioctl.h>
#include <sys/stat.h>

#define MIN_SECONDS 0.1
#define MAX_SECONDS 10.0
#define DEFAULT_MAG 75   // default strength

static int parse_seconds_ms(const char *s, int *out_ms)
{
	char *end;
	errno = 0;
	double sec = strtod(s, &end);

	if (errno || end == s || *end != '\0' ||
	    !(sec >= MIN_SECONDS && sec <= MAX_SECONDS))
		return -1;

	*out_ms = (int)(sec * 1000.0 + 0.5);
	return 0;
}

static int parse_magnitude(const char *s, int *out_pct)
{
	char *end = NULL;
	errno = 0;
	long pct = strtol(s, &end, 10);

	if (errno || end == s || *end != '\0')
		return -1;
	if (pct < 10 || pct > 100)
		return -1;

	*out_pct = (int)pct;
	return 0;
}


static int is_event_name(const char *s)
{
	if (strncmp(s, "event", 5) != 0 || !isdigit((unsigned char)s[5]))
		return 0;

	for (const char *p = s + 6; *p; ++p)
		if (!isdigit((unsigned char)*p))
			return 0;

	return 1;
}

static int normalize_dev_path(const char *arg, char *out, size_t outsz)
{
	if (!arg || !*arg)
		return -1;

	int n;
	if (strchr(arg, '/'))
	{
		n = snprintf(out, outsz, "%s", arg);
	}
	else
	{
		if (!is_event_name(arg))
			return -1;
		n = snprintf(out, outsz, "/dev/input/%s", arg);
	}

	if (n < 0 || (size_t)n >= outsz)
		return -1;

	struct stat st;
	return stat(out, &st) == 0 && S_ISCHR(st.st_mode) ? 0 : -1;
}

static int is_internal_controller(const char *name)
{
	FILE *file = fopen("/usr/share/emulationstation/es_input.cfg", "r");
	if (!file)
		return 0;

	char *line = NULL;
	size_t capacity = 0;
	int internal = 0;
	size_t name_len = strlen(name);

	while (getline(&line, &capacity, file) != -1)
	{
		char *p = line;
		while (isspace((unsigned char)*p))
			++p;

		if (strncmp(p, "<inputConfig ", 13) != 0)
			continue;

		char *end = strchr(p, '>');
		if (!end)
			continue;
		*end = '\0';

		if (!strstr(p, " internal=\"1\""))
			continue;

		char *device = strstr(p, " deviceName=\"");
		if (!device)
			continue;
		device += strlen(" deviceName=\"");

		char *quote = strchr(device, '"');
		if (quote && (size_t)(quote - device) == name_len && memcmp(device, name, name_len) == 0)
		{
			internal = 1;
			break;
		}
	}

	free(line);
	fclose(file);
	return internal;
}

static int find_internal_device(char *out, size_t outsz)
{
	glob_t events = {0};
	int found = -1;

	// Match event devices against the internal controllers in es_input.cfg.
	if (glob("/sys/class/input/event[0-9]*", 0, NULL, &events) != 0)
	{
		globfree(&events);
		return -1;
	}

	for (size_t i = 0; i < events.gl_pathc; ++i)
	{
		char path[512];
		char *name = NULL;
		size_t capacity = 0;

		int n = snprintf(path, sizeof(path), "%s/device/name",
		                 events.gl_pathv[i]);
		if (n < 0 || (size_t)n >= sizeof(path))
			continue;

		FILE *file = fopen(path, "r");
		if (!file)
			continue;

		ssize_t length = getline(&name, &capacity, file);
		fclose(file);

		if (length <= 0)
		{
			free(name);
			continue;
		}

		if (name[length - 1] == '\n')
			name[length - 1] = '\0';

		int internal = is_internal_controller(name);
		free(name);

		if (!internal)
			continue;

		const char *event = strrchr(events.gl_pathv[i], '/');
		n = snprintf(out, outsz, "/dev/input/%s", event + 1);
		if (n >= 0 && (size_t)n < outsz)
		{
			found = 0;
			break;
		}
	}

	globfree(&events);
	return found;
}

static void full_sleep_ms(int ms)
{
	struct timespec ts = {
		.tv_sec = ms / 1000,
		.tv_nsec = (ms % 1000) * 1000000L
	};

	while (nanosleep(&ts, &ts) == -1 && errno == EINTR)
	{
		// Finish sleeping if interrupted.
	}
}

static int has_ff_bit(const unsigned char *bits, unsigned int bit)
{
	return (bits[bit / 8] >> (bit % 8)) & 1;
}

static int write_ff_event(int fd, unsigned short code, int value)
{
	struct input_event event = {0};
	event.type = EV_FF;
	event.code = code;
	event.value = value;

	ssize_t written;
	do
	{
		written = write(fd, &event, sizeof(event));
	} while (written < 0 && errno == EINTR);

	if (written == (ssize_t)sizeof(event))
		return 0;

	if (written >= 0)
		errno = EIO;

	return -1;
}

static int upload_and_play(int fd, struct ff_effect *eff, int ms)
{
	eff->id = -1;
	eff->replay.length = (unsigned short)ms;
	eff->replay.delay = 0;

	if (ioctl(fd, EVIOCSFF, eff) < 0)
		return -1;

	if (write_ff_event(fd, (unsigned short)eff->id, 1) < 0) 
	{
		int error = errno;
		(void)ioctl(fd, EVIOCRMFF, eff->id);
		errno = error;
		return -1;
	}

	// Keep the effect alive until playback finishes.
	full_sleep_ms(ms + 30);

	(void)write_ff_event(fd, (unsigned short)eff->id, 0);
	(void)ioctl(fd, EVIOCRMFF, eff->id);
	return 0;
}

int main(int argc, char **argv)
{
	if (argc < 2 || argc > 4)
	{
		fprintf(stderr,
			"Usage: %s <seconds %.1f..%.1f> [magnitude 10-100] "
			"[eventX | /dev/input/eventX]\n",
			argv[0], MIN_SECONDS, MAX_SECONDS);
		return 1;
	}

	int ms;
	if (parse_seconds_ms(argv[1], &ms) != 0)
	{
		fprintf(stderr, "Invalid seconds: %s (must be %.1f..%.1f)\n",
			argv[1], MIN_SECONDS, MAX_SECONDS);
		return 1;
	}

	int mag_pct = DEFAULT_MAG;
	if (argc >= 3 && parse_magnitude(argv[2], &mag_pct) != 0)
	{
		fprintf(stderr, "Invalid magnitude: %s (must be 10-100)\n",
			argv[2]);
		return 1;
	}

	char devpath[256];
	if (argc == 4)
	{
		if (normalize_dev_path(argv[3], devpath, sizeof(devpath)) != 0)
		{
			fprintf(stderr, "Invalid input device: %s\n", argv[3]);
			return 1;
		}
	} 
	else if (find_internal_device(devpath, sizeof(devpath)) != 0)
	{
		fprintf(stderr, "No matching internal controller found\n");
		return 1;
	}

	int fd = open(devpath, O_RDWR | O_CLOEXEC);
	if (fd < 0)
	{
		perror("open");
		return 1;
	}

	// Check supported effects once.
	unsigned char ff[FF_MAX / 8 + 1] = {0};
	if (ioctl(fd, EVIOCGBIT(EV_FF, sizeof(ff)), ff) < 0)
	{
		perror("EVIOCGBIT(EV_FF)");
		close(fd);
		return 1;
	}

	const int have_rumble = has_ff_bit(ff, FF_RUMBLE);
	const int have_periodic = has_ff_bit(ff, FF_PERIODIC) && has_ff_bit(ff, FF_SINE);

	if (!have_rumble && !have_periodic) 
	{
		fprintf(stderr, "Device supports neither rumble nor periodic sine\n");
		close(fd);
		return 1;
	}

	if (has_ff_bit(ff, FF_GAIN))
		(void)write_ff_event(fd, FF_GAIN, 0xFFFF);

	struct ff_effect eff = {0};

	// Prefer rumble
	if (have_rumble)
	{
		eff.type = FF_RUMBLE;
		unsigned short magnitude = (unsigned short)((mag_pct * 0xFFFF) / 100);
		eff.u.rumble.strong_magnitude = magnitude;
		eff.u.rumble.weak_magnitude = magnitude;

		if (upload_and_play(fd, &eff, ms) == 0)
		{
			close(fd);
			return 0;
		}
	}

	// fallback to periodic sine
	if (have_periodic)
	{
		memset(&eff, 0, sizeof(eff));
		eff.type = FF_PERIODIC;
		eff.u.periodic.waveform = FF_SINE;
		eff.u.periodic.magnitude = (short)((mag_pct * 0x7FFF) / 100);
		eff.u.periodic.period = 25; // 40 Hz

		if (upload_and_play(fd, &eff, ms) == 0)
		{
			close(fd);
			return 0;
		}
	}

	int error = errno;
	close(fd);
	fprintf(stderr, "Force-feedback playback failed: %s\n", strerror(error));
	return 1;
}
