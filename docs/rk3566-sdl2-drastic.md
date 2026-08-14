# SDL2 and sdl2_drastic patches on rk3566 — what and why

Written 2026-08-06 as part of the RGB30 test drop. Scope: rk3566
boards using the mali-blob-gbm libmali variant with the KMSDRM SDL2
video backend.

The intent is to give reviewers and downstream users (acmeplus's
in-progress rk3566 unification, trngaje's SDL_drastic upstream, and
anyone chasing a similar drastic-on-mali stack) a per-patch
justification so decisions to keep, drop or generalise each patch are
informed.

## TL;DR

Two independent piles of patches touch libSDL2 for our RGB30 build:

1. **9 board patches** under `board/rockchip/rk3566/patches/sdl2/`.
   These already exist in knulli and target the *system* libSDL2. Our
   only change (commit `66b36fd`) is a symlink that makes them apply
   to sdl2_drastic's bundled libSDL2 fork as well. None of these
   patches are ours; they cover panel rotation, RGA blit, VSync
   forcing, cursor rotation, build-without-mali-headers, kmsdrmmouse
   correctness, and fbcon auto-rotate. All are needed regardless of
   CPU frequency.

2. **1 sdl2_drastic-only patch** under
   `package/emulators/advanced_drastic/sdl2_drastic/0007-rk3566-adopt-sdl-egl-context.patch`.
   This one *is* ours. It fixes an outright black-screen crash caused
   by trngaje's `video_handler` thread trying to bring up its own
   DRM+GBM+EGL in parallel with SDL's KMSDRM backend. On the mali-blob-gbm
   variant the two can't coexist. Threaded video decoupling and a menu-
   crash guard are also folded into the same patch.

## Part 1 — the 9 board patches (pre-existing knulli)

These are applied to system SDL2 via `BR2_GLOBAL_PATCH_DIR`
`board/rockchip/patches` + `board/rockchip/rk3566/patches`. We added
`board/rockchip/rk3566/patches/sdl2_drastic/` as a symlink to
`board/rockchip/rk3566/patches/sdl2/`, so sdl2_drastic's bundled
libSDL2 fork gets the same 9 patches from a single source of truth.

| Patch | Author | What | Why on rk3566 | Generic beyond rk3566? |
|---|---|---|---|---|
| `0001-Split-V-and-P-M.patch` | Fewtarius | Split GLES2 render pixel-format handling | Portrait-panel colour correctness | Any GLES2 stack |
| `0002-Force-VSync-when-using-KMSDRM.patch` | JohnnyOnFlame | Hard-set swap interval to 1 | Prevents tearing on the fixed-refresh panel | Debatable — see "Wider knulli-side wins" note |
| `0003-Implement-librga-framebuffer-rotation.patch` | JohnnyOnFlame | Rotate frames through librga (RGA) blit | RGB30's panel is physically rotated 90° relative to the framebuffer; HW-accelerated rotation is the only tolerable path | Any rk3566/rk3288 board with rotated panel |
| `0004-KMSDRM-Rotate-the-cursor.patch` | JohnnyOnFlame | Rotate mouse cursor to match panel | Corollary of 0003 | Same |
| `0004-fix-touch-mouse.patch` | JohnnyOnFlame | Fix `SYNTHESIZE_TOUCH_TO_MOUSE` guard | Touch → mouse synthesis correctness | Generic SDL2 fix; worth upstreaming |
| `0005-KMSDRM-Rotation-should-respect-panel-orientation.patch` | JohnnyOnFlame | Read panel-orientation from KMS connector, feed to rotation math | Auto-picks the right rotation for the RGB30 panel instead of hard-coding | Any rk3566/rk3288 board |
| `0007-Support-building-without-hacky-libmali-headers.patch` | JohnnyOnFlame | Build guards | Lets sdl2 build against upstream headers when mali-blob-headers aren't present | Build hygiene, not runtime |
| `0008-fix-kmsdrmmouse-declaration.patch` | knulli team | Rename typo `SDL_mksdrmmous.c` → `SDL_kmsdrmmouse.c` | Build fix on newer SDL2 tarballs | Build hygiene |
| `0012-rga-fbcon-auto-rotate.patch` | knulli team | Auto-rotate fbcon via RGA at KMSDRM init | Console text is rotated correctly on portrait panels; makes serial consoles/emergency shells legible on-screen | Any rk3566 board with a portrait panel |

