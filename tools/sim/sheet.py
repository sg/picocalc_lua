import sys, zlib, struct

def read_png(path):
    d = open(path, 'rb').read()
    assert d[:8] == b'\x89PNG\r\n\x1a\n'
    pos, idat = 8, b''
    while pos < len(d):
        n, typ = struct.unpack('>I4s', d[pos:pos + 8])
        body = d[pos + 8:pos + 8 + n]
        if typ == b'IHDR': w, h, depth, ctype, _, _, inter = struct.unpack('>IIBBBBB', body)
        elif typ == b'IDAT': idat += body
        pos += 12 + n
    assert depth == 8 and inter == 0 and ctype in (2, 6), (depth, ctype, inter)
    bpp = 3 if ctype == 2 else 4
    raw = zlib.decompress(idat)
    stride = w * bpp
    rows, prev = [], bytearray(stride)
    for y in range(h):
        f = raw[y * (stride + 1)]
        line = bytearray(raw[y * (stride + 1) + 1:(y + 1) * (stride + 1)])
        for i in range(stride):
            a = line[i - bpp] if i >= bpp else 0
            b = prev[i]
            c = prev[i - bpp] if i >= bpp else 0
            if f == 1: line[i] = (line[i] + a) & 255
            elif f == 2: line[i] = (line[i] + b) & 255
            elif f == 3: line[i] = (line[i] + (a + b) // 2) & 255
            elif f == 4:
                p = a + b - c; pa, pb, pc = abs(p - a), abs(p - b), abs(p - c)
                line[i] = (line[i] + (a if pa <= pb and pa <= pc else b if pb <= pc else c)) & 255
        rows.append(bytes(line) if bpp == 3 else bytes(b for i, b in enumerate(line) if i % 4 != 3))
        prev = line
    return w, h, rows

def write_png(path, w, h, rows):
    def chunk(t, b): return struct.pack('>I', len(b)) + t + b + struct.pack('>I', zlib.crc32(t + b))
    raw = b''.join(b'\x00' + r for r in rows)
    open(path, 'wb').write(b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('>IIBBBBB', w, h, 8, 2, 0, 0, 0))
                           + chunk(b'IDAT', zlib.compress(raw, 6)) + chunk(b'IEND', b''))

def crop(img, box):
    w, h, rows = img
    x0, y0, x1, y1 = box
    return x1 - x0, y1 - y0, [r[x0 * 3:x1 * 3] for r in rows[y0:y1]]

def scale(img, k):
    w, h, rows = img
    out = []
    for r in rows:
        line = b''.join(r[i:i + 3] * k for i in range(0, len(r), 3))
        out.extend([line] * k)
    return w * k, h * k, out

if __name__ == '__main__':
    # sheet.py OUT COLS [--crop x0,y0,x1,y1] [--scale K] IN...
    out, cols, args = sys.argv[1], int(sys.argv[2]), sys.argv[3:]
    box, k = None, 1
    while args and args[0].startswith('--'):
        if args[0] == '--crop': box = tuple(map(int, args[1].split(',')))
        if args[0] == '--scale': k = int(args[1])
        args = args[2:]
    imgs = [read_png(a) for a in args]
    if box: imgs = [crop(i, box) for i in imgs]
    if k > 1: imgs = [scale(i, k) for i in imgs]
    w, h = imgs[0][0], imgs[0][1]
    gap = 4
    nrows = (len(imgs) + cols - 1) // cols
    W, H = cols * w + (cols - 1) * gap, nrows * h + (nrows - 1) * gap
    sep = b'\x60\x60\x60'
    rows = []
    for r in range(nrows):
        for y in range(h):
            line = b''
            for c in range(cols):
                i = r * cols + c
                line += imgs[i][2][y] if i < len(imgs) else b'\x00' * (w * 3)
                if c < cols - 1: line += sep * gap
            rows.append(line)
        if r < nrows - 1: rows.extend([sep * W] * gap)
    write_png(out, W, H, rows)
    print(out, W, H)
