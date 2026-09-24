#!/usr/bin/env python3
"""Runs the live assistant benchmark with every scenario run in its OWN
process, so one run's kernel work never stalls another run's clock.

  tools/ai_lab/bench.py NAME [--set main|holdout|all] [--only a,b] [--par 6]
                             [--repeat 1] [--env K=V ...]

Snapshots frontend/ first (so edits made while it runs do not leak in),
writes /tmp/lab/runs/NAME.json (all results + creativity) and NAME_r/ (renders,
transcripts). Needs PATH with flutter, PROTOTYPE_NATIVE_DIR, DEEPSEEK_API_KEY.
"""
import argparse, json, os, shutil, subprocess, sys, concurrent.futures as cf, time

ap = argparse.ArgumentParser()
ap.add_argument('name')
ap.add_argument('--set', default='main')
ap.add_argument('--only', default='')
ap.add_argument('--par', type=int, default=4)
ap.add_argument('--repeat', type=int, default=1)
ap.add_argument('--env', action='append', default=[])
ap.add_argument('--root', default=os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))
a = ap.parse_args()

runs = '/tmp/lab/runs'
os.makedirs(runs, exist_ok=True)
snap = f'/tmp/lab/wt/{a.name}'
shutil.rmtree(snap, ignore_errors=True)
os.makedirs(snap)
shutil.copytree(f'{a.root}/frontend', f'{snap}/base', symlinks=True,
                ignore=lambda d, names: ['build'] if os.path.abspath(d) == os.path.abspath(f'{a.root}/frontend') else [])
with open(f'{runs}/{a.name}.diff', 'w') as f:
    subprocess.run(['git', 'diff', 'HEAD'], cwd=a.root, stdout=f)
head = subprocess.run(['git', 'rev-parse', '--short', 'HEAD'], cwd=a.root, capture_output=True, text=True).stdout.strip()

spec = json.load(open(f'{snap}/base/test/bench/scenarios.json'))
only = [x for x in a.only.split(',') if x]
scen = [s for s in spec['scenarios']
        if (s['id'] in only if only else (a.set == 'all' or s.get('set', 'main') == a.set))]
jobs = []
for s in scen:
    n = max(a.repeat, 3 if s.get('creative') else 1)
    for i in range(n):
        jobs.append((s['id'], i))

extra = dict(kv.split('=', 1) for kv in a.env)

def run(job):
    sid, i = job
    w = f'{snap}/{sid}-{i}'
    shutil.copytree(f'{snap}/base', w, symlinks=True)
    out = f'{w}/out.json'
    env = dict(os.environ, AI_BENCH='live', AI_BENCH_KEY=os.environ['DEEPSEEK_API_KEY'],
               AI_BENCH_ONLY=sid, AI_BENCH_RUN=str(i), AI_BENCH_OUT=out,
               AI_BENCH_RENDER=f'{runs}/{a.name}_r', **extra)
    with open(f'{w}/log.txt', 'w') as log:
        subprocess.run(['timeout', '3600', 'flutter', 'test', '--no-pub', 'test/bench/ai_bench_test.dart'],
                       cwd=w, env=env, stdout=log, stderr=subprocess.STDOUT)
    try:
        r = json.load(open(out))['scenarios']
    except Exception as e:
        # Keep what the process said: a crash with no result is a finding.
        keep = f'{runs}/{a.name}_r/{sid}-{i}.crash.log'
        os.makedirs(os.path.dirname(keep), exist_ok=True)
        shutil.copy(f'{w}/log.txt', keep)
        r = [{'id': sid, 'run': i, 'pass': False, 'fast': False,
              'failures': [f'harness: no output ({e}); log kept in {keep}'], 'speed': []}]
    shutil.rmtree(w, ignore_errors=True)
    return r

t0 = time.time()
results = []
with cf.ThreadPoolExecutor(a.par) as ex:
    for r in ex.map(run, jobs):
        results.extend(r)
        for x in r:
            print(f"  {x['id']}#{x.get('run')}: {'OK ' if x.get('pass') else 'BAD'} "
                  f"{'fast' if x.get('fast') else 'slow'} first {x.get('firstOpS')} total {x.get('seconds')} / {x.get('refSeconds')} "
                  f"rounds {x.get('rounds')} rb {x.get('rolledBack')} "
                  + '; '.join((x.get('failures') or []) + (x.get('speed') or [])), flush=True)

def distinct(p, q):
    sa, sb = p['size'], q['size']
    for i in range(3):
        if abs(sa[i] - sb[i]) > 0.08 * max(sa[i], sb[i], 1e-9):
            return True
    if abs(p['volume'] - q['volume']) > 0.15 * max(p['volume'], q['volume'], 1e-9):
        return True
    return p['features'] != q['features']

creative = {}
for s in scen:
    if not s.get('creative'):
        continue
    rs = [r for r in results if r['id'] == s['id'] and r.get('signature') and r.get('pass')]
    same = [f"runs {rs[i]['run']} and {rs[j]['run']} are the same design"
            for i in range(len(rs)) for j in range(i + 1, len(rs)) if not distinct(rs[i]['signature'], rs[j]['signature'])]
    creative[s['id']] = {'passingRuns': len(rs), 'same': same}
summary = {'name': a.name, 'head': head, 'set': a.set, 'env': extra, 'wall': time.time() - t0,
           'accurate': sum(1 for r in results if r.get('pass')),
           'fast': sum(1 for r in results if r.get('fast')),
           'both': sum(1 for r in results if r.get('pass') and r.get('fast')),
           'of': len(results), 'creative': creative, 'scenarios': results}
json.dump(summary, open(f'{runs}/{a.name}.json', 'w'), indent=1)
print(f"SUMMARY {a.name}: accurate {summary['accurate']}/{len(results)}, fast {summary['fast']}/{len(results)}, "
      f"both {summary['both']}/{len(results)}, creative {json.dumps(creative)}")
shutil.rmtree(snap, ignore_errors=True)
