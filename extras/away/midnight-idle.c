/* midnight-idle [--input] <timeout_ms> — prints "idle" / "resume" lines on stdout.
 * Uses KWin's ext_idle_notifier_v1 get_idle_notification, which RESPECTS Wayland
 * idle inhibitors (mpv, browsers playing video). DBus inhibitors (SDL games,
 * jellyfin-mpv-shim) are checked separately by midnight-screensaver.py.
 * --input uses get_input_idle_notification (protocol v2) instead, which IGNORES
 * inhibitors: idle means "no keyboard/mouse", even while a video plays. The
 * desktop widgets' away detector uses it; the screensaver must not. */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <wayland-client.h>
#include "ext-idle-notify-v1-client.h"

static struct wl_seat *seat;
static struct ext_idle_notifier_v1 *notifier;
static uint32_t notifier_v;

static void reg_global(void *d, struct wl_registry *r, uint32_t name, const char *iface, uint32_t v) {
    if (!strcmp(iface, wl_seat_interface.name) && !seat)
        seat = wl_registry_bind(r, name, &wl_seat_interface, 1);
    else if (!strcmp(iface, ext_idle_notifier_v1_interface.name))
        { notifier_v = v < 2 ? v : 2;
          notifier = wl_registry_bind(r, name, &ext_idle_notifier_v1_interface, notifier_v); }
}
static void reg_remove(void *d, struct wl_registry *r, uint32_t name) {}
static const struct wl_registry_listener reg_l = { reg_global, reg_remove };

static void on_idled(void *d, struct ext_idle_notification_v1 *n)   { puts("idle");   fflush(stdout); }
static void on_resumed(void *d, struct ext_idle_notification_v1 *n) { puts("resume"); fflush(stdout); }
static const struct ext_idle_notification_v1_listener note_l = { on_idled, on_resumed };

int main(int argc, char **argv) {
    int input = argc == 3 && !strcmp(argv[1], "--input");
    if (argc != 2 && !input) { fprintf(stderr, "usage: %s [--input] <timeout_ms>\n", argv[0]); return 2; }
    uint32_t ms = (uint32_t)strtoul(argv[argc - 1], NULL, 10);
    struct wl_display *dpy = wl_display_connect(NULL);
    if (!dpy) { fprintf(stderr, "midnight-idle: no wayland display\n"); return 1; }
    struct wl_registry *reg = wl_display_get_registry(dpy);
    wl_registry_add_listener(reg, &reg_l, NULL);
    wl_display_roundtrip(dpy);
    if (!seat || !notifier) { fprintf(stderr, "midnight-idle: compositor lacks ext_idle_notifier_v1\n"); return 1; }
    if (input && notifier_v < 2) { fprintf(stderr, "midnight-idle: compositor lacks input idle (v2)\n"); return 1; }
    struct ext_idle_notification_v1 *n = input
        ? ext_idle_notifier_v1_get_input_idle_notification(notifier, ms, seat)
        : ext_idle_notifier_v1_get_idle_notification(notifier, ms, seat);
    ext_idle_notification_v1_add_listener(n, &note_l, NULL);
    while (wl_display_dispatch(dpy) != -1) {}
    return 1;   /* compositor went away: let systemd restart us */
}
