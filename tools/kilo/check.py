# The checks behind check.sh: kilo_host is the editor built for the host, cases the directory of key scripts.
import os, random, re, shutil, subprocess, sys

kilo, cases, work = sys.argv[1:4]
sample = os.path.join(cases, 'sample.lua')
sample_text = open(sample, 'rb').read()
update = bool(os.environ.get('UPDATE'))
failures = []

def fail(what):
    failures.append(what)
    print('FAIL:', what)

def run(keys, start=True, name='work.lua', **env):
    """Edits a copy of the sample (or a new file) with a key script; gives status, saved file, screen, terminal bytes, stderr."""
    d = os.path.join(work, 'run')
    shutil.rmtree(d, ignore_errors=True)
    os.mkdir(d)
    if start:
        shutil.copy(sample, os.path.join(d, 'work.lua'))
    with open(os.path.join(d, 'keys'), 'w') as f:
        f.write(keys)
    full = dict(os.environ, KILO_RAW='raw', KILO_SCREEN='screen', **{k: str(v) for k, v in env.items()})
    r = subprocess.run([kilo, name, 'keys'], cwd=d, capture_output=True, env=full)
    def read(name):
        path = os.path.join(d, name)
        return open(path, 'rb').read() if os.path.exists(path) else None
    return r.returncode, read('work.lua'), read('screen'), read('raw') or b'', r.stderr.decode(errors='replace')

def beside():
    """The copy a save writes next to the file, if the last run left one."""
    path = os.path.join(work, 'run', 'work.lua.~tmp')
    return open(path, 'rb').read() if os.path.exists(path) else None

def peak(err):
    return int(re.search(r'heap peak (\d+) bytes in (\d+)', err).group(1))

def allocations(err):
    return int(re.search(r'heap peak (\d+) bytes in (\d+)', err).group(2))

# 1. each case leaves the file and the screen it is expected to
names = sorted(n[:-5] for n in os.listdir(cases) if n.endswith('.keys'))
scripts = {n: open(os.path.join(cases, n + '.keys')).read() for n in names}
# these two start without the sample: one on a file that does not exist yet, one with no name at all
how = {n: {'start': n not in ('type', 'saveas'), 'name': '' if n == 'saveas' else 'work.lua'} for n in names}
for n in names:
    status, saved, screen, _, err = run(scripts[n], **how[n])
    if status != 0:
        fail('%s: exit %d\n%s' % (n, status, err[:2000]))
        continue
    for ext, got in (('saved', saved), ('screen', screen)):
        path = os.path.join(cases, n + '.' + ext)
        if update:
            open(path, 'wb').write(got)
        elif not os.path.exists(path) or open(path, 'rb').read() != got:
            fail('%s: the %s is not what %s expects' % (n, ext, os.path.basename(path)))
print('cases: %d run' % len(names))

# 2. a file too big for the heap is refused, and is left alone
status, saved, _, _, err = run('<F2>', KILO_HEAP=2000)
if status != 2 or 'not enough memory' not in err or saved != sample_text:
    fail('a file that does not fit: exit %d, %s' % (status, err.strip()))

status, _, _, _, err = run('<F2>')
loaded = peak(err)

# 3. typing until the heap is spent loses nothing, says so, and can still be saved
status, saved, _, raw, err = run('<DOWN*5>' + '~' * 3000 + '<F1><F2>', KILO_HEAP=loaded + 600)
typed = (saved or b'').count(b'~')
if status != 0 or saved is None or saved.replace(b'~', b'') != sample_text or not 0 < typed < 3000 or b'Out of memory' not in raw:
    fail('typing until memory runs out: exit %d, %d typed\n%s' % (status, typed, err[:2000]))

# 4. a cut that cannot be copied removes nothing
status, saved, _, raw, err = run('<F4><DOWN*60><C-x><F1><F2>', KILO_HEAP=loaded + 300)
if status != 0 or saved != sample_text or b'Out of memory' not in raw:
    fail('a cut with no room for the copy: exit %d\n%s' % (status, err[:2000]))

