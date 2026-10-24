# timburr

Personal offline-first workout log for Android. Timburr carries a log everywhere; so does this app.

Vite + React + TypeScript, wrapped with Capacitor. Local IndexedDB (Dexie) as the working copy, synced to a personal Supabase project. Design: [docs/design.md](docs/design.md).

## Supabase setup

1. Create a project at [supabase.com](https://supabase.com). The free plan is enough. Pick a region near you.
2. Open **SQL Editor**, paste [`supabase/migrations/001_init.sql`](supabase/migrations/001_init.sql), and click **Run**.
3. Create your user: **Authentication > Users > Add user > Create new user**. Enter your email and password, and tick **Auto Confirm User**.
4. Disable sign-ups: **Authentication > Sign In / Providers**, turn off **Allow new users to sign up**, then **Save**.
5. Copy your keys from **Project Settings > API Keys**: the Project URL and the **publishable** key (`sb_publishable_...`, or the legacy `anon` key).
6. Create `.env` and fill it in:

   ```sh
   cp .env.example .env
   ```

Never put the secret / `service_role` key in `.env`, the app or this repo. The app only needs the publishable key: RLS limits every row to its owner.

A free project pauses after about 7 days of low activity. The app keeps working offline. Restore the project from the dashboard and sync resumes.

## Development

```sh
npm install
npm run dev     # app in the desktop browser
npm test        # unit tests
npm run lint
```

## Android

These steps need Android Studio. The commands below use its bundled JDK.

```sh
export JAVA_HOME="/Applications/Android Studio.app/Contents/jbr/Contents/Home"
npm run android                          # web build + copy into android/
(cd android && ./gradlew assembleDebug)  # android/app/build/outputs/apk/debug/app-debug.apk
```

Signed release builds and the GitHub Actions release workflow arrive in stage 4.

## Exercise library

The bundled library is [free-exercise-db](https://github.com/yuhonas/free-exercise-db) (Unlicense), pinned to one commit and trimmed (no images) by `npm run build:exercises`.
