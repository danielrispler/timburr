// Downloads exercises-dataset at a pinned commit and writes the trimmed copy bundled in the app.
// Data and text are MIT. The GIFs and thumbnails are © Gym visual and are not bundled: the app
// downloads them on demand and shows the credit. Run: node scripts/build-exercises.mjs
import { writeFile } from 'node:fs/promises'

const COMMIT = '7455efae41b330c265e7cd4b78dfa848e7ce5ebd'
const url = `https://raw.githubusercontent.com/hasaneyldrm/exercises-dataset/${COMMIT}/data/exercises.json`
// The library before this one, kept to map exercises already logged under its ids.
const OLD_COMMIT = 'f00c92c7dcf1216a928a52c3706c7ce8e2f71ed5'
const oldUrl = `https://raw.githubusercontent.com/yuhonas/free-exercise-db/${OLD_COMMIT}/dist/exercises.json`

async function get(u) {
  const res = await fetch(u)
  if (!res.ok) throw new Error(`${res.status} ${u}`)
  return res.json()
}
const all = await get(url)
const old = await get(oldUrl)

// Gym names Daniel knows, searchable and shown in brackets. Keyed by dataset id.
const ALIASES = {
  '0597': ['Hip Abduction Machine'],
  '0598': ['Hip Adduction Machine'],
  '0861': ['Seated Pulley Row'],
  '0178': ['Lateral Raise with Cable'],
}

// Old free-exercise-db id -> dataset id, picked by hand for every exercise logged before the switch.
// Old ids whose names match exactly are added below.
const LEGACY = {
  Barbell_Deadlift: '0032',
  Dumbbell_Rear_Lunge: '0381',
  Seated_Leg_Curl: '0599',
  Leg_Extensions: '0585',
  Standing_Dumbbell_Calf_Raise: '0417',
  Pullups: '0652',
  Standing_Military_Press: '1456',
  'Barbell_Incline_Bench_Press_-_Medium_Grip': '0047',
  'Seated_One-arm_Cable_Pulley_Rows': '0214',
  Cable_Crossover: '0227',
  Hammer_Curls: '0313',
  Reverse_Flyes: '0383',
  Standing_Dumbbell_Triceps_Extension: '0430',
  Barbell_Squat: '0043',
  Romanian_Deadlift: '0085',
  Calf_Press: '2289',
  Thigh_Abductor: '0597',
  Thigh_Adductor: '0598',
  Seated_Cable_Rows: '0861',
  'Barbell_Bench_Press_-_Medium_Grip': '0025',
  Bent_Over_Barbell_Row: '0027',
  'Wide-Grip_Lat_Pulldown': '0150',
  Dumbbell_Bicep_Curl: '0294',
  'Triceps_Pushdown_-_Rope_Attachment': '0200',
}

const key = (s) => s.toLowerCase().replace(/[^a-z0-9]/g, '')
const byName = new Map(all.map((e) => [key(e.name), e.id]))
for (const o of old) LEGACY[o.id] ??= byName.get(key(o.name))
const ids = new Set(all.map((e) => e.id))
const legacyOf = {}
for (const [o, n] of Object.entries(LEGACY)) {
  if (!n) continue
  if (!ids.has(n)) throw new Error(`legacy ${o} -> unknown id ${n}`)
  ;(legacyOf[n] ??= []).push(o)
}
for (const id of Object.keys(ALIASES)) if (!ids.has(id)) throw new Error(`alias for unknown id ${id}`)
const oldName = Object.fromEntries(old.map((o) => [o.id, o.name]))

const title = (s) => s.replace(/(^|[\s(\-/])([a-z])/g, (_, p, c) => p + c.toUpperCase())

const trimmed = all.map((e) => {
  const name = title(e.name)
  const legacyIds = legacyOf[e.id] ?? []
  // Old names stay searchable, and imports written with them still match.
  const oldNames = legacyIds.map((o) => oldName[o]).filter((n) => key(n) !== key(name))
  return {
    id: e.id,
    name,
    category: e.category,
    equipment: e.equipment,
    primaryMuscles: [e.target],
    secondaryMuscles: e.secondary_muscles.filter((m) => m !== e.target),
    instructions: e.instruction_steps.en,
    aliases: [...(ALIASES[e.id] ?? []), ...oldNames],
    legacyIds,
    media: e.media_id ? e.gif_url.replace(/^videos\/|\.gif$/g, '') : null,
  }
})

await writeFile(new URL('../assets/exercises.json', import.meta.url), JSON.stringify(trimmed) + '\n')
console.log(`wrote ${trimmed.length} exercises from ${COMMIT}, ${Object.values(LEGACY).filter(Boolean).length} legacy ids`)