**Our contribution: `66b36fd`** — the sdl2_drastic patch symlink. Without
this, sdl2_drastic's bundled libSDL2 would silently miss all 9 patches,
which is what shipped previously and manifested as the "rotated wrong",
"tearing", "black cursor" family of drastic-only visual bugs.

These patches cover correctness (rotation, touch), build hygiene
(headers, filename), or a design choice (0002 force-vsync) — the panel
is rotated, RGA is the only sane way to rotate it, and mali-blob can't
be built against upstream headers without 0007.

**One item flagged for future discussion:**
`0002-Force-VSync-when-using-KMSDRM.patch` is a knulli-wide policy patch,
not an rk3566-specific fix. It blocks apps that would want
`SDL_GL_SetSwapInterval(0)` for lower input lag. A "default 1, allow
override" relaxation would be a generic knulli win. Not in scope for
this PR.

## Part 2 — the sdl2_drastic-only patch we authored

Path: `package/emulators/advanced_drastic/sdl2_drastic/0007-rk3566-adopt-sdl-egl-context.patch`.
Gated by `ADVDRASTIC_SDL_GL` (defined only on rk3568 target). h700
(mali-fbdev) and a133 code paths are untouched.

### Why the patch exists — root cause

sdl2_drastic ships a `video_handler` thread (`drastic_video.c` inside
the fork) that sets up its own DRM+GBM+EGL and drives the display
directly, in parallel with SDL's KMSDRM backend that main initialised
via `SDL_CreateWindow` / `SDL_GL_CreateContext`. On the h700 mali-fbdev
stack this happens to work because the two backends use different
subsystems. On rk3566 with mali-blob-gbm it doesn't:

- `gbm_bo_get_handle()` on a mali-blob GBM buffer does **not** return a
  valid DRM GEM handle, so `drmModeAddFB` on it fails EINVAL. The
  video_handler's flip pipeline dies at first frame.
- Even if we somehow synthesised a valid handle, both SDL and
  video_handler would be fighting for DRM master on the same CRTC.

Result on stock upstream sdl2_drastic on rk3566: audio + input work,
display never comes up (black screen), then eventually the process
dies. It's a hard architectural incompatibility with the mali-blob-gbm
variant.

### What the patch actually does — three concerns in one file

The patch has been through three iterations (commits `b407c0a`,
`168d49c`, `0bbc16b`); the final file combines three concerns.

**A. Cross-thread EGL context adoption (`b407c0a`, the core change).**
Instead of building a parallel DRM/EGL setup, video_handler *adopts*
the SDL-created EGL context and drives it from the video thread:

1. Main thread's first render callback calls
   `release_main_gl_context_once`, which stashes the current
   `SDL_Window` + `SDL_GLContext` pointers and then
   `SDL_GL_MakeCurrent(win, NULL)` to release. Mali blob's documented
   behaviour: source thread must unbind before another thread can bind.
2. video_handler lazy-inits on its first `GFX_Flip`/`GFX_Copy` (so main
   has definitely released) and calls `SDL_GL_MakeCurrent(saved_win,
   saved_ctx)`. Cross-thread migration succeeds.
3. `GFX_Flip` calls `SDL_GL_SwapWindow(vid.window)` — **not** raw
   `eglSwapBuffers`. Raw `eglSwapBuffers` only cycles the EGL back
   buffer; SDL's `KMSDRM_GLES_SwapWindow` wraps it in the full
   `lock_front_buffer` / `drmModeAddFB` / `drmModePageFlip` pipeline
   that promotes the GBM front buffer to the scanout plane.

Guard rails: if `egl_init` never succeeds (e.g. main never released)
`GFX_Flip`/`GFX_Copy` no-op, so audio and input keep working even if
video is broken. Lazy-init has a thread-id check so it only runs on
video_handler.

**B. Threaded video decoupling (`168d49c`).** Once the pipeline works,
`SDL_GL_SwapWindow` on this stack takes ~30 ms (kernel 4.19 legacy
`drmModePageFlip` allows only one flip in flight; add mali GPU work +
RGA blit). Under the parent commit `sdl_update_screens` blocked the
main thread on every flip, capping ~30 fps. This commit moves the swap
off main entirely: main pushes a "please display" signal via
`nds.update_menu` / cond_var, video_handler wakes and swaps.

Main should never block on display flips regardless — this is an
architectural cleanup, and it covers the tail of heavier games that
would otherwise drop frames when main and flip share the same thread.

