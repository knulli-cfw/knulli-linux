#!/usr/bin/env bash
#
# build-cores.sh <profile> <cache-dir> <sysroot-bin> <overlay-dir> <patch-dir> <upstream-rev>
#
# Build every libretro core for one ABI profile and leave a drop behind.
# Called by "make <board>-cores-drop", NOT by an image build -- libretro-super.mk
# only checks the drop exists and installs it.  See there for why.
#
# WHY THIS LIVES OUTSIDE THE BUILDROOT OUTPUT TREE
#
# The work directory holds ~140 core git checkouts (several GB, an hour or more
# of cloning).  If it lived in output/<board>/build it would be destroyed by
# "make <board>-clean" and re-cloned from scratch, and it would be duplicated
# per board even though the drop is shared across every board on the ABI.  So
# the cache is a sibling of output/ and outlives any single board's build --
# the same reasoning that has install-32bit-libs.sh reach into a second output
# tree rather than rebuild libraries per board.
#
#    <cache>/libretro-super/     upstream clone + our patch + our overlay
#    <cache>/drop/<profile>/     cores/ + assets/, what actually gets installed
#
# THE CACHE IS THE POINT.  "make h700-cores-drop" builds the aarch64-v8a drop
# once; h700, a133, rk3326 and rk3576 image builds then install it and compile
# nothing.  Re-running is a no-op unless the drop is removed or FORCE=1.

set -euo pipefail

PROFILE="${1:?profile}"
CACHE="${2:?cache dir}"
SYSROOT_BIN="${3:?sysroot bin}"
OVERLAY="${4:?overlay dir}"
PATCHDIR="${5:?patch dir}"
UPSTREAM_REV="${6:?upstream rev}"

UPSTREAM_URL="${LIBRETRO_SUPER_URL:-https://github.com/libretro/libretro-super.git}"
WORK="$CACHE/libretro-super"
DROP="$CACHE/drop/$PROFILE"

say() { echo "libretro-super: $*"; }

# ---- cache hit? ------------------------------------------------------------
# A PARTIAL drop is deliberately NOT a hit.  Its missing cores are unstamped, so
# a rerun retries exactly those and leaves the rest alone -- which is the whole
# loop for bringing a profile up.  Treating it as a hit would mean the only way
# to retry 13 cores is FORCE=1, i.e. rebuilding all 130.
# UPDATE=1 opens the same gate as FORCE=1 but builds far less: it sets NOCLEAN
# for the buildbot, which skips the per-core fetch/reset, so a core already in
# the work tree keeps its HEAD and reports BUILD=NO.  Only cores missing
# locally, or whose recipe line or patch set changed, are built.  FORCE=1 has
# no such effect on the buildbot -- it only opens this gate, and everything
# rebuilds because fetch+reset moves HEAD on every unpinned core.
if [ -n "${LIBRETRO_SUPER_UPDATE:-}" ]; then
	export NOCLEAN=1
fi
GATE_OPEN="${LIBRETRO_SUPER_FORCE:-}${LIBRETRO_SUPER_UPDATE:-}"

if [ -d "$DROP/cores" ] && [ ! -f "$DROP/PARTIAL" ] && [ -z "$GATE_OPEN" ]; then
	say "drop for $PROFILE already built ($(ls "$DROP/cores" | wc -l) cores) -- nothing to do"
	say "pass UPDATE=1 to add missing/changed cores, or FORCE=1 to rebuild every core"
	exit 0
fi
if [ -f "$DROP/PARTIAL" ] && [ -z "$GATE_OPEN" ]; then
	say "drop for $PROFILE is PARTIAL -- retrying $(wc -l < "$DROP/PARTIAL") missing cores"
fi
if [ -n "${LIBRETRO_SUPER_UPDATE:-}" ]; then
	say "UPDATE mode: not fetching upstream, building only missing/changed cores"
fi

# ---- host tools ------------------------------------------------------------
# Checked here rather than declared as Buildroot DEPENDENCIES: rsync has no
# host-* package in Buildroot (only a target one), and git is a host-system
# tool by definition since it is what fetches the sources in the first place.
for _t in git rsync; do
	command -v "$_t" >/dev/null || {
		echo "libretro-super: '$_t' is required on the build host but was not found" >&2
		exit 1
	}
done

# ---- the toolchain precondition -------------------------------------------
# Checked before any cloning: a missing cross toolchain is the one failure that
# is cheap to detect and expensive to discover an hour into a build.
# gen-toolchain.sh checks the exact compiler binary too; this is the early,
# obvious version of the same check.
[ -d "$SYSROOT_BIN" ] || {
	echo "libretro-super: no toolchain at $SYSROOT_BIN" >&2
	echo "" >&2
	echo "  Profile '$PROFILE' is compiled against a REFERENCE board's sysroot, not" >&2
	echo "  against whichever board is building -- the drop is shared by every board" >&2
	echo "  on this ABI, so its contents must not depend on build order." >&2
	echo "" >&2
	echo "  Build that board first, then retry.  To deliberately build against a" >&2
	echo "  different sysroot, change SYSROOT_BOARD in the profile." >&2
	exit 1
}

# ---- upstream checkout -----------------------------------------------------
mkdir -p "$CACHE"
if [ ! -d "$WORK/.git" ]; then
	say "cloning upstream libretro-super"
	git clone "$UPSTREAM_URL" "$WORK"
fi

say "pinning upstream to $UPSTREAM_REV"
git -C "$WORK" fetch --all --quiet || true
# Reset only the files upstream owns.  A plain "git reset --hard" would also
# blow away the untracked core checkouts under $WORK, which is exactly what the
# cache exists to preserve -- so no -x/-d clean here, ever.
git -C "$WORK" checkout --quiet --force "$UPSTREAM_REV"
git -C "$WORK" checkout --quiet -- .

