# AGENTS.md

musl-only twin of `z-repo` (`x86_64-musl`, `void-musl-full`). Binpkgs ship as `stable` release assets, never committed.

- Templates in `SrDicov/z-packages` (`srcpkgs/`). `check_outdated.py --arch=x86_64-musl` skips templates `broken=` under musl guard and non-matching `archs=`.
- Same dispatch inputs as glibc twin: `packages=` (empty = auto), `sync_only=true`, `force=true`. Daily `0 3 * * *`.
- Build runs on Ubuntu + manual docker (`void-musl` image, NOT a job `container:` — musl libc can't run GH's glibc-linked action runtimes). Host does checkout/clone/seed/gh; container (`.github/scripts/build-musl.sh`) does bootstrap+build as `builder` via `chroot --userspec`; publish (`.github/scripts/publish.sh`) runs in a second container call, `if: always()`.
- Same signing key as `z-repo` (`secrets.XBPS_PRIVATE_KEY`).