# 5. pasting until the heap is spent stops there
status, saved, _, raw, err = run('<F4><DOWN*10><C-c>' + '<C-v>' * 200 + '<F1><F2>', KILO_HEAP=loaded + 6000)
if status != 0 or saved is None or len(saved) <= len(sample_text) or b'Out of memory' not in raw:
    fail('pasting until memory runs out: exit %d\n%s' % (status, err[:2000]))

# 6. a save that the card has no room for leaves the old file as it was, and the text held as unsaved
status, saved, screen, raw, err = run('x<F1><F2>', KILO_DISK=500)
if status != 0 or b'Card is full' not in raw or b'Unsaved' not in raw or saved != sample_text or beside() is not None:
    fail('a full card: exit %d\n%s' % (status, err[:2000]))

# 7. a save leaves nothing beside the file, and one that cannot be renamed says where the text is
status, saved, _, _, err = run('x<F1><F2>')
if status != 0 or saved != b'x' + sample_text or beside() is not None:
    fail('a save: exit %d\n%s' % (status, err[:2000]))
status, saved, _, raw, err = run('x<F1><F2>', KILO_NORENAME=1)
if status != 0 or b"Can't rename" not in raw or beside() != b'x' + sample_text:
    fail('a save that cannot be renamed: exit %d\n%s' % (status, err[:2000]))
print('memory and card limits: checked')

# 8. every allocation in every case fails in turn, alone
swept = 0
for n in names:
    status, _, _, _, err = run(scripts[n], **how[n])
    for at in range(1, allocations(err) + 1):
        status, _, _, _, err = run(scripts[n], KILO_FAIL_AT=at, **how[n])
        swept += 1
        if status not in (0, 2):
            fail('%s with allocation %d failing: exit %d\n%s' % (n, at, status, err[:2000]))
            break
print('single failures: %d runs' % swept)

# 9. random keys in a heap of random size
plain = list('abcxyz  ()=.,019') + ['-', '-', '[', '[', ']', ']', '"', "'", '\\', 'local ', 'end', '--[[', ']]', '--']
moves = ['<UP>', '<DOWN>', '<LEFT>', '<RIGHT>', '<HOME>', '<END>', '<PGUP>', '<PGDN>', '<S-LEFT>', '<S-RIGHT>']
edits = ['<ENTER>', '<BS>', '<DEL>', '<TAB>', '<C-TAB>']
marks = ['<F4>', '<C-c>', '<C-x>', '<C-v>', '<ESC>']
finds = ['l', 'o', 'c', 'a', ' ', 'e', 'n', 'd', '<BS>', '<DOWN>', '<UP>', '1']

def random_keys(rng, n):
    out = []
    for _ in range(n):
        r = rng.random()
        if r < 0.30:
            out.append(rng.choice(plain))
        elif r < 0.62:
            out.append(rng.choice(moves) if rng.random() < 0.7 else '<%s*%d>' % (rng.choice(['UP', 'DOWN', 'LEFT', 'RIGHT']), rng.randint(2, 40)))
        elif r < 0.80:
            out.append(rng.choice(edits))
        elif r < 0.94:
            out.append(rng.choice(marks))
        elif r < 0.97:
            out.append('<F3>' + ''.join(rng.choice(finds) for _ in range(rng.randint(1, 6))) + rng.choice(['<ENTER>', '<ESC>']))
        elif r < 0.985:
            out.append('<C-l>')
        else:
            out.append('<F1>')
    return ''.join(out) + '<ESC><F1><F2*4>'

runs = int(os.environ.get('RANDOM_RUNS', 300))
seed0 = int(os.environ.get('SEED', 1))
for seed in range(seed0, seed0 + runs):
    rng = random.Random(seed)
    keys = random_keys(rng, rng.randint(20, 400))
    start = rng.random() < 0.85
    env = {}
    if rng.random() < 0.7:
        env['KILO_HEAP'] = rng.randint(300, loaded + 6000)
    status, _, _, _, err = run(keys, start=start, **env)
    if status not in (0, 2):
        fail('random keys, SEED=%d RANDOM_RUNS=1 %s: exit %d\n%s' % (seed, env, status, err[:2000]))
        break
print('random keys: %d runs' % runs)

if failures:
    sys.exit('%d checks failed' % len(failures))
print('all checks passed')
