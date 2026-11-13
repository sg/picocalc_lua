#!/bin/sh
# Builds the firmware's editor (submodules/kilo) for the host with the address and undefined-behaviour
# sanitizers on, and runs it through key scripts, allocation failures and a full card.
#
#   tools/kilo/check.sh
#
# UPDATE=1 rewrites what the cases in tools/kilo/cases expect (the saved file and the last screen) from
# what the editor now does: read the diff before keeping it. harness.c has the key script format.
set -e
here=$(cd "$(dirname "$0")" && pwd)
repo=$(cd "$here/../.." && pwd)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

inc="-I$here/stubs -I$repo/submodules/kilo"
san="-g -O1 -w -fsanitize=address,undefined -fno-sanitize-recover=undefined"
# only the editor's own calls are redirected, so that the harness keeps the real ones
gcc $san $inc -Drealloc=test_realloc -Dfree=test_free -Dwrite=test_write -Dtime=test_time \
    -c -o "$work/kilo.o" "$repo/submodules/kilo/kilo.c"
gcc $san $inc -o "$work/kilo" "$here/harness.c" "$work/kilo.o"

python3 -I "$here/check.py" "$work/kilo" "$here/cases" "$work"
