#!/usr/bin/env python3
#
# Build an emulator drop out of a build of the emulator packages.
#
# The drop is the payload of the packages in emulators.set, so every other board
# on the same ABI installs them instead of compiling them.  They are ~24 minutes
# of a board build and change far less often than the rest of the image.
#
# WHY BUILDROOT STILL DOES THE BUILDING
#
# libretro cores get their own out-of-tree builder, because a core is a
# self-contained .so behind one narrow ABI -- libretro-super can build it
# knowing almost nothing about the image.  An emulator is an executable linked
# against dozens of sysroot libraries (SDL2, ffmpeg, boost, fluidsynth, ...), so
# an out-of-tree builder would have to reimplement the dependency graph
# buildroot already resolves, and that copy is what would rot.  Buildroot stays
# the builder; what changes is WHEN it runs -- once per ABI when the emulators
# actually change, in its own output dir, never as part of an image build.
#
# WHAT IS BUILT IS NOT THE WHOLE IMAGE
#
# "make <board>-emulators-drop" asks buildroot for the emulator packages BY
# NAME, not for "all".  Buildroot resolves their dependencies from the board's
# own config -- so the closure is exact and nothing hand-maintains it -- but
# nothing outside that closure gets built: no kernel, no rootfs, no kodi, no
# emulationstation.  --print-targets emits that package list.
#
# The cost is that target-finalize never runs, and that is where buildroot
# strips binaries and deletes headers and static libs.  So this script does both
# itself when it copies the payload; otherwise the drop would ship unstripped
# binaries and a usr/include tree.
#
# WHAT GOES IN, AND WHAT DELIBERATELY DOES NOT
#
# build/packages-file-list.txt maps every installed file to the package that
# installed it, so the payload is exact rather than guessed from paths or
# timestamps.
#
# Libraries are NOT in the drop.  SDL2, ffmpeg, python3, pulseaudio and the rest
# are part of the core firmware on their own merits, so the image keeps building
# them and a second copy here could only drift from the first.  The handful that
# existed *only* for the emulators are named in the gate symbol's select list
# instead, so the image keeps those too -- see
# BR2_PACKAGE_KNULLI_EXTERNAL_EMULATORS in package/system/knulli-system.
#
# Usage:
#   harvest-drop.py --output-dir output/emulators-drop/h700 --profile aarch64-v8a \
#                   --cache emulators-cache --set emulators.set \
#                   --pkgdirs <dir> [--pkgdirs <dir> ...] [--readelf <bin>]
#   harvest-drop.py --print-targets --config <.config> --set emulators.set \
#                   --pkgdirs <dir> [--pkgdirs <dir> ...]

import argparse
import glob
import os
import re
import shutil
import subprocess
import sys


def norm(name):
    # buildroot spells one package two ways: '-' in directory names, '_' in make
    # variables and symbols (dosbox-x -> DOSBOX_X).  Compare on one spelling.
    return name.replace("_", "-").lower()


def load_set(path):
    """emulators.set -> (packages, keep).

    packages maps normalised -> as-written.  Both spellings are needed: the file
    list and dependency data use one, and the manifests should echo back what the
    set file actually says, or anyone comparing the two files trips over
    advanced_drastic vs advanced-drastic.

    keep holds the '#keep <name>' lines: packages that live under an emulator
    directory but deliberately stay in the base image, so the "installed but not
    listed" warning does not fire on them every time.
    """
    names = {}
    keep = set()
    for line in open(path):
        stripped = line.strip()
        if stripped.startswith("#keep "):
            keep.add(norm(stripped.split(None, 1)[1].strip()))
            continue
        line = line.split("#")[0].strip()
        if line:
            names[norm(line)] = line
    return names, keep


