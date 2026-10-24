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
  await db.exec(readFileSync(new URL('./migrations/001_init.sql', import.meta.url), 'utf8'))
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
