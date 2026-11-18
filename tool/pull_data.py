# Read-only (GET only): copies every synced table from Supabase into a backup-shaped JSON.
# Run: python3 -I tool/pull_data.py [out.json]   (default .data/supabase.json)
# Needs VITE_SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY in .env. Prints only row counts.
import json, os, sys, urllib.request

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
env = {}
for line in open(os.path.join(ROOT, '.env')):
    if '=' in line and not line.lstrip().startswith('#'):
        k, v = line.strip().split('=', 1)
        env[k] = v.strip('"\'')
url, key = env['VITE_SUPABASE_URL'], env['SUPABASE_SERVICE_ROLE_KEY']

tables = {}
for t in ['exercises', 'routines', 'routine_exercises', 'routine_sets', 'workouts', 'workout_exercises', 'sets']:
    rows, off = [], 0
    while True:
        req = urllib.request.Request(f'{url}/rest/v1/{t}?select=*&order=id&offset={off}&limit=1000',
                                     headers={'apikey': key, 'Authorization': f'Bearer {key}'}, method='GET')
        page = json.load(urllib.request.urlopen(req))
        rows += page
        off += 1000
        if len(page) < 1000:
            break
    tables[t] = rows
    print(f'{t}: {len(rows)} rows')

out = sys.argv[1] if len(sys.argv) > 1 else os.path.join(ROOT, '.data', 'supabase.json')
os.makedirs(os.path.dirname(out), exist_ok=True)
with open(out, 'w') as f:
    json.dump({'tables': tables}, f)
print('saved', out)
