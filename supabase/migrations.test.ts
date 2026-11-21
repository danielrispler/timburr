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
  for (const f of ['001_init.sql', '002_routine_sets_and_sports.sql', '003_drops_backups_health.sql', '004_app_errors.sql', '005_alternatives_and_skip.sql', '006_runs.sql']) {
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

describe('004_app_errors.sql', () => {
  it('upserts own errors, hides them from others and anon', async () => {
    const id = 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb'
    const push = (count: number) =>
      as(me, () =>
        rows(
          `insert into app_errors (id, source, error_type, message, stack, context, count, first_at, last_at, app_version, os)
           values ($1, 'sync', 'StateError', 'Bad state: boom', '#0 main', '{"table": "sets"}', $2, now(), now(), '0.1.0+1', 'android 15')
           on conflict (id) do update set count = excluded.count, last_at = excluded.last_at`,
          [id, count],
        ),
      )
    await push(1)
    await push(3)
    expect(await as(me, () => rows('select user_id, count, context from app_errors'))).toEqual([{ user_id: me, count: 3, context: { table: 'sets' } }])
    expect(await as(other, () => rows('select * from app_errors'))).toHaveLength(0)
    await expect(push(0)).rejects.toThrow(/count/)

    await db.exec('set role anon')
    await expect(rows('select * from app_errors')).rejects.toThrow(/permission denied/)
    await db.exec('reset role')
  })
})

describe('005_alternatives_and_skip.sql', () => {
  it('stores alternatives and the skipped flag', async () => {
    const [a] = await as(me, () => rows(`insert into exercises (id, name, load_type) values (gen_random_uuid(), 'Leg extension (upstairs)', 'weighted') returning id`))
    const [b] = await as(me, () => rows(`insert into exercises (id, name, load_type) values (gen_random_uuid(), 'Leg extension (downstairs)', 'weighted') returning id`))
    const [w] = await as(me, () => rows(`insert into workouts (id, started_at) values (gen_random_uuid(), now()) returning id`))
    await as(me, () =>
      rows(`insert into workout_exercises (id, workout_id, exercise_id, alternative_ids, skipped, position) values (gen_random_uuid(), $1, $2, $3, true, 0)`, [w.id, a.id, [b.id]]),
    )
    expect(await as(me, () => rows('select alternative_ids, skipped from workout_exercises where workout_id = $1', [w.id]))).toEqual([
      { alternative_ids: [b.id], skipped: true },
    ])
  })
})

describe('006_runs.sql', () => {
  const cardioId = 'cccccccc-cccc-cccc-cccc-cccccccccccc'
  const trackId = 'dddddddd-dddd-dddd-dddd-dddddddddddd'
  const upsertTrack = (points: string, updatedAt: string, uid = me) =>
    as(uid, () =>
      rows(
        `insert into cardio_tracks (id, user_id, cardio_id, points, updated_at) values ($1, $2, $3, $4, $5)
         on conflict (id) do update set points = excluded.points, updated_at = excluded.updated_at`,
        [trackId, uid, cardioId, points, updatedAt],
      ),
    )

  it('stores the Run columns on cardio', async () => {
    await as(me, () =>
      rows(
        `insert into cardio (id, type, started_at, distance_km, duration_sec, elapsed_sec, title, source, external_id, elevation_gain_m, max_hr, avg_cadence, calories, route, edited_fields)
         values ($1, 'run', now(), 5.2, 1500, 1620, 'Morning run', 'file', 'strava-1', 42.5, 181, 84.5, 350, 'abc', $2)`,
        [cardioId, ['title']],
      ),
    )
    expect(await as(me, () => rows('select title, source, edited_fields, elapsed_sec from cardio where id = $1', [cardioId]))).toEqual([
      { title: 'Morning run', source: 'file', edited_fields: ['title'], elapsed_sec: 1620 },
    ])
    await expect(as(me, () => rows(`update cardio set source = 'strava' where id = $1`, [cardioId]))).rejects.toThrow(/source/)
    // Existing rows (old types, no new columns) are still valid.
    await as(me, () => rows(`insert into cardio (id, type, started_at, distance_km, duration_sec) values (gen_random_uuid(), 'swim', now(), 1, 1800)`))
  })

  it('keeps one track per Run, newest write wins, hidden from others and anon', async () => {
    await upsertTrack('v2', '2026-10-24T10:00:00Z')
    await upsertTrack('stale', '2026-10-24T09:00:00Z')
    expect(await as(me, () => rows('select points from cardio_tracks'))).toEqual([{ points: 'v2' }])
    await upsertTrack('v3', '2026-10-24T11:00:00Z')
    expect(await as(me, () => rows('select points from cardio_tracks'))).toEqual([{ points: 'v3' }])
    await expect(
      as(me, () => rows(`insert into cardio_tracks (id, cardio_id, points) values (gen_random_uuid(), $1, 'dup')`, [cardioId])),
    ).rejects.toThrow(/unique/)

    expect(await as(other, () => rows('select * from cardio_tracks'))).toHaveLength(0)
    await expect(upsertTrack('mine now', '2026-10-24T12:00:00Z', other)).rejects.toThrow()
    await db.exec('set role anon')
    await expect(rows('select * from cardio_tracks')).rejects.toThrow(/permission denied/)
    await db.exec('reset role')
  })

  it('keeps one settings row per user under RLS and last-write-wins', async () => {
    const id = 'eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee'
    const put = (maxHr: number, at: string) =>
      as(me, () =>
        rows(
          `insert into settings (id, max_hr, birth_year, stride_m, updated_at) values ($1, $2, 1990, 0.915, $3)
           on conflict (id) do update set max_hr = excluded.max_hr, updated_at = excluded.updated_at`,
          [id, maxHr, at],
        ),
      )
    await put(190, '2026-10-24T10:00:00Z')
    await put(150, '2026-10-24T09:00:00Z')
    expect(await as(me, () => rows('select max_hr, stride_m from settings'))).toEqual([{ max_hr: 190, stride_m: '0.915' }])
    await expect(
      as(me, () => rows(`insert into settings (id, max_hr) values (gen_random_uuid(), 180)`)),
    ).rejects.toThrow(/unique/)
    expect(await as(other, () => rows('select * from settings'))).toHaveLength(0)
    await expect(put(300, '2026-10-24T11:00:00Z')).rejects.toThrow(/max_hr/)
  })
})
