#!/bin/bash
# Release integrity check: every .xbps asset needs its .sig2 and every
# .sig2 its .xbps, every signature verifies against the published key,
# and every package the repodata indexes needs both.
# Prints one line per discrepancy; exit 0 when clean, 1 when not.
# Usage: bash .github/scripts/check-assets.sh [REPO] [TAG]
set -e
set -o pipefail

REPO="${1:-SrDicov/z-repo}"
TAG="${2:-stable}"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

gh api "repos/$REPO/releases/tags/$TAG" --paginate --jq '.assets[].name' \
  | sort -u > "$tmp/assets"
repodata=$(grep -E -- '^[a-z0-9_-]+-repodata$' "$tmp/assets" | head -1)
if [ -z "$repodata" ]; then
  echo "no repodata asset in release $REPO@$TAG"
  exit 1
fi
gh release download "$TAG" --repo "$REPO" -p "$repodata" --clobber \
  -O "$tmp/$repodata"

pub="$tmp/zlinux-repo.pub"
# current key: the release asset, falling back to the committed one
if ! gh release download "$TAG" --repo "$REPO" -p zlinux-repo.pub \
    --clobber -O "$pub" 2>/dev/null; then
  if [ ! -f keys/zlinux-repo.pub ]; then
    echo "no zlinux-repo.pub: release asset or committed key required"
    exit 1
  fi
  cp keys/zlinux-repo.pub "$pub"
fi

# pkgver + architecture of everything the published index advertises
bsdtar -xOf "$tmp/$repodata" index.plist | awk -v FS='[<>]' '
  /^\t<dict>$/ { intopkg = 1; next }
  intopkg && /^\t<\/dict>$/ {
    if (pkgver != "" && arch != "") print pkgver, arch
    intopkg = 0; pkgver = ""; arch = ""; next
  }
  intopkg && $2 == "key" { field = $3; next }
  intopkg && $2 == "string" && field == "architecture" { arch = $3; field = "" }
  intopkg && $2 == "string" && field == "pkgver" { pkgver = $3; field = "" }
' > "$tmp/index"

bad=0
for a in $(grep -E -- '\.xbps(\.sig2)?$' "$tmp/assets"); do
  case "$a" in
    *.sig2)
      grep -Fxq -- "${a%.sig2}" "$tmp/assets" || {
        echo ".sig2 without .xbps: $a"; bad=1; } ;;
    *)
      grep -Fxq -- "$a.sig2" "$tmp/assets" || {
        echo ".xbps without .sig2: $a"; bad=1; } ;;
  esac
done
while read -r pkgver arch; do
  for f in "$pkgver.$arch.xbps" "$pkgver.$arch.xbps.sig2"; do
    grep -Fxq -- "$f" "$tmp/assets" || { echo "indexed, no asset: $f"; bad=1; }
  done
done < "$tmp/index"

# cryptographic check: .sig2 is RSA-SHA256 over the .xbps digest
mkdir -p "$tmp/dl"
gh release download "$TAG" --repo "$REPO" -p '*.xbps' -p '*.xbps.sig2' \
  --clobber -D "$tmp/dl"
for x in "$tmp"/dl/*.xbps; do
  [ -f "$x" ] || continue
  if ! openssl dgst -sha256 -verify "$pub" -signature "$x.sig2" "$x" \
      >/dev/null 2>&1; then
    echo "invalid signature: ${x##*/}"
    bad=1
  fi
done
exit $bad
