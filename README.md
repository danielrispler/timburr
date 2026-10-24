# timburr

Personal offline-first workout log for Android. Timburr carries a log everywhere; so does this app.

Flutter + Dart. Local SQLite (drift) as the working copy, synced to a personal Supabase project. Spec: [#3](https://github.com/danielrispler/timburr/issues/3). Design: [docs/design.md](docs/design.md).

## Supabase setup

1. Create a project at [supabase.com](https://supabase.com). The free plan is enough. Pick a region near you.
2. Open **SQL Editor** and run each file in [`supabase/migrations/`](supabase/migrations/) in order: paste it and click **Run**.
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

## Import from the command line

`tool/timburr-import` writes a v1 import file (format: `importFormat` in [`lib/data/importer.dart`](lib/data/importer.dart)) straight into Supabase. It signs in as you, so RLS still applies. It pulls your data into memory, runs the app's importer (same validation and name matching) and pushes the result. The phone picks it up on its next sync. An AI assistant can write the JSON and run the command.

Add `TIMBURR_EMAIL` and `TIMBURR_PASSWORD` to `.env` (git-ignored), next to `VITE_SUPABASE_URL` and `VITE_SUPABASE_PUBLISHABLE_KEY`. Sync the phone first: last write wins.

```sh
tool/timburr-import workouts.json --dry-run        # validate, list new custom exercises, write nothing
tool/timburr-import workouts.json --save-routines  # import; an unknown "routine" name becomes a saved workout
```

## Signed release builds

Every build must use the same keystore, or Android refuses to install updates over the old app.

1. Create the keystore once, outside the repo:

   ```sh
   export JAVA_HOME="/Applications/Android Studio.app/Contents/jbr/Contents/Home"
   "$JAVA_HOME/bin/keytool" -genkeypair -v -keystore ~/timburr-release.jks \
     -alias timburr -keyalg RSA -keysize 4096 -validity 36500
   ```

2. Back up `~/timburr-release.jks` and its passwords in a password manager (for example, as an attachment). If you lose them, you cannot ship updates to the installed app.
3. Create `android/key.properties` (git-ignored):

   ```properties
   storeFile=/Users/you/timburr-release.jks
   storePassword=...
   keyAlias=timburr
   keyPassword=...
   ```

4. Build: `flutter build apk --release --dart-define-from-file=.env.json`. Without `key.properties`, release builds fall back to the debug key.

The env vars `TIMBURR_KEYSTORE_PATH`, `TIMBURR_KEYSTORE_PASSWORD`, `TIMBURR_KEY_ALIAS` and `TIMBURR_KEY_PASSWORD` override `key.properties`.

### GitHub release

Pushing a `v*` tag (for example `git tag v0.2.0 && git push origin v0.2.0`) runs `.github/workflows/release.yml`. It builds the signed APK with `versionCode` = the workflow run number and attaches it to a GitHub Release. First add these repository secrets (**Settings > Secrets and variables > Actions**):

- `KEYSTORE_BASE64`: the output of `base64 -i ~/timburr-release.jks`
- `KEYSTORE_PASSWORD`, `KEY_ALIAS`, `KEY_PASSWORD`
- `SUPABASE_URL`, `SUPABASE_PUBLISHABLE_KEY` (the publishable key only, never `service_role`)

## Exercise library

The bundled library is [free-exercise-db](https://github.com/yuhonas/free-exercise-db) (Unlicense), pinned to one commit and trimmed (no images) by `node scripts/build-exercises.mjs`, which writes `assets/exercises.json`.