def file_list_sources(output_dir):
    """Where the package -> file mapping can be read from.

    Each package writes build/<pkg>/.files-list.txt as it installs; buildroot
    concatenates those into build/packages-file-list.txt, but only in
    target-finalize, which a package-targeted build never reaches.  The aggregate
    is a plain cat of the parts (buildroot/Makefile:807), so reading the parts is
    equivalent, not an approximation.
    """
    build = os.path.join(output_dir, "build")
    aggregate = os.path.join(build, "packages-file-list.txt")
    if os.path.isfile(aggregate):
        return [aggregate]
    return sorted(glob.glob(os.path.join(build, "*", ".files-list.txt")))


def load_file_list(paths):
    owned = {}
    for path in paths:
        for line in open(path):
            line = line.rstrip("\n")
            if "," not in line:
                continue
            pkg, rel = line.split(",", 1)
            rel = rel.lstrip("./")
            if rel:
                owned.setdefault(norm(pkg), []).append(rel)
    return owned


def config_in_paths(pkg, pkgdirs):
    """Every place a package's Config.in might be, nearest first.

    A family directory holds its packages one level down -- openbor holds
    openbor6412, mupen64plus holds mupen64plus-core, advanced_drastic holds
    sdl2_drastic -- so a package dir is not always a direct child of a pkgdir.
    Missing the nested level is not cosmetic: it is how the openbor, n64 and
    easyrpg symbols went un-exported and their systems vanished from
    EmulationStation.
    """
    spellings = (pkg, pkg.replace("-", "_"))
    for parent in pkgdirs:
        for candidate in spellings:
            yield os.path.join(parent, candidate, "Config.in")
    for parent in pkgdirs:
        if not os.path.isdir(parent):
            continue
        for family in sorted(os.listdir(parent)):
            for candidate in spellings:
                yield os.path.join(parent, family, candidate, "Config.in")


def package_symbol(pkg, pkgdirs):
    """The BR2_PACKAGE_* symbol for a package, from its own Config.in.

    es_systems.yml gates standalone emulators on these symbols exactly as it
    gates cores, and the gate that stops building the packages also removes the
    symbols from .config.  The drop re-exports them so EmulationStation still
    lists what is installed.
    """
    for config_in in config_in_paths(pkg, pkgdirs):
        if os.path.isfile(config_in):
            found = re.findall(r"^config (BR2_PACKAGE_[A-Z0-9_]+)",
                               open(config_in, errors="ignore").read(), re.M)
            if found:
                return found[0]
    return None


# Mirrors buildroot's target-finalize.  It runs after every package installs and
# before the rootfs is made, so a normal build never ships these -- but a build
# that only asks for some packages never reaches it.
PURGE_DIRS = (
    "usr/include/", "usr/share/aclocal/", "usr/lib/pkgconfig/",
    "usr/share/pkgconfig/", "usr/lib/cmake/", "usr/share/cmake/",
    "usr/lib/rpm/", "usr/doc/", "usr/share/doc/", "usr/man/", "usr/share/man/",
    "usr/info/", "usr/share/info/", "usr/share/gtk-doc/",
    "lib/debug/", "usr/lib/debug/",
)
PURGE_LIB_DIRS = ("lib/", "usr/lib/", "usr/libexec/")
PURGE_LIB_SUFFIXES = (".a", ".la", ".prl")


# The Vulkan loader belongs to the image, never to the drop.  A vendor GPU blob
# that ships its own libvulkan.so.1 overwrites vulkan-loader's file in target/,
# and harvesting that copies the replacement into the payload -- where it lands
# on top of a correct loader on every later build, long after the blob itself
# has been fixed.  The image always builds vulkan-loader for itself, so there is
# nothing here worth carrying.
NEVER_HARVEST = (
    "usr/lib/libvulkan.so",
)


def is_never_harvested(rel):
    return rel.startswith(NEVER_HARVEST)


