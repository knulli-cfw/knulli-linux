#!/usr/bin/env bash
# vim: set ts=3 sw=3 noet ft=sh :
#
# gen-recipe.sh <profile> [<profile> ...] [--sysroot-bin <dir>]   (or: --all)
#
# Compose a buildbot recipe + .conf pair for an ABI PROFILE:
#
#    profiles/<name>.profile   HOW   -- toolchain, ABI, platform, dist dir,
#                                       core sets, patch set
#    coresets/<set>.coreset    WHAT  -- the core lines, no per-core args
#    coreargs/cores.args       WHICH -- per-core args, gated on ARCH_CLASS
#
# Output:
#
#    recipes/generated/<profile>        the recipe
#    recipes/generated/<profile>.conf   its conf
#
# then build with:
#
#    ./libretro-buildbot-recipe.sh recipes/generated/<profile>
#
# THE BUILD UNIT IS THE PROFILE, NOT THE DEVICE.  dist/ is keyed on the CPU/ABI
# profile, so generating per device would emit N identical recipes writing into
# one dist/ -- duplicated work, and a race if two ran at once.  devices/*.device
# is the integration map (device -> profile), consumed downstream when a device
# image picks cores out of its profile's dist/; it is not an input here.
#
# This generator only writes into recipes/generated/.  The hand-written
# recipes/linux/* are never touched.

set -euo pipefail

BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUT_DIR="$BASE_DIR/recipes/generated"

die() { echo "gen-recipe: $*" >&2; exit 1; }

