# Timburr

Personal offline-first Android workout log for one user, Daniel. Flutter + Dart, with drift (SQLite) as the local store, synced to a personal Supabase project.

## Read first

- Spec: GitHub issue #3. The full product spec and stage plan.
- `docs/brief.md`: the original requirements, verbatim. Read it before building any feature.
- `docs/design.md`: the data model, sync and screens decided in planning. Where it differs from the brief, design.md and the spec win.

## Stage workflow

Work follows the four stages in the brief.

- Each stage gets one branch and one PR: `stage-N` into `main`. Merging the PR is Daniel's approval for the next stage.
- End each stage with a summary and a list of what to test on the phone. Then stop.
- Ask Daniel only about big decisions. Pick sensible defaults for small ones and list them in the stage summary.

## Rules

- The app ships only the Supabase publishable (anon) key.
- Secrets stay in `.env` locally and in repository secrets in CI: the service_role key, the keystore and its passwords.
- Every schema change ships as a new numbered migration in `supabase/migrations/`, plus a case in `supabase/migrations.test.ts`.
- Pure logic gets `flutter_test` tests: PRs, 1RM, volume, pace, import validation, sync, backup.
- Issues go in GitHub Issues on `danielrispler/timburr`. Triage labels: `needs-triage`, `needs-info`, `ready-for-agent`, `ready-for-human`, `wontfix`.

## Gotchas

- Put a build on the phone with `tool/phone.sh`: it bakes in the Supabase config, checks it, and installs over the old app with `adb install -r`. Flutter finds Android Studio's Java by itself, so leave `JAVA_HOME` alone and leave Gradle to `flutter`.
- Bugs that depend on real data or sync: read `docs/debugging.md`.
- The repo keeps its hand formatting (`dart format` would rewrite 52 of 61 files), so edit by hand.
- The migration tests run in PGlite (Postgres in WASM). Docker is not needed, and the daemon is usually off.