# ---- our patch on upstream files ------------------------------------------
for p in "$PATCHDIR"/*.patch; do
	[ -e "$p" ] || continue
	if git -C "$WORK" apply --reverse --check "$p" >/dev/null 2>&1; then
		say "already applied: $(basename "$p")"
	elif git -C "$WORK" apply --whitespace=nowarn "$p"; then
		say "applied: $(basename "$p")"
	else
		echo "libretro-super: FAILED to apply $(basename "$p") -- upstream rev moved?" >&2
		exit 1
	fi
done

# ---- our overlay (files upstream never had) --------------------------------
# Not a patch: these are whole new files, and expressing them as a diff against
# an empty tree would make every edit a patch-regeneration chore.
say "overlaying knulli tree"
rsync -a "$OVERLAY"/ "$WORK"/
chmod +x "$WORK"/gen-recipe.sh "$WORK"/gen-toolchain.sh \
         "$WORK"/make-drop.sh "$WORK"/check-assets.sh

# ---- generate, build, package ---------------------------------------------
say "generating wrapper toolchain for $PROFILE"
"$WORK/gen-toolchain.sh" "$PROFILE" --sysroot-bin "$SYSROOT_BIN"

# --sysroot-bin for the same reason gen-toolchain.sh gets it: the profile's
# SYSROOT_BIN is an absolute path into whichever tree the profile was authored
# in, and it does not exist here (nor in the container at all).  Passing it
# keeps the recipe's PATH and the generated cmake toolchain file agreeing with
# the wrapper about which sysroot this is.
say "generating recipe for $PROFILE"
"$WORK/gen-recipe.sh" "$PROFILE" --sysroot-bin "$SYSROOT_BIN"

# TMPDIR is where the buildbot puts its per-core logs (and its own scratch:
# vars, built-cores).  Left at the default it resolves to /tmp, which inside the
# build container is container-local -- so the log of a core that FAILED was
# already gone by the time the run reported the failure, which is precisely when
# it is wanted.  Pointed at the cache instead, beside the clone rather than
# inside it: build-cores.sh does "git checkout --force" on $WORK every run, so
# logs kept under there would be at the mercy of it.
#
# This does export TMPDIR to the compilers too, so their scratch files land here
# as well.  They are transient -- gcc unlinks them per invocation -- and the
# alternative is patching the buildbot to take a separate log root, which is a
# lot of divergence from upstream for a directory nobody looks in.
BUILDBOT_TMP="$CACHE/buildbot"
mkdir -p "$BUILDBOT_TMP"

say "building cores for $PROFILE (this is the slow part, and it is cached)"
say "logs: $BUILDBOT_TMP/log/*/$(date +%Y-%m-%d)/"
bb_status=0
( cd "$WORK" && TMPDIR="$BUILDBOT_TMP" ./libretro-buildbot-recipe.sh "recipes/generated/$PROFILE" ) || bb_status=$?

# ---- failures: package what built, unless told not to ----------------------
# Failing cores do NOT withhold the drop.  A profile is brought up incrementally
# -- a handful of cores wanting per-core args or patches is the normal state for
# a while -- and refusing to package would block every image build on the ABI on
# work that has nothing to do with them.
#
# What makes that safe is that the gap is never silent: the drop carries a
# PARTIAL file naming exactly what is missing, and libretro-super.mk prints it
# at image-build time.  Nothing downstream has to take completeness on trust.
#
# LIBRETRO_SUPER_REQUIRE_ALL is the opposite bargain, for when a drop is meant
# to be final: any failure and nothing is packaged at all.
if [ "$bb_status" -ne 0 ] && [ -n "${LIBRETRO_SUPER_REQUIRE_ALL:-}" ]; then
	echo "" >&2
	echo "libretro-super: cores failed and REQUIRE_ALL was set -- no drop packaged" >&2
	echo "  logs:  $BUILDBOT_TMP/log/*/$(date +%Y-%m-%d)/" >&2
	echo "  rerun without REQUIRE_ALL to package the cores that did build" >&2
	exit "$bb_status"
fi

say "packaging drop"
"$WORK/make-drop.sh" "$PROFILE" --out "$DROP"

[ -d "$DROP/cores" ] || { echo "libretro-super: no drop produced" >&2; exit 1; }

# Written after make-drop.sh, which does not know about it, and removed on a
# clean run so a drop cannot stay marked partial once it is complete.
rm -f "$DROP/PARTIAL"
if [ "$bb_status" -ne 0 ]; then
	# The list comes from the buildbot's local hook.  If it is absent the run
	# failed some other way -- a broken recipe, a shell error -- and the drop
	# must still be marked, or an unmarked partial drop is exactly the silent
	# gap PARTIAL exists to prevent.
	if [ -f "$BUILDBOT_TMP/failed-cores" ]; then
		cp "$BUILDBOT_TMP/failed-cores" "$DROP/PARTIAL"
	else
		echo "(the build exited $bb_status without naming cores -- see the logs)" \
			> "$DROP/PARTIAL"
	fi
	say "drop ready but PARTIAL: $DROP ($(ls "$DROP/cores" | wc -l) cores)"
	say "missing: $(tr '\n' ' ' < "$DROP/PARTIAL")"
	say "logs: $BUILDBOT_TMP/log/*/$(date +%Y-%m-%d)/"
	# Exit 0: the drop asked for was produced, and the gap is recorded in
	# PARTIAL rather than in this status.  REQUIRE_ALL is how a caller asks for
	# a status that fails on missing cores.
	exit 0
fi
say "drop ready: $DROP ($(ls "$DROP/cores" | wc -l) cores)"
