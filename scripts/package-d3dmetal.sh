#!/bin/bash
# Packs Apple's D3DMetal from a Game Porting Toolkit download into the archive the `d3dmetal`
# component points to, without changing a byte of Apple's files:
#
#   scripts/package-d3dmetal.sh <GPTK .dmg or the folder it opens to> [output folder]
#
# The archive holds the toolkit's /redist/lib (external/ with D3DMetal.framework and
# libd3dshared.dylib, wine/ with the Windows front ends and their unix links) plus Apple's
# License.rtf and Acknowledgements.rtf, which must travel with every copy. Apple's licence allows
# passing it on for non-commercial purposes only (section 2A(iii)) – Nightforge is free, and has
# to stay so for this. Stops if anything in external/ isn't signed by Apple itself.
set -euo pipefail

SOURCE="${1:?usage: $0 <GPTK .dmg or folder> [output folder]}"
OUTDIR="${2:-.}"
WORK="$(mktemp -d)"
MOUNT=""
cleanup() {
  [ -n "$MOUNT" ] && hdiutil detach -quiet "$MOUNT" || true
  rm -rf "$WORK"
}
trap cleanup EXIT

if [ -f "$SOURCE" ]; then
  MOUNT="$WORK/mount"
  mkdir -p "$MOUNT"
  hdiutil attach -quiet -nobrowse -readonly -mountpoint "$MOUNT" "$SOURCE"
  ROOT="$MOUNT"
else
  ROOT="$SOURCE"
fi

LIB="$(find "$ROOT" -maxdepth 4 -type d -path '*/redist/lib' | head -1)"
[ -n "$LIB" ] || { echo "no redist/lib in $SOURCE" >&2; exit 1; }
TOOLKIT="$(dirname "$(dirname "$LIB")")"
for f in License.rtf Acknowledgements.rtf; do
  [ -f "$TOOLKIT/$f" ] || { echo "missing $f next to redist/ – Apple's notices must ship with it" >&2; exit 1; }
done
for code in external/libd3dshared.dylib external/D3DMetal.framework; do
  codesign --verify --strict -R='anchor apple' "$LIB/$code" || { echo "$code is not signed by Apple" >&2; exit 1; }
done
[ -f "$LIB/wine/x86_64-windows/d3d12.dll" ] || { echo "no D3D12 front end in $LIB/wine" >&2; exit 1; }

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' \
  "$LIB/external/D3DMetal.framework/Versions/A/Resources/Info.plist")"
NAME="nightforge-d3dmetal-$VERSION"
STAGE="$WORK/$NAME"
mkdir -p "$STAGE"
# -p keeps the symlinks of wine/x86_64-unix and the framework's own as links.
cp -Rp "$LIB" "$STAGE/lib"
cp -p "$TOOLKIT/License.rtf" "$TOOLKIT/Acknowledgements.rtf" "$STAGE/"
cat > "$STAGE/README.txt" <<EOF
Apple's D3DMetal $VERSION from the Game Porting Toolkit (/redist/lib), unmodified and signed by Apple.
Distributed by Nightforge for non-commercial use on Apple-branded systems, under Apple's licence in
License.rtf (section 2A(iii)); Nightforge is free. Source: https://developer.apple.com/games/game-porting-toolkit/
EOF

mkdir -p "$OUTDIR"
ARCHIVE="$OUTDIR/$NAME.tar.gz"
tar -czf "$ARCHIVE" -C "$WORK" "$NAME"
# The copy in the archive must still pass, links and all.
CHECK="$WORK/check"
mkdir -p "$CHECK"
tar -xzf "$ARCHIVE" -C "$CHECK"
codesign --verify --strict -R='anchor apple' "$CHECK/$NAME/lib/external/D3DMetal.framework"
codesign --verify --strict -R='anchor apple' "$CHECK/$NAME/lib/external/libd3dshared.dylib"

echo "version $VERSION"
echo "archive $ARCHIVE"
echo "size    $(stat -f %z "$ARCHIVE")"
echo "sha256  $(shasum -a 256 "$ARCHIVE" | cut -d' ' -f1)"
