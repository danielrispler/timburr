# Status

Updated 2026-10-24, end of session 1. Update this file at the end of every session and every stage.

## Where we are

Stage 1 is done on branch `stage-1`, in [PR #2](https://github.com/danielrispler/timburr/pull/2), and is waiting for Daniel's approval. Merging PR #2 means "go" for stage 2.

## Waiting on Daniel

1. Review and merge PR #2.
2. Supabase setup per the README: create the project, run the migration, add the user, disable sign-ups, and fill in `.env`. It was not done in session 1. Stage 2 needs it to test auth and sync on a real project.
3. Confirm the test seams for #1. This was asked in session 1 and never answered:
   - the exercise catalog module, tested against Dexie on `fake-indexeddb`;
   - the sync engine, tested against an in-memory fake of Supabase.

## Open issues

- [#1](https://github.com/danielrispler/timburr/issues/1): research the exercise reference model. It is labelled `ready-for-agent`. Stage 1 ships candidate A, a merged `exercises` table. Library rows get the id `uuidv5(library_id)`. Settle #1 before stage 2 writes real data, because changing the model later needs a data migration.

## Next: stage 2

The scope is in [brief.md](brief.md), Stages. Do these alongside it:

- Settle #1 first, or confirm candidate A.
- Lazy-load `src/data/exercises.json` (756 KB) with a dynamic import. Today it is in the main chunk and triggers Vite's chunk-size warning.
- Add the Capacitor plugins listed in [design.md](design.md), Stack, and `uuid` for the v5 ids.

## Unverified

- The migration has only run in PGlite with a stubbed `auth` schema. It has never run on a real Supabase project.
- The dashboard menu names in the README's Supabase setup were written from memory.

## Session 1 decisions not recorded elsewhere

- **Name.** Timburr is the Pokémon that carries a log. Repo: [danielrispler/timburr](https://github.com/danielrispler/timburr).
- **Public repo and releases.** Each APK carries the Supabase URL and the publishable key. Daniel accepted this because sign-ups are off and RLS guards every row.
- **Cost of abuse.** Expected to be about $0: failed logins are rate-limited and not billed. If the key is abused, rotate it and ship a new build.
- **Free-tier pause.** Supabase pauses a free project after about 7 days of low activity, and it can be restored for up to 90 days. Daniel accepted this, so there is no keepalive job.
- **Dexie over SQLite.** It is simpler. The same code also runs in the browser and could target iOS later.
- **Planning.** Session 1 ran the grilling skill on the brief; every answer is in design.md. Issue #1 was written with the to-spec skill.
