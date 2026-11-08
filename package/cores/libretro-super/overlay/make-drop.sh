#!/usr/bin/env bash
# vim: set ts=3 sw=3 noet ft=sh :
#
# make-drop.sh <profile> [--out <dir>]      (or: --all)
#
# Package a built profile into a DROP: the single directory the knulli build
# consumes once BR2_PACKAGE_KNULLI_EXTERNAL_LIBRETRO_CORES is set and Buildroot
# stops compiling cores.
#
#    drop/<profile>/
#       cores/            the .so files, renamed to what knulli expects
#       assets/           a TARGET_DIR-rooted tree (usr/share/..., usr/bin/...)
#       cores.list        core -> installed name, one per line
#       knulli.list       payload the knulli side must install from ITS OWN tree
#       drop.info         provenance
#
# assets/ is rooted at TARGET_DIR so the knulli side is a plain recursive copy
# with no per-core knowledge -- it does not need to read the manifest, parse
# rows, or know that fbneo has DATs.  All of that is resolved here, where the
# checkouts are.
#
# Inputs: dist/<profile>/ (from libretro-buildbot-recipe.sh), plus
# coreassets/cores.assets and coreassets/cores.map.
#
# THE DROP IS KEYED ON THE PROFILE, NOT THE DEVICE, for the same reason dist/
# is: boards sharing an ABI share artifacts.  devices/*.device maps a board to
# its profile; that lookup happens on the knulli side.

set -euo pipefail

BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MANIFEST="$BASE_DIR/coreassets/cores.assets"
COREMAP="$BASE_DIR/coreassets/cores.map"
OUT_ROOT="$BASE_DIR/drop"

die() { echo "make-drop: $*" >&2; exit 1; }

# rsync is what makes exclude= and directory-merge semantics cheap; every other
# option here (cp -a plus find-prune) is worse.  It is already a build-host
# requirement -- knulli's own libretro-fbneo.mk shells out to it.
command -v rsync >/dev/null || die "rsync is required"