# Read "KEY value..." files.  Blank lines and #-comments are dropped.  Echoes
# the value of $2 in file $1, or nothing.  Later definitions win.
kv_get() {
	awk -v key="$2" '
		/^[[:space:]]*(#|$)/ { next }
		$1 == key { $1 = ""; sub(/^[[:space:]]+/, ""); v = $0 }
		END { if (v != "") print v }
	' "$1"
}

gen_one() {
	local profile_name="$1"
	local sysroot_override="${2:-}"
	local prof="$BASE_DIR/profiles/${profile_name}.profile"
	[ -f "$prof" ] || die "no such profile: $prof"

	# The recipe is named after the profile, so PATCH_SET (which the buildbot
	# defaults to the recipe basename) and the stamp dir line up by default.
	local device="$profile_name" coresets patch_set
	coresets="$(kv_get "$prof" CORESETS)"
	patch_set="$(kv_get "$prof" PATCH_SET)"
	[ -n "$coresets" ] || die "$profile_name: CORESETS not set"

	local arch_class toolchain_bin toolchain_name sysroot_bin platform dist_dir
	local patch_tags extra_args cmake_extra_args makeportable uname_m
	arch_class="$(kv_get "$prof" ARCH_CLASS)"
	# TOOLCHAIN_BIN is derived, not declared: the wrapper toolchain is generated
	# by gen-toolchain.sh into toolchain-<TOOLCHAIN_NAME>/bin, and a profile that
	# could name a different path would just be a way to point the recipe at a
	# toolchain nobody generated.
	toolchain_name="$(kv_get "$prof" TOOLCHAIN_NAME)"
	[ -n "$toolchain_name" ] || die "$profile_name: TOOLCHAIN_NAME not set"
	toolchain_bin="$BASE_DIR/toolchain-${toolchain_name}/bin"
	# --sysroot-bin wins over the profile, same as gen-toolchain.sh: the profile
	# can only name one absolute path, and this tree is checked out in more than
	# one place (the knulli build runs it out of cores-cache/, in a container
	# where the profile's path does not exist at all).
	sysroot_bin="${sysroot_override:-$(kv_get "$prof" SYSROOT_BIN)}"
	platform="$(kv_get "$prof" PLATFORM)"
	# DERIVED, not declared, for the same reason as TOOLCHAIN_BIN above -- and
	# because make-drop.sh already reads $BASE_DIR/dist/<profile> unconditionally.
	# A profile that could name a different dist would just be a way to have the
	# buildbot write where make-drop.sh does not look.
	dist_dir="$BASE_DIR/dist/${profile_name}"
	patch_tags="$(kv_get "$prof" PATCH_TAGS)"
	extra_args="$(kv_get "$prof" EXTRA_ARGS)"
	cmake_extra_args="$(kv_get "$prof" CMAKE_EXTRA_ARGS)"
	makeportable="$(kv_get "$prof" MAKEPORTABLE)"
	uname_m="$(kv_get "$prof" UNAME_M)"
	[ -n "$arch_class" ] || die "$profile_name: ARCH_CLASS not set"
	[ -n "$platform" ]   || die "$profile_name: PLATFORM not set"

	# PATCH_SET defaults (in the buildbot) to the recipe basename, which is the
	# profile name -- the same thing a profile normally declares explicitly.
	patch_set="${patch_set:-$profile_name}"

	mkdir -p "$OUT_DIR"

	# ----- the recipe -----------------------------------------------------
	#
	# NO comments, NO blank lines.  libretro-buildbot-recipe.sh:626 reads the
	# recipe with a bare `while read line; do eval "set -- \$line"` -- it has no
	# comment handling at all.  A "#..." line survives only by accident, because
	# its 5th word is not "YES" so the ENABLED check at :662 skips it; a comment
	# whose 5th word happened to be YES would be treated as a core and cloned.
	# Provenance goes in <device>.provenance instead.
	local recipe="$OUT_DIR/$device"
	: > "$recipe"

	local set_name set_file
	for set_name in $coresets; do
		set_file="$BASE_DIR/coresets/${set_name}.coreset"
		[ -f "$set_file" ] || die "$device: no such coreset: $set_file"
		awk -v arch="$arch_class" -v argfile="$BASE_DIR/coreargs/cores.args" \
		    -v uname_m="$uname_m" \
		    -v cmake_tc="$BASE_DIR/cmake/${profile_name}-toolchain.cmake" '
			# Expand profile placeholders in an arg value.  Only ${UNAME_M} for
			# now: it lets one coreargs line serve every profile instead of
			# needing an arm32/arm64 pair per arch-detecting core.
			function expand(s) {
				gsub(/\$\{UNAME_M\}/, uname_m, s)
				gsub(/\$\{CMAKE_TOOLCHAIN\}/, cmake_tc, s)
				return s
			}
			BEGIN {
				while ((getline line < argfile) > 0) {
					if (line ~ /^[[:space:]]*(#|$)/) continue
					n = split(line, f, /[[:space:]]+/)
					scope = f[2]
					if (scope != "any" && scope != arch) continue
					a = ""
					# A value may be double-quoted to contain spaces, e.g.
					#   GL_LIB="-lGLESv2 -lEGL"
					# The recipe format cannot carry that: the buildbot flattens
					# ARGS into one string and evals it twice, so any real space
					# word-splits.  Emit @SP@ instead; the builder restores it
					# (see the local fence in libretro-buildbot-recipe.sh).
					for (i = 3; i <= n; i++) {
						t = f[i]
						if (t ~ /="/ && t !~ /"$/) {         # opening quote
							while (i < n && t !~ /"$/) t = t "@SP@" f[++i]
						}
						gsub(/"/, "", t)
						a = a " " expand(t)
					}
					args[f[1]] = args[f[1]] a
				}
				close(argfile)
			}
			/^[[:space:]]*(#|$)/ { next }
			{ print $0 args[$1] }
		' "$set_file" >> "$recipe"
	done

	# ----- the conf -------------------------------------------------------
	#
	# Also comment-free: the conf parser at libretro-buildbot-recipe.sh:25-39
	# skips only EMPTY lines, then does `export ${KEY}="${VALUE}"` -- a "#..."
	# line yields `export #=...`, i.e. "not a valid identifier" on every run.
	local conf="$OUT_DIR/${device}.conf"
	{
		echo "platform $platform"
		echo "PLATFORM $platform"
		echo "MAKEPORTABLE ${makeportable:-NO}"
		echo "CORE_JOB YES"
		echo "MAKE make"
		echo "CMAKE cmake"
		# PATH is special-cased by the conf parser: wrapper toolchain first so
		# its CC shadows the sysroot's.
		if [ -n "$sysroot_bin" ]; then
			echo "PATH ${toolchain_bin}:${sysroot_bin}"
		else
			echo "PATH ${toolchain_bin}"
		fi
		local k v
		for k in CC CXX CXX11 CXX17 AR RANLIB STRIP; do
			v="$(kv_get "$prof" "$k")"
			[ -n "$v" ] && echo "$k $v"
		done
		echo "RARCH_DIST_DIR $dist_dir"
		echo "PATCH_SET $patch_set"
		[ -n "$patch_tags" ] && echo "PATCH_TAGS $patch_tags"
		[ -n "$extra_args" ] && echo "EXTRA_ARGS $extra_args"
		# ${CMAKE_TOOLCHAIN} is expanded here, not by the shell: the conf
		# parser exports the value verbatim, so an unexpanded ${...} would
		# reach cmake as a literal.
		[ -n "$cmake_extra_args" ] && \
			echo "CMAKE_EXTRA_ARGS ${cmake_extra_args//\$\{CMAKE_TOOLCHAIN\}/$BASE_DIR/cmake/${profile_name}-toolchain.cmake}"
	} > "$conf"

	# ----- cmake toolchain file -------------------------------------------
	# COMMAND=CMAKE cores get no cross-compile hints from the buildbot: its
	# EXTRAARGS case has an empty default for platform=unix, so cmake would
	# treat this as a NATIVE build -- try_run checks misbehave and find_package
	# resolves HOST zlib/png.  CORE_ARGS are passed straight to cmake, so a
	# core opts in with -DCMAKE_TOOLCHAIN_FILE=${CMAKE_TOOLCHAIN} in coreargs.
	# Generated from the profile so the compilers can never drift from it.
	mkdir -p "$BASE_DIR/cmake"
	local tcfile="$BASE_DIR/cmake/${profile_name}-toolchain.cmake"
	# A sysroot that will not resolve is FATAL, never a quietly omitted
	# FIND_ROOT_PATH: without it cmake silently resolves host zlib/png and the
	# core builds against x86 headers, which is the exact failure the toolchain
	# file exists to prevent.  It surfaces as a link error hundreds of cores
	# later, or not at all.
	local sysroot
	[ -d "$sysroot_bin" ] || die "$profile_name: SYSROOT_BIN does not exist: $sysroot_bin (pass --sysroot-bin)"
	# "|| true": under set -e a failing command substitution aborts the script at
	# the assignment, so without it the die below can never be reached.
	sysroot="$(cd "${sysroot_bin}/.." 2>/dev/null && ls -d */sysroot 2>/dev/null | head -1)" || true
	[ -n "$sysroot" ] || die "$profile_name: no */sysroot under $(dirname "$sysroot_bin") -- is that a buildroot host dir?"
	sysroot="$(cd "${sysroot_bin}/.." && cd "$sysroot" && pwd)"
	{
		echo "# GENERATED by gen-recipe.sh from profiles/${profile_name}.profile -- do not edit."
		echo "set(CMAKE_SYSTEM_NAME Linux)"
		echo "set(CMAKE_SYSTEM_PROCESSOR ${uname_m})"
		echo "set(CMAKE_C_COMPILER   \"${toolchain_bin}/$(kv_get "$prof" CC)\")"
		echo "set(CMAKE_CXX_COMPILER \"${toolchain_bin}/$(kv_get "$prof" CXX)\")"
		# NOT CMAKE_SYSROOT: the Buildroot gcc already has its sysroot baked
		# in, and the wrapper prepends the ISA flags.  Only find_package needs
		# steering, or it picks up host libraries.
		echo "set(CMAKE_FIND_ROOT_PATH \"${sysroot}\" \"${sysroot}/usr\")"
		echo "set(PKG_CONFIG_SYSROOT_DIR \"${sysroot}\")"
		echo "set(CMAKE_FIND_ROOT_PATH_MODE_PROGRAM NEVER)"
		echo "set(CMAKE_FIND_ROOT_PATH_MODE_LIBRARY ONLY)"
		echo "set(CMAKE_FIND_ROOT_PATH_MODE_INCLUDE ONLY)"
		echo "set(CMAKE_FIND_ROOT_PATH_MODE_PACKAGE ONLY)"
	} > "$tcfile"

	# ----- provenance -----------------------------------------------------
	# Everything the generated files cannot carry, because neither parser
	# tolerates a comment.  Not read by anything; it exists so a stray
	# recipes/generated/ file is traceable back to its inputs.
	{
		echo "GENERATED by gen-recipe.sh -- do not edit $device or ${device}.conf by hand."
		echo
		echo "profile  profiles/${profile_name}.profile   (ARCH_CLASS ${arch_class})"
		echo "devices  $(grep -l "^PROFILE ${profile_name}\$" "$BASE_DIR"/devices/*.device 2>/dev/null | xargs -r -n1 basename | sed 's/\.device$//' | tr '\n' ' ')"
		echo "coresets ${coresets}"
		echo "args     coreargs/cores.args, scopes: any + ${arch_class}"
		echo "cores    $(wc -l < "$recipe")"
		echo
		echo "The ARM_NEON / CORTEX_A9 / ARM_HARDFLOAT conf keys are deliberately absent."
		echo "They append to FORMAT_COMPILER_TARGET at libretro-buildbot-recipe.sh:104-108,"
		echo "but libretro-config.sh is sourced immediately afterwards and, for platform=unix,"
		echo "assigns FORMAT_COMPILER_TARGET=\"unix\" outright -- so those keys have no effect."
		echo "ISA/ABI flags come from the wrapper toolchain instead; see the profile."
	} > "$OUT_DIR/${device}.provenance"

	echo "gen-recipe: wrote $recipe ($(wc -l < "$recipe") cores), $conf, ${device}.provenance"
}

[ $# -gt 0 ] || die "usage: $0 <profile> [<profile> ...] [--sysroot-bin <dir>]   |   $0 --all"

PROFILES=()
SYSROOT=""
while [ $# -gt 0 ]; do
	case "$1" in
		--all)
			for _p in "$BASE_DIR"/profiles/*.profile; do
				_p="${_p##*/}"; PROFILES+=("${_p%.profile}")
			done
			;;
		--sysroot-bin) SYSROOT="$2"; shift ;;
		*)             PROFILES+=("$1") ;;
	esac
	shift
done

[ "${#PROFILES[@]}" -gt 0 ] || die "no profile given"
for p in "${PROFILES[@]}"; do gen_one "$p" "$SYSROOT"; done
