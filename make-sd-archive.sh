#!/bin/sh
# Build an SD-card update archive that the device's tar command can
# extract from / with "tar x /sd_files.tar.gz".
#
#   ./make-sd-archive.sh [output]     default: $DEPLOY/sd_files.tar.gz
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
#   fetch http://<host>:<port>/sd_files.tar.gz /sd_files.tar.gz
#   tar t /sd_files.tar.gz
#   tar x /sd_files.tar.gz        (answer 'a' at the overwrite prompt)
set -e

DEPLOY=${DEPLOY:-/home/steve/dev/picocalc/uf2-deploy}
OUT=${1:-$DEPLOY/sd_files.tar.gz}
SRC=$(cd "$(dirname "$0")/sd_files" && pwd)

LOCAL_CONFIGS="lua/picolua.conf lua/wx.conf lua/shell/update_config.lua"
SECRETS="lua/wifi.conf"

list=$(mktemp)
trap 'rm -f "$list"' EXIT

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
    -C "$SRC" -c $compress -f "$OUT" -T "$list"

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

echo "$(wc -l < "$list") files, $(wc -c < "$OUT") bytes: $OUT"
if [ -n "$VERBOSE" ]; then
    cat "$list"
fi