make_drop() {
	local profile="$1" out="$2"
	local dist="$BASE_DIR/dist/$profile"

	[ -d "$dist" ] || die "no dist for profile '$profile' -- build it first: ./libretro-buildbot-recipe.sh recipes/generated/$profile"

	rm -rf "$out"
	mkdir -p "$out/cores" "$out/assets"

	# ----- cores ----------------------------------------------------------
	# The map is only the disagreements; anything unlisted ships under its own
	# name.  Reading it into an array keeps the per-core loop from re-scanning
	# the file 115 times.
	local n_cores=0 n_renamed=0
	declare -A rename
	if [ -f "$COREMAP" ]; then
		while read -r from to _; do
			case "$from" in ''|'#'*) continue ;; esac
			[ -n "${to:-}" ] && rename["$from"]="$to"
		done < "$COREMAP"
	fi

	local so base target
	for so in "$dist"/*.so; do
		[ -e "$so" ] || continue
		base="$(basename "$so")"
		target="${rename[$base]:-$base}"
		cp -a "$so" "$out/cores/$target"
		echo "$base $target" >> "$out/cores.list"
		n_cores=$((n_cores+1))
		[ "$target" != "$base" ] && n_renamed=$((n_renamed+1))
	done
	[ "$n_cores" -gt 0 ] || die "$profile: dist/ has no .so files"

	# Renaming to a name we ALSO build under would silently clobber one core
	# with another.  Cheap to check, impossible to debug on target.
	local dupes
	dupes="$(cut -d' ' -f2 "$out/cores.list" | sort | uniq -d)"
	[ -n "$dupes" ] && die "$profile: two cores map to the same target name: $dupes"

	# ----- assets ---------------------------------------------------------
	# A payload row only applies if THIS profile actually shipped the core it
	# belongs to.  Otherwise every profile carried mame's 113 MB hash/ tree and
	# ppsspp's 23 MB of assets regardless of whether those cores were built for
	# it -- armv7 builds neither, and was getting both.
	local n_asset=0 n_pending=0 n_knulli=0 n_nocore=0
	: > "$out/knulli.list"

	declare -A shipped
	local t
	while read -r _ t; do shipped["$t"]=1; done < "$out/cores.list"

	while read -r core origin src dest opts; do
		case "$core" in ''|'#'*) continue ;; esac
		[ -z "${dest:-}" ] && continue

		# The .so this core installs.  Defaults to <core>_libretro.so; the
		# cores whose name does not follow that (mame2010 -> mame0139, pc98 ->
		# np2kai, ...) carry an explicit so= in opts.
		local soname="${core}_libretro.so" o
		for o in ${opts//,/ }; do
			case "$o" in so=*) soname="${o#so=}" ;; esac
		done
		if [ -z "${shipped[$soname]:-}" ]; then
			n_nocore=$((n_nocore+1))
			continue
		fi

		local dst="$out/assets/$dest"

		case "$origin" in
			mkdir)
				mkdir -p "$dst"
				n_asset=$((n_asset+1))
				;;
			knulli)
				# Deliberately NOT copied.  These files belong to the knulli
				# tree (evmapy key maps, knulli's own flycast .info files);
				# duplicating them here would create a second copy that drifts
				# from the one upstream maintains.  Recorded so the knulli-side
				# installer can act on them.
				echo "$core $src $dest" >> "$out/knulli.list"
				n_knulli=$((n_knulli+1))
				;;
			core|build|static)
				local abs
				case "$origin" in
					static) abs="$BASE_DIR/coreassets/static/$src" ;;
					*)      abs="$BASE_DIR/$src" ;;
				esac

				if [ ! -e "$abs" ]; then
					# Not fatal: the core is simply not in a coreset yet, or
					# (origin=build) has not built.  check-assets.sh reports
					# the same thing; here we just leave it out and say so.
					echo "  pending: $core ($src)"
					n_pending=$((n_pending+1))
					continue
				fi

				local excl=() o
				for o in ${opts//,/ }; do
					case "$o" in exclude=*) excl+=(--exclude="${o#exclude=}") ;; esac
				done

				if [ -d "$abs" ]; then
					# Trailing slashes: copy the CONTENTS of src into dest,
					# which is what "dest is the final path of what src
					# becomes" means for a directory.
					mkdir -p "$dst"
					rsync -a "${excl[@]}" "$abs/" "$dst/"
				else
					mkdir -p "$(dirname "$dst")"
					rsync -a "${excl[@]}" "$abs" "$dst"
				fi
				n_asset=$((n_asset+1))
				;;
			*)
				die "unknown origin '$origin' for $core"
				;;
		esac
	done < "$MANIFEST"

	# ----- provenance -----------------------------------------------------
	{
		echo "profile   $profile"
		echo "cores     $n_cores ($n_renamed renamed via coreassets/cores.map)"
		echo "assets    $n_asset rows applied, $n_pending pending, $n_nocore skipped (core not in this profile), $n_knulli left to knulli"
		echo "size      cores $(du -sh "$out/cores" | cut -f1), assets $(du -sh "$out/assets" | cut -f1)"
		echo
		echo "Consumed by board/scripts/install-libretro-cores.sh in the knulli"
		echo "tree, which copies cores/ to /usr/lib/libretro and assets/ over"
		echo "TARGET_DIR.  It needs no knowledge of individual cores: every"
		echo "per-core decision (renames, exclude rules, which payload comes"
		echo "from which checkout) was resolved here."
		echo
		echo "knulli.list is the exception -- payload that lives in the knulli"
		echo "tree and is installed from there, not from this drop."
	} > "$out/drop.info"

	echo "make-drop: $profile -> $out"
	sed 's/^/  /' "$out/drop.info" | head -4
}

[ $# -gt 0 ] || die "usage: $0 <profile> [--out <dir>]   |   $0 --all"

PROFILES=()
OUT_OVERRIDE=""
while [ $# -gt 0 ]; do
	case "$1" in
		--all)
			for _p in "$BASE_DIR"/profiles/*.profile; do
				_p="${_p##*/}"; PROFILES+=("${_p%.profile}")
			done
			;;
		--out) OUT_OVERRIDE="$2"; shift ;;
		*)     PROFILES+=("$1") ;;
	esac
	shift
done

[ "${#PROFILES[@]}" -gt 0 ] || die "no profile given"

for p in "${PROFILES[@]}"; do
	# --all sweeps every profile, including ones never built; skip those
	# quietly rather than aborting the sweep.
	if [ ! -d "$BASE_DIR/dist/$p" ]; then
		echo "make-drop: skipping $p (never built)"
		continue
	fi
	make_drop "$p" "${OUT_OVERRIDE:-$OUT_ROOT/$p}"
done
