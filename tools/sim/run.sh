#!/bin/sh
# Drives picocalc-sim without a window: builds a card from this repo's sd_files, boots a firmware on it,
# brings up the shell, then plays a script of keys and screenshots.
#
#   tools/sim/run.sh UF2 SCRIPT [OUTDIR]
#
# SCRIPT holds simulator script lines (wait MS, type TEXT\n, key CHORD, screenshot FILE.png; see
# frontend/script.c in picocalc_sim). Screenshots land in OUTDIR (default: the current directory), and
# sheet.py puts several of them on one image.
#
# Environment:
#   SIM, MKCARD   the simulator and its card builder (default: picocalc_sim/build beside this repo)
#   OVERLAY       a directory copied over the card's files, for test scripts and data
#   SD            a card tree to use instead of this repo's sd_files
#   WIFI=1        join the simulator's access point before SCRIPT starts
#   PLAIN=1       the board has no Wi-Fi, so the boot asks only whether to start the shell
#
# The card also gets tools/sim/card: blocks.lua (largest free block, and how much can be had in 4 KB
# blocks), fragment.lua (pins allocations through the free memory), gzbench.lua (times gzip on
# /sd_files-test.tar.gz) and simwifi.lua. Run them on the card with "run /lua/NAME.lua".
set -e
here=$(cd "$(dirname "$0")" && pwd)
repo=$(cd "$here/../.." && pwd)
SIM=${SIM:-$repo/../picocalc_sim/build/picocalc-sim}
MKCARD=${MKCARD:-$repo/../picocalc_sim/build/tools/mkcard/picocalc-sim-mkcard}

if [ $# -lt 2 ]; then
    sed -n '2,20p' "$0" | sed 's/^# \{0,1\}//'
    exit 1
fi
uf2=$(realpath "$1")
script=$(realpath "$2")
out=${3:-.}
mkdir -p "$out"

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
mkdir "$work/card"
if [ -n "$SD" ]; then
    cp -r "$SD"/. "$work/card/"
else
    # tracked and untracked files but nothing .gitignore lists, so no credentials or per-device state
    (cd "$repo/sd_files" && git ls-files -co --exclude-standard | tar -cf - -T -) | tar -xf - -C "$work/card"
fi
rm -f "$work/card/lua/wifi.conf"
cp -r "$here/card"/. "$work/card/"
[ -n "$OVERLAY" ] && cp -r "$OVERLAY"/. "$work/card/"
"$MKCARD" "$work/card.img" -s 64 "$work/card" >/dev/null

{
    echo 'wait 5000'
    # a board with Wi-Fi first asks whether to connect, and the stored settings are not on this card
    [ -n "$PLAIN" ] || printf 'type n\\n\nwait 1500\n'
    printf 'type y\\n\nwait 4000\n'
    [ -n "$WIFI" ] && printf 'type run /lua/simwifi.lua\\n\nwait 16000\n'
    cat "$script"
    echo 'quit 0'
} > "$work/run.pcs"

wifi=--no-wifi
[ -n "$WIFI" ] && wifi=
cd "$out"
"$SIM" --headless --flash none $wifi --card "$work/card.img" --script "$work/run.pcs" "$uf2" >/dev/null 2>&1
