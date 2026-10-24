// Downloads free-exercise-db (Unlicense) at a pinned commit and writes the trimmed copy bundled in the app.
// Images and unused fields are dropped to keep the APK small. Run: npm run build:exercises
import { writeFile } from 'node:fs/promises'

const COMMIT = 'f00c92c7dcf1216a928a52c3706c7ce8e2f71ed5'
const url = `https://raw.githubusercontent.com/yuhonas/free-exercise-db/${COMMIT}/dist/exercises.json`

const res = await fetch(url)
if (!res.ok) throw new Error(`${res.status} ${url}`)
const all = await res.json()

const trimmed = all.map((e) => ({
  id: e.id,
  name: e.name,
  category: e.category,
  equipment: e.equipment ?? null,
  primaryMuscles: e.primaryMuscles,
  secondaryMuscles: e.secondaryMuscles,
  instructions: e.instructions,
}))

await writeFile(new URL('../src/data/exercises.json', import.meta.url), JSON.stringify(trimmed) + '\n')
console.log(`wrote ${trimmed.length} exercises from ${COMMIT}`)
