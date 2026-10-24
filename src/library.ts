import data from './data/exercises.json'

export type LoadType = 'weighted' | 'bodyweight' | 'timed'

// Trimmed free-exercise-db entry, see scripts/build-exercises.mjs.
export type LibraryExercise = {
  id: string
  name: string
  category: string
  equipment: string | null
  primaryMuscles: string[]
  secondaryMuscles: string[]
  instructions: string[]
}

export const library = data as LibraryExercise[]

// The dataset has no load type. Body-only defaults to bodyweight; timed (e.g. plank) is set by the user.
export const defaultLoadType = (e: LibraryExercise): LoadType =>
  e.equipment === 'body only' ? 'bodyweight' : 'weighted'
