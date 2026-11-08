#!/usr/bin/env bash
# vim: set ts=3 sw=3 noet ft=sh :
#
# check-assets.sh [<knulli-linux-root>]
#
# Validate coreassets/cores.assets: every src must actually resolve.
#
# This exists because the manifest's whole value is being trustworthy at the
# moment the knulli build stops compiling cores.  A src that quietly stopped
# existing -- upstream renamed a directory, a core dropped out of a coreset and
# its checkout went away -- would show up as missing BIOS or a core that will
# not draw its menus, on target, long after the fact.  Run this before cutting
# a drop.
#
# "core" rows resolve against this repo's checkouts, "static" against
# coreassets/static/, "knulli" against the knulli-linux root (optional: skipped
# with a note when not given, since that tree is not ours and may not be here).
#
# Exit 1 if any REQUIRED src is missing.  Rows for cores that have no checkout
# because the core is not in any coreset are reported as "pending", not failed:
# the manifest deliberately keeps them so the inventory stays complete.

set -uo pipefail

BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MANIFEST="$BASE_DIR/coreassets/cores.assets"
KNULLI_ROOT="${1:-}"

[ -f "$MANIFEST" ] || { echo "check-assets: no manifest at $MANIFEST" >&2; exit 1; }

ok=0 pending=0 skipped=0 fail=0

while read -r core origin src dest opts; do
	case "$core" in ''|'#'*) continue ;; esac
	[ -z "${dest:-}" ] && continue

	case "$origin" in
		mkdir)
			ok=$((ok+1))
			;;
		build)
			# Produced by the core's build, not by its checkout.  Absent until
			# that core builds, which is a normal state, not a broken manifest.
			if [ -e "$BASE_DIR/$src" ]; then
				ok=$((ok+1))
			else
				echo "pending  $core: $src (build artifact -- core not built yet)"
				pending=$((pending+1))
			fi
			;;
		core)
			# The checkout directory is the first path component.  When the
			# whole checkout is absent the core simply is not in a coreset --
			# that is the "pending" case, distinct from a checkout that exists
			# but no longer contains the file, which is a real breakage.
			checkout="${src%%/*}"
			if [ ! -d "$BASE_DIR/$checkout" ]; then
				echo "pending  $core: no checkout $checkout (core not in any coreset)"
				pending=$((pending+1))
			elif [ -e "$BASE_DIR/$src" ]; then
				ok=$((ok+1))
			else
				echo "MISSING  $core: $src (checkout $checkout exists -- path moved upstream?)" >&2
				fail=$((fail+1))
			fi
			;;
		static)
			if [ -e "$BASE_DIR/coreassets/static/$src" ]; then
				ok=$((ok+1))
			else
				echo "MISSING  $core: coreassets/static/$src" >&2
				fail=$((fail+1))
			fi
			;;
		knulli)
			if [ -z "$KNULLI_ROOT" ]; then
				skipped=$((skipped+1))
			elif [ -e "$KNULLI_ROOT/$src" ]; then
				ok=$((ok+1))
			else
				echo "MISSING  $core: $src (under $KNULLI_ROOT)" >&2
				fail=$((fail+1))
			fi
			;;
		*)
			echo "MISSING  $core: unknown origin '$origin'" >&2
			fail=$((fail+1))
			;;
	esac
done < "$MANIFEST"

echo
echo "resolved $ok, pending $pending, failed $fail"
[ "$skipped" -gt 0 ] && echo "skipped $skipped knulli-origin rows (pass the knulli-linux root to check them)"
[ "$fail" -gt 0 ] && exit 1
exit 0
