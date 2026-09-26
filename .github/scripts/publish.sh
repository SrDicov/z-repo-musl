#!/bin/bash
# Idempotent publish for z-repo autobuild: prune old versions, sign,
# index, upload changed assets, delete stale ones.
# Safe on empty dirs and safe to re-run (rescue path on build failure).
# Env: ARCH, REPO_TAG, GH_REPO, XBPS_PRIVATE_KEY, SIGNED_BY (optional).
set -e
set -o pipefail

DIR="${1:?usage: publish.sh <binpkgs dir>}"
cd "$DIR"
shopt -s nullglob
pkgs=( *.xbps )
if [ "${#pkgs[@]}" -eq 0 ]; then
  echo "no packages in $DIR, nothing to publish"
  exit 0
fi
: "${SIGNED_BY:=Z Linux Core <SrDicov@gmail.com>}"

echo "$XBPS_PRIVATE_KEY" > /tmp/rsa.pem
chmod 600 /tmp/rsa.pem
# keep only the newest <pkg>-<ver>_<rev> per pkgname: no duplicates
ARCH="$ARCH" python3 - <<'EOF'
import os, re
from collections import defaultdict
arch = os.environ["ARCH"]
pkgs = defaultdict(list)
for f in os.listdir("."):
    m = re.match(r"(.+)-([^-]+)_([^.]+)\.%s\.xbps$" % re.escape(arch), f)
    if m:
        pkgs[m.group(1)].append((m.group(2), m.group(3), f))
def vkey(v):
    return tuple(int(p) if p.isdigit() else p for p in re.split(r"[.]", v))
for name, vers in pkgs.items():
    vers.sort(key=lambda t: (vkey(t[0]), t[1]))
    for _, _, f in vers[:-1]:
        for ext in ("", ".sig2", ".sig"):
            try:
                os.remove(f + ext)
            except FileNotFoundError:
                pass
        print("pruned", f)
EOF
for f in *.xbps; do
  [ -f "$f.sig2" ] || xbps-rindex --sign-pkg --privkey /tmp/rsa.pem "$f"
done
xbps-rindex -a *.xbps
xbps-rindex --sign --signedby "$SIGNED_BY" --privkey /tmp/rsa.pem .
rm -f /tmp/rsa.pem

repodata="$ARCH-repodata"
gh release view "$REPO_TAG" >/dev/null 2>&1 || \
  gh release create "$REPO_TAG" --title "Z Linux $ARCH repo" \
    --notes "Rolling XBPS repo for $ARCH."
# drop stale assets (old versions no longer published)
for a in $(gh release view "$REPO_TAG" --json assets --jq '.assets[].name'); do
  case "$a" in
    "$repodata") ;;
    *.xbps*) [ -e "$a" ] || gh release delete-asset "$REPO_TAG" "$a" -y ;;
  esac
done
# upload new/changed assets (same name+size = already there).
# NOTE: RSA sigs are fixed-size, so after a key rotation same-size sigs
# would look current: RESIGN=true forces upload of everything.
for f in "$repodata" *.xbps*; do
  [ -e "$f" ] || continue
  n=$(basename "$f"); s=$(stat -c%s "$f")
  rs=$(gh release view "$REPO_TAG" --json assets \
    --jq ".assets[] | select(.name==\"$n\") | .size" 2>/dev/null || true)
  if [ "${RESIGN:-false}" != "true" ] && [ "$rs" = "$s" ]; then
    echo "up to date: $n"
  else
    gh release upload "$REPO_TAG" --clobber "$f"
  fi
done
