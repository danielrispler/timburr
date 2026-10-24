# timburr

Personal offline-first workout log for Android. Timburr carries a log everywhere; so does this app.

Flutter + Dart. Local SQLite (drift) as the working copy, synced to a personal Supabase project. Spec: [#3](https://github.com/danielrispler/timburr/issues/3). Design: [docs/design.md](docs/design.md).

## Supabase setup

1. Create a project at [supabase.com](https://supabase.com). The free plan is enough. Pick a region near you.
2. Open **SQL Editor**, paste [`supabase/migrations/001_init.sql`](supabase/migrations/001_init.sql), and click **Run**.
3. Create your user: **Authentication > Users > Add user > Create new user**. Enter your email and password, and tick **Auto Confirm User**.
4. Disable sign-ups: **Authentication > Sign In / Providers**, turn off **Allow new users to sign up**, then **Save**.
5. Copy your keys from **Project Settings > API Keys**: the Project URL and the **publishable** key (`sb_publishable_...`, or the legacy `anon` key).
6. Create `.env.json` (git-ignored) and fill it in:

   ```sh
   cp .env.example.json .env.json
   ```

Never put the secret / `service_role` key in `.env.json`, the app or this repo. The app only needs the publishable key: RLS limits every row to its owner.

A free project pauses after about 7 days of low activity. The app keeps working offline. Restore the project from the dashboard and sync resumes.

## Development

Needs the Flutter SDK and Android Studio (for the Android SDK). Gradle needs Java. With no system Java, point it at Android Studio's bundled JDK first:

```sh
export JAVA_HOME="/Applications/Android Studio.app/Contents/jbr/Contents/Home"
flutter run --dart-define-from-file=.env.json        # app on a device or emulator
flutter build apk --dart-define-from-file=.env.json  # APK in build/app/outputs/flutter-apk/
flutter test                                         # unit tests
(cd supabase && npm install && npm test)             # migration tests in PGlite, no Docker
```

Signed release builds and the GitHub Actions release workflow arrive in stage 4.

## Exercise library

The bundled library is [free-exercise-db](https://github.com/yuhonas/free-exercise-db) (Unlicense), pinned to one commit and trimmed (no images) by `node scripts/build-exercises.mjs`, which writes `assets/exercises.json`.
