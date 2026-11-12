// Decompresses a gzip file the way picolua-api/gzip.c does, through a 1 KB input buffer and a source
// callback, so that check.sh can compare the result with gzip's. Built with UZLIB_DICT_CHUNK_BITS it gives
// uzlib the window as scattered 4 KB blocks, as the firmware does.
//
//   gztest IN.gz OUT STEP      (STEP: bytes asked for at a time)
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stddef.h>
#include <stdbool.h>
#include <stdint.h>
#include "uzlib.h"

#define INBUF 1024
#define DICT 32768
typedef struct { FILE *f; struct uzlib_uncomp u; uint8_t in[INBUF]; } R;

static int src(struct uzlib_uncomp *d) {
    R *r = (R *)((char *)d - offsetof(R, u));
    size_t n = fread(r->in, 1, INBUF, r->f);
    if (n == 0) return -1;
    d->source = r->in + 1;
    d->source_limit = r->in + n;
    return r->in[0];
}

int main(int argc, char **argv) {
    if (argc < 4) return 2;
    int step = atoi(argv[3]);
    R r; memset(&r, 0, sizeof r);
    r.f = fopen(argv[1], "rb");
    FILE *out = fopen(argv[2], "wb");
    if (!r.f || !out) return 2;
    uzlib_init();
#ifdef UZLIB_DICT_CHUNK_BITS
    static unsigned char *chunks[DICT >> UZLIB_DICT_CHUNK_BITS];
    // scattered on purpose, with unrelated allocations between them
    for (unsigned i = 0; i < DICT >> UZLIB_DICT_CHUNK_BITS; i++) {
        chunks[i] = malloc(1 << UZLIB_DICT_CHUNK_BITS);
        void *between = malloc(100 + i * 37);
        (void)between;
    }
    uzlib_uncompress_init(&r.u, chunks, DICT);
#else
    uzlib_uncompress_init(&r.u, malloc(DICT), DICT);
#endif
    size_t n = fread(r.in, 1, INBUF, r.f);
    r.u.source = r.in; r.u.source_limit = r.in + n;
    if (uzlib_gzip_parse_header(&r.u) != TINF_OK) { fprintf(stderr, "bad header\n"); return 1; }
    r.u.source_read_cb = src;
    uint8_t *buf = malloc(step);
    for (;;) {
        r.u.dest_start = buf; r.u.dest = buf; r.u.dest_limit = buf + step;
        int res = uzlib_uncompress_chksum(&r.u);
        fwrite(buf, 1, r.u.dest - buf, out);
        if (res == TINF_DONE) break;
        if (res != TINF_OK) { fprintf(stderr, "error %d\n", res); return 1; }
    }
    fclose(out);
    return 0;
}