**C. Menu-crash guard (`0bbc16b`).** After egl_init has run on
video_handler, calling `GFX_Copy` / `GFX_Flip` from main SEGVs (NULL
current GL context on main). One call site inside
`display_custom_setting` was still doing that. Fix: hard-guard both
functions to no-op if called off video_handler; replace the offending
inline calls with `nds.update_menu = 1` so video_handler picks up the
render via the normal cond_signal path (the same path the drastic menu
uses everywhere else).

### What's drastic-specific vs generic

The patch is glue between trngaje's sdl2_drastic control flow and SDL's
KMSDRM backend. Concretely:

- **Drastic-specific**: the naming (`vid.eglDisplay`, `nds.update_menu`),
  the release/adopt handshake being triggered from a render callback,
  the `ADVDRASTIC_SDL_GL` build gate. These are directly wired into
  drastic's video pipeline and wouldn't apply to another app.
- **Generic-worthy** (worth extracting for trngaje/SDL_drastic upstream):
  - the *pattern* of "release SDL's GL context on main, adopt it on
    a worker thread, drive display via `SDL_GL_SwapWindow` instead of
    a parallel DRM setup" is a real recipe for any app currently using
    a parallel DRM path on a mali-blob-gbm platform;
  - the threaded-video decoupling (moving swap off main) is entirely
    generic — nothing about it is drastic-shaped;
  - the "never call GFX functions from a non-video thread" invariant
    is a design cleanup, not rockchip-shaped.

### Could we replace this with a generic libSDL2?

Not really, and not without changing scope significantly:

- The patch doesn't modify libSDL2 itself — it only uses libSDL2's
  documented API (`SDL_GL_MakeCurrent`, `SDL_GL_SwapWindow`). What it
  changes is *how sdl2_drastic uses libSDL2*.
- If we wanted to give an unmodified sdl2_drastic (or any other app)
  a working rk3566 experience without app-side changes, that would
  require a shim inside libSDL2 that intercepted attempts to bring up
  a parallel DRM/EGL and redirected them to the SDL backend. That's a
  much bigger design change and would break apps that legitimately want
  their own DRM (e.g. anything that needs page-flip control SDL doesn't
  expose).

For this PR's scope, keeping the patch as a drastic-specific gate is
the right call.

## Buildroot submodule changes

Two commits on the buildroot submodule pointer
(`685c499` bumps the pointer; the submodule commits are `2beea9cc` +
`2ac1b632`):

- `sdl2: always add libgbm/libegl deps when KMSDRM is enabled` —
  works around a `.config` vs `auto.conf` divergence where kconfig
  strips `HAS_LIBGBM=y` / `HAS_LIBEGL=y` from `.config` after
  `syncconfig` (they persist in `auto.conf`). Package `.mk` reads
  `.config`, so the guards fail on clean builds and sdl2 configures
  against missing gbm.h. Drop the inner guards; KMSDRM always needs
  both. Real root cause of the kconfig strip is unknown; worth a
  follow-up.
- `weston: force renderer-gl=false on knulli builds` — the mali libmali
  blob provides only the older gbm ABI. Weston 14's GL renderer needs
  `gbm_bo_get_fd_for_plane` / `gbm_bo_create_with_modifiers2`, which
  aren't present, so it won't link. The shipped release image has
  undefined symbols in libweston-14/drm-backend.so from this — nothing
  actually launches weston. So no functional loss from forcing pixman.

Both are build-hygiene, not runtime perf. Worth landing whether or
not the drastic patches do.

## Testing done

All patches were verified end-to-end on a Powkiddy RGB30 v2 board:

- Mario Kart DS runs at playable speed with our per-device
  `drastic.cfg` layout;
- 2D scenes at 60 fps, 3D playable;
- Menus, HOT+R1 fast-forward, layout switching all work via device
  buttons;
- Console + fbcon rotation both correct;
- No black-screen crash (regression baseline: stock sdl2_drastic on
  rk3566 without patch A gives a black screen).

Still to test on a v1 board.

## Related work / see also

- `docs/rk3566-uboot-rebuild.md` — u-boot rebuild story that pairs
  with the DTB HW-rev split
- upstream: acmeplus's incoming rk3566 unification (will need our
  u-boot changes merged in); trngaje's SDL_drastic (upstream target
  for the threaded-video + adopt-context bits)
