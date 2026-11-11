#!/bin/sh
# Build an SD-card update archive that the device's tar command can
# extract from / with "tar x /sd_files.tar.gz".
#
#   ./make-sd-archive.sh [output]     default: $DEPLOY/sd_files-<version>.tar.gz
#
# A version.txt holding $VERSION (default: git describe) is added so
# the update command on the device knows what it is running, and the
# same string names the archive so fetch-dev on the device finds it.
#
# Members come from git (tracked plus untracked-but-not-ignored files
# under sd_files/), so credentials, history, screenshots and logs that
# .gitignore lists never reach the archive. Per-device settings listed
# in LOCAL_CONFIGS are left out too so an update does not reset them.
#
# On the device:
#   mkdir /backup
#   cd /
#   tar c /backup/sd-before.tar main.lua shell.lua fonts lua
#   fetch-dev <version>           (serve $DEPLOY with: python3 -m http.server 8080 -d $DEPLOY)
#   tar t /sd_files-<version>.tar.gz
#   tar x /sd_files-<version>.tar.gz        (answer 'a' at the overwrite prompt)
set -e

DEPLOY=${DEPLOY:-/home/steve/dev/picocalc/uf2-deploy}
SRC=$(cd "$(dirname "$0")/sd_files" && pwd)
VERSION=${VERSION:-$(git -C "$SRC" describe --tags --always --dirty=+ 2>/dev/null || echo unknown)}
OUT=${1:-$DEPLOY/sd_files-$VERSION.tar.gz}

LOCAL_CONFIGS="lua/picolua.conf lua/wx.conf lua/asteroids.conf lua/shell/update_config.lua"
SECRETS="lua/wifi.conf"

list=$(mktemp)
stage=$(mktemp -d)
trap 'rm -rf "$list" "$stage"' EXIT
printf '%s\n' "$VERSION" > "$stage/version.txt"

git -C "$SRC" ls-files -co --exclude-standard | sort > "$list"

for f in $LOCAL_CONFIGS $SECRETS; do
    grep -v -x -F "$f" "$list" > "$list.tmp" || true
    mv "$list.tmp" "$list"
done

if [ ! -s "$list" ]; then
    echo "*** no files found under $SRC ***" >&2
    exit 1
fi

# the device parser only understands plain ustar; GNU tar refuses names
# that do not fit it instead of silently emitting an extension
case "$OUT" in
    *.gz|*.tgz) compress=-z ;;
    *)          compress= ;;
esac

mkdir -p "$(dirname "$OUT")"
tar --format=ustar --owner=0 --group=0 --numeric-owner \
    -c $compress -f "$OUT" -C "$SRC" -T "$list" -C "$stage" version.txt

if [ -n "$compress" ]; then
    gzip -t "$OUT"
fi

for f in $SECRETS; do
    if tar -t $compress -f "$OUT" | grep -q -x -F "$f"; then
        rm -f "$OUT"
        echo "*** $f ended up in the archive, removed $OUT ***" >&2
        exit 1
    fi
done

echo "$(wc -l < "$list") files plus version.txt ($VERSION), $(wc -c < "$OUT") bytes: $OUT"
if [ -n "$VERBOSE" ]; then
    cat "$list"
fi
