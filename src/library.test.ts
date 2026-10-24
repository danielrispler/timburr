import { describe, expect, it } from 'vitest'
import { defaultLoadType, library } from './library'

describe('bundled exercise library', () => {
  it('has unique ids and case-insensitively unique names (import matching relies on it)', () => {
    expect(library.length).toBeGreaterThan(800)
    expect(new Set(library.map((e) => e.id)).size).toBe(library.length)
    expect(new Set(library.map((e) => e.name.toLowerCase())).size).toBe(library.length)
  })

  it('ships without images', () => {
    expect(library.some((e) => 'images' in e)).toBe(false)
  })

  it('defaults body-only exercises to bodyweight and the rest to weighted', () => {
    const pushUp = library.find((e) => e.id === 'Pushups')!
    const bench = library.find((e) => e.id === 'Barbell_Bench_Press_-_Medium_Grip')!
    expect(defaultLoadType(pushUp)).toBe('bodyweight')
    expect(defaultLoadType(bench)).toBe('weighted')
  })
})