def is_development(rel):
    if rel.startswith(PURGE_DIRS):
        return True
    # Scoped to the library dirs exactly as target-finalize scopes it: a game
    # data file is free to end in .a, and deleting it would be silent corruption.
    if rel.startswith(PURGE_LIB_DIRS) and rel.endswith(PURGE_LIB_SUFFIXES):
        return True
    return rel.endswith(".cmake") and rel.startswith(("usr/lib/", "usr/share/"))


def elf_class(path):
    """32, 64, or None if not an ELF."""
    with open(path, "rb") as fp:
        header = fp.read(5)
    if header[:4] != b"\x7fELF":
        return None
    return 32 if header[4] == 1 else 64


def elf_needed(readelf, path):
    try:
        out = subprocess.run([readelf, "-d", path], capture_output=True, text=True).stdout
    except OSError:
        return []
    return re.findall(r"\(NEEDED\).*\[([^\]]+)\]", out)


def print_targets(args):
    """Package names to hand buildroot, so it builds these and their deps only.

    A name whose symbol is not enabled for this board is skipped: emulators.set
    is the union over the ABI, and asking buildroot for a package the board does
    not select would build it anyway, outside the config that describes it.
    """
    listed, _ = load_set(args.setfile)
    enabled = set()
    if args.config and os.path.exists(args.config):
        for line in open(args.config):
            if line.startswith("BR2_PACKAGE_") and line.rstrip("\n").endswith("=y"):
                enabled.add(line.split("=", 1)[0])
    targets = []
    for pkg in sorted(listed):
        symbol = package_symbol(pkg, args.pkgdirs)
        # No symbol found means no Config.in under the emulator pkgdirs (the lua
        # modules live in buildroot's own tree).  Those are selected by the
        # emulator that needs them, so buildroot pulls them in regardless.
        if symbol is None or symbol in enabled:
            targets.append(listed[pkg])
    print(" ".join(targets))


