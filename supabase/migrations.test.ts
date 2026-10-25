// Runs the real migration in PGlite (Postgres in WASM) with a stub of Supabase's auth schema,
// then checks RLS and the last-write-wins trigger.
import { PGlite } from '@electric-sql/pglite'
import { readFileSync } from 'node:fs'
import { beforeAll, describe, expect, it } from 'vitest'

const me = '11111111-1111-1111-1111-111111111111'
const other = '22222222-2222-2222-2222-222222222222'
const workoutId = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'
const db = new PGlite()

const as = async <T>(uid: string, fn: () => Promise<T>): Promise<T> => {
  await db.exec(`set role authenticated; set request.jwt.claim.sub = '${uid}'`)
  try {
    return await fn()
  } finally {
    await db.exec('reset role')
  }
}
const rows = async (sql: string, params?: unknown[]) => (await db.query<Record<string, unknown>>(sql, params)).rows
const upsertWorkout = (notes: string, updatedAt: string) =>
  rows(
    `insert into workouts (id, user_id, started_at, notes, updated_at) values ($1, $2, now(), $3, $4)
     on conflict (id) do update set notes = excluded.notes, updated_at = excluded.updated_at`,
    [workoutId, me, notes, updatedAt],
  )

beforeAll(async () => {
  await db.exec(`
    create role anon nologin;
    create role authenticated nologin;
    create schema auth;
    create table auth.users (id uuid primary key);
    create function auth.uid() returns uuid language sql stable
      as $$ select nullif(current_setting('request.jwt.claim.sub', true), '')::uuid $$;
    grant usage on schema auth, public to anon, authenticated;
  `)
  for (const f of ['001_init.sql', '002_routine_sets_and_sports.sql', '003_drops_backups_health.sql']) {
    await db.exec(readFileSync(new URL(`./migrations/${f}`, import.meta.url), 'utf8'))
  }
  await rows('insert into auth.users values ($1), ($2)', [me, other])
})

describe('001_init.sql', () => {
  it('keeps the newest write and bumps server_updated_at', async () => {
    await as(me, () => upsertWorkout('v2', '2026-10-24T10:00:00Z'))
    const [before] = await as(me, () => rows('select server_updated_at from workouts'))
    await as(me, () => upsertWorkout('stale', '2026-10-24T09:00:00Z'))
    expect((await as(me, () => rows('select notes from workouts')))[0].notes).toBe('v2')

    await as(me, () => upsertWorkout('v3', '2026-10-24T11:00:00Z'))
    const [after] = await as(me, () => rows('select notes, server_updated_at from workouts'))
    expect(after.notes).toBe('v3')
    expect(after.server_updated_at as Date > (before.server_updated_at as Date)).toBe(true)
  })

  it('hides and protects rows from other users and anon', async () => {
    expect(await as(other, () => rows('select * from workouts'))).toHaveLength(0)
    await as(other, () => rows(`update workouts set notes = 'hacked'`))
    expect((await as(me, () => rows('select notes from workouts')))[0].notes).toBe('v3')
    await expect(
      as(other, () => rows('insert into workouts (id, user_id, started_at) values (gen_random_uuid(), $1, now())', [me])),
    ).rejects.toThrow(/row-level security/)

    await db.exec('set role anon')
    await expect(rows('select * from workouts')).rejects.toThrow(/permission denied/)
    await db.exec('reset role')
  })

  it('allows one row per library exercise, library xor custom, owned by the caller', async () => {
    await expect(
      as(me, () => rows(`insert into exercises (id, library_id, name, load_type) values (gen_random_uuid(), 'X', 'Y', 'weighted')`)),
    ).rejects.toThrow(/check/)
    await as(me, () => rows(`insert into exercises (id, library_id) values (gen_random_uuid(), 'Pushups')`))
    await expect(
      as(me, () => rows(`insert into exercises (id, library_id) values (gen_random_uuid(), 'Pushups')`)),
    ).rejects.toThrow(/unique/)
    expect((await as(me, () => rows('select user_id from exercises')))[0].user_id).toBe(me)
  })
})

describe('002_routine_sets_and_sports.sql', () => {
  it('stores planned sets under RLS', async () => {
    const [ex] = await as(me, () => rows(`insert into exercises (id, library_id) values (gen_random_uuid(), 'Squat') returning id`))
    const [r] = await as(me, () => rows(`insert into routines (id, name) values (gen_random_uuid(), 'Legs') returning id`))
    const [re] = await as(me, () =>
      rows(`insert into routine_exercises (id, routine_id, exercise_id, position) values (gen_random_uuid(), $1, $2, 0) returning id`, [r.id, ex.id]),
    )
    await as(me, () => rows(`insert into routine_sets (id, routine_exercise_id, set_number, reps) values (gen_random_uuid(), $1, 1, 5)`, [re.id]))
    expect(await as(me, () => rows('select reps from routine_sets'))).toEqual([{ reps: 5 }])
    expect(await as(other, () => rows('select * from routine_sets'))).toHaveLength(0)
  })

  it('allows sports without distance, but not distance types', async () => {
    const add = (type: string, km: number | null) =>
      as(me, () => rows(`insert into cardio (id, type, started_at, distance_km, duration_sec) values (gen_random_uuid(), $1, now(), $2, 3600)`, [type, km]))
    await add('padel', null)
    await add('swim', 1.525)
    expect(await as(me, () => rows(`select distance_km from cardio where type = 'swim'`))).toEqual([{ distance_km: '1.525' }])
    await expect(add('run', null)).rejects.toThrow(/cardio_distance_check/)
    await expect(add('golf', 5)).rejects.toThrow(/cardio_type_check/)
  })
})

describe('003_drops_backups_health.sql', () => {
  it('stores drop sets, backup exercises and health stats', async () => {
    const [a] = await as(me, () => rows(`insert into exercises (id, library_id) values (gen_random_uuid(), 'Pull-up') returning id`))
    const [b] = await as(me, () => rows(`insert into exercises (id, library_id) values (gen_random_uuid(), 'Assisted Pull-up') returning id`))
    const [r] = await as(me, () => rows(`insert into routines (id, name) values (gen_random_uuid(), 'Upper B') returning id`))
    await as(me, () =>
      rows(`insert into routine_exercises (id, routine_id, exercise_id, backup_exercise_id, position) values (gen_random_uuid(), $1, $2, $3, 0)`, [r.id, a.id, b.id]),
    )
    const [w] = await as(me, () =>
      rows(`insert into workouts (id, started_at, avg_hr, calories, active_sec, effort, cardio_load) values (gen_random_uuid(), now(), 91, 255, 3689, 5, 5) returning id`),
    )
    const [we] = await as(me, () =>
      rows(`insert into workout_exercises (id, workout_id, exercise_id, backup_exercise_id, position) values (gen_random_uuid(), $1, $2, $3, 0) returning id`, [w.id, a.id, b.id]),
    )
    await as(me, () => rows(`insert into sets (id, workout_exercise_id, set_number, reps, is_drop) values (gen_random_uuid(), $1, 1, 5, true)`, [we.id]))
    expect(await as(me, () => rows('select is_drop from sets where workout_exercise_id = $1', [we.id]))).toEqual([{ is_drop: true }])
    await expect(as(me, () => rows(`update workouts set effort = 11 where id = $1`, [w.id]))).rejects.toThrow(/effort/)
  })
})
