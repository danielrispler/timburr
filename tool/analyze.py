# Prints routines, plan slots, linked workouts and exercise history from a backup-shaped JSON
# (app "Export backup" file or tool/pull_data.py output).
# Run: python3 -I tool/analyze.py DATA.json [ROUTINE_REGEX] [EXERCISE_REGEX]
import json, os, re, sys
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
T = json.load(open(sys.argv[1]))['tables']
for t in ('exercises', 'routines', 'routine_exercises', 'routine_sets', 'workouts', 'workout_exercises', 'sets'):
    T.setdefault(t, [])
ROUTINE_RE = sys.argv[2] if len(sys.argv) > 2 else 'lower b'
EXERCISE_RE = sys.argv[3] if len(sys.argv) > 3 else 'deadlift'
_lib = json.load(open(os.path.join(ROOT, 'assets', 'exercises.json')))
lib = {e['id']: e['name'] for e in _lib}
for e in _lib:  # old ids resolve to the new entry, like lib/data/catalog.dart
    for old in e.get('legacyIds') or []: lib.setdefault(old, e['name'])
live = lambda r: not r.get('deleted_at')
ex = {e['id']: e for e in T['exercises']}
def name(i):
    e = ex.get(i)
    if not e: return f'?{i[:8]}'
    return e.get('name') or lib.get(e.get('library_id')) or e.get('library_id') or '?'
def custom(i): return ex.get(i, {}).get('library_id') is None
def alts(r): return r.get('alternative_ids') or []
ts = lambda s: (s or '')[:19]

print('== Routines')
for r in sorted(T['routines'], key=lambda r: r['created_at']):
    print(f"  {r['name']!r:24} created {ts(r['created_at'])}  updated {ts(r['updated_at'])}  {'DELETED' if not live(r) else ''}")

wex = [e for e in T['workout_exercises'] if live(e)]
wsets = [s for s in T['sets'] if live(s)]
wo = {w['id']: w for w in T['workouts'] if live(w)}
def sets_of(we_id):
    return sorted([s for s in wsets if s['workout_exercise_id'] == we_id], key=lambda s: s['set_number'])
fmt = lambda ss: ', '.join(f"{s.get('weight_kg')}x{s.get('reps') or s.get('duration_sec')}{'(drop)' if s.get('is_drop') else ''}{'' if s.get('done') else '(not done)'}" for s in ss)
def kind(w):
    if w['finished_at'] is None: return 'IN PROGRESS'
    return 'IMPORTED-shape (finished==started)' if w['finished_at'] == w['started_at'] else 'live/I-did-it'

for rname in [r['name'] for r in T['routines'] if live(r) and re.search(ROUTINE_RE, r['name'], re.I)]:
    r = next(x for x in T['routines'] if x['name'] == rname and live(x))
    print(f"\n== Routine {rname!r} slots (routine created {ts(r['created_at'])})")
    for re_ in sorted([e for e in T['routine_exercises'] if e['routine_id'] == r['id'] and live(e)], key=lambda e: e['position']):
        rs = sorted([s for s in T['routine_sets'] if s['routine_exercise_id'] == re_['id'] and live(s)], key=lambda s: s['set_number'])
        print(f"  [{re_['position']}] {name(re_['exercise_id'])}   alternatives={[name(a) for a in alts(re_)]}  backup={name(re_['backup_exercise_id']) if re_.get('backup_exercise_id') else None}")
        planned = ', '.join('%sx%s' % (s.get('weight_kg'), s.get('reps') or s.get('duration_sec')) for s in rs)
        print(f"       planned: {planned}   sets created {sorted({ts(s['created_at']) for s in rs})} updated {sorted({ts(s['updated_at']) for s in rs})}")
    print(f"\n== Workouts linked to {rname!r}")
    for w in sorted([w for w in wo.values() if w.get('routine_id') == r['id']], key=lambda w: w['started_at']):
        print(f"  started {ts(w['started_at'])} finished {ts(w['finished_at'])} created {ts(w['created_at'])} updated {ts(w['updated_at'])}  -> {kind(w)}")
        for e in sorted([e for e in wex if e['workout_id'] == w['id']], key=lambda e: e['position']):
            ss = sets_of(e['id'])
            print(f"     {name(e['exercise_id']):36} {fmt(ss)}  {'SKIPPED' if e.get('skipped') else ''} alts={len(alts(e))}  sets updated {max([ts(s['updated_at']) for s in ss] or [''])}")

pat = EXERCISE_RE
print(f"\n== Every session of exercises matching {pat!r}")
for e in sorted([e for e in wex if re.search(pat, name(e['exercise_id']), re.I) and e['workout_id'] in wo], key=lambda e: wo[e['workout_id']]['started_at']):
    w = wo[e['workout_id']]
    rn = next((r['name'] for r in T['routines'] if r['id'] == w.get('routine_id')), None)
    print(f"  {ts(w['started_at'])} {name(e['exercise_id'])} [{rn}] {kind(w)}: {fmt(sets_of(e['id']))}")

print('\n== Custom exercises (machines are custom exercises)')
for e in sorted([e for e in T['exercises'] if custom(e['id']) and live(e)], key=lambda e: e['created_at']):
    print(f"  {e['name']!r} created {ts(e['created_at'])}")
print('\n== Routine slots for calf / leg extension, with alternatives')
for re_ in [e for e in T['routine_exercises'] if live(e) and re.search('calf|extension', name(e['exercise_id']), re.I)]:
    rn = next((r['name'] for r in T['routines'] if r['id'] == re_['routine_id'] and live(r)), None)
    if rn: print(f"  {rn!r}: {name(re_['exercise_id'])}  alternatives={[name(a) for a in alts(re_)]}  slot updated {ts(re_['updated_at'])}")
print('\n== Exercises named like calf / extension')
for e in T['exercises']:
    if re.search('calf|extension', name(e['id']), re.I): print(f"  {name(e['id'])!r} custom={custom(e['id'])} deleted={not live(e)}")
