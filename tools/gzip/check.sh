#!/bin/sh
# Checks on the host that uzlib gives the same output with the gzip window in 4 KB blocks, as the firmware
# builds it, as with the window in one piece, and that both match gzip itself.
#
#   tools/gzip/check.sh [more.gz ...]
#
# The streams it makes include matches at the full window distance and ones that start and end on block
# edges; any .gz files named are tested as well (a release's sd_files archive, say).
set -e
here=$(cd "$(dirname "$0")" && pwd)
src=$here/../../submodules/uzlib/src
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

for build in chunk flat; do
    [ $build = chunk ] && def=-DUZLIB_DICT_CHUNK_BITS=12 || def=
    gcc -O2 -w -I"$src" $def -o "$work/gz_$build" "$here/gztest.c" \
        "$src/tinflate.c" "$src/tinfgzip.c" "$src/crc32.c" "$src/adler32.c"
done

python3 -I - "$work" <<'PY'
import gzip, random, sys
work = sys.argv[1]
random.seed(7)
def w(name, data):
    with gzip.open(work + '/' + name, 'wb', compresslevel=9) as f:
        f.write(data)
blk = bytes(random.getrandbits(8) for _ in range(32768))
w('p32768.gz', blk * 6)
w('p20011.gz', bytes(random.getrandbits(8) for _ in range(20011)) * 9)
w('p4096.gz', blk[:4096] * 60)
w('p4097.gz', blk[:4097] * 60)
w('text.gz', b''.join(b'line %d of some repetitive text, %d\n' % (i, i * 7919 % 1013) for i in range(200000)))
w('zeros.gz', bytes(1 << 20))
w('tiny.gz', b'hello')
w('empty.gz', b'')
PY

fail=0
for f in "$work"/*.gz "$@"; do
    gzip -dc "$f" > "$work/ref.bin"
    for step in 1 513 1024 4096 65536; do
        for build in chunk flat; do
            if ! "$work/gz_$build" "$f" "$work/out.bin" $step || ! cmp -s "$work/ref.bin" "$work/out.bin"; then
                echo "FAIL: $(basename "$f") with the window $build, reading $step at a time"
                fail=1
            fi
        done
    done
    echo "$(basename "$f"): $(stat -c %s "$work/ref.bin") bytes ok"
done
[ $fail = 0 ] && echo "all streams match" || exit 1
