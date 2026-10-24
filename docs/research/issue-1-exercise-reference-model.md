# Exercise reference model (issue #1)

Question: how should routines, workouts and per-exercise settings reference an exercise that is either a bundled library exercise (free-exercise-db string id) or a custom one (client uuid)? Candidates: A merged table, B text reference, C two tables. Source: https://github.com/danielrispler/timburr/issues/1

## Recommendation

Keep **A as shipped** in `supabase/migrations/001_init.sql`: id = `uuidv5(APP_NAMESPACE, library_id)` for library rows, random uuid for custom rows, `unique (user_id, library_id)` as a backstop. No migration change needed. Two small additions for Stage 2 (code, not schema):

1. Fix the namespace uuid as a constant in the app and never change it. Do not mix `user_id` into the name.
2. Library display names come from the bundle; when a library id is missing from a newer bundle, fall back to a humanized `library_id` (or add an optional cached `name` later). This keeps history readable (story 19).

B and C both pass the stories but give up foreign keys (B) or double every reference column and query (C), for no gain at one user.

## Why A holds

| Criterion | A merged | B text ref | C two tables |
| --- | --- | --- | --- |
| Referential integrity | Real FK on every reference [pg-fk] | None; kind told by string format | FK only on the uuid column, plus a `num_nonnulls(...) = 1` check [pg-check] |
| Push/pull order | `exercises` first, already in design order | No ordering need | Settings table must also be ordered |
| Two offline devices, same library exercise | Same uuidv5 on both [rfc-v5]; second push is an upsert on `id` [pg-onconflict], last-write-wins trigger picks one | Settings still need a keyed table; same problem as C | Needs `unique (user_id, library_id)` on settings and upsert on that key |
| Restore into fresh project (new `user_id`) | Id does not depend on `user_id`, so restored ids equal recomputed ids | Fine | Fine if settings keyed by `library_id` |
| Library id renamed/removed | Row and history stay (FK to own row); only display name needs fallback | Dangling text, same fallback | Same as B |
| Import name matching | Search bundle + custom rows, then get-or-create row by uuidv5 | Same search | Same search |
| "Last time", PRs, stats | One `exercise_id` join | One text column, no FK | Two columns, `coalesce` or `OR` in every query |
| Code size | One table, one code path, plus `ensureLibraryRow()` | Smallest schema, format-sniffing everywhere | Largest |

Details:

- **Determinism.** UUIDv5 is a SHA-1 hash of namespace + name; the same inputs always give the same uuid [rfc-v5]. Dart `uuid` package exposes `Uuid().v5(namespace, name)` [dart-uuid]; Postgres `uuid-ossp` has `uuid_generate_v5(namespace, name)` if the server ever needs it [pg-uuid-ossp]. Because the name is `library_id` alone, a restore into a project with a different `auth.uid()` reproduces the same ids. This is safe only with one user per project: two users in one project would collide on primary key. The issue scopes multi-user out.
- **Duplicates.** Two devices create the same row offline; both push `insert ... on conflict (id) do update`, so the second becomes an update, which the existing `touch_row` stale-update guard resolves by `updated_at` [pg-onconflict]. `unique (user_id, library_id)` catches a bug where some path uses a random id. Custom rows have `library_id` null; Postgres treats nulls as distinct in unique constraints by default, so many custom rows are allowed [pg-unique].
- **Deletes.** Soft delete (`deleted_at`) keeps the row, so old workouts keep a valid FK and the name (stories 7-8). Pickers filter `deleted_at is null`.
- **Local store.** The issue mentions Dexie, but the repo uses drift (SQLite) per CLAUDE.md. SQLite does not enforce foreign keys unless `PRAGMA foreign_keys = ON` is set per connection [sqlite-fk]; drift docs show enabling it in `beforeOpen` [drift-migrations]. Pull applies tables in dependency order, so enabling it is safe; leaving it off is also acceptable since the server enforces FKs.
- **RLS.** All three models put `user_id = auth.uid()` on every row; A needs no extra table policy [supabase-rls].

## Open uncertainties

- Namespace choice is arbitrary; any fixed uuid works. Changing it later re-keys every library row.
- Restore-with-merge (story 16) for custom exercises matches by name, not id; that is app logic, unaffected by the model.
- Sources below were cited from known stable doc URLs; their exact section anchors were not re-fetched in this session.

## Sources

- [rfc-v5] RFC 9562, section 5.5 (UUID Version 5): https://www.rfc-editor.org/rfc/rfc9562#section-5.5
- [dart-uuid] `uuid` package: https://pub.dev/packages/uuid
- [pg-uuid-ossp] PostgreSQL uuid-ossp: https://www.postgresql.org/docs/current/uuid-ossp.html
- [pg-fk] PostgreSQL foreign keys: https://www.postgresql.org/docs/current/ddl-constraints.html#DDL-CONSTRAINTS-FK
- [pg-unique] PostgreSQL unique constraints and NULLs: https://www.postgresql.org/docs/current/ddl-constraints.html#DDL-CONSTRAINTS-UNIQUE-CONSTRAINTS
- [pg-check] PostgreSQL `num_nonnulls`: https://www.postgresql.org/docs/current/functions-comparison.html
- [pg-onconflict] PostgreSQL INSERT ... ON CONFLICT: https://www.postgresql.org/docs/current/sql-insert.html#SQL-ON-CONFLICT
- [sqlite-fk] SQLite foreign key support: https://www.sqlite.org/foreignkeys.html#fk_enable
- [drift-migrations] drift migrations, `beforeOpen`: https://drift.simonbinder.eu/migrations/
- [supabase-rls] Supabase Row Level Security: https://supabase.com/docs/guides/database/postgres/row-level-security
