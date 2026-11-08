# Profile-driven recipe generation

Local extension. Splits a buildbot recipe into four pieces so that devices
sharing a CPU/ABI share one `dist/` instead of each rebuilding the same cores.

```
devices/<device>.device    WHO    profile to consume, core sets, patch set
profiles/<name>.profile    HOW    toolchain, ABI, platform, dist dir, patch tags
coresets/<set>.coreset     WHAT   recipe lines with NO per-core args
coreargs/cores.args        WHICH  per-core args, scoped any|arm32|arm64
        |
        v  ./gen-recipe.sh <device>
recipes/generated/<device>{,.conf,.provenance}
```

The recipe and conf are **comment-free on purpose**. Neither of the buildbot's
parsers handles `#`: the conf loop (`libretro-buildbot-recipe.sh:25-39`) skips
only empty lines and then `export ${KEY}="${VALUE}"`, so a comment produces
`export #=...` → *not a valid identifier*; the recipe loop (`:626`) is a bare
`while read line; do eval "set -- \$line"`, where a comment survives only
because its 5th word isn't `YES` and the ENABLED check at `:662` skips it.
Anything a human needs to know goes in `<device>.provenance`, which nothing reads.

Build: `./libretro-buildbot-recipe.sh recipes/generated/<device>`

## Why the split

`dist/` is keyed on the **CPU/ABI profile, not the device** — GPU is excluded
from the key, because a non-GL core's output is identical on two devices with
the same ABI. `atm7039` and a future `atm7051.device` both point at
`armv7-neon-cortexa9-hf` and reuse one set of `.so` files.

`coreargs/cores.args` carries the other axis: args that are true of one *core*.
Its `scope` column is matched against the profile's `ARCH_CLASS`, so the
ARM32-only asm gates (`USE_CYCLONE`, `USE_DRZ80`, `DYNAREC=ari64`,
`CPU_ARCH=arm`) attach on armv7 profiles and vanish on aarch64, while identity
args (`EMUTYPE=`, `USE_BLARGG_APU=1`) attach everywhere.

## Pinning a core to a commit

Recipe/coreset field 4 accepts `<branch>` or `<branch>@<sha>`:

```
2048 libretro-2048 https://github.com/libretro/libretro-2048.git master@fe340fc1d4... YES GENERIC Makefile.libretro .
```

A pinned core is hard reset to that commit every run and **never** to the branch
tip, so an upstream regression cannot land silently — the failure mode
`doublecherrygb` hit when upstream vendored libmobile mid-day. The branch is
still required: it is what gets fetched, and what a shallow clone needs.

Because GitHub does not enable `uploadpack.allowReachableSHA1InWant`, a bare
`fetch <sha>` is refused; `ensure_pinned_rev` therefore tries it anyway (other
hosts allow it), then deepens the branch 64 → 512 → 4096 commits, and only
unshallows as a last resort. Most pins land in the first step.

Changing a pin changes the recipe line, which the existing
`.libretro-core-recipe` check already turns into a rebuild. An unresolvable pin
logs `!!! PIN NOT FOUND` and falls back to the branch rather than failing.

Pins are a tool, not a default: knulli/batocera pin conservatively and many of
those commits are old enough to be worth moving forward deliberately.

## Status

| profile | enabled | built | notes |
|---|---|---|---|
| `armv7-neon-cortexa9-hf` | 125 | 113 | tier1 57/57; devices atm7039 (+ATM7051) |
| `aarch64-v8a` | 127 | 115 | +`arm64-only` coreset (`mame` off, `dolphin`, `play`) |
| `aarch64-v8.2a` | - | never built | wrapper toolchain exists, no device pointed at it yet |
| `armv7-neon-cortexa7-hf` | - | never built | ditto |

Count what is actually there with:

```sh
p=armv7-neon-cortexa9-hf
comm -23 <(awk '$5=="YES"{print $1}' recipes/generated/$p | sort) \
         <(ls dist/$p/*.so | xargs -n1 basename | sed 's/_libretro\.so$//' | sort)
```

### Known-unbuildable, and why

Not failures to chase -- each is a property of the target, not of the recipe.

| core | armv7 | aarch64 | reason |
|---|---|---|---|
| `blastem`, `kronos` | x | x | Makefiles emit `-m64` / `-msse` |
| `bsnes`, `bsnes_hd_beta` | x | x | need X11/Xrandr headers |
| `boom3`, `desmume`, `melondsds` | x | x | desktop GL |
| `easyrpg` | x | x | needs SDL3 in the sysroot |
| `emuscv` | x | x | bootstraps host tool `tools/bin2c` with the cross CC |
| `mupen64plus_next` | x | x | undiagnosed |
| `same_cdi` | x | ok | armv7 only: MAME PCH (`obj/libretro/emu.h`) missing under -j32 |
| `ppsspp` | x | ok | `GL_MAX_CLIP_DISTANCES_EXT` absent from GLES headers |
| `dolphin` | n/a | x | refuses 4-byte pointers; `arm64-only` coreset |
| `play` | n/a | x | hard-includes `<GLES3/gl3.h>`; `arm64-only` coreset |
| `pcsx2` | n/a | n/a | `github.com/libretro/pcsx2` is gone; `ENABLED=NO` |

A 404 on clone surfaces as `fatal: could not read Username for 'https://github.com'`,
because git falls back to asking for credentials. It is not an auth problem.

## Gotchas that cost real debugging time

**Never run `gen-recipe.sh` while a build is in flight.** `libretro-buildbot-recipe.sh:943`
reads the recipe with a live `while read ... done < $RECIPE`, and the generator
truncates that same inode -- the running loop's offset lands mid-file and it
silently skips cores. The symptom is a core missing from the run's `processing`
lines but still present in `dist/` from an earlier build, which reads as success.

**`EXTRA_ARGS` is make-only; `CMAKE_EXTRA_ARGS` is cmake-only.** CORE_ARGS goes
straight onto the cmake command line, so a make variable like `HAVE_NEON=1`
arrives as a positional argument and cmake reads it as the source directory.
The visible error is the *next* step failing with `No rule to make target
'Makefile'`, which points nowhere near the cause.

**`VAR=value` in a CMAKE core's args is exported, not passed to cmake.** Make
re-exports command-line variables to its recipe subprocesses, which is how the
compiler wrapper receives `NO_FAST_MATH=1`; cmake has no equivalent, so the
CMAKE branch splits those tokens out and exports them itself.
