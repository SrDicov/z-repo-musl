# AGENTS.md

musl-only twin of `z-repo` (`x86_64-musl`, `void-musl-full`). Binpkgs ship as `stable` release assets, never committed.

- Templates in `SrDicov/z-packages` (`srcpkgs/`). `check_outdated.py --arch=x86_64-musl` skips templates `broken=` under musl guard and non-matching `archs=`.
- Same dispatch inputs as glibc twin: `packages=` (empty = auto), `sync_only=true`, `force=true`. Daily `0 3 * * *`.
- Same speed setup: treeless clone, `repo-ci`, `XBPS_PRESERVE_PKGS/CCACHE/MAKEJOBS`, cached `hostdir/sources` + `hostdir/ccache` (key `musl-xbps-v1`).
- Same signing key as `z-repo` (`secrets.XBPS_PRIVATE_KEY`).
