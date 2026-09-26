#!/usr/bin/env python3
"""Decide which z-packages templates need (re)building.

Static template parsing only (never source them). For each real template
dir in srcpkgs/ (symlinked dirs are built via their parent, like the
build loop does), the main binpkg <pkg>-<ver>_<rev>.<arch>.xbps must be
present in the published file list. Parent-binpkg presence implies its
subpackages (same version, built in the same xbps-src run; template-only
changes require a revision bump per repo rules).

musl exclusion uses the standard idiom: a `broken=` assignment guarded by
XBPS_TARGET_LIBC = musl.

Usage (single-arch, release-based):
    check_outdated.py <srcpkgs dir> <asset list> [--arch=x86_64]
        [pkgname=release-asset-list ...]
    Prints `pkgs:<pkgs>` (empty = all current).

Usage (legacy dual-arch, git-tree based):
    check_outdated.py <srcpkgs dir> <x86_64 list> <musl list>
        [pkgname=release-asset-list ...]
    Prints `glibc:<pkgs>` / `musl:<pkgs>` lines (empty = all current).
Packages shipped via a dedicated GitHub release (too big for git,
e.g. librewolf) are compared against their release asset list instead
of the main pool via `pkgname=file` extras.
"""

import fnmatch
import os
import re
import sys


def parse_template(path):
    """Extract pkgname/version/revision/archs with shell-safe static rules:
    plain VAR="value" assignments, no substitution (enforced by repo rules).
    """
    vals = {}
    # Void style is usually unquoted (pkgname=foo); accept both forms.
    # First occurrence wins: top-level assignments precede subpackage
    # functions and conditionals that reuse the same names.
    assign = re.compile(r'^(pkgname|version|revision|archs)="?([^"\s]*)"?\s*$')
    with open(path) as fh:
        for line in fh:
            m = assign.match(line.strip())
            if m and m.group(1) not in vals:
                vals[m.group(1)] = m.group(2)
    return vals


def musl_broken(path):
    """True if the template sets broken= under a musl guard."""
    guard = re.compile(r'XBPS_TARGET_LIBC"\s*=\s*"musl"')
    with open(path) as fh:
        recent_guard = False
        window = []
        for line in fh:
            s = line.strip()
            window.append(s)
            window = window[-6:]
            if guard.search(s):
                recent_guard = True
            if s.startswith("broken=") and (
                recent_guard or "musl" in " ".join(window)
            ):
                return True
            if s == "fi":
                recent_guard = False
    return False


def wanted_for(archs, target):
    if not archs:
        return True
    return any(fnmatch.fnmatchcase(target, pat) for pat in archs.split())


def load_pool(path):
    with open(path) as fh:
        return {ln.strip() for ln in fh if ln.strip().endswith(".xbps")}


def collect_need(srcpkgs, arch, pool, release_lists):
    """Templates in srcpkgs missing their main binpkg from pool."""
    need = []
    for entry in sorted(os.listdir(srcpkgs)):
        tpldir = os.path.join(srcpkgs, entry)
        if not os.path.isdir(tpldir) or os.path.islink(tpldir):
            continue
        tpl = os.path.join(tpldir, "template")
        if not os.path.isfile(tpl):
            continue
        vals = parse_template(tpl)
        if not all(k in vals for k in ("pkgname", "version", "revision")):
            print(f"WARN: {entry}: cannot parse version, forcing build")
            need.append(entry)
            continue
        if arch == "x86_64-musl" and musl_broken(tpl):
            continue
        if not wanted_for(vals.get("archs", ""), arch):
            continue
        want = (
            f"{vals['pkgname']}-{vals['version']}_"
            f"{vals['revision']}.{arch}.xbps"
        )
        if want not in release_lists.get(entry, pool):
            need.append(entry)
    return need


def main():
    args = sys.argv[1:]
    arch = "x86_64"
    rest = []
    for a in args:
        if a.startswith("--arch="):
            arch = a.split("=", 1)[1]
        else:
            rest.append(a)
    positionals, extras = [], {}
    for item in rest:
        if "=" in item and os.path.isfile(item.split("=", 1)[1]):
            pkg, path = item.split("=", 1)
            extras[pkg] = path
        else:
            positionals.append(item)
    release_lists = {pkg: load_pool(p) for pkg, p in extras.items()}
    if len(positionals) == 2:
        # single-arch: srcpkgs + one asset list
        srcpkgs, listfile = positionals
        need = collect_need(srcpkgs, arch, load_pool(listfile), release_lists)
        print(f"pkgs:{' '.join(need)}")
        return
    srcpkgs, glibc_list, musl_list = positionals[:3]
    published = {"x86_64": load_pool(glibc_list),
                 "x86_64-musl": load_pool(musl_list)}
    for target in ("x86_64", "x86_64-musl"):
        need = collect_need(srcpkgs, target, published[target], release_lists)
        print(f"{'glibc' if target == 'x86_64' else 'musl'}:{' '.join(need)}")


if __name__ == "__main__":
    main()