def harvest(args):
    target = os.path.join(args.output_dir, "target")
    if not os.path.isdir(target):
        sys.exit("harvest-drop: %s is missing -- harvest a finished build" % target)
    sources = file_list_sources(args.output_dir)
    if not sources:
        sys.exit("harvest-drop: no package file lists under %s/build -- nothing has been\n"
                 "installed there, so there is no payload to harvest" % args.output_dir)

    # Refuse a build that installed the drop instead of building the emulators.
    # It still has payload for anything not yet gated, so the harvest would
    # "succeed" with a fraction of the set and overwrite a good drop with it.
    config = os.path.join(args.output_dir, ".config")
    strip_enabled = True
    enabled = set()
    if os.path.exists(config):
        lines = list(open(config))
        if any(l.startswith("BR2_PACKAGE_KNULLI_EXTERNAL_EMULATORS=y") for l in lines):
            sys.exit("harvest-drop: %s was built WITH the emulators gate on, so it has no\n"
                     "emulator payload of its own to harvest.  Build with the gate off:\n"
                     "  make <board>-emulators-drop" % args.output_dir)
        strip_enabled = any(l.startswith("BR2_STRIP_strip=y") for l in lines)
        for line in lines:
            line = line.rstrip("\n")
            if line.startswith("BR2_PACKAGE_") and line.endswith("=y"):
                enabled.add(line.split("=", 1)[0])

    owned = load_file_list(sources)

    # Refuse an output dir that has ever had a drop installed into it.  Buildroot
    # credits files to a package by diffing target/ around its install step, so a
    # payload file already sitting there byte-identical is credited to nobody --
    # the harvest then silently produces a payload missing every unchanged file.
    # Observed: 3242 files became 1554 while the reported size barely moved,
    # because only the recompiled binaries differed from the installed ones.
    if "knulli-emulators-drop" in owned:
        sys.exit("harvest-drop: %s has had an emulator drop installed into its target/,\n"
                 "so buildroot's file-to-package attribution there is not trustworthy and\n"
                 "the payload would come out incomplete.  Harvest a tree that has only\n"
                 "ever been built with the gate off:\n"
                 "  make <board>-emulators-drop" % args.output_dir)

    listed, keep = load_set(args.setfile)
    present = [p for p in listed if p in owned]
    absent = [listed[p] for p in listed if p not in owned]

    # Split the absentees.  emulators.set is the union over the whole ABI, and no
    # single board enables all of it -- a133 has no azahar, dolphin-emu or vita3k
    # -- so an entry this board's config never selected is simply not applicable
    # here and the consumer must not treat its absence as a stale drop.  An entry
    # the config DOES select and that still has no payload means this build never
    # got that far, and harvesting it would write a drop that looks complete.
    # Entries with no symbol of their own (the lua modules corsixth loads) cannot
    # be judged either way and count as not applicable.
    not_applicable, incomplete = [], []
    for pkg in listed:
        if pkg in owned:
            continue
        symbol = package_symbol(pkg, args.pkgdirs)
        if symbol and symbol in enabled:
            incomplete.append(listed[pkg])
        else:
            not_applicable.append(listed[pkg])
    if incomplete:
        sys.exit("harvest-drop: %d packages this board enables have no payload in %s:\n"
                 "  %s\n"
                 "The build did not finish -- harvesting now would write a drop that looks\n"
                 "complete.  Finish it first:\n"
                 "  make <board>-emulators-drop"
                 % (len(incomplete), args.output_dir, " ".join(sorted(incomplete))))

    candidates = set()
    for parent in args.pkgdirs:
        if not os.path.isdir(parent):
            continue
        for entry in os.listdir(parent):
            first = os.path.join(parent, entry)
            if not os.path.isdir(first):
                continue
            if os.path.isfile(os.path.join(first, "Config.in")):
                candidates.add(norm(entry))
            # A family directory holds its packages one level down: openbor
            # holds openbor6412, mupen64plus holds mupen64plus-core.  A
            # directory name is not always a package name.
            for nested in os.listdir(first):
                if os.path.isfile(os.path.join(first, nested, "Config.in")):
                    candidates.add(norm(nested))

    if not present:
        sys.exit("harvest-drop: none of the listed packages were installed in %s.\n"
                 "Was this build made with BR2_PACKAGE_KNULLI_EXTERNAL_EMULATORS unset?"
                 % args.output_dir)

    drop = os.path.join(args.cache, "drop", args.profile)
    payload = os.path.join(drop, "payload")
    if os.path.isdir(drop):
        shutil.rmtree(drop)
    os.makedirs(payload)

    # --- payload ---
    # Files the file list names but target/ no longer has are normal: a package
    # can install a file a later package overwrites or removes.  Only their
    # absence in bulk would mean something is wrong.
    kept = {}
    copied = missing = purged = 0
    to_strip = []
    for pkg in present:
        files = []
        for rel in owned[pkg]:
            if is_development(rel) or is_never_harvested(rel):
                purged += 1
                continue
            src = os.path.join(target, rel)
            if not os.path.lexists(src):
                missing += 1
                continue
            if os.path.isdir(src) and not os.path.islink(src):
                continue
            dst = os.path.join(payload, rel)
            os.makedirs(os.path.dirname(dst), exist_ok=True)
            if os.path.islink(src):
                if os.path.lexists(dst):
                    os.remove(dst)
                os.symlink(os.readlink(src), dst)
            else:
                shutil.copy2(src, dst)
                if not rel.endswith(".ko") and not rel.startswith("lib/firmware/"):
                    to_strip.append(dst)
            files.append(rel)
            copied += 1
        kept[pkg] = files

    # --- strip ---
    # Exactly buildroot's STRIPCMD -- plain strip plus the two section removals,
    # no --strip-unneeded, so the payload comes out byte-for-byte the way an image
    # build's target-finalize would have left it.  Not just a size win: the image
    # build strips whatever is in target/, so an unstripped payload would make the
    # drop look far bigger than what it contributes to the image.
    stripped = 0
    if strip_enabled and args.strip:
        batch = [p for p in to_strip if elf_class(p) is not None]
        for i in range(0, len(batch), 200):
            chunk = batch[i:i + 200]
            subprocess.run([args.strip, "--remove-section=.comment",
                            "--remove-section=.note"] + chunk,
                           capture_output=True)
        stripped = len(batch)

    # --- manifests ---
    with open(os.path.join(drop, "files.list"), "w") as fp:
        for pkg in sorted(kept):
            for rel in sorted(kept[pkg]):
                fp.write("%s,%s\n" % (pkg, rel))

    with open(os.path.join(drop, "packages.list"), "w") as fp:
        fp.write("# package files\n")
        for pkg in sorted(kept):
            fp.write("%s %d\n" % (pkg, len(kept[pkg])))

    # Symbols for es_systems.yml.  A few packages genuinely have none -- the lua
    # modules corsixth loads at runtime -- and no yml rule names those either.
    symbols = {}
    for pkg in sorted(present):
        symbol = package_symbol(pkg, args.pkgdirs)
        if symbol:
            symbols[pkg] = symbol
    with open(os.path.join(drop, "emulators.config"), "w") as fp:
        fp.write("# Generated by harvest-drop.py -- do not edit.\n")
        fp.write("# Emulators and ports installed from the %s drop.\n" % args.profile)
        for pkg in sorted(symbols, key=lambda p: symbols[p]):
            fp.write("%s=y\n" % symbols[pkg])

    with open(os.path.join(drop, "emulators.list"), "w") as fp:
        for pkg in sorted(present):
            fp.write("%s\n" % listed[pkg])

    # Set members this profile/GPU does not build, so the consumer can tell them
    # apart from members a stale drop predates.
    with open(os.path.join(drop, "not-applicable.list"), "w") as fp:
        for name in sorted(not_applicable):
            fp.write("%s\n" % name)

    # --- what the payload needs from the image it lands in ---
    # The consumer checks this against the board's rootfs, so a board whose
    # config does not provide something fails its build instead of shipping an
    # emulator that dies when the user launches it.  This is the check that
    # keeps one drop honest across four boards.
    # Split by ELF class.  Some payload is 32-bit armhf -- advanced_drastic
    # ships a prebuilt helper -- and 32-bit libraries are not part of the rootfs
    # this build produces: install-32bit-libs.sh layers them in from a second
    # output dir, per board.  Holding both ABIs to the same standard would fail
    # every 64-bit board over a dependency it is not supposed to have.
    needed = {32: set(), 64: set()}
    shipped = set()
    for pkg, files in kept.items():
        for rel in files:
            path = os.path.join(payload, rel)
            if os.path.islink(path) or not os.path.isfile(path):
                continue
            bits = elf_class(path)
            if bits is None:
                continue
            needed[bits].update(elf_needed(args.readelf, path))
            shipped.add(os.path.basename(rel))
    external = sorted(needed[64] - shipped)
    external32 = sorted(needed[32] - shipped)
    with open(os.path.join(drop, "sonames.list"), "w") as fp:
        for soname in external:
            fp.write("%s\n" % soname)
    with open(os.path.join(drop, "sonames-32.list"), "w") as fp:
        fp.write("# From 32-bit payload.  Satisfied by the board's armhf layer,\n")
        fp.write("# not by this build -- see board/scripts/install-32bit-libs.sh.\n")
        for soname in external32:
            fp.write("%s\n" % soname)

    size = subprocess.run(["du", "-sh", payload], capture_output=True, text=True).stdout.split()[0]
    with open(os.path.join(drop, "drop.info"), "w") as fp:
        fp.write("profile    %s\n" % args.profile)
        fp.write("harvested  %s\n" % args.output_dir)
        fp.write("packages   %d\n" % len(present))
        fp.write("files      %d\n" % copied)
        fp.write("size       %s\n" % size)
        fp.write("stripped   %d\n" % stripped)
        fp.write("sonames    %d required from the image, %d from 32-bit payload\n"
                 % (len(external), len(external32)))
        fp.write("\n")
        fp.write("Installed by package/emulators/knulli-emulators-drop, which checks\n")
        fp.write("sonames.list against the board's rootfs and re-exports\n")
        fp.write("emulators.config so es_systems.yml still sees these emulators.\n")
        fp.write("Carries no libraries: see BR2_PACKAGE_KNULLI_EXTERNAL_EMULATORS.\n")

    print("[INFO] harvest-drop: %d packages, %d files, %s" % (len(present), copied, size))
    print("[INFO] harvest-drop: %d sonames required from the image" % len(external))
    if stripped:
        print("[INFO] harvest-drop: stripped %d binaries (target-finalize does not run "
              "for a package-targeted build)" % stripped)
    elif not strip_enabled:
        print("[INFO] harvest-drop: BR2_STRIP_strip is off, payload left unstripped")
    if purged:
        print("[INFO] harvest-drop: %d development files left out (headers, static libs, "
              "pkgconfig, docs)" % purged)
    if external32:
        print("[INFO] harvest-drop: %d sonames from 32-bit payload, satisfied by the "
              "board's armhf layer: %s" % (len(external32), " ".join(external32)))
    if absent:
        print("[INFO] harvest-drop: listed but not built for this board, skipped: %s"
              % " ".join(sorted(absent)))
    # Judged on what the board's config ENABLES, not on what this build installed.
    # A package-targeted build only ever installs set members and their
    # dependencies, so "installed but not listed" can never fire for the case that
    # matters -- an emulator nobody added to the set.  azahar, dolphin-emu,
    # melonds, vita3k and aethersx2 were all found by hand for exactly that reason.
    unlisted = []
    for c in sorted(candidates):
        if c in listed or c in keep or c.startswith("retroarch"):
            continue
        symbol = package_symbol(c, args.pkgdirs)
        if (symbol and symbol in enabled) or (not enabled and c in owned):
            unlisted.append(c)
    if unlisted:
        print("[WARN] harvest-drop: emulator/port packages this board enables but that are "
              "NOT in emulators.set, so every board still compiles them: %s" % " ".join(unlisted))
        print("[WARN] harvest-drop: add each to emulators.set, or to its '#keep' section "
              "if it belongs in the base image")
    missing_symbol = [listed[p] for p in present if p not in symbols]
    if missing_symbol:
        print("[INFO] harvest-drop: no BR2_PACKAGE_* symbol, so no es_systems.yml rule "
              "gates on them: %s" % " ".join(sorted(missing_symbol)))
    if missing:
        print("[INFO] harvest-drop: %d listed files were no longer in target/" % missing)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--print-targets", action="store_true",
                    help="print the package names to build, then exit")
    ap.add_argument("--config", help="board .config, for --print-targets")
    ap.add_argument("--output-dir", help="build to harvest (output/emulators-drop/<board>)")
    ap.add_argument("--profile", help="ABI profile the drop is stored under")
    ap.add_argument("--cache", help="drop cache root")
    ap.add_argument("--set", required=True, dest="setfile", help="emulators.set")
    ap.add_argument("--pkgdirs", action="append", required=True,
                    help="directory holding package dirs (repeatable)")
    ap.add_argument("--readelf", default="readelf", help="readelf to scan the payload with")
    ap.add_argument("--strip", help="strip to run over the payload")
    args = ap.parse_args()

    if args.print_targets:
        print_targets(args)
        return

    for name in ("output_dir", "profile", "cache"):
        if not getattr(args, name):
            sys.exit("harvest-drop: --%s is required" % name.replace("_", "-"))
    if not args.strip and args.readelf.endswith("-readelf"):
        args.strip = args.readelf[:-len("-readelf")] + "-strip"
    harvest(args)


if __name__ == "__main__":
    main()
