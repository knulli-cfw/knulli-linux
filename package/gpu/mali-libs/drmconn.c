// The blob's VK_KHR_display takes the first connected connector; its
// drmModeGetResources import is renamed to this, which puts drmConn first.
#include <stdio.h>
#include <xf86drmMode.h>

drmModeResPtr knlModeGetResources(int fd)
{
    drmModeResPtr res = drmModeGetResources(fd);
    FILE *f = fopen("/var/run/drmConn", "r");
    int conn = 0;

    if (f) {
        if (fscanf(f, "%d", &conn) != 1)
            conn = 0;
        fclose(f);
    }

    if (res && conn > 0 && conn < res->count_connectors) {
        uint32_t id = res->connectors[conn];
        for (int i = conn; i > 0; i--)
            res->connectors[i] = res->connectors[i - 1];
        res->connectors[0] = id;
    }
    return res;
}
