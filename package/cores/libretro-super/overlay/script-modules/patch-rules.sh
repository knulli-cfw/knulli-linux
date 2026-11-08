# vim: set ts=3 sw=3 noet ft=sh : bash
#
# Tag-layered core patching.
#
# The buildbot does "git reset --hard FETCH_HEAD" + "git clean -xdf" both before
# and after every core build, so a patched working tree cannot survive between
# runs.  Patches are therefore re-applied on each build.
#
# A target declares what it *is* rather than who it is, via PATCH_TAGS in its
# .conf, e.g.
#
#    PATCH_TAGS armv7 neon cortex-a9 fbdev buildroot
#
# and patches are layered in that order, most general first:
#
#    patches/_common/${core}/*.patch      every target
#    patches/${tag}/${core}/*.patch       once per tag, in PATCH_TAGS order
#    patches/${PATCH_SET}/${core}/*.patch the target itself, last word
#
# so a fix that belongs to "every 32-bit ARM core" is written once under
# patches/armv7/ and picked up by every target carrying that tag, instead of
# being copied into each device's directory.  Within a directory, lexical order
# (hence the 0001- prefixes).  PATCH_SET defaults to the recipe's basename.
#
# Because "git clean -xdf" also wipes any stamp kept inside the core checkout,
# the applied-patch fingerprint lives outside it, under .patch-stamps/.  That
# stamp is what makes a *patch* edit force a rebuild -- upstream's BUILD=YES
# logic only notices new commits and recipe-line changes, so without it an
# edited patch would silently never be built.

# Absolute, because apply_core_patches runs "git -C <checkout> apply <path>",
# which resolves a relative <path> against the checkout rather than the cwd --
# and BASE_DIR is only "." when the script is invoked as ./libretro-buildbot-recipe.sh.
PATCH_ROOT="$(cd "${BASE_DIR}" && pwd)/patches"

patch_set_dirs() {
	# $1 = core name.  Echoes the patch dirs that exist, in application order:
	# _common, then each PATCH_TAGS entry, then the target's own set.
	# Symlinked dirs are followed, so cores sharing a repo (the six vice_*)
	# can point at one real patch dir.
	local core="$1" d tag
	for tag in _common ${PATCH_TAGS} "${PATCH_SET}"; do
		d="${PATCH_ROOT}/${tag}/${core}"
		[ -d "$d" ] && echo "$d"
	done
}

core_patch_list() {
	# $1 = core name.  Echoes every patch file, in application order.
	local d
	patch_set_dirs "$1" | while read -r d; do
		# -L: patch dirs may be symlinks (cores sharing a repo, e.g. the six
		# vice_*).  "[ -d ]" follows symlinks but find does not, so without -L
		# a symlinked dir silently yields no patches at all.
		find -L "$d" -maxdepth 1 \( -name '*.patch' -o -name '*.diff' \) | sort
	done
}

core_patch_stamp() {
	# $1 = core name.  Fingerprint of the patch set's *contents*, so editing a
	# patch in place (same filename) still invalidates.
	local list
	list="$(core_patch_list "$1")"
	[ -z "$list" ] && { echo "none"; return; }
	echo "$list" | xargs cat 2>/dev/null | sha256sum | cut -d' ' -f1
}

core_patches_changed() {
	# $1 = core name.  True when the stamp differs from the last applied set.
	local core="$1" stampfile
	stampfile="${BASE_DIR}/.patch-stamps/${PATCH_SET}/${core}"
	[ "$(cat "$stampfile" 2>/dev/null)" != "$(core_patch_stamp "$core")" ]
}

record_core_patch_stamp() {
	# $1 = core name.  Call this ONLY after the core built AND its artifact was
	# copied into dist/.  The stamp means "this patch set was applied and the
	# core produced an artifact", so writing it earlier makes a FAILED core look
	# up to date forever: HEAD unchanged + recipe line unchanged + stamp present
	# => BUILD=NO on every subsequent run, while dist/ keeps serving whatever
	# .so happened to be there from before.  doublecherrygb hit exactly that.
	local core="$1"
	[ "${CORE_PATCHES_OK:-1}" = "1" ] || return 0
	mkdir -p -- "${BASE_DIR}/.patch-stamps/${PATCH_SET}"
	core_patch_stamp "$core" > "${BASE_DIR}/.patch-stamps/${PATCH_SET}/${core}"
}

clear_core_patch_stamp() {
	# $1 = core name.  Drop the stamp so the next run retries this core.
	rm -f -- "${BASE_DIR}/.patch-stamps/${PATCH_SET}/${1}"
}

apply_core_patches() {
	# $1 = core name, $2 = checkout dir (relative to BASE_DIR or absolute).
	# Applies patches only.  The stamp is written later, by
	# record_core_patch_stamp, once the build has actually succeeded.
	#
	# Note a core with NO patches still gets a stamp (the literal "none"),
	# because core_patch_stamp returns "none" while an absent stampfile reads
	# as "" -- the two never match, so without it core_patches_changed forces
	# BUILD=YES on every single run.  That is what made all 81 cores rebuild
	# when nothing had changed.
	local core="$1" dir="$2" p list rc=0
	CORE_PATCHES_OK=1
	list="$(core_patch_list "$core")"
	[ -z "$list" ] && return 0

	echo "=== applying patches for ${core} (set: ${PATCH_SET}) ==="
	while read -r p; do
		[ -z "$p" ] && continue
		if git -C "$dir" apply --reverse --check "$p" >/dev/null 2>&1; then
			echo "  already applied, skipping: ${p##*/}"
			continue
		fi
		if git -C "$dir" apply --whitespace=nowarn "$p" 2>/dev/null; then
			echo "  applied (git apply): ${p##*/}"
		elif patch -d "$dir" -p1 -N -r - < "$p" >/dev/null 2>&1; then
			echo "  applied (patch -p1): ${p##*/}"
		else
			echo "  !!! FAILED to apply: $p" >&2
			rc=1
		fi
	done <<< "$list"

	if [ "$rc" != "0" ]; then
		# Drop the stamp so the next run retries rather than reporting the core
		# as up to date with patches missing, and block record_core_patch_stamp
		# from re-creating it after a build that ran against an unpatched tree.
		CORE_PATCHES_OK=0
		clear_core_patch_stamp "$core"
	fi
	return $rc
}
