#!/bin/bash
# Inner build for the void-musl docker (runs as root inside the container).
# Mounts: z-packages at /void-packages. Env: PKGS (space separated).
# Never exits nonzero: records failures in /void-packages/failed.txt so the
# host can publish partial results and report afterwards.
set -e
xbps-install -Syu xbps 2>&1 | tail -n 2
xbps-install -y base-devel xtools bash git perl tar xz python3 github-cli shadow ccache 2>&1 | tail -n 2
useradd -m builder 2>/dev/null || true
chown -R builder:builder /void-packages
chroot --userspec=builder:builder / /bin/bash -c \
  "cd /void-packages && common/travis/set_mirror.sh 2>/dev/null || true"
chroot --userspec=builder:builder / /bin/bash -c \
  "cd /void-packages && ./xbps-src binary-bootstrap 2>&1 | tail -n 20"
failed=""
for pkg in $PKGS; do
  if [ -L "/void-packages/srcpkgs/$pkg" ]; then
    echo "=== Skipping $pkg (symlink, built with parent) ==="
    continue
  fi
  if [ ! -d "/void-packages/srcpkgs/$pkg" ]; then
    echo "FAIL $pkg (no such template)"; failed="$failed $pkg"; continue
  fi
  echo "=== Building $pkg (x86_64-musl) ==="
  # pipefail inside bash -c: | tail must not mask xbps-src failures
  chroot --userspec=builder:builder / /bin/bash -c \
    "set -o pipefail; cd /void-packages && ./xbps-src pkg $pkg 2>&1 | tail -n 60" \
    || { echo "FAIL $pkg"; failed="$failed $pkg"; }
done
# native builds land in hostdir/binpkgs/ top level: move to x86_64-musl/
if ls /void-packages/hostdir/binpkgs/*.xbps 1>/dev/null 2>&1; then
  mv /void-packages/hostdir/binpkgs/*.xbps /void-packages/hostdir/binpkgs/x86_64-musl/ 2>/dev/null || true
  mv /void-packages/hostdir/binpkgs/*.xbps.sig2 /void-packages/hostdir/binpkgs/x86_64-musl/ 2>/dev/null || true
fi
echo "$failed" > /void-packages/failed.txt
[ -z "$failed" ] || echo "FAILED packages:$failed (publishing partial results anyway)"
exit 0
